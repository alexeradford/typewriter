import AppKit

final class LibraryDocumentController: NSDocumentController {
    private let library: DocumentLibraryStore

    init(library: DocumentLibraryStore = .shared) {
        self.library = library
        super.init()
    }

    required init?(coder: NSCoder) {
        library = .shared
        super.init(coder: coder)
    }

    override func typeForContents(
        of url: URL
    ) throws -> String {
        // File providers can report an app document package as public.folder
        // until Launch Services has downloaded or indexed it. The extension is
        // part of Typewriter's on-disk format, so resolve it deterministically.
        if url.pathExtension.caseInsensitiveCompare("typewriter")
            == .orderedSame {
            return Document.typeIdentifier
        }
        return try super.typeForContents(of: url)
    }

    override func newDocument(_ sender: Any?) {
        let activeWindowController =
            (currentDocument?.windowControllers.first {
                $0.window?.isKeyWindow == true
            } as? DocumentWindowController)
            ?? documents.lazy
                .flatMap(\.windowControllers)
                .first {
                    $0.window?.isVisible == true
                } as? DocumentWindowController

        guard let activeWindowController else {
            super.newDocument(sender)
            return
        }
        activeWindowController.createNewLibraryDocument()
    }

    override func makeUntitledDocument(
        ofType typeName: String
    ) throws -> NSDocument {
        let document = try super.makeUntitledDocument(ofType: typeName)
        let reservation = try library.reserveNewDocument()
        document.fileType = typeName
        document.fileURL = reservation.url
        document.isDraft = false
        document.displayName = reservation.item.title
        return document
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        let imported: LibraryImport
        do {
            imported = try library.importDocument(at: url)
        } catch {
            completionHandler(nil, false, error)
            return
        }

        super.openDocument(
            withContentsOf: imported.url,
            display: displayDocument
        ) { [weak self] document, wasAlreadyOpen, error in
            if error != nil {
                self?.library.discardFailedImport(imported)
            }
            completionHandler(document, wasAlreadyOpen, error)
        }
    }
}
