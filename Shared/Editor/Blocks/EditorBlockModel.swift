#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

enum EditorBlockKind: Equatable {
    case code
    case divider
    case table(columns: Int)
}

struct EditorBlockPresentation {
    let kind: EditorBlockKind
    let beginsGroup: Bool
    let endsGroup: Bool
}

protocol EditorBlockPresentationProviding: AnyObject {
    func blockPresentation(at documentLocation: Int) -> EditorBlockPresentation?
}

enum EditorBlockStyle {
    static let dividerMarker = "\u{200B}"
    static let codeFont = EditorFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static let codeBackgroundColor = EditorColor(editorWhite: 0.94, alpha: 1)
    static let codeBorderColor = EditorColor(editorWhite: 0.84, alpha: 1)
    static let dividerColor = EditorColor(editorWhite: 0.76, alpha: 1)
    static let dividerLineHeight: CGFloat = 21
    static let dividerVerticalSpacing: CGFloat = 8
    static let horizontalInset: CGFloat = 12
    static let verticalInset: CGFloat = 7

    static var code: NSParagraphStyle {
        let style = EditorParagraphStyle.body.mutableCopy() as! NSMutableParagraphStyle
        style.lineSpacing = 2
        style.paragraphSpacing = 0
        style.firstLineHeadIndent = horizontalInset
        style.headIndent = horizontalInset
        style.tailIndent = -horizontalInset
        return style
    }

    static var divider: NSParagraphStyle {
        let style = EditorParagraphStyle.body.mutableCopy() as! NSMutableParagraphStyle
        style.minimumLineHeight = dividerLineHeight
        style.maximumLineHeight = dividerLineHeight
        style.paragraphSpacingBefore = dividerVerticalSpacing
        style.paragraphSpacing = dividerVerticalSpacing
        return style
    }

    static func kind(
        from paragraphStyle: NSParagraphStyle?,
        backgroundColor: EditorColor?,
        paragraphText: String? = nil
    ) -> EditorBlockKind? {
        guard let paragraphStyle else { return nil }

        if let columns = EditorTableStyle.columnCount(
            paragraphStyle: paragraphStyle,
            backgroundColor: backgroundColor,
            paragraphText: paragraphText
        ) {
            return .table(columns: columns)
        }

        if paragraphText?
            .trimmingCharacters(in: .newlines) == dividerMarker,
           approximatelyEqual(paragraphStyle.minimumLineHeight, dividerLineHeight),
           approximatelyEqual(paragraphStyle.maximumLineHeight, dividerLineHeight),
           approximatelyEqual(paragraphStyle.paragraphSpacingBefore, dividerVerticalSpacing),
           approximatelyEqual(paragraphStyle.paragraphSpacing, dividerVerticalSpacing) {
            return .divider
        }

        // Migrate documents created by the first code-block implementation
        // before they can trigger AppKit's TextKit 1 compatibility path.
        if paragraphStyle.textBlocks.contains(where: { !($0 is NSTextTableBlock) }) {
            return .code
        }

        guard
            backgroundColor != nil,
            paragraphStyle.textLists.isEmpty,
            approximatelyEqual(paragraphStyle.firstLineHeadIndent, horizontalInset),
            approximatelyEqual(paragraphStyle.headIndent, horizontalInset),
            approximatelyEqual(paragraphStyle.lineSpacing, 2),
            approximatelyEqual(paragraphStyle.paragraphSpacing, 0)
        else {
            return nil
        }
        return .code
    }

    private static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.01
    }
}

enum EditorTableStyle {
    static let minimumColumns = 2
    static let defaultColumns = 3
    static let defaultRows = 3
    static let rowHeight: CGFloat = 32
    static let cellPadding: CGFloat = 8
    static let backgroundColor = EditorColor(editorWhite: 0.985, alpha: 1)
    static let borderColor = EditorColor(editorWhite: 0.78, alpha: 1)

    static func paragraphStyle(columns: Int, availableWidth: CGFloat) -> NSParagraphStyle {
        let columns = max(minimumColumns, columns)
        let width = max(120, availableWidth)
        let columnWidth = width / CGFloat(columns)
        let style = EditorParagraphStyle.body.mutableCopy() as! NSMutableParagraphStyle
        style.minimumLineHeight = rowHeight
        style.maximumLineHeight = rowHeight
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        style.firstLineHeadIndent = cellPadding
        style.headIndent = cellPadding
        style.tailIndent = -cellPadding
        style.defaultTabInterval = columnWidth
        style.tabStops = (1..<columns).map {
            NSTextTab(
                textAlignment: .left,
                location: columnWidth * CGFloat($0) + cellPadding,
                options: [:]
            )
        }
        return style
    }

    static func columnCount(
        paragraphStyle: NSParagraphStyle,
        backgroundColor _: EditorColor?,
        paragraphText: String?
    ) -> Int? {
        guard let paragraphText else { return nil }
        let row = paragraphText.trimmingCharacters(in: .newlines)
        let columns = row.components(separatedBy: "\t").count
        guard
            columns >= minimumColumns,
            abs(paragraphStyle.minimumLineHeight - rowHeight) < 0.01,
            abs(paragraphStyle.maximumLineHeight - rowHeight) < 0.01,
            abs(paragraphStyle.firstLineHeadIndent - cellPadding) < 0.01,
            abs(paragraphStyle.headIndent - cellPadding) < 0.01,
            paragraphStyle.tabStops.count == columns - 1
        else {
            return nil
        }
        return columns
    }
}
