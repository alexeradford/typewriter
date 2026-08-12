import AppKit

private final class DocumentContentStore: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var wrapper: FileWrapper?

    nonisolated func replace(with wrapper: FileWrapper) {
        lock.lock()
        self.wrapper = wrapper
        lock.unlock()
    }

    nonisolated func snapshot() -> FileWrapper? {
        lock.lock()
        defer { lock.unlock() }
        return wrapper
    }
}

final class Document: NSDocument {
    static let typeIdentifier = "ca.alexradford.typewriter-document"

    private let contentStore = DocumentContentStore()
    private var isQuickPrinting = false
    private var libraryDocumentID: UUID?
    private var pendingAutosave: Task<Void, Never>?
    private var isInitialLibrarySaveScheduled = false
    private var loadedMetadata: TypewriterDocumentMetadata?
    private(set) var libraryDisplayTitle = "Untitled"

    override init() {
        super.init()
        printInfo.paperSize = PrintPreferences.defaultPaperSize.size
    }

    override nonisolated class var autosavesInPlace: Bool { true }

    override func close() {
        pendingAutosave?.cancel()
        pendingAutosave = nil
        super.close()
    }

    override func makeWindowControllers() {
        let content = editorContentForPresentation()
        updateLibraryIdentity()
        let controller = DocumentWindowController(
            documentContent: content,
            printInfo: printInfo
        )
        addWindowController(controller)
        controller.setActiveLibraryDocument(url: fileURL)
        updateLibraryPresentation()
        ensureInitialLibrarySave()
    }

    func adoptWindowControllerForLibraryNavigation(
        _ controller: DocumentWindowController
    ) {
        let content = editorContentForPresentation()
        updateLibraryIdentity()

        // NSDocument's implementation detaches the controller from its previous
        // document before assigning it to this one.
        addWindowController(controller)
        controller.replaceDocumentContent(
            content,
            printInfo: printInfo,
            documentURL: fileURL
        )
        controller.setActiveLibraryDocument(url: fileURL)
        updateLibraryPresentation()
        ensureInitialLibrarySave()
    }

    override func data(ofType typeName: String) throws -> Data {
        let content = documentWindowController?.editor.attributedContent ?? Self.newDocumentContent()
        return try content.data(
            from: NSRange(location: 0, length: content.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtfd,
                .paperSize: printInfo.paperSize,
                .leftMargin: EditorPageLayout.margin,
                .rightMargin: EditorPageLayout.margin,
                .topMargin: EditorPageLayout.margin,
                .bottomMargin: EditorPageLayout.margin
            ]
        )
    }

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        let content = documentWindowController?.editor.attributedContent
            ?? Self.newDocumentContent()
        let summary = librarySummary
        let libraryItem = libraryDocumentID.flatMap(
            DocumentLibraryStore.shared.document(withID:)
        )
        let metadata = TypewriterDocumentMetadata(
            documentID: loadedMetadata?.documentID
                ?? libraryItem?.id
                ?? UUID(),
            createdAt: loadedMetadata?.createdAt
                ?? libraryItem?.createdAt
                ?? Date(),
            title: summary.title,
            titleOverride: libraryItem?.titleOverride
                ?? loadedMetadata?.titleOverride,
            previewText: summary.previewText,
            pageCount: summary.pageCount
        )
        return try TypewriterDocumentPackage.makeFileWrapper(
            content: content,
            metadata: metadata,
            paperSize: printInfo.paperSize
        )
    }

    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        let wrapper = FileWrapper(regularFileWithContents: data)
        guard TypewriterDocumentPackage.decode(wrapper) != nil else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "This Typewriter document is damaged or uses an unsupported format."
            ])
        }
        contentStore.replace(with: wrapper)
    }

    override nonisolated func read(
        from fileWrapper: FileWrapper,
        ofType typeName: String
    ) throws {
        guard TypewriterDocumentPackage.decode(fileWrapper) != nil else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey:
                    "This Typewriter document is damaged or uses an unsupported format."
            ])
        }
        contentStore.replace(with: fileWrapper)
    }

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let summary = librarySummary
        super.save(
            to: url,
            ofType: typeName,
            for: saveOperation
        ) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else {
                    completionHandler(error)
                    return
                }
                if error == nil {
                    updateLibraryRecord(with: summary)
                }
                completionHandler(error)
            }
        }
    }

    func quickPrint() {
        guard !isQuickPrinting, let controller = documentWindowController else { return }
        isQuickPrinting = true

        let performPrint = { [weak self, weak controller] in
            guard let self, let controller else { return }
            let operation = controller.editor.makePrintOperation(printInfo: PrintPreferences.configuredPrintInfo(from: printInfo))
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            operation.jobTitle = displayName
            let succeeded = operation.run()
            isQuickPrinting = false
            controller.editor.showPrintResult(succeeded: succeeded)
        }

        if PrintPreferences.shouldAnimatePrint {
            controller.editor.animatePageEjection(completion: performPrint)
        } else {
            performPrint()
        }
    }

    func printShowingPanel() {
        guard let editor = documentWindowController?.editor else { return }
        let operation = editor.makePrintOperation(printInfo: PrintPreferences.configuredPrintInfo(from: printInfo))
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.jobTitle = displayName
        operation.run()
    }

    func pageLayoutDidChange() {
        documentWindowController?.editor.updatePageLayout(
            EditorPageLayout(printInfo: printInfo)
        )
        updateChangeCount(.changeDone)
        scheduleLibraryAutosave()
    }

    func editorContentDidChange() {
        updateChangeCount(.changeDone)
        updateLibraryPresentation()
        scheduleLibraryAutosave()
    }

    func saveBeforeLibraryNavigation(
        completionHandler: @escaping (Error?) -> Void
    ) {
        pendingAutosave?.cancel()
        pendingAutosave = nil
        autosave(
            withImplicitCancellability: false,
            completionHandler: completionHandler
        )
    }

    func libraryMetadataDidChange() {
        updateLibraryIdentity()
        documentWindowController?.setActiveLibraryDocument(url: fileURL)
        documentWindowController?.refreshDocumentTitle()
        autosave(withImplicitCancellability: false) { [weak self] error in
            guard let error else { return }
            self?.documentWindowController?.window?.presentError(error)
        }
    }

    private var documentWindowController: DocumentWindowController? {
        windowControllers.first as? DocumentWindowController
    }

    private func editorContentForPresentation() -> NSAttributedString {
        let decoded = contentStore.snapshot().flatMap(
            TypewriterDocumentPackage.decode
        )
        loadedMetadata = decoded?.metadata
        if let paperSize = decoded?
            .documentAttributes?[NSAttributedString.DocumentAttributeKey.paperSize]
            as? NSSize {
            printInfo.paperSize = paperSize
        }
        return decoded?.content ?? Self.newDocumentContent()
    }

    private func updateLibraryIdentity() {
        let libraryItem = fileURL.flatMap { url in
            if let loadedMetadata {
                return DocumentLibraryStore.shared.reconcilePackageMetadata(
                    loadedMetadata,
                    at: url
                )
            }
            return DocumentLibraryStore.shared.document(at: url)
        }
        libraryDocumentID = libraryItem?.id
        if let title = libraryItem?.title {
            libraryDisplayTitle = title
            displayName = title
        }
    }

    private var librarySummary: LibraryDocumentSummary {
        guard let editor = documentWindowController?.editor else {
            return LibraryDocumentSummary(
                title: displayName,
                previewText: "",
                pageCount: 1
            )
        }

        let cleaned = editor.attributedContent.string
            .replacingOccurrences(of: EditorBlockStyle.dividerMarker, with: "")
            .replacingOccurrences(of: "\u{FFFC}", with: " ")
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        let inferredTitle = lines.first.map {
            String($0.prefix(100))
        } ?? "Untitled"
        let title = libraryDocumentID
            .flatMap(DocumentLibraryStore.shared.document(withID:))?
            .titleOverride ?? inferredTitle
        let previewText = lines
            .dropFirst()
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return LibraryDocumentSummary(
            title: title,
            previewText: String(previewText.prefix(180)),
            pageCount: editor.numberOfPages
        )
    }

    private func updateLibraryPresentation() {
        let summary = librarySummary
        libraryDisplayTitle = summary.title
        displayName = summary.title
        documentWindowController?.refreshDocumentTitle()
    }

    private func scheduleLibraryAutosave() {
        pendingAutosave?.cancel()
        pendingAutosave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            autosave(
                withImplicitCancellability: true
            ) { [weak self] error in
                guard let error else { return }
                self?.documentWindowController?.window?.presentError(error)
            }
        }
    }

    private func ensureInitialLibrarySave() {
        guard
            let libraryDocumentID,
            let fileURL,
            DocumentLibraryStore.shared.isManagedURL(fileURL),
            !FileManager.default.fileExists(atPath: fileURL.path),
            !isInitialLibrarySaveScheduled
        else {
            if let libraryDocumentID, let fileURL {
                DocumentLibraryStore.shared.updateSavedDocument(
                    documentID: libraryDocumentID,
                    currentURL: fileURL,
                    summary: librarySummary
                ) { [weak self] error in
                    guard let error else { return }
                    self?.documentWindowController?.window?.presentError(error)
                }
            }
            return
        }

        isInitialLibrarySaveScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            save(
                to: fileURL,
                ofType: fileType ?? Self.typeIdentifier,
                for: .saveOperation
            ) { [weak self] error in
                self?.isInitialLibrarySaveScheduled = false
                guard let error else { return }
                DocumentLibraryStore.shared.discardReservation(
                    documentID: libraryDocumentID
                )
                self?.documentWindowController?.window?.presentError(error)
            }
        }
    }

    private func updateLibraryRecord(with summary: LibraryDocumentSummary) {
        guard let libraryDocumentID, let fileURL else { return }
        libraryDisplayTitle = summary.title
        displayName = summary.title
        DocumentLibraryStore.shared.updateSavedDocument(
            documentID: libraryDocumentID,
            currentURL: fileURL,
            summary: summary
        ) { [weak self] error in
            guard let self else { return }
            if let error {
                documentWindowController?.window?.presentError(error)
                return
            }
            documentWindowController?.setActiveLibraryDocument(url: self.fileURL)
            documentWindowController?.refreshDocumentTitle()
        }
    }

    private static func newDocumentContent() -> NSAttributedString {
        NSAttributedString(
            string: "",
            attributes: EditorTextSystem.defaultTypingAttributes
        )
    }
}
