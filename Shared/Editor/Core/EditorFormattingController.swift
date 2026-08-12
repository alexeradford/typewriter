#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

final class EditorFormattingController {
    private unowned let textView: EditorTextView
    private unowned let textContentStorage: NSTextContentStorage
    private unowned let textStorage: NSTextStorage

    var layoutAttributesDidChange: (() -> Void)?
    var selectionStateDidChange: (() -> Void)?

    init(
        textView: EditorTextView,
        textContentStorage: NSTextContentStorage,
        textStorage: NSTextStorage
    ) {
        self.textView = textView
        self.textContentStorage = textContentStorage
        self.textStorage = textStorage
    }

    var currentAttributes: [NSAttributedString.Key: Any] {
        let selection = textView.selectedRange()
        if selection.length == 0 {
            return textView.typingAttributes
        }
        guard textStorage.length > 0 else {
            return textView.typingAttributes
        }

        let string = textStorage.string as NSString
        let upperBound = min(NSMaxRange(selection), string.length)
        var candidate = min(selection.location, upperBound)
        while candidate < upperBound {
            let character = string.substring(
                with: NSRange(location: candidate, length: 1)
            )
            if character != "\n", character != "\r", character != "\t" {
                return textStorage.attributes(at: candidate, effectiveRange: nil)
            }
            candidate += 1
        }

        return textStorage.attributes(
            at: min(selection.location, textStorage.length - 1),
            effectiveRange: nil
        )
    }

    var isCodeSnippetSelected: Bool {
        let selection = textView.selectedRange()
        if selection.length == 0 {
            return EditorInlineStyle.isCodeSnippetBackground(
                textView.typingAttributes[.backgroundColor] as? EditorColor
            )
        }

        var containsContent = false
        var allContentIsCode = true
        textStorage.enumerateAttribute(
            .backgroundColor,
            in: selection
        ) { [textStorage] value, range, _ in
            let contents = (textStorage.string as NSString).substring(with: range)
            guard !contents.trimmingCharacters(in: .newlines).isEmpty else {
                return
            }
            containsContent = true
            if !EditorInlineStyle.isCodeSnippetBackground(value as? EditorColor) {
                allContentIsCode = false
            }
        }
        return containsContent && allContentIsCode
    }

    func apply(_ style: EditorTextStyle) {
        textView.undoManager?.beginUndoGrouping()
        transformFont(actionName: "Change Text Style") { _ in style.font }
        let paragraph = EditorParagraphStyle.body.mutableCopy()
            as! NSMutableParagraphStyle
        paragraph.paragraphSpacing = style.paragraphSpacing
        applyAttribute(
            .paragraphStyle,
            value: paragraph,
            paragraphWide: true,
            actionName: "Change Text Style"
        )
        textView.undoManager?.endUndoGrouping()
    }

    func applyFontFamily(_ family: String) {
        transformFont(actionName: "Change Font") { oldFont in
            EditorFontSupport.shared.convert(oldFont, toFamily: family)
        }
    }

    func applySystemFont() {
        transformFont(actionName: "Change Font") { oldFont in
            let manager = EditorFontSupport.shared
            var font = EditorFont.systemFont(ofSize: oldFont.pointSize)
            let oldTraits = manager.traits(of: oldFont)
            if oldTraits.contains(.boldFontMask) {
                font = manager.convert(font, toHaveTrait: .boldFontMask)
            }
            if oldTraits.contains(.italicFontMask) {
                font = manager.convert(font, toHaveTrait: .italicFontMask)
            }
            return font
        }
    }

    func applyFontSize(_ size: CGFloat) {
        transformFont(actionName: "Change Font Size") { oldFont in
            EditorFontSupport.shared.convert(oldFont, toSize: size)
        }
    }

    func toggleTrait(_ trait: EditorFontTrait) {
        transformFont(actionName: "Change Font Trait") { oldFont in
            let manager = EditorFontSupport.shared
            return manager.traits(of: oldFont).contains(trait)
                ? manager.convert(oldFont, toNotHaveTrait: trait)
                : manager.convert(oldFont, toHaveTrait: trait)
        }
    }

    func toggleUnderline() {
        let current = currentAttributes[.underlineStyle] as? Int ?? 0
        applyAttribute(
            .underlineStyle,
            value: current == 0 ? NSUnderlineStyle.single.rawValue : 0,
            actionName: "Toggle Underline"
        )
    }

    func applyTextColor(_ color: EditorColor) {
        applyAttribute(
            .foregroundColor,
            value: color,
            actionName: "Change Text Color"
        )
    }

    func toggleCodeSnippet() {
        let removeStyle = isCodeSnippetSelected
        let selection = textView.selectedRange()
        if selection.length == 0 {
            updateCodeSnippetTypingAttributes(removing: removeStyle)
            layoutAttributesDidChange?()
            return
        }

        performAttributeEdit(
            in: selection,
            actionName: "Toggle Code Snippet"
        ) { [textStorage] in
            textStorage.enumerateAttribute(
                .font,
                in: selection
            ) { value, range, _ in
                let font = value as? EditorFont ?? EditorTextStyle.body.font
                textStorage.addAttribute(
                    .font,
                    value: removeStyle
                        ? EditorInlineStyle.removingCodeSnippet(from: font)
                        : EditorInlineStyle.applyingCodeSnippet(to: font),
                    range: range
                )
            }

            if removeStyle {
                textStorage.removeAttribute(.backgroundColor, range: selection)
            } else {
                textStorage.addAttribute(
                    .backgroundColor,
                    value: EditorInlineStyle.codeSnippetBackgroundColor,
                    range: selection
                )
            }
        }
        layoutAttributesDidChange?()
    }

    /// Moves the insertion point's formatting affinity across a code-snippet
    /// boundary without moving its document location. This mirrors how a
    /// native rich-text caret can sit on either side of an inline style run.
    func exitCodeSnippetIfAtBoundary(
        moving direction: EditorInlineNavigationDirection
    ) -> Bool {
        let selection = textView.selectedRange()
        guard
            selection.length == 0,
            selection.location != NSNotFound,
            selection.location <= textStorage.length
        else {
            return false
        }

        let location = selection.location
        let outsideLocation: Int?
        switch direction {
        case .forward:
            guard
                location > 0,
                isCodeSnippet(at: location - 1),
                location == textStorage.length
                    || !isCodeSnippet(at: location)
            else {
                return false
            }
            outsideLocation = location < textStorage.length ? location : nil

        case .backward:
            guard
                location < textStorage.length,
                isCodeSnippet(at: location),
                location == 0
                    || !isCodeSnippet(at: location - 1)
            else {
                return false
            }
            outsideLocation = location > 0 ? location - 1 : nil
        }

        setTypingAttributesOutsideCodeSnippet(
            usingCharacterAt: outsideLocation
        )
        selectionStateDidChange?()
        return true
    }

    private func transformFont(
        actionName: String,
        _ transform: (EditorFont) -> EditorFont
    ) {
        let selection = textView.selectedRange()
        if selection.length == 0 {
            let oldFont = currentAttributes[.font] as? EditorFont
                ?? .systemFont(ofSize: 15)
            textView.typingAttributes[.font] = transform(oldFont)
            layoutAttributesDidChange?()
            return
        }

        performAttributeEdit(in: selection, actionName: actionName) {
            textStorage.enumerateAttribute(.font, in: selection) { value, range, _ in
                let oldFont = value as? EditorFont ?? .systemFont(ofSize: 15)
                textStorage.addAttribute(
                    .font,
                    value: transform(oldFont),
                    range: range
                )
            }
        }
        layoutAttributesDidChange?()
    }

    private func applyAttribute(
        _ key: NSAttributedString.Key,
        value: Any,
        paragraphWide: Bool = false,
        actionName: String
    ) {
        var range = textView.selectedRange()
        if paragraphWide, textStorage.length > 0 {
            range = (textStorage.string as NSString).paragraphRange(for: range)
        }
        if range.length == 0 {
            textView.typingAttributes[key] = value
            layoutAttributesDidChange?()
            return
        }

        performAttributeEdit(in: range, actionName: actionName) {
            textStorage.addAttribute(key, value: value, range: range)
        }
        layoutAttributesDidChange?()
    }

    private func performAttributeEdit(
        in range: NSRange,
        actionName: String,
        _ mutation: () -> Void
    ) {
        guard textView.shouldChangeText(in: range, replacementString: nil) else {
            return
        }

        textContentStorage.performEditingTransaction {
            textStorage.beginEditing()
            mutation()
            textStorage.endEditing()
        }
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
    }

    private func updateCodeSnippetTypingAttributes(removing: Bool) {
        let font = currentAttributes[.font] as? EditorFont ?? EditorTextStyle.body.font
        textView.typingAttributes[.font] = removing
            ? EditorInlineStyle.removingCodeSnippet(from: font)
            : EditorInlineStyle.applyingCodeSnippet(to: font)
        if removing {
            textView.typingAttributes.removeValue(forKey: .backgroundColor)
        } else {
            textView.typingAttributes[.backgroundColor] =
                EditorInlineStyle.codeSnippetBackgroundColor
        }
    }

    private func isCodeSnippet(at location: Int) -> Bool {
        guard location >= 0, location < textStorage.length else {
            return false
        }
        return EditorInlineStyle.isCodeSnippetBackground(
            textStorage.attribute(
                .backgroundColor,
                at: location,
                effectiveRange: nil
            ) as? EditorColor
        )
    }

    private func setTypingAttributesOutsideCodeSnippet(
        usingCharacterAt outsideLocation: Int?
    ) {
        var attributes = textView.typingAttributes

        if let outsideLocation {
            let outsideAttributes = textStorage.attributes(
                at: outsideLocation,
                effectiveRange: nil
            )
            if let font = outsideAttributes[.font] as? EditorFont {
                attributes[.font] = font
            }
            if let background = outsideAttributes[.backgroundColor] as? EditorColor,
               !EditorInlineStyle.isCodeSnippetBackground(background) {
                attributes[.backgroundColor] = background
            } else {
                attributes.removeValue(forKey: .backgroundColor)
            }
        } else {
            let font = attributes[.font] as? EditorFont
                ?? currentAttributes[.font] as? EditorFont
                ?? EditorTextStyle.body.font
            attributes[.font] = EditorInlineStyle.removingCodeSnippet(
                from: font
            )
            if EditorInlineStyle.isCodeSnippetBackground(
                attributes[.backgroundColor] as? EditorColor
            ) {
                attributes.removeValue(forKey: .backgroundColor)
            }
        }

        textView.typingAttributes = attributes
    }
}
