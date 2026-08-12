import AppKit

struct EditorDocumentViewState {
    let selectedRange: NSRange
    let scrollOrigin: NSPoint
}

final class EditorViewController: NSViewController, NSTextViewDelegate {
    let textSystem: EditorTextSystem

    var textView: EditorTextView { textSystem.textView }

    private let pageView: PageCanvasView
    private let documentCanvas: EditorScrollDocumentView
    private let scrollView = NSScrollView()
    private let countLabel = NSTextField(labelWithString: "0 words")
    private let printerLabel = NSTextField(labelWithString: "")
    private let statusMessage = NSTextField(labelWithString: "")
    private var contentWasLoaded = false
    private var isAnimatingPageEjection = false
    private var pageEjectionCompletions: [() -> Void] = []
    private var pageLayout: EditorPageLayout
    private var pageCapacity = 8
    private var geometryUpdateIsScheduled = false
    private var revealPageTransitionWhenUpdatingGeometry = false
    private var isReplacingDocumentContent = false

    var selectionDidChange: (() -> Void)?
    var contentDidChange: (() -> Void)?

    var attributedContent: NSAttributedString {
        textSystem.attributedContent
    }

    var currentAttributes: [NSAttributedString.Key: Any] {
        textSystem.formattingController.currentAttributes
    }

    var numberOfPages: Int {
        pageView.pageCount
    }

    var documentViewState: EditorDocumentViewState {
        EditorDocumentViewState(
            selectedRange: textView.selectedRange(),
            scrollOrigin: scrollView.contentView.bounds.origin
        )
    }

    init(documentContent: NSAttributedString, pageLayout: EditorPageLayout) {
        let textSystem = EditorTextSystem(
            content: documentContent,
            containerWidth: pageLayout.contentSize.width
        )
        self.textSystem = textSystem
        self.pageLayout = pageLayout
        pageView = PageCanvasView(
            textView: textSystem.textView,
            pageLayout: pageLayout
        )
        documentCanvas = EditorScrollDocumentView(pageView: pageView)
        super.init(nibName: nil, bundle: nil)
        textSystem.configurePageLayout(
            pageLayout,
            pageCapacity: pageCapacity
        )

        textSystem.blockController.selectionStateDidChange = { [weak self] in
            self?.selectionDidChange?()
        }
        textSystem.formattingController.selectionStateDidChange = {
            [weak self] in
            self?.selectionDidChange?()
        }
        textSystem.contentInsertionController.layoutDidChange = { [weak self] in
            self?.scheduleDocumentGeometryUpdate()
        }
        textSystem.didEnterCompatibilityMode = {
            assertionFailure(
                "The editor unexpectedly entered TextKit 1 compatibility mode. "
                    + "Do not access NSTextView.layoutManager."
            )
        }
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = CanvasBackgroundView(frame: NSRect(x: 0, y: 0, width: 980, height: 730))
        root.autoresizingMask = [.width, .height]
        view = root

        // Reserve space at the bottom for the status overlay; combined with
        // automaticallyAdjustsContentInsets this keeps the page clear of both the
        // title bar (top) and the word-count row (bottom).
        root.additionalSafeAreaInsets = NSEdgeInsets(top: 0, left: 0, bottom: 26, right: 0)

        configureTextView()
        configureScrollView()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)
        configureStatusOverlay(in: root)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(printPreferencesChanged(_:)),
            name: PrintPreferences.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(generalPreferencesChanged(_:)),
            name: GeneralPreferences.didChangeNotification,
            object: nil
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        scheduleDocumentGeometryUpdate()
        updateStatus()
        contentWasLoaded = true
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        scheduleDocumentGeometryUpdate()
    }

    func textDidChange(_ notification: Notification) {
        if let editedRange =
            textView.consumePaginationLayoutInvalidationRange() {
            textSystem.invalidatePaginationLayout(
                from: editedRange
            )
        }
        scheduleDocumentGeometryUpdate(
            revealPageTransition: true
        )
        updateStatus(animated: true)
        selectionDidChange?()
        if contentWasLoaded, !isReplacingDocumentContent {
            contentDidChange?()
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        textSystem.listController.selectionDidChange()
        selectionDidChange?()
    }

    @objc private func printPreferencesChanged(_ notification: Notification) {
        updateStatus()
    }

    @objc private func generalPreferencesChanged(_ notification: Notification) {
        updateStatisticsVisibility()
    }

    func apply(style: EditorTextStyle) {
        textSystem.formattingController.apply(style)
        selectionDidChange?()
    }

    func applyFontFamily(_ family: String) {
        textSystem.formattingController.applyFontFamily(family)
        selectionDidChange?()
    }

    func applySystemFont() {
        textSystem.formattingController.applySystemFont()
        selectionDidChange?()
    }

    func applyFontSize(_ size: CGFloat) {
        textSystem.formattingController.applyFontSize(size)
        selectionDidChange?()
    }

    func toggleTrait(_ trait: NSFontTraitMask) {
        textSystem.formattingController.toggleTrait(trait)
        selectionDidChange?()
    }

    func toggleUnderline() {
        textSystem.formattingController.toggleUnderline()
        selectionDidChange?()
    }

    func applyTextColor(_ color: NSColor) {
        textSystem.formattingController.applyTextColor(color)
        selectionDidChange?()
    }

    func toggleList(_ kind: EditorListKind) {
        textSystem.blockController.removeCodeBlockFormattingFromSelection()
        textSystem.listController.toggleList(kind)
        selectionDidChange?()
    }

    func toggleCodeBlock() {
        textSystem.listController.clearPendingEmptyParagraphList()
        textSystem.blockController.toggleCodeBlock()
        selectionDidChange?()
    }

    func insertDivider() {
        textSystem.listController.clearPendingEmptyParagraphList()
        textSystem.blockController.insertDivider()
        selectionDidChange?()
    }

    func insertImages(from urls: [URL]) throws {
        textSystem.listController.clearPendingEmptyParagraphList()
        textSystem.blockController.removeCodeBlockFormattingFromSelection()
        try textSystem.contentInsertionController.insertImages(from: urls)
        selectionDidChange?()
    }

    func insertTable(_ sender: Any?) {
        textSystem.listController.clearPendingEmptyParagraphList()
        textSystem.blockController.removeCodeBlockFormattingFromSelection()
        textSystem.contentInsertionController.insertTable()
        selectionDidChange?()
    }

    func toggleCodeSnippet() {
        textSystem.blockController.removeCodeBlockFormattingFromSelection()
        textSystem.formattingController.toggleCodeSnippet()
        selectionDidChange?()
    }

    func makePrintOperation(printInfo: NSPrintInfo) -> NSPrintOperation {
        let printableWidth = max(100, printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin)
        let printableHeight = max(100, printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin)
        let printSystem = EditorTextSystem(
            content: attributedContent,
            containerWidth: printableWidth
        )
        let printView = printSystem.textView
        printView.frame = NSRect(
            x: 0,
            y: 0,
            width: printableWidth,
            height: printableHeight
        )
        printView.isEditable = false
        printView.isSelectable = false
        printView.drawsBackground = false
        printView.textContainerInset = .zero
        printView.isHorizontallyResizable = false
        printView.isVerticallyResizable = true
        printView.minSize = NSSize(width: printableWidth, height: printableHeight)
        printView.maxSize = NSSize(width: printableWidth, height: .greatestFiniteMagnitude)
        let contentHeight = ceil(printSystem.contentHeight(ensuringFullLayout: true))
        printView.setFrameSize(NSSize(width: printableWidth, height: max(printableHeight, contentHeight)))
        printView.appearance = NSAppearance(named: .aqua)
        return NSPrintOperation(view: printView, printInfo: printInfo)
    }

    func updatePageLayout(_ pageLayout: EditorPageLayout) {
        guard self.pageLayout != pageLayout else { return }
        self.pageLayout = pageLayout
        pageCapacity = 8
        textSystem.configurePageLayout(
            pageLayout,
            pageCapacity: pageCapacity
        )
        scheduleDocumentGeometryUpdate()
        updateStatus()
    }

    func replaceDocumentContent(
        _ content: NSAttributedString,
        pageLayout: EditorPageLayout,
        restoring viewState: EditorDocumentViewState?
    ) {
        isReplacingDocumentContent = true
        defer { isReplacingDocumentContent = false }

        let undoManager = textView.undoManager
        let undoRegistrationWasEnabled =
            undoManager?.isUndoRegistrationEnabled ?? false
        if undoRegistrationWasEnabled {
            undoManager?.disableUndoRegistration()
        }

        self.pageLayout = pageLayout
        pageCapacity = 8
        textSystem.replaceContent(with: content)
        textSystem.migrateLegacyListMarkers()
        textSystem.normalizeStoredCodeBlocks()
        textSystem.configurePageLayout(
            pageLayout,
            pageCapacity: pageCapacity
        )
        textSystem.normalizeImageAttachments()

        if undoRegistrationWasEnabled {
            undoManager?.enableUndoRegistration()
        }
        undoManager?.removeAllActions()

        scheduleDocumentGeometryUpdate()
        updateStatus()
        restoreDocumentViewState(viewState)
        selectionDidChange?()
    }

    private func restoreDocumentViewState(
        _ viewState: EditorDocumentViewState?
    ) {
        let selection = viewState?.selectedRange
            ?? NSRange(location: 0, length: 0)
        let location = min(max(0, selection.location), textView.string.utf16.count)
        let length = min(
            max(0, selection.length),
            textView.string.utf16.count - location
        )
        textView.setSelectedRange(NSRange(location: location, length: length))

        guard let scrollOrigin = viewState?.scrollOrigin else {
            scrollToPageTop(0)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let clipView = scrollView.contentView
            let proposedBounds = NSRect(
                origin: scrollOrigin,
                size: clipView.bounds.size
            )
            clipView.scroll(
                to: clipView.constrainBoundsRect(proposedBounds).origin
            )
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    func animatePageEjection(completion: @escaping () -> Void) {
        pageEjectionCompletions.append(completion)
        guard !isAnimatingPageEjection else {
            return
        }
        isAnimatingPageEjection = true

        let caretY = textSystem.verticalOffset(
            atCharacterOffset: textView.selectedRange().location
        ) ?? 0
        let pageIndex = min(
            pageView.pageCount - 1,
            pageLayout.pageIndex(forTextOffsetY: caretY)
        )
        pageView.layoutSubtreeIfNeeded()
        guard let contentView = view.window?.contentView else {
            isAnimatingPageEjection = false
            finishPageEjection()
            return
        }
        let pageIndices = [pageIndex] + (0..<pageView.pageCount)
            .filter { $0 != pageIndex }
            .sorted {
                abs($0 - pageIndex) < abs($1 - pageIndex)
            }
        let pages = pageIndices.compactMap { index -> PagePrintAnimator.Page? in
            let pageRect = pageView.pageFrame(at: index)
            guard let image = pageView.shadowlessSnapshot(at: index) else {
                return nil
            }
            return PagePrintAnimator.Page(
                snapshot: image,
                frame: pageView.convert(pageRect, to: contentView)
            )
        }
        guard pages.count == pageView.pageCount else {
            isAnimatingPageEjection = false
            finishPageEjection()
            return
        }

        pageView.alphaValue = 0
        PagePrintAnimator.animate(
            pages: pages,
            in: contentView,
            revealContent: { [weak self] in
                self?.pageView.alphaValue = 1
            },
            completion: { [weak self] in
                guard let self else { return }
                pageView.alphaValue = 1
                isAnimatingPageEjection = false
                finishPageEjection()
            }
        )
    }

    private func finishPageEjection() {
        let completions = pageEjectionCompletions
        pageEjectionCompletions.removeAll()
        completions.forEach { $0() }
    }

    func showPrintResult(succeeded: Bool) {
        let printer = PrintPreferences.selectedPrinterName ?? NSPrintInfo.shared.printer.name
        showStatusMessage(succeeded ? "Sent to \(printer)" : "Print cancelled", symbol: succeeded ? "checkmark.circle.fill" : "xmark.circle")
    }

    private func configureTextView() {
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.usesFindPanel = true
        textView.usesFontPanel = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = NSColor(calibratedWhite: 0.09, alpha: 1)
        textView.typingAttributes = EditorTextSystem.defaultTypingAttributes
        textView.insertionPointColor = TypewriterTheme.accent
        textView.linkTextAttributes = [.foregroundColor: TypewriterTheme.accent, .underlineStyle: NSUnderlineStyle.single.rawValue]
        textView.setAccessibilityLabel("Document text")
        textSystem.migrateLegacyListMarkers()
        textSystem.normalizeStoredCodeBlocks()
        textSystem.normalizeImageAttachments()
        textView.delegate = self
    }

    private func configureScrollView() {
        scrollView.documentView = documentCanvas
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        // Let the scroll view inset its content by the safe area so the page clears
        // the transparent unified title bar/toolbar (via .fullSizeContentView) while the
        // canvas background still extends underneath it.
        scrollView.automaticallyAdjustsContentInsets = true
    }

    private func configureStatusOverlay(in root: NSView) {
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .tertiaryLabelColor
        printerLabel.font = .systemFont(ofSize: 11)
        printerLabel.textColor = .tertiaryLabelColor
        statusMessage.font = .systemFont(ofSize: 11, weight: .semibold)
        statusMessage.textColor = TypewriterTheme.accent
        statusMessage.alphaValue = 0

        let left = NSStackView(views: [countLabel, statusMessage])
        left.orientation = .horizontal
        left.spacing = 14
        let stack = NSStackView(views: [left, NSView(), printerLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])
        updateStatisticsVisibility()
    }

    private func scheduleDocumentGeometryUpdate(
        revealPageTransition: Bool = false
    ) {
        guard isViewLoaded else { return }
        revealPageTransitionWhenUpdatingGeometry =
            revealPageTransitionWhenUpdatingGeometry || revealPageTransition
        guard !geometryUpdateIsScheduled else { return }
        geometryUpdateIsScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.geometryUpdateIsScheduled = false
            let shouldReveal = self.revealPageTransitionWhenUpdatingGeometry
            self.revealPageTransitionWhenUpdatingGeometry = false
            self.updateDocumentGeometry(
                revealPageTransition: shouldReveal
            )
        }
    }

    private func updateDocumentGeometry(
        revealPageTransition: Bool
    ) {
        guard isViewLoaded else { return }
        let previousPageCount = pageView.pageCount
        let pageCount = documentPageCount()
        if pageCount + 2 >= pageCapacity {
            pageCapacity = max(pageCapacity * 2, pageCount + 8)
            textSystem.configurePageLayout(
                pageLayout,
                pageCapacity: pageCapacity
            )
        }
        let pageGeometryChanged = pageView.update(
            pageLayout: pageLayout,
            pageCount: pageCount
        )
        let availableWidth = max(
            scrollView.contentSize.width,
            pageLayout.paperSize.width + 96
        )
        let desiredCanvasSize = NSSize(
            width: availableWidth,
            height: pageView.frame.height + 72
        )
        if documentCanvas.frame.size != desiredCanvasSize {
            documentCanvas.setFrameSize(desiredCanvasSize)
            documentCanvas.needsLayout = true
        }
        guard pageGeometryChanged else { return }

        documentCanvas.layoutSubtreeIfNeeded()
        pageView.layoutSubtreeIfNeeded()
        clampScrollPosition()
        updateStatus()

        guard revealPageTransition else { return }
        if pageCount > previousPageCount {
            scrollToPageTop(pageCount - 1)
        }
    }

    private func documentPageCount() -> Int {
        let documentEnd = NSRange(
            location: textSystem.textStorage.length,
            length: 0
        )
        if let caretRect = textViewRect(for: documentEnd) {
            return pageLayout.pageIndex(
                forTextOffsetY: caretRect.midY
            ) + 1
        }
        let usedHeight = textSystem.documentEndLayoutBottom()
            ?? textSystem.contentHeight(ensuringFullLayout: true)
        return pageLayout.pageCount(forTextHeight: usedHeight)
    }

    private func textViewRect(for characterRange: NSRange) -> NSRect? {
        guard let window = textView.window else { return nil }
        var actualRange = NSRange()
        let screenRect = textView.firstRect(
            forCharacterRange: characterRange,
            actualRange: &actualRange
        )
        guard screenRect.height > 0 else { return nil }
        return textView.convert(
            window.convertFromScreen(screenRect),
            from: nil
        )
    }

    private func scrollToPageTop(_ pageIndex: Int) {
        let pageRect = pageView.convert(
            pageView.pageFrame(at: pageIndex),
            to: documentCanvas
        )
        let clipView = scrollView.contentView
        let topPadding = scrollView.contentInsets.top + 12
        let requestedBounds = NSRect(
            x: clipView.bounds.minX,
            y: pageRect.minY - topPadding,
            width: clipView.bounds.width,
            height: clipView.bounds.height
        )
        clipView.scroll(
            to: clipView.constrainBoundsRect(requestedBounds).origin
        )
        scrollView.reflectScrolledClipView(clipView)
    }

    private func clampScrollPosition() {
        let clipView = scrollView.contentView
        clipView.scroll(
            to: clipView.constrainBoundsRect(clipView.bounds).origin
        )
        scrollView.reflectScrolledClipView(clipView)
    }

    private func updateStatus(animated: Bool = false) {
        let statisticsText = textView.string
            .replacingOccurrences(
                of: EditorBlockStyle.dividerMarker + "\n",
                with: ""
            )
            .replacingOccurrences(
                of: EditorBlockStyle.dividerMarker,
                with: ""
            )
        let words = statisticsText.split { $0.isWhitespace || $0.isNewline }.count
        let characters = statisticsText.count
        let pages = numberOfPages
        countLabel.stringValue = "\(words) \(words == 1 ? "word" : "words")  ·  "
            + "\(characters) \(characters == 1 ? "character" : "characters")  ·  "
            + "\(pages) \(pages == 1 ? "page" : "pages")"
        let printer = PrintPreferences.selectedPrinterName ?? NSPrintInfo.shared.printer.name
        printerLabel.stringValue = printer.isEmpty ? "⌘↩  System default printer" : "⌘↩  \(printer)"
        if animated {
            countLabel.wantsLayer = true
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.45
            fade.toValue = 1
            fade.duration = 0.2
            countLabel.layer?.add(fade, forKey: "countFade")
        }
    }

    private func updateStatisticsVisibility() {
        countLabel.isHidden = !GeneralPreferences.showDocumentStatistics
    }

    private func showStatusMessage(_ message: String, symbol: String) {
        statusMessage.stringValue = "\(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "" : "")\(message)"
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            statusMessage.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                self?.statusMessage.animator().alphaValue = 0
            }
        }
    }

}
