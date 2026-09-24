import Foundation

struct MobileLibraryItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let fileURL: URL
    let title: String
    let previewText: String
    let pageCount: Int
    let createdAt: Date
    let modifiedAt: Date
    let folderName: String?
}

actor MobileDocumentLibraryStorage {
    private static let iCloudContainerIdentifier =
        "iCloud.ca.alexradford.Typewriter"

    private let fileManager: FileManager
    private let providedRootURL: URL?
    private var resolvedRootURL: URL?
    private var savedDocuments: [UUID: (revision: Int, fileURL: URL)] = [:]

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        providedRootURL = rootURL
        self.fileManager = fileManager
    }

    func items() throws -> [MobileLibraryItem] {
        let rootURL = try libraryRootURL()
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .creationDateKey,
                .isDirectoryKey,
                .isPackageKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var itemsByID: [UUID: MobileLibraryItem] = [:]
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.caseInsensitiveCompare("typewriter")
                == .orderedSame else {
                continue
            }
            guard let item = try? item(at: fileURL, rootURL: rootURL) else {
                continue
            }
            if let existing = itemsByID[item.id],
               existing.modifiedAt >= item.modifiedAt {
                continue
            }
            itemsByID[item.id] = item
        }
        return itemsByID.values.sorted(by: Self.sortItems)
    }

    func loadDocument(at fileURL: URL) throws -> TypewriterMobileDocument.Snapshot {
        try coordinatedRead(at: fileURL) { coordinatedURL in
            let wrapper = try FileWrapper(
                url: coordinatedURL,
                options: .immediate
            )
            return try TypewriterMobileDocument.decode(wrapper)
        }
    }

    func save(
        _ snapshot: TypewriterMobileDocument.Snapshot,
        currentURL: URL?,
        revision: Int
    ) throws -> URL {
        if let saved = savedDocuments[snapshot.metadata.documentID],
           saved.revision >= revision {
            return saved.fileURL
        }
        let rootURL = try libraryRootURL()
        let fileURL: URL
        if let currentURL,
           isManaged(currentURL, by: rootURL),
           fileManager.fileExists(atPath: currentURL.path) {
            fileURL = currentURL
        } else if let existing = try items().first(where: {
            $0.id == snapshot.metadata.documentID
        }) {
            fileURL = existing.fileURL
        } else {
            fileURL = availableURL(
                named: snapshot.metadata.title,
                in: rootURL
            )
        }
        let wrapper = try TypewriterMobileDocument.fileWrapper(for: snapshot)
        try coordinatedWrite(at: fileURL) { coordinatedURL in
            let originalURL = fileManager.fileExists(atPath: coordinatedURL.path)
                ? coordinatedURL
                : nil
            try wrapper.write(
                to: coordinatedURL,
                options: .atomic,
                originalContentsURL: originalURL
            )
        }
        savedDocuments[snapshot.metadata.documentID] = (revision, fileURL)
        return fileURL
    }

    func importDocument(at sourceURL: URL) throws -> URL {
        let rootURL = try libraryRootURL()
        if isManaged(sourceURL, by: rootURL) {
            _ = try loadDocument(at: sourceURL)
            return sourceURL
        }

        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let snapshot = try loadDocument(at: sourceURL)
        if let existing = try items().first(where: {
            $0.id == snapshot.metadata.documentID
        }) {
            return existing.fileURL
        }
        return try save(snapshot, currentURL: nil, revision: 0)
    }

    func delete(_ item: MobileLibraryItem) throws {
        let rootURL = try libraryRootURL()
        guard isManaged(item.fileURL, by: rootURL) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try coordinatedDelete(at: item.fileURL) { coordinatedURL in
            try fileManager.removeItem(at: coordinatedURL)
        }
        savedDocuments[item.id] = nil
    }

    private func libraryRootURL() throws -> URL {
        if let resolvedRootURL {
            return resolvedRootURL
        }

        let rootURL: URL
        if let providedRootURL {
            rootURL = providedRootURL
        } else if fileManager.ubiquityIdentityToken != nil,
                  let containerURL = fileManager.url(
                    forUbiquityContainerIdentifier:
                        Self.iCloudContainerIdentifier
                  ) {
            rootURL = containerURL.appendingPathComponent(
                "Documents",
                isDirectory: true
            )
        } else {
            let applicationSupportURL = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            rootURL = applicationSupportURL
                .appendingPathComponent("Typewriter", isDirectory: true)
                .appendingPathComponent("Documents", isDirectory: true)
        }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        resolvedRootURL = rootURL
        return rootURL
    }

    private func item(
        at fileURL: URL,
        rootURL: URL
    ) throws -> MobileLibraryItem {
        let snapshot = try loadDocument(at: fileURL)
        let values = try? fileURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey
        ])
        let parentURL = fileURL.deletingLastPathComponent()
        let folderName = normalized(parentURL) == normalized(rootURL)
            ? nil
            : parentURL.lastPathComponent
        return MobileLibraryItem(
            id: snapshot.metadata.documentID,
            fileURL: fileURL,
            title: snapshot.metadata.title,
            previewText: snapshot.metadata.previewText,
            pageCount: snapshot.metadata.pageCount,
            createdAt: snapshot.metadata.createdAt,
            modifiedAt: values?.contentModificationDate
                ?? values?.creationDate
                ?? snapshot.metadata.createdAt,
            folderName: folderName
        )
    }

    private func availableURL(named proposedTitle: String, in rootURL: URL) -> URL {
        let title = sanitizedTitle(proposedTitle)
        var suffix = 1
        while true {
            let candidateTitle = suffix == 1 ? title : "\(title) \(suffix)"
            let candidateURL = rootURL
                .appendingPathComponent(candidateTitle)
                .appendingPathExtension("typewriter")
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            suffix += 1
        }
    }

    private func sanitizedTitle(_ proposedTitle: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:")
            .union(.controlCharacters)
            .union(.newlines)
        let cleaned = proposedTitle.unicodeScalars.map {
            forbidden.contains($0) ? " " : String($0)
        }.joined()
        let collapsed = cleaned
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        let title = String(collapsed.prefix(100))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled" : title
    }

    private func isManaged(_ fileURL: URL, by rootURL: URL) -> Bool {
        let rootPath = normalized(rootURL).path
        let filePath = normalized(fileURL).path
        return filePath.hasPrefix(rootPath + "/")
    }

    private func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func coordinatedRead<T>(
        at fileURL: URL,
        body: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: fileURL,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try body(coordinatedURL) }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }
        return try result.get()
    }

    private func coordinatedWrite(
        at fileURL: URL,
        body: (URL) throws -> Void
    ) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: fileURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try body(coordinatedURL)
            } catch {
                writeError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    private func coordinatedDelete(
        at fileURL: URL,
        body: (URL) throws -> Void
    ) throws {
        var coordinationError: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: fileURL,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try body(coordinatedURL)
            } catch {
                deleteError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let deleteError {
            throw deleteError
        }
    }

    private static func sortItems(
        _ lhs: MobileLibraryItem,
        _ rhs: MobileLibraryItem
    ) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt > rhs.modifiedAt
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
