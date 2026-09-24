import UIKit

/// UIKit's event bridge for the shared TextKit 2 editor.
///
/// Editing semantics remain in the shared controllers. This subclass translates
/// UIKit input, selection, and notification behavior into the narrow surface the
/// shared editor expects.
final class EditorTextView: UITextView {
    private var listController: EditorListController!
    private var blockController: EditorBlockController!
    private var formattingController: EditorFormattingController!
    private var contentInsertionController: EditorContentInsertionController!
    private var retainedTextLayoutDelegate: EditorTextLayoutDelegate!
    private var retainedTextLayoutManager: NSTextLayoutManager!
    private var retainedTextContentStorage: NSTextContentStorage!
    private var paginationLayoutInvalidationRange: NSRange?
    private var pendingUndoSnapshot: UndoSnapshot?
    private var isRestoringUndoSnapshot = false
    private lazy var fallbackUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()

    var contentDidChange: (() -> Void)?
    var selectionDidChange: (() -> Void)?
    var editingDidBegin: (() -> Void)?
    var editingDidEnd: (() -> Void)?

    override var undoManager: UndoManager? {
        super.undoManager ?? fallbackUndoManager
    }

    /// The editor is a scroll viewport. Its document height must not become
    /// the intrinsic height SwiftUI uses to size the representable.
    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: UIView.noIntrinsicMetric
        )
    }

    var string: String {
        textStorage.string
    }

    var textContainerOrigin: CGPoint {
        CGPoint(x: textContainerInset.left, y: textContainerInset.top)
    }

    func install(
        listController: EditorListController,
        blockController: EditorBlockController,
        formattingController: EditorFormattingController,
        contentInsertionController: EditorContentInsertionController,
        textLayoutDelegate: EditorTextLayoutDelegate,
        textLayoutManager: NSTextLayoutManager,
        textContentStorage: NSTextContentStorage
    ) {
        delegate = self
        self.listController = listController
        self.blockController = blockController
        self.formattingController = formattingController
        self.contentInsertionController = contentInsertionController
        retainedTextLayoutDelegate = textLayoutDelegate
        retainedTextLayoutManager = textLayoutManager
        retainedTextContentStorage = textContentStorage

        let checklistTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleChecklistTap(_:))
        )
        checklistTap.delegate = self
        addGestureRecognizer(checklistTap)
    }

    override func insertText(_ text: String) {
        if text == "\n" {
            insertSharedNewline()
            return
        }
        if text == "\t", contentInsertionController.moveToNextTableCell() {
            return
        }

        let selection = selectedRange
        if containsNewline(text) || containsNewline(in: selection) {
            requirePaginationLayoutInvalidation(around: selection)
        }
        let materialized = listController.insertionMaterializingPendingList(
            text,
            replacementRange: selection
        )
        insertSharedText(materialized, replacementRange: selection)
        listController.completePendingListInsertion(at: selection.location)
    }

    override func deleteBackward() {
        if contentInsertionController.handleTableDeleteBackward() { return }
        if blockController.removeCodeBlockAtParagraphStart() { return }
        if listController.removeListAtParagraphStart() { return }

        let selection = selectedRange
        let deletedRange = selection.length > 0
            ? selection
            : NSRange(
                location: max(0, selection.location - 1),
                length: selection.location > 0 ? 1 : 0
            )
        if containsNewline(in: deletedRange) {
            requirePaginationLayoutInvalidation(around: deletedRange)
        }
        super.deleteBackward()
        resetEmptyDocumentTypingAttributesIfNeeded()
        notifyTextChanged()
    }

    func selectedRange() -> NSRange {
        selectedRange
    }

    func setSelectedRange(_ range: NSRange) {
        selectedRange = range
        selectionDidChange?()
    }

    func shouldChangeText(
        in range: NSRange,
        replacementString: String?
    ) -> Bool {
        guard isEditable, range.location != NSNotFound else { return false }
        if !isRestoringUndoSnapshot {
            pendingUndoSnapshot = makeUndoSnapshot()
        }
        return true
    }

    func didChangeText() {
        registerPendingUndo()
        notifyTextChanged()
    }

    func breakUndoCoalescing() {
        // UIKit closes its event-scoped undo groups between editing commands.
        // Ending one explicitly can unbalance UIKit's private undo group.
    }

    func insertText(_ insertion: Any, replacementRange: NSRange) {
        insertSharedText(insertion, replacementRange: replacementRange)
    }

    func consumePaginationLayoutInvalidationRange() -> NSRange? {
        defer { paginationLayoutInvalidationRange = nil }
        return paginationLayoutInvalidationRange
    }

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            var actions = super.accessibilityCustomActions ?? []
            if listController?.isChecklistAtSelection == true {
                actions.append(UIAccessibilityCustomAction(
                    name: "Toggle checklist item",
                    target: self,
                    selector: #selector(toggleChecklistAccessibilityAction)
                ))
            }
            return actions
        }
        set {
            super.accessibilityCustomActions = newValue
        }
    }

    private func insertSharedNewline() {
        if contentInsertionController.moveToNextTableRow() { return }
        if let action = blockController.prepareForNewline() {
            switch action {
            case .consume:
                return
            case .continueCodeBlock:
                requirePaginationLayoutInvalidation(around: selectedRange)
                insertSharedText("\n", replacementRange: selectedRange)
                blockController.completeNewline()
                return
            }
        }
        guard let action = listController.prepareForNewline() else {
            requirePaginationLayoutInvalidation(around: selectedRange)
            insertSharedText("\n", replacementRange: selectedRange)
            return
        }
        switch action {
        case .consume:
            return
        case .continueList(let sourceState):
            requirePaginationLayoutInvalidation(around: selectedRange)
            insertSharedText("\n", replacementRange: selectedRange)
            listController.completeNewline(from: sourceState)
        }
    }

    private func insertSharedText(_ insertion: Any, replacementRange: NSRange) {
        let attributedInsertion: NSAttributedString
        if let value = insertion as? NSAttributedString {
            attributedInsertion = value
        } else if let value = insertion as? String {
            attributedInsertion = NSAttributedString(
                string: value,
                attributes: typingAttributes
            )
        } else {
            return
        }

        guard shouldChangeText(in: replacementRange, replacementString: nil) else {
            return
        }
        retainedTextContentStorage.performEditingTransaction {
            textStorage.replaceCharacters(
                in: replacementRange,
                with: attributedInsertion
            )
        }
        selectedRange = NSRange(
            location: replacementRange.location + attributedInsertion.length,
            length: 0
        )
        didChangeText()
    }

    @objc private func handleChecklistTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let point = recognizer.location(in: self)
        guard let target = listController.markerTarget(at: point) else { return }
        listController.toggleChecklist(target)
    }

    @objc private func toggleChecklistAccessibilityAction() -> Bool {
        listController.toggleChecklistAtSelection()
    }

    private func notifyTextChanged() {
        NotificationCenter.default.post(
            name: UITextView.textDidChangeNotification,
            object: self
        )
        contentDidChange?()
    }

    private func makeUndoSnapshot() -> UndoSnapshot {
        UndoSnapshot(
            content: textStorage.copy() as? NSAttributedString
                ?? NSAttributedString(),
            selection: selectedRange,
            typingAttributes: typingAttributes
        )
    }

    private func registerPendingUndo() {
        guard
            let snapshot = pendingUndoSnapshot,
            let undoManager
        else {
            pendingUndoSnapshot = nil
            return
        }
        pendingUndoSnapshot = nil
        undoManager.registerUndo(withTarget: self) { textView in
            textView.restoreUndoSnapshot(snapshot)
        }
    }

    private func restoreUndoSnapshot(_ snapshot: UndoSnapshot) {
        let inverse = makeUndoSnapshot()
        isRestoringUndoSnapshot = true
        retainedTextContentStorage.performEditingTransaction {
            textStorage.setAttributedString(snapshot.content)
        }
        selectedRange = snapshot.selection
        typingAttributes = snapshot.typingAttributes
        isRestoringUndoSnapshot = false

        undoManager?.registerUndo(withTarget: self) { textView in
            textView.restoreUndoSnapshot(inverse)
        }
        notifyTextChanged()
    }

    private func resetEmptyDocumentTypingAttributesIfNeeded() {
        guard textStorage.length == 0 else { return }
        listController.clearPendingEmptyParagraphList()
        typingAttributes = EditorTextSystem.defaultTypingAttributes
        font = EditorTextSystem.defaultTypingAttributes[.font] as? UIFont
        textColor = EditorTextSystem.defaultTypingAttributes[.foregroundColor] as? UIColor
    }

    private func containsNewline(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.newlines.contains($0) }
    }

    private func containsNewline(in range: NSRange) -> Bool {
        let string = textStorage.string as NSString
        guard
            range.location != NSNotFound,
            range.length > 0,
            NSMaxRange(range) <= string.length
        else {
            return false
        }
        return string.substring(with: range).unicodeScalars.contains {
            CharacterSet.newlines.contains($0)
        }
    }

    private func requirePaginationLayoutInvalidation(around range: NSRange) {
        guard range.location != NSNotFound else { return }
        paginationLayoutInvalidationRange = paginationLayoutInvalidationRange.map {
            NSUnionRange($0, range)
        } ?? range
    }
}

private struct UndoSnapshot {
    let content: NSAttributedString
    let selection: NSRange
    let typingAttributes: [NSAttributedString.Key: Any]
}

extension EditorTextView: UIGestureRecognizerDelegate, UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        editingDidBegin?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        editingDidEnd?()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        listController.selectionDidChange()
        selectionDidChange?()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        listController.markerTarget(at: touch.location(in: self)) != nil
    }
}
