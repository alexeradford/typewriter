import AppKit

final class DocumentLibraryStore {
    static let shared = DocumentLibraryStore()

    private struct Catalog: Codable {
        static let currentVersion = 4

        var version = currentVersion
        var documents: [LibraryDocumentItem] = []
        var folders: [LibraryFolder] = []
        var topLevelItems: [LibraryTopLevelItem] = []
        var sortOrder: LibrarySortOrder = .newestFirst

        private enum CodingKeys: String, CodingKey {
            case version
            case documents
            case folders
            case topLevelItems
            case sortOrder
        }

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(
                Int.self,
                forKey: .version
            ) ?? 1
            documents = try container.decodeIfPresent(
                [LibraryDocumentItem].self,
                forKey: .documents
            ) ?? []
            folders = try container.decodeIfPresent(
                [LibraryFolder].self,
                forKey: .folders
            ) ?? []
            topLevelItems = try container.decodeIfPresent(
                [LibraryTopLevelItem].self,
                forKey: .topLevelItems
            ) ?? []
            sortOrder = try container.decodeIfPresent(
                LibrarySortOrder.self,
                forKey: .sortOrder
            ) ?? .newestFirst
            version = Self.currentVersion
        }
    }

    enum StoreError: LocalizedError {
        case storageUnavailable
        case documentNotFound
        case folderNotFound
        case folderNotEmpty
        case unmanagedDocument
        case documentIsOpen
        case relocationFailed

        var errorDescription: String? {
            switch self {
            case .storageUnavailable:
                "Typewriter could not access its Library folder."
            case .documentNotFound:
                "The document could not be found in the Library."
            case .folderNotFound:
                "The Library folder could not be found."
            case .folderNotEmpty:
                "Move the documents out of this folder before deleting it."
            case .unmanagedDocument:
                "This document is not stored in the Typewriter Library."
            case .documentIsOpen:
                "Close the document before deleting it."
            case .relocationFailed:
                "Typewriter could not move the Library to its new location. The original Library was not changed."
            }
        }
    }

    let rootURL: URL
    let locationKind: DocumentLibraryLocation.Kind
    let locationDisplayName: String

    private let fileManager: FileManager
    private let catalogURL: URL
    private let securityScope: DocumentLibraryLocation.SecurityScope?
    private var catalog = Catalog()
    private(set) var initializationError: Error?
    private(set) var startupNotice: Error?

    init(
        fileManager: FileManager = .default,
        rootURL providedRootURL: URL? = nil,
        catalogURL providedCatalogURL: URL? = nil,
        legacyRootURL providedLegacyRootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let environmentRootURL = ProcessInfo.processInfo.environment[
            "TYPEWRITER_LIBRARY_ROOT"
        ].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let explicitRootURL = providedRootURL ?? environmentRootURL

        if let explicitRootURL {
            rootURL = explicitRootURL
            locationKind = .localFallback
            locationDisplayName = explicitRootURL.path(percentEncoded: false)
            securityScope = nil
            catalogURL = providedCatalogURL
                ?? explicitRootURL
                    .appendingPathComponent(".Typewriter", isDirectory: true)
                    .appendingPathComponent(
                        "Catalog.json",
                        isDirectory: false
                    )
        } else {
            let launch = DocumentLibraryLocation.launchLocations(
                fileManager: fileManager
            )
            rootURL = launch.selected.rootURL
            locationKind = launch.selected.kind
            locationDisplayName = launch.selected.displayName
            securityScope = launch.selected.securityScope
            catalogURL = DocumentLibraryLocation.applicationSupportRoot(
                fileManager: fileManager
            )
            .appendingPathComponent("LibraryState", isDirectory: true)
            .appendingPathComponent("Catalog.json", isDirectory: false)

            if launch.activeLocationUnavailable {
                initializationError = StoreError.storageUnavailable
                return
            }

            if launch.hasPendingSelection,
               let migrationSource = launch.migrationSource {
                do {
                    try Self.copyCurrentLibrary(
                        fileManager: fileManager,
                        catalogURL: catalogURL,
                        from: migrationSource.rootURL,
                        to: rootURL
                    )
                    DocumentLibraryLocation.commitPendingSelection()
                } catch {
                    startupNotice = error
                    DocumentLibraryLocation.clearPendingSelection()
                    initializationError = error
                    return
                }
            }
        }

        do {
            try createStorageDirectories()
            if let providedLegacyRootURL {
                try migrateLegacyLibraryIfNeeded(
                    from: providedLegacyRootURL
                )
            } else if explicitRootURL == nil {
                try migrateLegacyLibraryIfNeeded(
                    from: DocumentLibraryLocation.applicationSupportRoot(
                        fileManager: fileManager
                    ).appendingPathComponent("Library", isDirectory: true)
                )
            }
            try loadCatalog()
            try reconcileCatalogWithDisk()
        } catch {
            initializationError = error
        }
    }

    var snapshot: LibrarySnapshot {
        LibrarySnapshot(
            documents: catalog.documents,
            folders: catalog.folders.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            },
            topLevelItems: catalog.topLevelItems,
            sortOrder: catalog.sortOrder
        )
    }

    func document(withID id: UUID) -> LibraryDocumentItem? {
        catalog.documents.first { $0.id == id }
    }

    func document(at url: URL) -> LibraryDocumentItem? {
        let normalizedURL = normalized(url)
        return catalog.documents.first {
            managedURL(for: $0).map(normalized) == normalizedURL
        }
    }

    func url(for document: LibraryDocumentItem) -> URL? {
        managedURL(for: document)
    }

    @discardableResult
    func reconcilePackageMetadata(
        _ metadata: TypewriterDocumentMetadata,
        at url: URL
    ) -> LibraryDocumentItem? {
        guard
            let index = catalog.documents.firstIndex(where: {
                managedURL(for: $0).map(normalized) == normalized(url)
            })
        else {
            return nil
        }
        let oldID = catalog.documents[index].id
        if oldID != metadata.documentID,
           !catalog.documents.contains(where: {
               $0.id == metadata.documentID
           }) {
            catalog.documents[index].id = metadata.documentID
            catalog.topLevelItems = catalog.topLevelItems.map { item in
                item == .document(oldID)
                    ? .document(metadata.documentID)
                    : item
            }
        }
        apply(metadata, toDocumentAt: index)
        try? persistAndNotify()
        return catalog.documents[index]
    }

    func isManagedURL(_ url: URL) -> Bool {
        let rootPath = normalized(rootURL).path
        let candidatePath = normalized(url).path
        return candidatePath == rootPath
            || candidatePath.hasPrefix(rootPath + "/")
    }

    func reserveNewDocument() throws -> (item: LibraryDocumentItem, url: URL) {
        try checkStorage()
        let id = UUID()
        let destinationURL = availableURL(
            named: "Untitled",
            in: rootURL,
            pathExtension: "typewriter"
        )
        let item = LibraryDocumentItem(
            id: id,
            relativePath: relativePath(for: destinationURL),
            createdAt: Date(),
            title: "Untitled",
            previewText: "",
            pageCount: 1,
            pinnedAt: nil,
            folderID: nil
        )
        catalog.documents.append(item)
        try persistAndNotify()
        return (item, destinationURL)
    }

    func importDocument(at sourceURL: URL) throws -> LibraryImport {
        try checkStorage()
        if isManagedURL(sourceURL) {
            let item = try registerManagedDocumentIfNeeded(at: sourceURL)
            return LibraryImport(
                documentID: item.id,
                url: sourceURL,
                copiedIntoLibrary: false
            )
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let title = normalizedDocumentTitle(
            sourceURL.deletingPathExtension().lastPathComponent
        )
        let destinationURL = availableURL(
            named: title,
            in: rootURL,
            pathExtension: "typewriter"
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let packageMetadata = TypewriterDocumentPackage.metadata(
            at: destinationURL
        )
        let values = try? sourceURL.resourceValues(forKeys: [.creationDateKey])
        let item = LibraryDocumentItem(
            id: uniqueDocumentID(preferred: packageMetadata?.documentID),
            relativePath: relativePath(for: destinationURL),
            createdAt: packageMetadata?.createdAt
                ?? values?.creationDate
                ?? Date(),
            title: packageMetadata?.title ?? title,
            titleOverride: packageMetadata?.titleOverride,
            previewText: packageMetadata?.previewText ?? "",
            pageCount: packageMetadata?.pageCount ?? 1,
            pinnedAt: nil,
            folderID: nil
        )
        catalog.documents.append(item)
        do {
            try persistAndNotify()
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
        return LibraryImport(
            documentID: item.id,
            url: destinationURL,
            copiedIntoLibrary: true
        )
    }

    func discardFailedImport(_ imported: LibraryImport) {
        guard imported.copiedIntoLibrary else { return }
        catalog.documents.removeAll { $0.id == imported.documentID }
        catalog.topLevelItems.removeAll {
            $0 == .document(imported.documentID)
        }
        if fileManager.fileExists(atPath: imported.url.path) {
            try? fileManager.removeItem(at: imported.url)
        }
        try? persistAndNotify()
    }

    func discardReservation(documentID: UUID) {
        guard
            let item = document(withID: documentID),
            let url = managedURL(for: item),
            !fileManager.fileExists(atPath: url.path)
        else {
            return
        }
        catalog.documents.removeAll { $0.id == documentID }
        catalog.topLevelItems.removeAll {
            $0 == .document(documentID)
        }
        try? persistAndNotify()
    }

    func updateSavedDocument(
        documentID: UUID,
        currentURL: URL,
        summary: LibraryDocumentSummary,
        completion: ((Error?) -> Void)? = nil
    ) {
        guard
            let index = catalog.documents.firstIndex(where: {
                $0.id == documentID
            }),
            isManagedURL(currentURL)
        else {
            completion?(StoreError.documentNotFound)
            return
        }

        catalog.documents[index].relativePath = relativePath(for: currentURL)
        catalog.documents[index].title =
            catalog.documents[index].titleOverride ?? summary.title
        catalog.documents[index].previewText = summary.previewText
        catalog.documents[index].pageCount = summary.pageCount

        let title = catalog.documents[index].title
        moveDocumentFile(
            documentID,
            toTitle: title,
            titleOverride: catalog.documents[index].titleOverride,
            completion: completion
        )
    }

    func renameDocument(
        _ documentID: UUID,
        to proposedTitle: String,
        completion: @escaping (Error?) -> Void
    ) {
        guard let index = catalog.documents.firstIndex(where: {
            $0.id == documentID
        }) else {
            completion(StoreError.documentNotFound)
            return
        }
        let title = normalizedDocumentTitle(proposedTitle)
        catalog.documents[index].title = title
        catalog.documents[index].titleOverride = title
        moveDocumentFile(
            documentID,
            toTitle: title,
            titleOverride: title,
            completion: completion
        )
    }

    func deleteDocument(_ documentID: UUID) throws {
        try checkStorage()
        guard
            let index = catalog.documents.firstIndex(where: {
                $0.id == documentID
            }),
            let documentURL = managedURL(for: catalog.documents[index])
        else {
            throw StoreError.documentNotFound
        }
        guard NSDocumentController.shared.document(for: documentURL) == nil else {
            throw StoreError.documentIsOpen
        }

        let originalCatalog = catalog
        let stagedURL = rootURL
            .appendingPathComponent(".Deleted", isDirectory: true)
            .appendingPathComponent(
                "\(documentID.uuidString).typewriter",
                isDirectory: false
            )
        let documentExists = fileManager.fileExists(atPath: documentURL.path)
        if documentExists {
            try fileManager.createDirectory(
                at: stagedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: documentURL, to: stagedURL)
        }

        catalog.documents.remove(at: index)
        catalog.topLevelItems.removeAll {
            $0 == .document(documentID)
        }
        do {
            try persistAndNotify()
        } catch {
            catalog = originalCatalog
            if documentExists {
                try? fileManager.moveItem(at: stagedURL, to: documentURL)
            }
            throw error
        }
        if documentExists {
            try? fileManager.removeItem(at: stagedURL)
        }
    }

    func setPinned(_ pinned: Bool, documentID: UUID) throws {
        guard let index = catalog.documents.firstIndex(where: {
            $0.id == documentID
        }) else {
            throw StoreError.documentNotFound
        }
        let topLevelItem = LibraryTopLevelItem.document(documentID)
        if pinned {
            if catalog.documents[index].pinnedAt == nil {
                catalog.documents[index].pinnedAt = Date()
            }
            if !catalog.topLevelItems.contains(topLevelItem) {
                catalog.topLevelItems.append(topLevelItem)
            }
        } else {
            catalog.documents[index].pinnedAt = nil
            catalog.topLevelItems.removeAll { $0 == topLevelItem }
        }
        try persistAndNotify()
    }

    func moveTopLevelItem(
        _ item: LibraryTopLevelItem,
        to proposedIndex: Int
    ) throws {
        switch item.kind {
        case .document:
            guard let documentIndex = catalog.documents.firstIndex(where: {
                $0.id == item.itemID
            }) else {
                throw StoreError.documentNotFound
            }
            if catalog.documents[documentIndex].pinnedAt == nil {
                catalog.documents[documentIndex].pinnedAt = Date()
            }
        case .folder:
            guard catalog.folders.contains(where: {
                $0.id == item.itemID
            }) else {
                throw StoreError.folderNotFound
            }
        }

        let existingIndex = catalog.topLevelItems.firstIndex(of: item)
        catalog.topLevelItems.removeAll { $0 == item }
        let adjustedIndex = if let existingIndex, existingIndex < proposedIndex {
            proposedIndex - 1
        } else {
            proposedIndex
        }
        let insertionIndex = min(
            max(0, adjustedIndex),
            catalog.topLevelItems.count
        )
        catalog.topLevelItems.insert(item, at: insertionIndex)
        try persistAndNotify()
    }

    @discardableResult
    func createFolder(named proposedName: String) throws -> LibraryFolder {
        let name = normalizedFolderName(proposedName)
        let url = availableURL(named: name, in: rootURL)
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        let folder = LibraryFolder(
            id: UUID(),
            name: url.lastPathComponent,
            createdAt: Date(),
            relativePath: relativePath(for: url)
        )
        catalog.folders.append(folder)
        catalog.topLevelItems.append(.folder(folder.id))
        try persistAndNotify()
        return folder
    }

    func renameFolder(
        _ folderID: UUID,
        to proposedName: String,
        completion: @escaping (Error?) -> Void
    ) {
        guard
            let folderIndex = catalog.folders.firstIndex(where: {
                $0.id == folderID
            })
        else {
            completion(StoreError.folderNotFound)
            return
        }
        let sourceURL = folderURL(for: catalog.folders[folderIndex])
        let name = normalizedFolderName(proposedName)
        let destinationURL = availableURL(
            named: name,
            in: rootURL,
            excluding: sourceURL
        )
        guard normalized(sourceURL) != normalized(destinationURL) else {
            catalog.folders[folderIndex].name = name
            tryPersistAndComplete(completion)
            return
        }

        let documents = catalog.documents.filter { $0.folderID == folderID }
        let hasOpenDocument = documents.contains { item in
            guard let url = managedURL(for: item) else { return false }
            return NSDocumentController.shared.document(for: url) != nil
        }
        guard !hasOpenDocument else {
            completion(StoreError.documentIsOpen)
            return
        }

        let originalCatalog = catalog
        do {
            try fileManager.moveItem(
                at: sourceURL,
                to: destinationURL
            )
            catalog.folders[folderIndex].name =
                destinationURL.lastPathComponent
            catalog.folders[folderIndex].relativePath = relativePath(
                for: destinationURL
            )
            for document in documents {
                guard let index = catalog.documents.firstIndex(where: {
                    $0.id == document.id
                }) else {
                    continue
                }
                let oldURL = sourceURL.appendingPathComponent(
                    URL(fileURLWithPath: document.relativePath)
                        .lastPathComponent
                )
                let newURL = destinationURL.appendingPathComponent(
                    oldURL.lastPathComponent
                )
                catalog.documents[index].relativePath = relativePath(
                    for: newURL
                )
            }
            try persistAndNotify()
            completion(nil)
        } catch {
            catalog = originalCatalog
            if fileManager.fileExists(atPath: destinationURL.path),
               !fileManager.fileExists(atPath: sourceURL.path) {
                try? fileManager.moveItem(
                    at: destinationURL,
                    to: sourceURL
                )
            }
            completion(error)
        }
    }

    func deleteEmptyFolder(_ folderID: UUID) throws {
        guard
            let folder = catalog.folders.first(where: { $0.id == folderID })
        else {
            throw StoreError.folderNotFound
        }
        guard !catalog.documents.contains(where: {
            $0.folderID == folderID
        }) else {
            throw StoreError.folderNotEmpty
        }
        let url = folderURL(for: folder)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        catalog.folders.removeAll { $0.id == folderID }
        catalog.topLevelItems.removeAll {
            $0 == .folder(folderID)
        }
        try persistAndNotify()
    }

    func moveDocument(
        _ documentID: UUID,
        toFolder folderID: UUID?,
        completion: @escaping (Error?) -> Void
    ) {
        guard
            let item = document(withID: documentID),
            let sourceURL = managedURL(for: item)
        else {
            completion(StoreError.documentNotFound)
            return
        }
        let destinationDirectory: URL
        if let folderID {
            guard let folder = catalog.folders.first(where: {
                $0.id == folderID
            }) else {
                completion(StoreError.folderNotFound)
                return
            }
            destinationDirectory = folderURL(for: folder)
        } else {
            destinationDirectory = rootURL
        }

        do {
            try fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            completion(error)
            return
        }
        let destinationURL = availableURL(
            named: sourceURL.deletingPathExtension().lastPathComponent,
            in: destinationDirectory,
            pathExtension: "typewriter",
            excluding: sourceURL
        )
        guard normalized(sourceURL) != normalized(destinationURL) else {
            completion(nil)
            return
        }

        moveFile(at: sourceURL, to: destinationURL) { [weak self] error in
            guard let self else {
                completion(error)
                return
            }
            if let error {
                completion(error)
                return
            }
            guard let index = catalog.documents.firstIndex(where: {
                $0.id == documentID
            }) else {
                completion(StoreError.documentNotFound)
                return
            }
            catalog.documents[index].relativePath = relativePath(
                for: destinationURL
            )
            catalog.documents[index].folderID = folderID
            tryPersistAndComplete(completion)
        }
    }

    func setSortOrder(_ sortOrder: LibrarySortOrder) throws {
        guard catalog.sortOrder != sortOrder else { return }
        catalog.sortOrder = sortOrder
        try persistAndNotify()
    }

    private func moveDocumentFile(
        _ documentID: UUID,
        toTitle title: String,
        titleOverride: String?,
        completion: ((Error?) -> Void)?
    ) {
        guard
            let item = document(withID: documentID),
            let sourceURL = managedURL(for: item)
        else {
            completion?(StoreError.documentNotFound)
            return
        }
        let destinationURL = availableURL(
            named: title,
            in: sourceURL.deletingLastPathComponent(),
            pathExtension: "typewriter",
            excluding: sourceURL
        )

        let finish: (Error?) -> Void = { [weak self] error in
            guard let self else {
                completion?(error)
                return
            }
            if let error {
                completion?(error)
                return
            }
            guard let index = catalog.documents.firstIndex(where: {
                $0.id == documentID
            }) else {
                completion?(StoreError.documentNotFound)
                return
            }
            catalog.documents[index].relativePath = relativePath(
                for: destinationURL
            )
            if NSDocumentController.shared.document(
                for: destinationURL
            ) == nil {
                TypewriterDocumentPackage.updateMetadata(
                    at: destinationURL,
                    title: title,
                    titleOverride: titleOverride
                )
            }
            tryPersistAndComplete { error in
                completion?(error)
            }
        }

        guard normalized(sourceURL) != normalized(destinationURL) else {
            finish(nil)
            return
        }
        moveFile(at: sourceURL, to: destinationURL, completion: finish)
    }

    private func moveFile(
        at sourceURL: URL,
        to destinationURL: URL,
        completion: @escaping (Error?) -> Void
    ) {
        if let openDocument = NSDocumentController.shared.document(
            for: sourceURL
        ) {
            openDocument.move(to: destinationURL) { error in
                Task { @MainActor in
                    completion(error)
                }
            }
            return
        }
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            completion(nil)
        } catch {
            completion(error)
        }
    }

    private func createStorageDirectories() throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func migrateLegacyLibraryIfNeeded(
        from legacyRoot: URL
    ) throws {
        guard !fileManager.fileExists(atPath: catalogURL.path) else {
            return
        }
        let legacyCatalogURL = legacyRoot.appendingPathComponent(
            "Catalog.json"
        )
        guard fileManager.fileExists(atPath: legacyCatalogURL.path) else {
            return
        }

        var legacyCatalog = try Self.decodeCatalog(at: legacyCatalogURL)
        var migratedFolders: [UUID: LibraryFolder] = [:]
        for folder in legacyCatalog.folders {
            let destination = availableURL(named: folder.name, in: rootURL)
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            var migrated = folder
            migrated.name = destination.lastPathComponent
            migrated.relativePath = relativePath(for: destination)
            migratedFolders[folder.id] = migrated
        }

        var migratedDocuments: [LibraryDocumentItem] = []
        var createdURLs: [URL] = []
        do {
            for var document in legacyCatalog.documents {
                let sourceURL = legacyRoot.appendingPathComponent(
                    document.relativePath
                )
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    continue
                }
                let directory = document.folderID
                    .flatMap { migratedFolders[$0] }
                    .map(folderURL(for:))
                    ?? rootURL
                let destination = availableURL(
                    named: document.title,
                    in: directory,
                    pathExtension: "typewriter"
                )
                try fileManager.copyItem(at: sourceURL, to: destination)
                createdURLs.append(destination)
                document.relativePath = relativePath(for: destination)
                migratedDocuments.append(document)
            }
        } catch {
            for url in createdURLs {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }

        legacyCatalog.documents = migratedDocuments
        legacyCatalog.folders = Array(migratedFolders.values)
        catalog = legacyCatalog
        try persistCatalog()
    }

    private static func copyCurrentLibrary(
        fileManager: FileManager,
        catalogURL: URL,
        from sourceRoot: URL,
        to destinationRoot: URL
    ) throws {
        guard normalized(sourceRoot) != normalized(destinationRoot) else {
            return
        }
        try fileManager.createDirectory(
            at: destinationRoot,
            withIntermediateDirectories: true
        )

        var catalog = try decodeCatalogIfPresent(at: catalogURL) ?? Catalog()
        var copiedURLs: [URL] = []
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isPackageKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw StoreError.relocationFailed
        }
        do {
            for case let source as URL in enumerator {
                let sourceRelativePath = relativePath(
                    for: source,
                    relativeTo: sourceRoot
                )
                let values = try source.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isPackageKey
                ])
                let isDocument =
                    source.pathExtension.caseInsensitiveCompare("typewriter")
                    == .orderedSame

                if values.isDirectory == true && !isDocument {
                    try fileManager.createDirectory(
                        at: destinationRoot.appendingPathComponent(
                            sourceRelativePath,
                            isDirectory: true
                        ),
                        withIntermediateDirectories: true
                    )
                    continue
                }

                guard isDocument else { continue }
                var destination = destinationRoot.appendingPathComponent(
                    sourceRelativePath
                )
                if fileManager.fileExists(atPath: destination.path),
                   TypewriterDocumentPackage.metadata(at: destination)?
                    .documentID
                    == TypewriterDocumentPackage.metadata(at: source)?
                    .documentID {
                    continue
                }
                if fileManager.fileExists(atPath: destination.path) {
                    destination = availableRelocationURL(
                        for: destination,
                        fileManager: fileManager
                    )
                    if let index = catalog.documents.firstIndex(where: {
                        $0.relativePath == sourceRelativePath
                    }) {
                        catalog.documents[index].relativePath = relativePath(
                            for: destination,
                            relativeTo: destinationRoot
                        )
                    }
                }
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: source, to: destination)
                copiedURLs.append(destination)
            }
            try encodeCatalog(catalog, to: catalogURL)
        } catch {
            for url in copiedURLs {
                try? fileManager.removeItem(at: url)
            }
            throw StoreError.relocationFailed
        }
    }

    private static func availableRelocationURL(
        for proposedURL: URL,
        fileManager: FileManager
    ) -> URL {
        let directory = proposedURL.deletingLastPathComponent()
        let baseName = proposedURL.deletingPathExtension().lastPathComponent
        let pathExtension = proposedURL.pathExtension
        var suffix = 2
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func relativePath(
        for url: URL,
        relativeTo rootURL: URL
    ) -> String {
        let rootPath = normalized(rootURL).path
        let candidatePath = normalized(url).path
        guard candidatePath.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        return String(candidatePath.dropFirst(rootPath.count + 1))
    }

    private func loadCatalog() throws {
        guard fileManager.fileExists(atPath: catalogURL.path) else {
            return
        }
        do {
            catalog = try Self.decodeCatalog(at: catalogURL)
        } catch {
            let backupURL = catalogURL.deletingLastPathComponent()
                .appendingPathComponent(
                    "Catalog.corrupt-\(UUID().uuidString).json"
                )
            try fileManager.moveItem(at: catalogURL, to: backupURL)
            catalog = Catalog()
        }
    }

    private func reconcileCatalogWithDisk() throws {
        let existingURLs = managedDocumentURLs()
        var seenIDs = Set<UUID>()
        var seenPaths = Set<String>()

        for url in existingURLs {
            let path = relativePath(for: url)
            let metadata = TypewriterDocumentPackage.metadata(at: url)
            let index = metadata.flatMap { packageMetadata in
                catalog.documents.firstIndex {
                    $0.id == packageMetadata.documentID
                }
            } ?? catalog.documents.firstIndex {
                $0.relativePath == path
            }

            if let index {
                catalog.documents[index].relativePath = path
                apply(metadata, toDocumentAt: index)
                catalog.documents[index].folderID = folderID(
                    forDocumentURL: url
                )
                seenIDs.insert(catalog.documents[index].id)
            } else {
                let item = makeDocumentItem(for: url, metadata: metadata)
                catalog.documents.append(item)
                seenIDs.insert(item.id)
            }
            seenPaths.insert(path)
        }

        catalog.documents.removeAll {
            !seenIDs.contains($0.id) && !seenPaths.contains($0.relativePath)
        }
        removeMissingFolders()
        normalizeTopLevelItems()
        try persistCatalog()
    }

    private func apply(
        _ metadata: TypewriterDocumentMetadata?,
        toDocumentAt index: Int
    ) {
        guard let metadata else { return }
        catalog.documents[index].title = metadata.title
        catalog.documents[index].titleOverride = metadata.titleOverride
        catalog.documents[index].previewText = metadata.previewText
        catalog.documents[index].pageCount = metadata.pageCount
    }

    private func makeDocumentItem(
        for url: URL,
        metadata: TypewriterDocumentMetadata?
    ) -> LibraryDocumentItem {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return LibraryDocumentItem(
            id: uniqueDocumentID(preferred: metadata?.documentID),
            relativePath: relativePath(for: url),
            createdAt: metadata?.createdAt
                ?? values?.creationDate
                ?? Date(),
            title: metadata?.title
                ?? url.deletingPathExtension().lastPathComponent,
            titleOverride: metadata?.titleOverride,
            previewText: metadata?.previewText ?? "",
            pageCount: metadata?.pageCount ?? 1,
            pinnedAt: nil,
            folderID: folderID(forDocumentURL: url)
        )
    }

    private func folderID(forDocumentURL url: URL) -> UUID? {
        let parent = url.deletingLastPathComponent()
        guard normalized(parent) != normalized(rootURL) else { return nil }
        let path = relativePath(for: parent)
        if let folder = catalog.folders.first(where: {
            $0.relativePath == path
        }) {
            return folder.id
        }
        let values = try? parent.resourceValues(forKeys: [.creationDateKey])
        let folder = LibraryFolder(
            id: UUID(),
            name: parent.lastPathComponent,
            createdAt: values?.creationDate ?? Date(),
            relativePath: path
        )
        catalog.folders.append(folder)
        if !catalog.topLevelItems.contains(.folder(folder.id)) {
            catalog.topLevelItems.append(.folder(folder.id))
        }
        return folder.id
    }

    private func removeMissingFolders() {
        let representedFolderIDs = Set(catalog.documents.compactMap(\.folderID))
        catalog.folders.removeAll { folder in
            let exists = fileManager.fileExists(
                atPath: folderURL(for: folder).path
            )
            return !exists && !representedFolderIDs.contains(folder.id)
        }
    }

    private func normalizeTopLevelItems() {
        let pinnedDocumentIDs = Set(
            catalog.documents.compactMap { document in
                document.pinnedAt == nil ? nil : document.id
            }
        )
        let folderIDs = Set(catalog.folders.map(\.id))
        var seen = Set<LibraryTopLevelItem>()

        catalog.topLevelItems = catalog.topLevelItems.filter { item in
            let exists = switch item.kind {
            case .document:
                pinnedDocumentIDs.contains(item.itemID)
            case .folder:
                folderIDs.contains(item.itemID)
            }
            return exists && seen.insert(item).inserted
        }

        let representedDocuments = Set(
            catalog.topLevelItems
                .filter { $0.kind == .document }
                .map(\.itemID)
        )
        let missingDocuments = catalog.documents
            .filter {
                $0.pinnedAt != nil && !representedDocuments.contains($0.id)
            }
            .sorted {
                ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast)
            }
        catalog.topLevelItems.append(
            contentsOf: missingDocuments.map { .document($0.id) }
        )

        let representedFolders = Set(
            catalog.topLevelItems
                .filter { $0.kind == .folder }
                .map(\.itemID)
        )
        let missingFolders = catalog.folders
            .filter { !representedFolders.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        catalog.topLevelItems.append(
            contentsOf: missingFolders.map { .folder($0.id) }
        )
    }

    private func managedDocumentURLs() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isPackageKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return enumerator.compactMap { element -> URL? in
            guard
                let url = element as? URL,
                url.pathExtension.caseInsensitiveCompare("typewriter")
                    == .orderedSame
            else {
                return nil
            }
            return url
        }
    }

    @discardableResult
    private func registerManagedDocumentIfNeeded(
        at url: URL,
        shouldPersist: Bool = true
    ) throws -> LibraryDocumentItem {
        guard isManagedURL(url) else {
            throw StoreError.unmanagedDocument
        }
        if let existing = document(at: url) {
            return existing
        }
        let metadata = TypewriterDocumentPackage.metadata(at: url)
        if let existing = metadata.flatMap({ packageMetadata in
            catalog.documents.first(where: {
                $0.id == packageMetadata.documentID
            })
        }) {
            return existing
        }
        let item = makeDocumentItem(for: url, metadata: metadata)
        catalog.documents.append(item)
        if shouldPersist {
            try persistAndNotify()
        }
        return item
    }

    private func managedURL(for item: LibraryDocumentItem) -> URL? {
        let candidate = rootURL.appendingPathComponent(item.relativePath)
        return isManagedURL(candidate) ? candidate : nil
    }

    private func folderURL(for folder: LibraryFolder) -> URL {
        rootURL.appendingPathComponent(
            folder.relativePath,
            isDirectory: true
        )
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = normalized(rootURL).path
        let candidatePath = normalized(url).path
        guard candidatePath.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        return String(candidatePath.dropFirst(rootPath.count + 1))
    }

    private func normalized(_ url: URL) -> URL {
        Self.normalized(url)
    }

    private static func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func normalizedFolderName(_ proposedName: String) -> String {
        sanitizedName(proposedName, fallback: "New Folder", maximumLength: 80)
    }

    private func normalizedDocumentTitle(_ proposedTitle: String) -> String {
        sanitizedName(proposedTitle, fallback: "Untitled", maximumLength: 100)
    }

    private func sanitizedName(
        _ proposedName: String,
        fallback: String,
        maximumLength: Int
    ) -> String {
        let forbidden = CharacterSet(charactersIn: "/:")
            .union(.controlCharacters)
            .union(.newlines)
        let cleaned = proposedName.unicodeScalars.map {
            forbidden.contains($0) ? " " : String($0)
        }.joined()
        let collapsed = cleaned
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let trimmed = String(collapsed.prefix(maximumLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." {
            return fallback
        }
        return trimmed
    }

    private func availableURL(
        named proposedName: String,
        in directory: URL,
        pathExtension: String? = nil,
        excluding excludedURL: URL? = nil
    ) -> URL {
        let baseName = pathExtension == nil
            ? normalizedFolderName(proposedName)
            : normalizedDocumentTitle(proposedName)
        var suffix = 1
        while true {
            let candidateName = suffix == 1
                ? baseName
                : "\(baseName) \(suffix)"
            var candidate = directory.appendingPathComponent(candidateName)
            if let pathExtension {
                candidate.appendPathExtension(pathExtension)
            }
            if let excludedURL,
               normalized(candidate) == normalized(excludedURL) {
                return candidate
            }
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private func uniqueDocumentID(preferred: UUID?) -> UUID {
        if let preferred,
           !catalog.documents.contains(where: { $0.id == preferred }) {
            return preferred
        }
        var id = UUID()
        while catalog.documents.contains(where: { $0.id == id }) {
            id = UUID()
        }
        return id
    }

    private func checkStorage() throws {
        if let initializationError {
            throw initializationError
        }
        guard fileManager.fileExists(atPath: rootURL.path) else {
            throw StoreError.storageUnavailable
        }
    }

    private func tryPersistAndComplete(
        _ completion: (Error?) -> Void
    ) {
        do {
            try persistAndNotify()
            completion(nil)
        } catch {
            completion(error)
        }
    }

    private func persistAndNotify() throws {
        try persistCatalog()
        NotificationCenter.default.post(
            name: .documentLibraryDidChange,
            object: self
        )
    }

    private func persistCatalog() throws {
        try fileManager.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encodeCatalog(catalog, to: catalogURL)
    }

    private static func encodeCatalog(
        _ catalog: Catalog,
        to catalogURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(catalog)
        try data.write(to: catalogURL, options: .atomic)
    }

    private static func decodeCatalog(at url: URL) throws -> Catalog {
        guard let catalog = try decodeCatalogIfPresent(at: url) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return catalog
    }

    private static func decodeCatalogIfPresent(
        at url: URL
    ) throws -> Catalog? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Catalog.self, from: data)
    }
}
