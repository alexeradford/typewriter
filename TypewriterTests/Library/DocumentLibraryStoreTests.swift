import AppKit
import Testing
@testable import Typewriter

@MainActor
struct DocumentLibraryStoreTests {
    @Test
    func reservationSummaryPinAndSortSurviveReload() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let reservation = try fixture.store.reserveNewDocument()
        try Data("document".utf8).write(to: reservation.url)
        fixture.store.updateSavedDocument(
            documentID: reservation.item.id,
            currentURL: reservation.url,
            summary: LibraryDocumentSummary(
                title: "Release Notes",
                previewText: "A durable preview",
                pageCount: 3
            )
        )
        try fixture.store.setPinned(true, documentID: reservation.item.id)
        try fixture.store.setSortOrder(.titleWithinDay)

        let reloaded = DocumentLibraryStore(rootURL: fixture.rootURL)
        let document = try #require(
            reloaded.document(withID: reservation.item.id)
        )
        #expect(document.title == "Release Notes")
        #expect(document.previewText == "A durable preview")
        #expect(document.pageCount == 3)
        #expect(document.pinnedAt != nil)
        #expect(
            reloaded.snapshot.topLevelItems
                == [.document(reservation.item.id)]
        )
        #expect(reloaded.snapshot.sortOrder == .titleWithinDay)
    }

    @Test
    func foldersAndPinnedDocumentsShareAPersistedOrder() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let firstDocument = try fixture.store.reserveNewDocument()
        let secondDocument = try fixture.store.reserveNewDocument()
        try Data("first".utf8).write(to: firstDocument.url)
        try Data("second".utf8).write(to: secondDocument.url)
        let folder = try fixture.store.createFolder(named: "Projects")
        try fixture.store.setPinned(true, documentID: firstDocument.item.id)
        try fixture.store.setPinned(true, documentID: secondDocument.item.id)

        try fixture.store.moveTopLevelItem(
            .document(secondDocument.item.id),
            to: 0
        )

        let expectedOrder: [LibraryTopLevelItem] = [
            .document(secondDocument.item.id),
            .folder(folder.id),
            .document(firstDocument.item.id)
        ]
        #expect(fixture.store.snapshot.topLevelItems == expectedOrder)

        try fixture.store.moveTopLevelItem(
            .document(secondDocument.item.id),
            to: 3
        )
        let downwardOrder: [LibraryTopLevelItem] = [
            .folder(folder.id),
            .document(firstDocument.item.id),
            .document(secondDocument.item.id)
        ]
        #expect(fixture.store.snapshot.topLevelItems == downwardOrder)

        let reloaded = DocumentLibraryStore(rootURL: fixture.rootURL)
        #expect(reloaded.snapshot.topLevelItems == downwardOrder)

        try reloaded.setPinned(false, documentID: secondDocument.item.id)
        #expect(
            reloaded.snapshot.topLevelItems
                == [.folder(folder.id), .document(firstDocument.item.id)]
        )
    }

    @Test
    func movingDocumentIntoFolderMovesFileAndCatalogTogether() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let reservation = try fixture.store.reserveNewDocument()
        let contents = Data("folder fixture".utf8)
        try contents.write(to: reservation.url)
        let folder = try fixture.store.createFolder(named: "Research")
        #expect(
            fixture.store.snapshot.topLevelItems == [.folder(folder.id)]
        )

        var moveError: Error?
        fixture.store.moveDocument(
            reservation.item.id,
            toFolder: folder.id
        ) {
            moveError = $0
        }

        #expect(moveError == nil)
        #expect(FileManager.default.fileExists(atPath: reservation.url.path) == false)
        let movedDocument = try #require(
            fixture.store.document(withID: reservation.item.id)
        )
        #expect(movedDocument.folderID == folder.id)
        let movedURL = try #require(fixture.store.url(for: movedDocument))
        #expect(try Data(contentsOf: movedURL) == contents)
    }

    @Test
    func versionOneCatalogMigratesToMixedTopLevelOrder() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let reservation = try fixture.store.reserveNewDocument()
        try Data("migration".utf8).write(to: reservation.url)
        let folder = try fixture.store.createFolder(named: "Archive")
        try fixture.store.setPinned(true, documentID: reservation.item.id)

        let catalogURL = fixture.rootURL
            .appendingPathComponent(".Typewriter", isDirectory: true)
            .appendingPathComponent("Catalog.json")
        let catalogData = try Data(contentsOf: catalogURL)
        var catalog = try #require(
            JSONSerialization.jsonObject(with: catalogData)
                as? [String: Any]
        )
        catalog["version"] = 1
        catalog.removeValue(forKey: "topLevelItems")
        try JSONSerialization.data(
            withJSONObject: catalog,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: catalogURL, options: .atomic)

        let reloaded = DocumentLibraryStore(rootURL: fixture.rootURL)
        #expect(
            Set(reloaded.snapshot.topLevelItems)
                == Set([
                    .document(reservation.item.id),
                    .folder(folder.id)
                ])
        )
    }

    @Test
    func importingExternalDocumentCopiesItIntoManagedStorage() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let externalURL = fixture.rootURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).typewriter")
        let contents = Data("external document".utf8)
        try contents.write(to: externalURL)
        defer { try? FileManager.default.removeItem(at: externalURL) }

        let imported = try fixture.store.importDocument(at: externalURL)

        #expect(imported.copiedIntoLibrary)
        #expect(imported.url != externalURL)
        #expect(fixture.store.isManagedURL(imported.url))
        #expect(try Data(contentsOf: imported.url) == contents)
        #expect(FileManager.default.fileExists(atPath: externalURL.path))
        #expect(fixture.store.document(withID: imported.documentID) != nil)
    }

    @Test
    func renamedDocumentKeepsItsNameAcrossContentUpdatesAndReload() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let reservation = try fixture.store.reserveNewDocument()
        try Data("document".utf8).write(to: reservation.url)
        var renameError: Error?
        fixture.store.renameDocument(
            reservation.item.id,
            to: "  Project Lighthouse  "
        ) {
            renameError = $0
        }
        #expect(renameError == nil)
        let renamedItem = try #require(
            fixture.store.document(withID: reservation.item.id)
        )
        let renamedURL = try #require(
            fixture.store.url(for: renamedItem)
        )
        #expect(renamedURL.lastPathComponent == "Project Lighthouse.typewriter")
        fixture.store.updateSavedDocument(
            documentID: reservation.item.id,
            currentURL: renamedURL,
            summary: LibraryDocumentSummary(
                title: "First line from the editor",
                previewText: "Updated preview",
                pageCount: 2
            )
        )

        let reloaded = DocumentLibraryStore(rootURL: fixture.rootURL)
        let document = try #require(
            reloaded.document(withID: reservation.item.id)
        )
        #expect(document.title == "Project Lighthouse")
        #expect(document.titleOverride == "Project Lighthouse")
        #expect(document.previewText == "Updated preview")
        #expect(document.pageCount == 2)
    }

    @Test
    func reservationsAndContentTitlesUseReadableCollisionSafeNames() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let first = try fixture.store.reserveNewDocument()
        try Data("first".utf8).write(to: first.url)
        let second = try fixture.store.reserveNewDocument()
        try Data("second".utf8).write(to: second.url)

        #expect(first.url.lastPathComponent == "Untitled.typewriter")
        #expect(second.url.lastPathComponent == "Untitled 2.typewriter")

        fixture.store.updateSavedDocument(
            documentID: first.item.id,
            currentURL: first.url,
            summary: LibraryDocumentSummary(
                title: "Release Notes",
                previewText: "",
                pageCount: 1
            )
        )
        let updated = try #require(
            fixture.store.document(withID: first.item.id)
        )
        #expect(
            fixture.store.url(for: updated)?.lastPathComponent
                == "Release Notes.typewriter"
        )
    }

    @Test
    func packageMetadataRebuildsStableIdentityWithoutCatalog() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let documentID = UUID()
        let metadata = TypewriterDocumentMetadata(
            documentID: documentID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            title: "Cross-device Draft",
            titleOverride: "Cross-device Draft",
            previewText: "Shared metadata",
            pageCount: 4
        )
        let wrapper = try TypewriterDocumentPackage.makeFileWrapper(
            content: NSAttributedString(string: "Cross-device Draft"),
            metadata: metadata,
            paperSize: NSPrintInfo().paperSize
        )
        let url = fixture.rootURL.appendingPathComponent(
            "Cross-device Draft.typewriter",
            isDirectory: true
        )
        try wrapper.write(
            to: url,
            options: .atomic,
            originalContentsURL: nil
        )

        let rebuiltRoot = fixture.rootURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Rebuilt-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: rebuiltRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: url,
            to: rebuiltRoot.appendingPathComponent(url.lastPathComponent)
        )
        defer { try? FileManager.default.removeItem(at: rebuiltRoot) }

        let rebuilt = DocumentLibraryStore(rootURL: rebuiltRoot)
        let item = try #require(rebuilt.document(withID: documentID))
        #expect(item.title == "Cross-device Draft")
        #expect(item.previewText == "Shared metadata")
        #expect(item.pageCount == 4)
    }

    @Test
    func legacyUUIDLibraryMigratesToReadablePathsWithoutDeletingSource()
        throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TypewriterLegacyMigration-\(UUID().uuidString)",
                isDirectory: true
            )
        let legacyRoot = parent.appendingPathComponent(
            "Legacy",
            isDirectory: true
        )
        let destinationRoot = parent.appendingPathComponent(
            "Destination",
            isDirectory: true
        )
        let metadataRoot = parent.appendingPathComponent(
            "Metadata",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }

        let documentID = UUID()
        let folderID = UUID()
        let legacyDocumentURL = legacyRoot
            .appendingPathComponent("Folders", isDirectory: true)
            .appendingPathComponent(
                folderID.uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                "\(documentID.uuidString).typewriter"
            )
        try FileManager.default.createDirectory(
            at: legacyDocumentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(to: legacyDocumentURL)
        let catalog: [String: Any] = [
            "version": 3,
            "documents": [[
                "id": documentID.uuidString,
                "relativePath":
                    "Folders/\(folderID.uuidString)/\(documentID.uuidString).typewriter",
                "createdAt": "1970-01-01T00:00:00Z",
                "title": "Research Notes",
                "previewText": "Migrated",
                "pageCount": 2,
                "folderID": folderID.uuidString
            ]],
            "folders": [[
                "id": folderID.uuidString,
                "name": "Projects",
                "createdAt": "1970-01-01T00:00:00Z"
            ]],
            "topLevelItems": [[
                "kind": "folder",
                "itemID": folderID.uuidString
            ]],
            "sortOrder": "newestFirst"
        ]
        try JSONSerialization.data(
            withJSONObject: catalog,
            options: [.prettyPrinted, .sortedKeys]
        ).write(
            to: legacyRoot.appendingPathComponent("Catalog.json"),
            options: .atomic
        )

        let store = DocumentLibraryStore(
            rootURL: destinationRoot,
            catalogURL: metadataRoot.appendingPathComponent("Catalog.json"),
            legacyRootURL: legacyRoot
        )
        let item = try #require(store.document(withID: documentID))
        let migratedURL = try #require(store.url(for: item))

        #expect(
            migratedURL.pathComponents.suffix(2)
                == ["Projects", "Research Notes.typewriter"]
        )
        #expect(FileManager.default.fileExists(atPath: migratedURL.path))
        #expect(
            FileManager.default.fileExists(atPath: legacyDocumentURL.path)
        )
    }

    @Test
    func renamingClosedFolderRenamesItsPhysicalDirectory() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let reservation = try fixture.store.reserveNewDocument()
        try Data("folder rename".utf8).write(to: reservation.url)
        let folder = try fixture.store.createFolder(named: "Projects")
        var moveError: Error?
        fixture.store.moveDocument(
            reservation.item.id,
            toFolder: folder.id
        ) {
            moveError = $0
        }
        #expect(moveError == nil)

        var renameError: Error?
        fixture.store.renameFolder(folder.id, to: "Writing") {
            renameError = $0
        }
        #expect(renameError == nil)
        let item = try #require(
            fixture.store.document(withID: reservation.item.id)
        )
        let url = try #require(fixture.store.url(for: item))
        #expect(
            url.pathComponents.suffix(2)
                == ["Writing", "Untitled.typewriter"]
        )
    }

    @Test
    func deletingDocumentRemovesItsFileCatalogEntryAndPinnedOrder() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let reservation = try fixture.store.reserveNewDocument()
        try Data("document".utf8).write(to: reservation.url)
        try fixture.store.setPinned(
            true,
            documentID: reservation.item.id
        )

        try fixture.store.deleteDocument(reservation.item.id)

        #expect(!FileManager.default.fileExists(atPath: reservation.url.path))
        #expect(
            fixture.store.document(withID: reservation.item.id) == nil
        )
        #expect(
            !fixture.store.snapshot.topLevelItems.contains(
                .document(reservation.item.id)
            )
        )
        let reloaded = DocumentLibraryStore(rootURL: fixture.rootURL)
        #expect(reloaded.document(withID: reservation.item.id) == nil)
    }

    private func makeFixture() throws -> Fixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TypewriterLibraryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = DocumentLibraryStore(rootURL: rootURL)
        if let error = store.initializationError {
            throw error
        }
        return Fixture(rootURL: rootURL, store: store)
    }
}

@MainActor
private struct Fixture {
    let rootURL: URL
    let store: DocumentLibraryStore

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
