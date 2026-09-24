import Foundation
import Testing
@testable import Typewriter_iOS

@Suite("iOS document library storage")
@MainActor
struct MobileDocumentLibraryStorageTests {
    @Test("Library saves, discovers, reopens, and deletes packages")
    func libraryRoundTrip() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Typewriter-Mobile-Library-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let storage = MobileDocumentLibraryStorage(rootURL: rootURL)
        let document = TypewriterMobileDocument()
        document.updateEditorContent(
            NSAttributedString(string: "A library document\nFirst version"),
            pageCount: 2
        )
        let firstRevision = document.revision
        let firstSnapshot = document.snapshot()

        let fileURL = try await storage.save(
            firstSnapshot,
            currentURL: nil,
            revision: firstRevision
        )
        let firstItems = try await storage.items()
        let firstItem = try #require(firstItems.first)
        #expect(firstItems.count == 1)
        #expect(firstItem.id == document.id)
        #expect(firstItem.title == "A library document")
        #expect(firstItem.pageCount == 2)

        document.updateEditorContent(
            NSAttributedString(string: "Updated title\nLatest version"),
            pageCount: 3
        )
        let latestSnapshot = document.snapshot()
        _ = try await storage.save(
            latestSnapshot,
            currentURL: fileURL,
            revision: document.revision
        )

        _ = try await storage.save(
            firstSnapshot,
            currentURL: fileURL,
            revision: firstRevision
        )
        let reopened = try await storage.loadDocument(at: fileURL)
        #expect(reopened.content.string == "Updated title\nLatest version")
        #expect(reopened.metadata.pageCount == 3)

        try await storage.delete(firstItem)
        #expect(try await storage.items().isEmpty)
    }

    @Test("Untouched launch draft is not added to the library")
    func pristineDraftIsNotSaved() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Typewriter-Pristine-Draft-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let storage = MobileDocumentLibraryStorage(rootURL: rootURL)
        let library = MobileDocumentLibrary(storage: storage)
        await library.start()
        let draft = try #require(library.selectedDocument)

        await library.save(draft)

        #expect(library.items.isEmpty)
        #expect(try await storage.items().isEmpty)
    }
}
