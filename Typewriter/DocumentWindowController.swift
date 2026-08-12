import AppKit
import UniformTypeIdentifiers

final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    let editor: EditorViewController

    private var documentToolbarController: DocumentToolbarController!
    private let librarySidebar = LibrarySidebarViewController()
    private let splitViewController = NSSplitViewController()
    private var isReplacingDocument = false
    private var documentViewStates: [UUID: EditorDocumentViewState] = [:]

    init(documentContent: NSAttributedString, printInfo: NSPrintInfo) {
        editor = EditorViewController(
            documentContent: documentContent,
            pageLayout: EditorPageLayout(printInfo: printInfo)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        documentToolbarController = DocumentToolbarController(editor: editor)
        documentToolbarController.quickPrintHandler = { [weak self] in
            (self?.document as? Document)?.quickPrint()
        }
        documentToolbarController.testPrintAnimationHandler = { [weak editor] in
            editor?.animatePageEjection {}
        }
        documentToolbarController.insertImageHandler = { [weak self] in
            self?.insertImage(nil)
        }
        documentToolbarController.insertTableHandler = { [weak self] in
            self?.insertTable(nil)
        }
        documentToolbarController.restoreEditorFocus = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.editor.textView)
        }
        librarySidebar.openDocumentHandler = { [weak self] document, disposition in
            self?.openLibraryDocument(document, disposition: disposition)
        }
        librarySidebar.deleteDocumentHandler = { [weak self] document in
            self?.deleteLibraryDocument(document)
        }

        window.title = "Untitled"
        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: librarySidebar
        )
        sidebarItem.minimumThickness = 240
        sidebarItem.maximumThickness = 360
        sidebarItem.preferredThicknessFraction = 0.27
        sidebarItem.canCollapse = true
        let editorItem = NSSplitViewItem(viewController: editor)
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(editorItem)

        window.contentViewController = splitViewController
        window.toolbar = documentToolbarController.makeToolbar()
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.delegate = self
        window.minSize = NSSize(width: 940, height: 560)
        window.tabbingMode = .disallowed
        window.isRestorable = false

        editor.selectionDidChange = { [weak self] in
            self?.documentToolbarController.refreshSelectionState()
        }
        editor.contentDidChange = { [weak self] in
            (self?.document as? Document)?.editorContentDidChange()
        }
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.makeFirstResponder(editor.textView)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        documentToolbarController.refreshSelectionState()
        setActiveLibraryDocument(url: document?.fileURL)
    }

    func setActiveLibraryDocument(url: URL?) {
        librarySidebar.setActiveDocument(url: url)
    }

    func refreshDocumentTitle() {
        synchronizeWindowTitleWithDocumentName()
    }

    func replaceDocumentContent(
        _ content: NSAttributedString,
        printInfo: NSPrintInfo,
        documentURL: URL?
    ) {
        let documentID = documentURL.flatMap {
            DocumentLibraryStore.shared.document(at: $0)?.id
        }
        editor.replaceDocumentContent(
            content,
            pageLayout: EditorPageLayout(printInfo: printInfo),
            restoring: documentID.flatMap { documentViewStates[$0] }
        )
        documentToolbarController.refreshSelectionState()
    }

    override func windowTitle(
        forDocumentDisplayName displayName: String
    ) -> String {
        (document as? Document)?.libraryDisplayTitle ?? displayName
    }

    private func openLibraryDocument(
        _ item: LibraryDocumentItem,
        disposition: LibraryDocumentOpenDisposition
    ) {
        guard
            let targetURL = DocumentLibraryStore.shared.url(for: item),
            targetURL.standardizedFileURL != document?.fileURL?.standardizedFileURL
        else {
            return
        }

        switch disposition {
        case .replaceCurrent:
            replaceCurrentDocument(with: targetURL)
        case .newTab:
            openDocumentInNewTab(at: targetURL)
        }
    }

    private func deleteLibraryDocument(_ item: LibraryDocumentItem) {
        guard
            !isReplacingDocument,
            let targetURL = DocumentLibraryStore.shared.url(for: item),
            let sourceWindow = window
        else {
            return
        }

        let isCurrentDocument =
            targetURL.standardizedFileURL
            == document?.fileURL?.standardizedFileURL
        if isCurrentDocument {
            guard let sourceDocument = document as? Document else { return }
            isReplacingDocument = true
            do {
                guard let replacement = try NSDocumentController.shared
                    .openUntitledDocumentAndDisplay(false) as? Document
                else {
                    isReplacingDocument = false
                    return
                }
                replacement.adoptWindowControllerForLibraryNavigation(self)
                sourceDocument.updateChangeCount(.changeCleared)
                sourceDocument.close()
                isReplacingDocument = false
                deleteClosedLibraryDocument(item, in: sourceWindow)
                focusEditor()
            } catch {
                isReplacingDocument = false
                sourceWindow.presentError(error)
            }
            return
        }

        if let openDocument = NSDocumentController.shared.document(
            for: targetURL
        ) {
            openDocument.updateChangeCount(.changeCleared)
            openDocument.close()
        }
        deleteClosedLibraryDocument(item, in: sourceWindow)
    }

    private func deleteClosedLibraryDocument(
        _ item: LibraryDocumentItem,
        in window: NSWindow
    ) {
        do {
            try DocumentLibraryStore.shared.deleteDocument(item.id)
        } catch {
            window.presentError(error)
        }
    }

    private func replaceCurrentDocument(with targetURL: URL) {
        guard
            !isReplacingDocument,
            let sourceDocument = document as? Document,
            let sourceWindow = window
        else {
            return
        }
        isReplacingDocument = true
        rememberCurrentDocumentViewState()

        sourceDocument.saveBeforeLibraryNavigation { [weak self] error in
            if let error {
                self?.isReplacingDocument = false
                sourceWindow.presentError(error)
                return
            }

            NSDocumentController.shared.openDocument(
                withContentsOf: targetURL,
                display: false
            ) { targetDocument, wasAlreadyOpen, error in
                if let error {
                    self?.isReplacingDocument = false
                    sourceWindow.presentError(error)
                    return
                }
                guard
                    let self,
                    let targetDocument = targetDocument as? Document
                else {
                    self?.isReplacingDocument = false
                    return
                }

                if wasAlreadyOpen,
                   let existingController = targetDocument
                    .windowControllers.first as? DocumentWindowController,
                   let existingWindow = existingController.window {
                    self.isReplacingDocument = false
                    targetDocument.showWindows()
                    existingWindow.makeKeyAndOrderFront(nil)
                    existingController.focusLibrarySidebar()
                    return
                }

                targetDocument.adoptWindowControllerForLibraryNavigation(self)
                sourceDocument.close()
                self.isReplacingDocument = false
                self.focusLibrarySidebar()
            }
        }
    }

    func createNewLibraryDocument() {
        guard
            !isReplacingDocument,
            let sourceDocument = document as? Document,
            let sourceWindow = window
        else {
            return
        }
        isReplacingDocument = true
        rememberCurrentDocumentViewState()

        sourceDocument.saveBeforeLibraryNavigation { [weak self] error in
            guard let self else { return }
            if let error {
                isReplacingDocument = false
                sourceWindow.presentError(error)
                return
            }

            do {
                guard let targetDocument = try NSDocumentController.shared
                    .openUntitledDocumentAndDisplay(false) as? Document
                else {
                    isReplacingDocument = false
                    return
                }
                targetDocument.adoptWindowControllerForLibraryNavigation(self)
                sourceDocument.close()
                isReplacingDocument = false
                focusEditor()
            } catch {
                isReplacingDocument = false
                sourceWindow.presentError(error)
            }
        }
    }

    private func rememberCurrentDocumentViewState() {
        guard
            let currentDocument = document as? Document,
            let url = currentDocument.fileURL,
            let documentID = DocumentLibraryStore.shared.document(at: url)?.id
        else {
            return
        }
        documentViewStates[documentID] = editor.documentViewState
    }

    private func focusLibrarySidebar() {
        librarySidebar.focusSelection()
    }

    private func focusEditor() {
        window?.makeFirstResponder(editor.textView)
    }

    private func openDocumentInNewTab(at targetURL: URL) {
        guard let sourceWindow = window else { return }
        NSDocumentController.shared.openDocument(
            withContentsOf: targetURL,
            display: false
        ) { targetDocument, _, error in
            if let error {
                sourceWindow.presentError(error)
                return
            }
            guard let targetDocument else { return }
            if targetDocument.windowControllers.isEmpty {
                targetDocument.makeWindowControllers()
            }
            guard
                let targetWindow = targetDocument.windowControllers.first?.window,
                targetWindow !== sourceWindow
            else {
                return
            }
            sourceWindow.addTabbedWindow(targetWindow, ordered: .above)
            targetWindow.makeKeyAndOrderFront(nil)
        }
    }

    @objc func toggleBold(_ sender: Any?) {
        editor.toggleTrait(.boldFontMask)
        finishFormattingCommand()
    }

    @objc func toggleItalic(_ sender: Any?) {
        editor.toggleTrait(.italicFontMask)
        finishFormattingCommand()
    }

    @objc func toggleUnderline(_ sender: Any?) {
        editor.toggleUnderline()
        finishFormattingCommand()
    }

    @objc func toggleBulletedList(_ sender: Any?) {
        editor.textSystem.listController.toggleList(.bullet)
        finishFormattingCommand()
    }

    @objc func toggleNumberedList(_ sender: Any?) {
        editor.textSystem.listController.toggleList(.numbered)
        finishFormattingCommand()
    }

    @objc func toggleChecklist(_ sender: Any?) {
        editor.textSystem.listController.toggleList(.checklist)
        finishFormattingCommand()
    }

    @objc func toggleChecklistItem(_ sender: Any?) {
        guard editor.textSystem.listController.toggleChecklistAtSelection() else {
            NSSound.beep()
            return
        }
        finishFormattingCommand()
    }

    @objc func toggleCodeBlock(_ sender: Any?) {
        editor.toggleCodeBlock()
        finishFormattingCommand()
    }

    @objc func insertDivider(_ sender: Any?) {
        editor.insertDivider()
        finishFormattingCommand()
    }

    @objc func insertImage(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Insert"
        panel.message = "Choose one or more images to insert into the document."
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard
                response == .OK,
                let self,
                let urls = panel?.urls,
                !urls.isEmpty
            else {
                return
            }

            let scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            }
            do {
                try editor.insertImages(from: urls)
                finishFormattingCommand()
            } catch {
                window.presentError(error)
            }
        }
    }

    @objc func insertTable(_ sender: Any?) {
        editor.insertTable(sender)
        finishFormattingCommand()
    }

    private func finishFormattingCommand() {
        documentToolbarController.refreshSelectionState()
        window?.makeFirstResponder(editor.textView)
    }
}
