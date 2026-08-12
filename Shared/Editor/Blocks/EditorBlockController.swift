#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

enum EditorBlockNewlineAction {
    case consume
    case continueCodeBlock
}

final class EditorBlockController {
    private unowned let textView: EditorTextView
    private unowned let textLayoutManager: NSTextLayoutManager
    private unowned let textContentStorage: NSTextContentStorage
    var selectionStateDidChange: (() -> Void)?

    private var textStorage: NSTextStorage {
        guard let storage = textContentStorage.textStorage else {
            preconditionFailure("TextKit 2 content storage lost its backing text storage")
        }
        return storage
    }

    init(
        textView: EditorTextView,
        textLayoutManager: NSTextLayoutManager,
        textContentStorage: NSTextContentStorage
    ) {
        self.textView = textView
        self.textLayoutManager = textLayoutManager
        self.textContentStorage = textContentStorage
    }

    var selectedBlockKind: EditorBlockKind? {
        let kinds = selectedParagraphRanges().map(blockKind)
        guard let first = kinds.first, let kind = first else { return nil }
        return kinds.allSatisfy { $0 == kind } ? kind : nil
    }

    func blockPresentation(at documentLocation: Int) -> EditorBlockPresentation? {
        let paragraph = paragraphRange(containing: documentLocation)
        guard let kind = blockKind(for: paragraph) else { return nil }
        if kind == .divider {
            return EditorBlockPresentation(
                kind: .divider,
                beginsGroup: true,
                endsGroup: true
            )
        }

        let previousIsSameKind: Bool
        if paragraph.location > 0 {
            previousIsSameKind = blockKind(
                for: paragraphRange(containing: paragraph.location - 1)
            ) == kind
        } else {
            previousIsSameKind = false
        }

        let nextLocation = NSMaxRange(paragraph)
        let nextIsSameKind = nextLocation < textStorage.length
            && blockKind(for: paragraphRange(containing: nextLocation)) == kind
        return EditorBlockPresentation(
            kind: kind,
            beginsGroup: !previousIsSameKind,
            endsGroup: !nextIsSameKind
        )
    }

    func toggleCodeBlock() {
        let paragraphs = selectedParagraphRanges()
        guard !paragraphs.isEmpty else { return }
        let shouldRemove = paragraphs.allSatisfy {
            blockKind(for: $0) == .code
        }
        applyCodeBlock(!shouldRemove, to: paragraphs, actionName: "Toggle Code Block")
    }

    func insertDivider() {
        let selection = textView.selectedRange()
        let string = textView.string as NSString
        let insertionLocation = min(selection.location, string.length)
        let needsLeadingNewline = insertionLocation > 0
            && !isNewline(string.character(at: insertionLocation - 1))
        let insertedString = (needsLeadingNewline ? "\n" : "")
            + EditorBlockStyle.dividerMarker + "\n"
        let replacementRange = NSRange(
            location: insertionLocation,
            length: min(selection.length, string.length - insertionLocation)
        )

        guard textView.shouldChangeText(
            in: replacementRange,
            replacementString: insertedString
        ) else {
            return
        }

        let insertion = NSMutableAttributedString()
        if needsLeadingNewline {
            insertion.append(NSAttributedString(
                string: "\n",
                attributes: attributesBeforeInsertion(at: insertionLocation)
            ))
        }
        insertion.append(NSAttributedString(
            string: EditorBlockStyle.dividerMarker + "\n",
            attributes: dividerAttributes
        ))

        textContentStorage.performEditingTransaction {
            textStorage.replaceCharacters(in: replacementRange, with: insertion)
        }
        let caretLocation = insertionLocation + insertion.length
        textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
        textView.typingAttributes = EditorTextSystem.defaultTypingAttributes
        textView.didChangeText()
        textView.undoManager?.setActionName("Insert Divider")

        let dividerLocation = insertionLocation + (needsLeadingNewline ? 1 : 0)
        refreshLayout(for: [
            paragraphRange(containing: dividerLocation),
            paragraphRange(containing: caretLocation)
        ])
        selectionStateDidChange?()
    }

    func removeCodeBlockFormattingFromSelection() {
        let paragraphs = selectedParagraphRanges()
        guard paragraphs.contains(where: { blockKind(for: $0) == .code }) else {
            return
        }
        applyCodeBlock(false, to: paragraphs, actionName: "Change Block Style")
    }

    func prepareForNewline() -> EditorBlockNewlineAction? {
        let paragraph = paragraphRange(containing: textView.selectedRange().location)
        guard blockKind(for: paragraph) == .code else { return nil }
        let contents = paragraph.length > 0
            ? (textView.string as NSString).substring(with: paragraph)
            : ""
        if contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            applyCodeBlock(false, to: [paragraph], actionName: "End Code Block")
            return .consume
        }
        return .continueCodeBlock
    }

    func completeNewline() {
        let paragraph = paragraphRange(containing: textView.selectedRange().location)
        applyCodeBlock(true, to: [paragraph], actionName: "Continue Code Block")
    }

    func removeCodeBlockAtParagraphStart() -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let paragraph = paragraphRange(containing: selection.location)
        guard
            selection.location == paragraph.location,
            blockKind(for: paragraph) == .code
        else {
            return false
        }
        applyCodeBlock(false, to: [paragraph], actionName: "End Code Block")
        return true
    }

    /// Rebuilds canonical code-block attributes and migrates the short-lived
    /// `NSTextBlock` representation that forced NSTextView into compatibility
    /// mode on edit.
    func normalizeStoredCodeBlocks() {
        guard textStorage.length > 0 else { return }
        var ranges: [NSRange] = []
        enumerateParagraphs(in: NSRange(location: 0, length: textStorage.length)) {
            if blockKind(for: $0) == .code { ranges.append($0) }
        }
        guard !ranges.isEmpty else { return }

        textContentStorage.performEditingTransaction {
            textStorage.beginEditing()
            for range in ranges {
                textStorage.addAttribute(
                    .paragraphStyle,
                    value: EditorBlockStyle.code,
                    range: range
                )
                textStorage.addAttribute(
                    .backgroundColor,
                    value: EditorBlockStyle.codeBackgroundColor,
                    range: range
                )
            }
            textStorage.endEditing()
        }
        refreshLayout(for: ranges)
    }

    private func applyCodeBlock(
        _ enabled: Bool,
        to paragraphs: [NSRange],
        actionName: String
    ) {
        let storedParagraphs = paragraphs.filter { $0.length > 0 }
        if let range = union(of: storedParagraphs) {
            guard textView.shouldChangeText(in: range, replacementString: nil) else {
                return
            }
            textContentStorage.performEditingTransaction {
                textStorage.beginEditing()
                for paragraph in storedParagraphs {
                    if enabled {
                        textStorage.addAttributes(codeAttributes, range: paragraph)
                    } else {
                        textStorage.addAttributes(bodyAttributes, range: paragraph)
                        textStorage.removeAttribute(.backgroundColor, range: paragraph)
                    }
                }
                textStorage.endEditing()
            }
            textView.didChangeText()
            textView.undoManager?.setActionName(actionName)
        }

        if paragraphs.contains(where: { $0.length == 0 })
            || textView.selectedRange().length == 0 {
            if !enabled {
                textView.typingAttributes.removeValue(forKey: .backgroundColor)
            }
            textView.typingAttributes.merge(
                enabled ? codeAttributes : bodyAttributes
            ) { _, newValue in newValue }
        }
        refreshLayout(for: paragraphs)
        selectionStateDidChange?()
    }

    private var codeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: EditorBlockStyle.codeFont,
            .paragraphStyle: EditorBlockStyle.code,
            .backgroundColor: EditorBlockStyle.codeBackgroundColor
        ]
    }

    private var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: EditorTextStyle.body.font, .paragraphStyle: EditorParagraphStyle.body]
    }

    private var dividerAttributes: [NSAttributedString.Key: Any] {
        [
            .font: EditorTextStyle.body.font,
            .foregroundColor: EditorColor.clear,
            .paragraphStyle: EditorBlockStyle.divider
        ]
    }

    private func attributesBeforeInsertion(at location: Int) -> [NSAttributedString.Key: Any] {
        guard location > 0, textStorage.length > 0 else {
            return textView.typingAttributes
        }
        return textStorage.attributes(
            at: min(location - 1, textStorage.length - 1),
            effectiveRange: nil
        )
    }

    private func blockKind(for paragraph: NSRange) -> EditorBlockKind? {
        let style: NSParagraphStyle?
        let backgroundColor: EditorColor?
        let paragraphText: String?
        if paragraph.location < textStorage.length {
            style = textStorage.attribute(
                .paragraphStyle,
                at: paragraph.location,
                effectiveRange: nil
            ) as? NSParagraphStyle
            backgroundColor = textStorage.attribute(
                .backgroundColor,
                at: paragraph.location,
                effectiveRange: nil
            ) as? EditorColor
            paragraphText = (textStorage.string as NSString).substring(with: paragraph)
        } else {
            style = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
            backgroundColor = textView.typingAttributes[.backgroundColor] as? EditorColor
            paragraphText = nil
        }
        return EditorBlockStyle.kind(
            from: style,
            backgroundColor: backgroundColor,
            paragraphText: paragraphText
        )
    }

    private func paragraphRange(containing location: Int) -> NSRange {
        let string = textView.string as NSString
        guard string.length > 0 else {
            return NSRange(location: 0, length: 0)
        }
        if location == string.length,
           isNewline(string.character(at: string.length - 1)) {
            return NSRange(location: string.length, length: 0)
        }
        return string.paragraphRange(
            for: NSRange(location: min(location, string.length - 1), length: 0)
        )
    }

    private func selectedParagraphRanges() -> [NSRange] {
        let string = textView.string as NSString
        guard string.length > 0 else {
            return [NSRange(location: 0, length: 0)]
        }
        let selection = textView.selectedRange()
        if selection.length == 0,
           selection.location == string.length,
           isNewline(string.character(at: string.length - 1)) {
            return [NSRange(location: string.length, length: 0)]
        }
        let location = min(selection.location, string.length - 1)
        let range = NSRange(
            location: location,
            length: min(selection.length, string.length - location)
        )
        let paragraphs = string.paragraphRange(for: range)
        var result: [NSRange] = []
        enumerateParagraphs(in: paragraphs) { result.append($0) }
        return result
    }

    private func enumerateParagraphs(
        in range: NSRange,
        _ body: (NSRange) -> Void
    ) {
        let string = textView.string as NSString
        var location = range.location
        while location < NSMaxRange(range) {
            let paragraph = string.paragraphRange(
                for: NSRange(location: location, length: 0)
            )
            body(paragraph)
            let next = NSMaxRange(paragraph)
            guard next > location else { break }
            location = next
        }
    }

    private func union(of ranges: [NSRange]) -> NSRange? {
        ranges.reduce(nil) { result, range in
            result.map { NSUnionRange($0, range) } ?? range
        }
    }

    private func refreshLayout(for paragraphs: [NSRange]) {
        let documentStart = textContentStorage.documentRange.location
        for paragraph in paragraphs {
            let startOffset = min(paragraph.location, textStorage.length)
            let endOffset = min(NSMaxRange(paragraph), textStorage.length)
            guard
                let start = textContentStorage.location(
                    documentStart,
                    offsetBy: startOffset
                ),
                let end = textContentStorage.location(
                    documentStart,
                    offsetBy: endOffset
                ),
                let range = NSTextRange(location: start, end: end)
            else {
                continue
            }
            textLayoutManager.invalidateLayout(for: range)
            textLayoutManager.ensureLayout(for: range)
        }
        textLayoutManager.textViewportLayoutController.layoutViewport()
#if canImport(AppKit)
        textView.needsDisplay = true
#else
        textView.setNeedsDisplay()
#endif
    }

    private func isNewline(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(character) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }
}

extension EditorBlockController: EditorBlockPresentationProviding {}
