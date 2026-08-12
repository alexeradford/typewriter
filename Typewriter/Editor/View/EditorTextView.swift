import AppKit

/// The editor's narrow AppKit event bridge.
///
/// Text semantics and layout live in collaborators installed by
/// `EditorTextSystem`; this subclass only routes native text-view events.
final class EditorTextView: NSTextView {
    private var listController: EditorListController!
    private var blockController: EditorBlockController!
    private var formattingController: EditorFormattingController!
    private var contentInsertionController: EditorContentInsertionController!
    private var retainedTextLayoutDelegate: EditorTextLayoutDelegate!
    private var retainedTextLayoutManager: NSTextLayoutManager!
    private var retainedTextContentStorage: NSTextContentStorage!
    private var pendingChecklistTarget: EditorListMarkerTarget?
    private var pendingChecklistMouseDown: NSEvent?
    private var paginationLayoutInvalidationRange: NSRange?

    func install(
        listController: EditorListController,
        blockController: EditorBlockController,
        formattingController: EditorFormattingController,
        contentInsertionController: EditorContentInsertionController,
        textLayoutDelegate: EditorTextLayoutDelegate,
        textLayoutManager: NSTextLayoutManager,
        textContentStorage: NSTextContentStorage
    ) {
        self.listController = listController
        self.blockController = blockController
        self.formattingController = formattingController
        self.contentInsertionController = contentInsertionController
        retainedTextLayoutDelegate = textLayoutDelegate
        retainedTextLayoutManager = textLayoutManager
        retainedTextContentStorage = textContentStorage
    }

    override func insertNewline(_ sender: Any?) {
        if contentInsertionController.moveToNextTableRow() {
            return
        }
        if let action = blockController.prepareForNewline() {
            switch action {
            case .consume:
                return
            case .continueCodeBlock:
                requirePaginationLayoutInvalidation(
                    around: selectedRange()
                )
                super.insertNewline(sender)
                blockController.completeNewline()
                return
            }
        }
        guard let action = listController.prepareForNewline() else {
            requirePaginationLayoutInvalidation(
                around: selectedRange()
            )
            super.insertNewline(sender)
            return
        }
        switch action {
        case .consume:
            return
        case .continueList(let sourceState):
            requirePaginationLayoutInvalidation(
                around: selectedRange()
            )
            super.insertNewline(sender)
            listController.completeNewline(from: sourceState)
        }
    }

    override func insertTab(_ sender: Any?) {
        if contentInsertionController.moveToNextTableCell() {
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if contentInsertionController.moveToPreviousTableCell() {
            return
        }
        super.insertBacktab(sender)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let insertionLocation = replacementRange.location == NSNotFound
            ? selectedRange().location
            : replacementRange.location
        let effectiveRange = replacementRange.location == NSNotFound
            ? selectedRange()
            : replacementRange
        if containsNewline(insertString)
            || containsNewline(in: effectiveRange) {
            requirePaginationLayoutInvalidation(
                around: effectiveRange
            )
        }
        let materializedInsertion = listController.insertionMaterializingPendingList(
            insertString,
            replacementRange: replacementRange
        )
        super.insertText(materializedInsertion, replacementRange: replacementRange)
        listController.completePendingListInsertion(at: insertionLocation)
    }

    override func deleteBackward(_ sender: Any?) {
        if contentInsertionController.handleTableDeleteBackward() { return }
        if blockController.removeCodeBlockAtParagraphStart() { return }
        if listController.removeListAtParagraphStart() { return }
        let selection = selectedRange()
        let deletedRange = selection.length > 0
            ? selection
            : NSRange(
                location: max(0, selection.location - 1),
                length: selection.location > 0 ? 1 : 0
            )
        if containsNewline(in: deletedRange) {
            requirePaginationLayoutInvalidation(
                around: deletedRange
            )
        }
        super.deleteBackward(sender)
        resetEmptyDocumentTypingAttributesIfNeeded()
    }

    override func deleteForward(_ sender: Any?) {
        if contentInsertionController.handleTableDeleteForward() { return }
        let selection = selectedRange()
        let deletedRange = selection.length > 0
            ? selection
            : NSRange(
                location: min(selection.location, string.utf16.count),
                length: selection.location < string.utf16.count ? 1 : 0
            )
        if containsNewline(in: deletedRange) {
            requirePaginationLayoutInvalidation(
                around: deletedRange
            )
        }
        super.deleteForward(sender)
        resetEmptyDocumentTypingAttributesIfNeeded()
    }

    override func moveLeft(_ sender: Any?) {
        if formattingController.exitCodeSnippetIfAtBoundary(
            moving: .backward
        ) {
            return
        }
        super.moveLeft(sender)
    }

    override func moveRight(_ sender: Any?) {
        if formattingController.exitCodeSnippetIfAtBoundary(
            moving: .forward
        ) {
            return
        }
        super.moveRight(sender)
    }

    override func cut(_ sender: Any?) {
        if containsNewline(in: selectedRange()) {
            requirePaginationLayoutInvalidation(
                around: selectedRange()
            )
        }
        super.cut(sender)
        resetEmptyDocumentTypingAttributesIfNeeded()
    }

    override func readSelection(
        from pboard: NSPasteboard,
        type: NSPasteboard.PasteboardType
    ) -> Bool {
        let didRead = super.readSelection(from: pboard, type: type)
        if didRead {
            contentInsertionController.normalizeImageAttachments()
        }
        return didRead
    }

    func consumePaginationLayoutInvalidationRange() -> NSRange? {
        defer { paginationLayoutInvalidationRange = nil }
        return paginationLayoutInvalidationRange
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard
            event.clickCount == 1,
            let target = listController.markerTarget(at: point)
        else {
            super.mouseDown(with: event)
            return
        }

        pendingChecklistTarget = target
        pendingChecklistMouseDown = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialEvent = pendingChecklistMouseDown else {
            super.mouseDragged(with: event)
            return
        }

        let distance = hypot(
            event.locationInWindow.x - initialEvent.locationInWindow.x,
            event.locationInWindow.y - initialEvent.locationInWindow.y
        )
        if distance > 4 {
            pendingChecklistTarget = nil
            pendingChecklistMouseDown = nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let pendingTarget = pendingChecklistTarget else {
            super.mouseUp(with: event)
            return
        }
        defer {
            pendingChecklistTarget = nil
            pendingChecklistMouseDown = nil
        }

        let point = convert(event.locationInWindow, from: nil)
        guard
            let currentTarget = listController.markerTarget(at: point),
            currentTarget.paragraphLocation == pendingTarget.paragraphLocation
        else {
            return
        }
        listController.toggleChecklist(currentTarget)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for markerRect in listController.visibleChecklistMarkerRects() {
            addCursorRect(markerRect, cursor: .pointingHand)
        }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = super.accessibilityCustomActions() ?? []
        if listController.isChecklistAtSelection {
            actions.append(
                NSAccessibilityCustomAction(
                    name: "Toggle checklist item",
                    target: self,
                    selector: #selector(toggleChecklistAccessibilityAction)
                )
            )
        }
        return actions
    }

    @objc private func toggleChecklistAccessibilityAction() -> Bool {
        listController.toggleChecklistAtSelection()
    }

    private func resetEmptyDocumentTypingAttributesIfNeeded() {
        guard string.isEmpty else { return }
        listController.clearPendingEmptyParagraphList()
        typingAttributes = EditorTextSystem.defaultTypingAttributes
        font = EditorTextSystem.defaultTypingAttributes[.font] as? NSFont
        textColor = EditorTextSystem.defaultTypingAttributes[.foregroundColor] as? NSColor
    }

    private func containsNewline(_ value: Any) -> Bool {
        let insertedString: String
        if let attributedString = value as? NSAttributedString {
            insertedString = attributedString.string
        } else if let string = value as? String {
            insertedString = string
        } else {
            return false
        }
        return insertedString.unicodeScalars.contains {
            CharacterSet.newlines.contains($0)
        }
    }

    private func containsNewline(in range: NSRange) -> Bool {
        guard
            range.location != NSNotFound,
            range.length > 0,
            NSMaxRange(range) <= string.utf16.count
        else {
            return false
        }
        let substring = (string as NSString).substring(with: range)
        return substring.unicodeScalars.contains {
            CharacterSet.newlines.contains($0)
        }
    }

    private func requirePaginationLayoutInvalidation(
        around range: NSRange
    ) {
        guard range.location != NSNotFound else { return }
        if let pendingRange = paginationLayoutInvalidationRange {
            paginationLayoutInvalidationRange = NSUnionRange(
                pendingRange,
                range
            )
        } else {
            paginationLayoutInvalidationRange = range
        }
    }
}
