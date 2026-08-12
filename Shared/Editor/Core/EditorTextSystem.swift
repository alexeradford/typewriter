#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Owns the TextKit 2 object graph used by an editor.
///
/// App-facing controllers should use this type instead of reaching through
/// `NSTextView` to layout objects. Keeping that boundary narrow makes the editor
/// suitable for extraction into its own module later.
final class EditorTextSystem {
    static var defaultTypingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: EditorTextStyle.body.font,
            .foregroundColor: EditorColor(editorWhite: 0.09, alpha: 1),
            .paragraphStyle: EditorParagraphStyle.body
        ]
    }

    let textView: EditorTextView
    let listController: EditorListController
    let blockController: EditorBlockController
    let formattingController: EditorFormattingController
    let contentInsertionController: EditorContentInsertionController

    private let textLayoutManager: NSTextLayoutManager
    private let textContentStorage: NSTextContentStorage
    private let textContainer: NSTextContainer
    private let textLayoutDelegate: EditorTextLayoutDelegate
    private var compatibilityModeObserver: NSObjectProtocol?

    var didEnterCompatibilityMode: (() -> Void)?

    var attributedContent: NSAttributedString {
        textStorage.copy() as? NSAttributedString ?? NSAttributedString()
    }

    var textStorage: NSTextStorage {
        guard let storage = textContentStorage.textStorage else {
            preconditionFailure("TextKit 2 content storage lost its backing text storage")
        }
        return storage
    }

    init(content: NSAttributedString, containerWidth: CGFloat) {
        let textLayoutManager = NSTextLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(
            width: containerWidth,
            height: .greatestFiniteMagnitude
        ))
        textLayoutManager.textContainer = textContainer
        let textContentStorage = NSTextContentStorage()
        textContentStorage.addTextLayoutManager(textLayoutManager)
        let textView = EditorTextView(
            frame: .zero,
            textContainer: textContainer
        )

        self.textView = textView
        self.textLayoutManager = textLayoutManager
        self.textContentStorage = textContentStorage
        self.textContainer = textContainer

        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContentStorage.includesTextListMarkers = false

        let layoutDelegate = EditorTextLayoutDelegate()
        textLayoutDelegate = layoutDelegate
        textLayoutManager.delegate = layoutDelegate
        textContentStorage.delegate = layoutDelegate
        textContentStorage.performEditingTransaction {
            textContentStorage.textStorage?.setAttributedString(content)
        }

        guard let textStorage = textContentStorage.textStorage else {
            preconditionFailure("TextKit 2 content storage has no backing text storage")
        }
        let listController = EditorListController(
            textView: textView,
            textLayoutManager: textLayoutManager,
            textContentStorage: textContentStorage
        )
        layoutDelegate.listPresentationProvider = listController
        self.listController = listController
        let blockController = EditorBlockController(
            textView: textView,
            textLayoutManager: textLayoutManager,
            textContentStorage: textContentStorage
        )
        layoutDelegate.blockPresentationProvider = blockController
        self.blockController = blockController
        formattingController = EditorFormattingController(
            textView: textView,
            textContentStorage: textContentStorage,
            textStorage: textStorage
        )
        contentInsertionController = EditorContentInsertionController(
            textView: textView,
            textLayoutManager: textLayoutManager,
            textContentStorage: textContentStorage,
            maximumImageWidth: containerWidth
        )
        formattingController.layoutAttributesDidChange = { [weak listController] in
            listController?.refreshSelectedParagraphLayout()
        }
        textView.install(
            listController: listController,
            blockController: blockController,
            formattingController: formattingController,
            contentInsertionController: contentInsertionController,
            textLayoutDelegate: layoutDelegate,
            textLayoutManager: textLayoutManager,
            textContentStorage: textContentStorage
        )

#if canImport(AppKit)
        observeCompatibilityMode()
#endif
    }

    deinit {
        if let compatibilityModeObserver {
            NotificationCenter.default.removeObserver(compatibilityModeObserver)
        }
    }

    func migrateLegacyListMarkers() {
        listController.migrateLegacyMarkers()
    }

    func normalizeStoredCodeBlocks() {
        blockController.normalizeStoredCodeBlocks()
    }

    func normalizeImageAttachments() {
        contentInsertionController.normalizeImageAttachments()
    }

    func replaceContent(with content: NSAttributedString) {
        listController.clearPendingEmptyParagraphList()
        textContentStorage.performEditingTransaction {
            textStorage.setAttributedString(content)
        }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.typingAttributes = Self.defaultTypingAttributes
        textLayoutManager.invalidateLayout(
            for: textContentStorage.documentRange
        )
    }

    func contentHeight(ensuringFullLayout: Bool = false) -> CGFloat {
        if ensuringFullLayout {
            textLayoutManager.ensureLayout(for: textContentStorage.documentRange)
        }
        return max(1, textLayoutManager.usageBoundsForTextContainer.maxY)
    }

    func configurePageLayout(
        _ layout: EditorPageLayout,
        pageCapacity: Int = 8
    ) {
        textContainer.editorContainerSize = CGSize(
            width: layout.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textContainer.exclusionPaths = layout.exclusionPaths(
            pageCapacity: pageCapacity
        )
        contentInsertionController.maximumImageSize = layout.contentSize
        contentInsertionController.normalizeImageAttachments()
        textLayoutDelegate.pageLayout = layout
        textLayoutManager.invalidateLayout(for: textContentStorage.documentRange)
    }

    /// Configures a continuous editor surface, used by the compact iOS UI.
    /// Document paper geometry remains part of persistence and page estimates,
    /// while the phone-sized editing viewport is allowed to use its full width.
    func configureContinuousLayout(containerWidth: CGFloat) {
        let width = max(1, containerWidth)
        textContainer.editorContainerSize = CGSize(
            width: width,
            height: .greatestFiniteMagnitude
        )
        textContainer.exclusionPaths = []
        contentInsertionController.maximumImageSize = CGSize(
            width: width,
            height: .greatestFiniteMagnitude
        )
        contentInsertionController.normalizeImageAttachments()
        textLayoutDelegate.pageLayout = nil
        textLayoutManager.invalidateLayout(for: textContentStorage.documentRange)
    }

    func invalidatePaginationLayout(from editedRange: NSRange) {
        let documentRange = textContentStorage.documentRange
        let startOffset = min(
            max(0, editedRange.location - 1),
            textStorage.length
        )
        guard let startLocation = textContentStorage.location(
            documentRange.location,
            offsetBy: startOffset
        ) else {
            return
        }
        var fragments: [NSTextLayoutFragment] = []
        textLayoutManager.enumerateTextLayoutFragments(
            from: startLocation,
            options: []
        ) { fragment in
            fragments.append(fragment)
            return true
        }
        fragments.forEach { $0.invalidateLayout() }
        guard let affectedRange = NSTextRange(
            location: startLocation,
            end: documentRange.endLocation
        ) else {
            return
        }
        textLayoutManager.invalidateLayout(for: affectedRange)
    }

    func documentEndLayoutBottom() -> CGFloat? {
        let endLocation = textContentStorage.documentRange.endLocation
        guard
            let endRange = NSTextRange(
                location: endLocation,
                end: endLocation
            )
        else {
            return nil
        }
        textLayoutManager.ensureLayout(for: endRange)
        return textLayoutManager.textLayoutFragment(for: endLocation)?
            .layoutFragmentFrame.maxY
    }

    func verticalOffset(atCharacterOffset characterOffset: Int) -> CGFloat? {
        let documentRange = textContentStorage.documentRange
        let safeOffset = min(max(0, characterOffset), textStorage.length)
        guard let location = textContentStorage.location(
            documentRange.location,
            offsetBy: safeOffset
        ) else {
            return nil
        }
        guard let range = NSTextRange(location: location, end: location) else {
            return nil
        }
        textLayoutManager.ensureLayout(for: range)
        return textLayoutManager.textLayoutFragment(for: location)?
            .layoutFragmentFrame.midY
    }

#if canImport(AppKit)
    private func observeCompatibilityMode() {
        compatibilityModeObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didSwitchToNSLayoutManagerNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.didEnterCompatibilityMode?()
        }
    }
#endif
}
