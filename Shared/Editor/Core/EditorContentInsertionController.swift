#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers

enum EditorImageImportError: LocalizedError {
    case unreadableImage(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            "“\(url.lastPathComponent)” could not be inserted because it is not a readable image."
        }
    }
}

/// Owns non-text content insertion and normalization.
///
/// Images are ordinary `NSTextAttachment` values so native copy, paste, and
/// drag behavior remains available. Tables are editable, tab-delimited
/// paragraphs with a durable RTF-safe style and TextKit 2 grid rendering.
final class EditorContentInsertionController {
    private unowned let textView: EditorTextView
    private unowned let textLayoutManager: NSTextLayoutManager
    private unowned let textContentStorage: NSTextContentStorage

    var maximumImageSize: CGSize
    var layoutDidChange: (() -> Void)?

    private var textStorage: NSTextStorage {
        guard let storage = textContentStorage.textStorage else {
            preconditionFailure("TextKit 2 content storage lost its backing text storage")
        }
        return storage
    }

    init(
        textView: EditorTextView,
        textLayoutManager: NSTextLayoutManager,
        textContentStorage: NSTextContentStorage,
        maximumImageWidth: CGFloat
    ) {
        self.textView = textView
        self.textLayoutManager = textLayoutManager
        self.textContentStorage = textContentStorage
        maximumImageSize = CGSize(
            width: maximumImageWidth,
            height: .greatestFiniteMagnitude
        )
    }

    func insertImages(from urls: [URL]) throws {
        guard !urls.isEmpty else { return }
        let attachments = try urls.map(makeImageAttachment)
        insertImageAttachments(attachments)
    }

    func insertTable(
        rows: Int = EditorTableStyle.defaultRows,
        columns: Int = EditorTableStyle.defaultColumns
    ) {
        let rows = max(1, rows)
        let columns = max(EditorTableStyle.minimumColumns, columns)
        let style = EditorTableStyle.paragraphStyle(
            columns: columns,
            availableWidth: maximumImageSize.width
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: EditorTextStyle.body.font,
            .foregroundColor: EditorColor(editorWhite: 0.09, alpha: 1),
            .backgroundColor: EditorTableStyle.backgroundColor,
            .paragraphStyle: style
        ]
        let row = String(repeating: "\t", count: columns - 1) + "\n"
        let insertion = NSMutableAttributedString()
        let selection = textView.selectedRange()
        let insertionLocation = min(selection.location, textView.string.utf16.count)
        if insertionLocation > 0,
           !(textView.string as NSString)
            .character(at: insertionLocation - 1)
            .isNewline {
            insertion.append(NSAttributedString(
                string: "\n",
                attributes: EditorTextSystem.defaultTypingAttributes
            ))
        }
        for _ in 0..<rows {
            insertion.append(NSAttributedString(string: row, attributes: attributes))
        }
        insertion.append(NSAttributedString(
            string: "\n",
            attributes: EditorTextSystem.defaultTypingAttributes
        ))

        textView.breakUndoCoalescing()
        textView.insertText(insertion, replacementRange: selection)
        let tableStart = insertionLocation
            + (insertion.string.hasPrefix("\n") ? 1 : 0)
        textView.setSelectedRange(NSRange(location: tableStart, length: 0))
        textView.typingAttributes = attributes
        textView.undoManager?.setActionName("Insert Table")
    }

    func moveToNextTableCell() -> Bool {
        guard let location = validSelectionLocation(),
              let table = tableParagraph(containing: location) else {
            return false
        }
        let starts = cellStarts(in: table.range)
        if let next = starts.first(where: { $0 > location }) {
            moveCaret(to: next, attributes: table.attributes)
            return true
        }
        if let nextRow = tableParagraph(startingAt: NSMaxRange(table.range)) {
            moveCaret(to: nextRow.range.location, attributes: nextRow.attributes)
            return true
        }
        if NSMaxRange(table.range) < textStorage.length {
            moveCaret(
                to: NSMaxRange(table.range),
                attributes: EditorTextSystem.defaultTypingAttributes
            )
            return true
        }
        appendTableRow(after: table)
        return true
    }

    func moveToPreviousTableCell() -> Bool {
        guard let location = validSelectionLocation(),
              let table = tableParagraph(containing: location) else {
            return false
        }
        let starts = cellStarts(in: table.range)
        let currentColumn = starts.lastIndex(where: { $0 <= location }) ?? 0
        if currentColumn > 0 {
            moveCaret(
                to: starts[currentColumn - 1],
                attributes: table.attributes
            )
            return true
        }
        guard
            table.range.location > 0,
            let previousRow = tableParagraph(
                containing: table.range.location - 1
            ),
            let previous = cellStarts(in: previousRow.range).last
        else {
            return true
        }
        moveCaret(to: previous, attributes: previousRow.attributes)
        return true
    }

    func moveToNextTableRow() -> Bool {
        guard let location = validSelectionLocation(),
              let table = tableParagraph(containing: location) else {
            return false
        }
        let currentColumn = cellStarts(in: table.range)
            .lastIndex(where: { $0 <= location }) ?? 0
        let nextRow: TableParagraph
        if let existingRow = tableParagraph(startingAt: NSMaxRange(table.range)) {
            nextRow = existingRow
        } else {
            appendTableRow(after: table)
            return true
        }
        let starts = cellStarts(in: nextRow.range)
        moveCaret(
            to: starts[min(currentColumn, starts.count - 1)],
            attributes: nextRow.attributes
        )
        return true
    }

    func handleTableDeleteBackward() -> Bool {
        guard
            let location = validSelectionLocation(),
            let table = tableParagraph(containing: location)
        else {
            return false
        }
        let starts = cellStarts(in: table.range)
        guard let column = starts.firstIndex(of: location), column > 0 else {
            return false
        }
        moveCaret(to: starts[column - 1], attributes: table.attributes)
        return true
    }

    func handleTableDeleteForward() -> Bool {
        guard
            let location = validSelectionLocation(),
            location < textStorage.length,
            let table = tableParagraph(containing: location),
            (textStorage.string as NSString).character(at: location) == 0x09
        else {
            return false
        }
        let starts = cellStarts(in: table.range)
        guard let next = starts.first(where: { $0 > location }) else {
            return false
        }
        moveCaret(to: next, attributes: table.attributes)
        return true
    }

    /// Applies page-aware bounds to images imported by paste or drag and to
    /// attachments decoded from RTFD, whose explicit bounds are not preserved
    /// by AppKit's serializer.
    @discardableResult
    func normalizeImageAttachments() -> Bool {
        guard textStorage.length > 0 else { return false }
        var changed = false
        textStorage.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: textStorage.length)
        ) { value, _, _ in
            guard
                let attachment = value as? NSTextAttachment,
                let sourceSize = imageSize(for: attachment)
            else {
                return
            }
            let fittedSize = sourceSize.aspectFit(within: maximumImageSize)
            guard
                fittedSize.width > 0,
                fittedSize.height > 0,
                !attachment.bounds.size.approximatelyEquals(fittedSize)
            else {
                return
            }
            attachment.bounds = CGRect(origin: .zero, size: fittedSize)
            changed = true
        }
        guard changed else { return false }
        textLayoutManager.invalidateLayout(for: textContentStorage.documentRange)
        layoutDidChange?()
        return true
    }

    private func makeImageAttachment(from url: URL) throws -> NSTextAttachment {
        let data = try Data(contentsOf: url)
        guard let image = EditorImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw EditorImageImportError.unreadableImage(url)
        }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        let attachment = NSTextAttachment(data: data, ofType: type.identifier)
        attachment.bounds = CGRect(
            origin: .zero,
            size: image.size.aspectFit(within: maximumImageSize)
        )
        return attachment
    }

    private func insertImageAttachments(_ attachments: [NSTextAttachment]) {
        let selection = textView.selectedRange()
        let insertionLocation = min(selection.location, textView.string.utf16.count)
        let needsLeadingNewline = insertionLocation > 0
            && !(textView.string as NSString)
                .character(at: insertionLocation - 1)
                .isNewline

        let insertion = NSMutableAttributedString()
        if needsLeadingNewline {
            insertion.append(NSAttributedString(
                string: "\n",
                attributes: EditorTextSystem.defaultTypingAttributes
            ))
        }
        for attachment in attachments {
            let image = NSMutableAttributedString(attachment: attachment)
            image.addAttributes(
                EditorTextSystem.defaultTypingAttributes,
                range: NSRange(location: 0, length: image.length)
            )
            image.addAttribute(
                .attachment,
                value: attachment,
                range: NSRange(location: 0, length: image.length)
            )
            insertion.append(image)
            insertion.append(NSAttributedString(
                string: "\n",
                attributes: EditorTextSystem.defaultTypingAttributes
            ))
        }

        textView.breakUndoCoalescing()
        textView.insertText(insertion, replacementRange: selection)
        textView.typingAttributes = EditorTextSystem.defaultTypingAttributes
        textView.undoManager?.setActionName(
            attachments.count == 1 ? "Insert Image" : "Insert Images"
        )
        normalizeImageAttachments()
    }

    private func imageSize(for attachment: NSTextAttachment) -> CGSize? {
        let currentSize = attachment.bounds.size
        if currentSize.width > 0, currentSize.height > 0 {
            return currentSize
        }
        if let image = attachment.image,
           image.size.width > 0,
           image.size.height > 0 {
            return image.size
        }
        if let contents = attachment.contents,
           let image = EditorImage(data: contents) {
            return image.size
        }
        if let contents = attachment.fileWrapper?.regularFileContents,
           let image = EditorImage(data: contents) {
            return image.size
        }
        return nil
    }

    private struct TableParagraph {
        let range: NSRange
        let columns: Int
        let attributes: [NSAttributedString.Key: Any]
    }

    private func validSelectionLocation() -> Int? {
        let selection = textView.selectedRange()
        guard
            selection.length == 0,
            selection.location != NSNotFound,
            selection.location <= textStorage.length
        else {
            return nil
        }
        return selection.location
    }

    private func tableParagraph(containing location: Int) -> TableParagraph? {
        guard textStorage.length > 0 else { return nil }
        let string = textStorage.string as NSString
        let lookupLocation = min(location, textStorage.length - 1)
        let range = string.paragraphRange(
            for: NSRange(location: lookupLocation, length: 0)
        )
        return tableParagraph(in: range)
    }

    private func tableParagraph(startingAt location: Int) -> TableParagraph? {
        guard location < textStorage.length else { return nil }
        let range = (textStorage.string as NSString).paragraphRange(
            for: NSRange(location: location, length: 0)
        )
        guard range.location == location else { return nil }
        return tableParagraph(in: range)
    }

    private func tableParagraph(in range: NSRange) -> TableParagraph? {
        guard range.location < textStorage.length else { return nil }
        let attributes = textStorage.attributes(
            at: range.location,
            effectiveRange: nil
        )
        guard
            let style = attributes[.paragraphStyle] as? NSParagraphStyle,
            let columns = EditorTableStyle.columnCount(
                paragraphStyle: style,
                backgroundColor: attributes[.backgroundColor] as? EditorColor,
                paragraphText: (textStorage.string as NSString)
                    .substring(with: range)
            )
        else {
            return nil
        }
        return TableParagraph(
            range: range,
            columns: columns,
            attributes: attributes
        )
    }

    private func cellStarts(in paragraph: NSRange) -> [Int] {
        let string = textStorage.string as NSString
        var starts = [paragraph.location]
        var location = paragraph.location
        while location < NSMaxRange(paragraph) {
            let character = string.character(at: location)
            if character == 0x09 {
                starts.append(location + 1)
            }
            if character.isNewline { break }
            location += 1
        }
        return starts
    }

    private func appendTableRow(after table: TableParagraph) {
        let insertionLocation = NSMaxRange(table.range)
        let row = String(repeating: "\t", count: table.columns - 1) + "\n"
        textView.insertText(
            NSAttributedString(string: row, attributes: table.attributes),
            replacementRange: NSRange(location: insertionLocation, length: 0)
        )
        moveCaret(to: insertionLocation, attributes: table.attributes)
        textView.undoManager?.setActionName("Add Table Row")
    }

    private func moveCaret(
        to location: Int,
        attributes: [NSAttributedString.Key: Any]
    ) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.typingAttributes = attributes
    }
}

private extension CGSize {
    func aspectFit(within bounds: CGSize) -> CGSize {
        guard width > 0, height > 0 else { return .zero }
        let widthScale = bounds.width > 0 ? bounds.width / width : 1
        let heightScale = bounds.height.isFinite && bounds.height > 0
            ? bounds.height / height
            : 1
        let scale = min(1, widthScale, heightScale)
        return CGSize(width: width * scale, height: height * scale)
    }

    func approximatelyEquals(_ other: CGSize) -> Bool {
        abs(width - other.width) < 0.01 && abs(height - other.height) < 0.01
    }
}

private extension unichar {
    var isNewline: Bool {
        self == 0x0A || self == 0x0D
    }
}
