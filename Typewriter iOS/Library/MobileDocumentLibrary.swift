import Foundation
import Observation

@MainActor
@Observable
final class MobileDocumentLibrary {
    private(set) var items: [MobileLibraryItem] = []
    private(set) var isLoading = true
    var selectedDocument: TypewriterMobileDocument?
    var errorMessage: String?

    private let storage: MobileDocumentLibraryStorage
    private var hasStarted = false

    init(storage: MobileDocumentLibraryStorage = MobileDocumentLibraryStorage()) {
        self.storage = storage
        selectedDocument = TypewriterMobileDocument()
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await storage.items()
        } catch {
            present(error)
        }
    }

    func newDocument() {
        selectedDocument = TypewriterMobileDocument()
    }

    func open(_ item: MobileLibraryItem) async {
        do {
            let snapshot = try await storage.loadDocument(at: item.fileURL)
            selectedDocument = TypewriterMobileDocument(
                snapshot: snapshot,
                fileURL: item.fileURL
            )
        } catch {
            present(error)
        }
    }

    func save(_ document: TypewriterMobileDocument) async {
        guard document.hasUnsavedChanges else { return }
        let revision = document.revision
        let snapshot = document.snapshot()
        do {
            let fileURL = try await storage.save(
                snapshot,
                currentURL: document.fileURL,
                revision: revision
            )
            document.markSaved(at: fileURL, revision: revision)
            upsertItem(
                snapshot: snapshot,
                fileURL: fileURL,
                modifiedAt: Date()
            )
        } catch {
            present(error)
        }
    }

    func importAndOpen(_ fileURL: URL) async {
        do {
            let importedURL = try await storage.importDocument(at: fileURL)
            let snapshot = try await storage.loadDocument(at: importedURL)
            selectedDocument = TypewriterMobileDocument(
                snapshot: snapshot,
                fileURL: importedURL
            )
            await refresh()
        } catch {
            present(error)
        }
    }

    func delete(_ item: MobileLibraryItem) async {
        do {
            try await storage.delete(item)
            items.removeAll { $0.id == item.id }
            if selectedDocument?.id == item.id {
                newDocument()
            }
        } catch {
            present(error)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func upsertItem(
        snapshot: TypewriterMobileDocument.Snapshot,
        fileURL: URL,
        modifiedAt: Date
    ) {
        let item = MobileLibraryItem(
            id: snapshot.metadata.documentID,
            fileURL: fileURL,
            title: snapshot.metadata.title,
            previewText: snapshot.metadata.previewText,
            pageCount: snapshot.metadata.pageCount,
            createdAt: snapshot.metadata.createdAt,
            modifiedAt: modifiedAt,
            folderName: items.first { $0.id == snapshot.metadata.documentID }?
                .folderName
        )
        items.removeAll { $0.id == item.id }
        items.append(item)
        items.sort {
            if $0.modifiedAt != $1.modifiedAt {
                return $0.modifiedAt > $1.modifiedAt
            }
            return $0.title.localizedStandardCompare($1.title)
                == .orderedAscending
        }
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
    }
}
