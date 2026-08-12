#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

struct EditorListPresentation {
    let state: EditorListState
    let ordinal: Int?
}

protocol EditorListPresentationProviding: AnyObject {
    func listPresentation(
        at documentLocation: Int
    ) -> EditorListPresentation?
}

final class EditorTextLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
    weak var listPresentationProvider: EditorListPresentationProviding?
    weak var blockPresentationProvider: EditorBlockPresentationProviding?
    var pageLayout: EditorPageLayout?

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        guard textElement is NSTextParagraph else {
            return NSTextLayoutFragment(
                textElement: textElement,
                range: textElement.elementRange
            )
        }

        let fragment = EditorListLayoutFragment(
            textElement: textElement,
            range: textElement.elementRange
        )
        fragment.representedEmptyParagraph = textElement
            .attributedStringContainsOnlyParagraphTerminators
        fragment.listPresentationProvider = self
        fragment.blockPresentationProvider = self
        fragment.pageLayout = pageLayout
        if let contentManager = textLayoutManager.textContentManager {
            let documentLocation = contentManager.offset(
                from: contentManager.documentRange.location,
                to: location
            )
            if documentLocation != NSNotFound {
                fragment.documentLocation = documentLocation
            }
        }
        return fragment
    }
}

extension EditorTextLayoutDelegate: NSTextContentStorageDelegate {
    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard
            range.length > 0,
            let textStorage = textContentStorage.textStorage,
            range.location < textStorage.length,
            let paragraphStyle = textStorage.attribute(
                .paragraphStyle,
                at: range.location,
                effectiveRange: nil
            ) as? NSParagraphStyle,
            let textList = paragraphStyle.textLists.last
        else {
            return nil
        }

        let storedParagraph = textStorage.attributedSubstring(from: range)
        let markerFont = storedParagraph.attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? EditorFont ?? EditorTextStyle.body.font
        let markerAttributes: [NSAttributedString.Key: Any] = [
            // The marker remains invisible, but it must retain the paragraph's
            // font metrics. On an empty list item this synthesized marker is
            // the only glyph TextKit lays out, so shrinking it would collapse
            // the entire line fragment around the custom checkbox.
            .font: markerFont,
            .foregroundColor: EditorColor.clear
        ]
        return NSTextListElement(
            parent: nil,
            textList: textList,
            contents: paragraphContents(from: storedParagraph),
            markerAttributes: markerAttributes,
            children: nil
        )
    }

    private func paragraphContents(
        from storedParagraph: NSAttributedString
    ) -> NSAttributedString {
        let contents = storedParagraph.mutableCopy() as! NSMutableAttributedString
        guard contents.length > 0 else { return contents }

        let string = contents.string as NSString
        let finalCharacter = string.character(at: string.length - 1)
        if let scalar = UnicodeScalar(finalCharacter),
           CharacterSet.newlines.contains(scalar) {
            // NSTextListElement owns the paragraph terminator. Passing the
            // backing storage's terminator as content produces an additional
            // empty line inside every list element.
            let terminatorLength = finalCharacter == 0x0A
                && string.length > 1
                && string.character(at: string.length - 2) == 0x0D
                ? 2
                : 1
            contents.deleteCharacters(in: NSRange(
                location: contents.length - terminatorLength,
                length: terminatorLength
            ))
        }
        return contents
    }
}

extension EditorTextLayoutDelegate: EditorListPresentationProviding {
    func listPresentation(
        at documentLocation: Int
    ) -> EditorListPresentation? {
        listPresentationProvider?.listPresentation(at: documentLocation)
    }
}

extension EditorTextLayoutDelegate: EditorBlockPresentationProviding {
    func blockPresentation(
        at documentLocation: Int
    ) -> EditorBlockPresentation? {
        blockPresentationProvider?.blockPresentation(at: documentLocation)
    }
}

final class EditorListLayoutFragment: NSTextLayoutFragment {
    private static let listItemSpacing: CGFloat = 3

    /// `NSTextParagraph.attributedString` is backed by the live text storage.
    /// TextKit can still query an invalidated fragment's frame after an edit
    /// has shortened that storage, at which point reading the paragraph again
    /// raises an out-of-bounds Objective-C exception. Capture this immutable
    /// fact while TextKit is vending the current text element instead.
    fileprivate var representedEmptyParagraph = false

    /// The controller supplies list state independently of TextKit's marker
    /// synthesis. Empty paragraphs use pending intent until the first
    /// attributed insertion materializes the real `NSTextList` metadata.
    weak var listPresentationProvider: EditorListPresentationProviding?
    weak var blockPresentationProvider: EditorBlockPresentationProviding?
    var pageLayout: EditorPageLayout?
    var documentLocation: Int?

    override var layoutFragmentFrame: CGRect {
        let frame = super.layoutFragmentFrame
        guard representedEmptyParagraph else { return frame }
        let closingLineHeight = textLineFragments.last?
            .typographicBounds.height ?? 0
        return pageLayout?.snappedLineFragmentRect(
            for: frame,
            closingLineHeight: closingLineHeight
        ) ?? frame
    }

    var listState: EditorListState? {
        listPresentation?.state
    }

    private var blockPresentation: EditorBlockPresentation? {
        guard let blockPresentationProvider, let documentLocation else {
            return nil
        }
        return blockPresentationProvider.blockPresentation(
            at: documentLocation
        )
    }

    private var listPresentation:
        EditorListPresentation? {
        guard
            let listPresentationProvider,
            let documentLocation
        else {
            return nil
        }

        return listPresentationProvider.listPresentation(
            at: documentLocation
        )
    }

    override var renderingSurfaceBounds: CGRect {
        let textBounds = textLineFragments.reduce(
            super.renderingSurfaceBounds
        ) { bounds, line in
            bounds.union(line.typographicBounds)
        }
        var bounds = textBounds
        if let codeBlockRect {
            bounds = bounds.union(codeBlockRect)
        }
        if let dividerRect {
            bounds = bounds.union(dividerRect)
        }
        if let tableRect {
            bounds = bounds.union(tableRect)
        }
        if let markerRect {
            bounds = bounds.union(markerRect)
        }
        return bounds
    }

    override var bottomMargin: CGFloat {
        if blockPresentation?.endsGroup == true {
            return max(
                super.bottomMargin,
                EditorBlockStyle.verticalInset + 1
            )
        }
        guard listState != nil else { return super.bottomMargin }
        // Custom markers fill the normal line height at body sizes. Reserve a
        // small inter-item gap so adjacent checkbox outlines never share pixels.
        return max(super.bottomMargin, Self.listItemSpacing)
    }

    override var topMargin: CGFloat {
        guard blockPresentation?.beginsGroup == true else {
            return super.topMargin
        }
        return max(super.topMargin, EditorBlockStyle.verticalInset)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        if let codeBlockRect, let blockPresentation {
            EditorCodeBlockRenderer.draw(
                blockPresentation,
                in: codeBlockRect,
                context: context
            )
        }
        if let dividerRect {
            EditorDividerRenderer.draw(in: dividerRect, context: context)
        }
        if let tableRect, let columns = tableColumnCount {
            EditorTableRenderer.draw(
                columns: columns,
                in: tableRect,
                context: context
            )
        }
        EditorCodeSnippetRenderer.draw(
            lineFragments: textLineFragments,
            context: context
        )
        super.draw(at: point, in: context)
        guard let listState, let markerRect else { return }
        EditorListMarkerRenderer.draw(
            listState,
            ordinal: listPresentation?.ordinal,
            font: markerFont,
            in: markerRect,
            context: context
        )
    }

    private var codeBlockRect: CGRect? {
        guard
            blockPresentation?.kind == .code,
            state == .layoutAvailable,
            let containerWidth = textLayoutManager?.textContainer?.editorContainerSize.width
        else {
            return nil
        }
        let textBounds = textLineFragments.reduce(CGRect.null) {
            $0.union($1.typographicBounds)
        }
        guard !textBounds.isNull else { return nil }
        let topInset = blockPresentation?.beginsGroup == true
            ? EditorBlockStyle.verticalInset
            : 1
        let bottomInset = blockPresentation?.endsGroup == true
            ? EditorBlockStyle.verticalInset
            : 1
        let outerStrokeInset: CGFloat = 0.5
        let topStrokeInset = blockPresentation?.beginsGroup == true
            ? outerStrokeInset
            : 0
        let bottomStrokeInset = blockPresentation?.endsGroup == true
            ? outerStrokeInset
            : 0
        return CGRect(
            x: -layoutFragmentFrame.minX + outerStrokeInset,
            y: textBounds.minY - topInset + topStrokeInset,
            width: containerWidth - (outerStrokeInset * 2),
            height: textBounds.height + topInset + bottomInset
                - topStrokeInset - bottomStrokeInset
        )
    }

    private var dividerRect: CGRect? {
        guard
            blockPresentation?.kind == .divider,
            state == .layoutAvailable,
            let containerWidth = textLayoutManager?.textContainer?.editorContainerSize.width,
            let firstLine = textLineFragments.first
        else {
            return nil
        }
        return CGRect(
            x: -layoutFragmentFrame.minX,
            y: firstLine.typographicBounds.midY - 0.5,
            width: containerWidth,
            height: 1
        )
    }

    private var tableColumnCount: Int? {
        guard
            let blockPresentation,
            case .table(let columns) = blockPresentation.kind
        else {
            return nil
        }
        return columns
    }

    private var tableRect: CGRect? {
        guard
            tableColumnCount != nil,
            state == .layoutAvailable,
            let containerWidth = textLayoutManager?.textContainer?.editorContainerSize.width
        else {
            return nil
        }
        let textBounds = textLineFragments.reduce(CGRect.null) {
            $0.union($1.typographicBounds)
        }
        guard !textBounds.isNull else { return nil }
        return CGRect(
            x: -layoutFragmentFrame.minX + 0.5,
            y: textBounds.minY,
            width: containerWidth - 1,
            height: max(EditorTableStyle.rowHeight, textBounds.height)
        )
    }

    var markerRectInContainer: CGRect? {
        guard let markerRect else { return nil }
        return markerRect.offsetBy(
            dx: layoutFragmentFrame.minX,
            dy: layoutFragmentFrame.minY
        )
    }

    private var markerRect: CGRect? {
        guard
            listState != nil,
            state == .layoutAvailable,
            let firstLine = textLineFragments.first
        else {
            return nil
        }

        let markerSize: CGSize
        switch listState?.kind {
        case .checklist:
            markerSize = CGSize(width: 18, height: 18)
        case .numbered:
            markerSize = CGSize(width: 28, height: 18)
        case .bullet, .none:
            markerSize = CGSize(width: 8, height: 8)
        }
        let markerCenterX = synthesizedMarkerCenterX(in: firstLine)
        let center = CGPoint(
            x: markerCenterX,
            y: textCenterY(in: firstLine)
        )
        return CGRect(
            x: center.x - markerSize.width / 2,
            y: center.y - markerSize.height / 2,
            width: markerSize.width,
            height: markerSize.height
        )
    }

    private var markerFont: EditorFont {
        guard
            let firstLine = textLineFragments.first,
            firstLine.attributedString.length > 0,
            let font = firstLine.attributedString.attribute(
                .font,
                at: 0,
                effectiveRange: nil
            ) as? EditorFont
        else {
            return EditorTextStyle.body.font
        }
        return font
    }

    private func textCenterY(in line: NSTextLineFragment) -> CGFloat {
        line.typographicBounds.midY
    }

    private func synthesizedMarkerCenterX(in line: NSTextLineFragment) -> CGFloat {
        if line.attributedString.length == 0 {
            // An empty pending item is still an ordinary paragraph fragment.
            // Anchor its marker to the list gutter so it occupies the same
            // container position as the synthesized marker after insertion.
            return EditorParagraphStyle.listIndent - layoutFragmentFrame.minX
        }

        let string = line.attributedString.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)
        let leadingTab = string.range(of: "\t", options: [], range: fullRange)
        guard leadingTab.location != NSNotFound else {
            return line.typographicBounds.minX
                - (EditorParagraphStyle.listIndent / 2)
        }

        let remainingRange = NSRange(
            location: NSMaxRange(leadingTab),
            length: string.length - NSMaxRange(leadingTab)
        )
        let trailingTab = string.range(of: "\t", options: [], range: remainingRange)
        guard trailingTab.location != NSNotFound else {
            return line.typographicBounds.minX
                - (EditorParagraphStyle.listIndent / 2)
        }

        let leadingX = line.locationForCharacter(
            at: NSMaxRange(leadingTab)
        ).x
        let trailingX = line.locationForCharacter(
            at: trailingTab.location
        ).x
        return (leadingX + trailingX) / 2
    }

}

private extension NSTextElement {
    var attributedStringContainsOnlyParagraphTerminators: Bool {
        guard let paragraph = self as? NSTextParagraph else { return false }
        return paragraph.attributedString.string.unicodeScalars.allSatisfy {
            CharacterSet.newlines.contains($0)
        }
    }
}

enum EditorDividerRenderer {
    static func draw(in rect: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setFillColor(EditorBlockStyle.dividerColor.cgColor)
        context.fill(rect)
    }
}

enum EditorTableRenderer {
    static func draw(
        columns: Int,
        in rect: CGRect,
        context: CGContext
    ) {
        guard columns >= EditorTableStyle.minimumColumns else { return }
        context.saveGState()
        defer { context.restoreGState() }

        context.setFillColor(EditorTableStyle.backgroundColor.cgColor)
        context.fill(rect)

        context.setStrokeColor(EditorTableStyle.borderColor.cgColor)
        context.setLineWidth(1)
        context.stroke(rect)

        let columnWidth = rect.width / CGFloat(columns)
        for column in 1..<columns {
            let x = rect.minX + columnWidth * CGFloat(column)
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        context.strokePath()
    }
}

enum EditorCodeBlockRenderer {
    static func draw(
        _ presentation: EditorBlockPresentation,
        in rect: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        let path = path(for: presentation, in: rect)
        context.addPath(path)
        context.setFillColor(EditorBlockStyle.codeBackgroundColor.cgColor)
        context.fillPath()

        context.setStrokeColor(EditorBlockStyle.codeBorderColor.cgColor)
        context.setLineWidth(1)
        context.addPath(borderPath(for: presentation, in: rect))
        context.strokePath()
    }

    private static func path(
        for presentation: EditorBlockPresentation,
        in rect: CGRect
    ) -> CGPath {
        let radius: CGFloat = 6
        let path = CGMutablePath()
        path.move(to: CGPoint(
            x: presentation.beginsGroup ? rect.minX + radius : rect.minX,
            y: rect.minY
        ))
        if presentation.beginsGroup {
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(
            x: rect.maxX,
            y: presentation.endsGroup ? rect.maxY - radius : rect.maxY
        ))
        if presentation.endsGroup {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.addLine(to: CGPoint(
            x: rect.minX,
            y: presentation.beginsGroup ? rect.minY + radius : rect.minY
        ))
        if presentation.beginsGroup {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        }
        path.closeSubpath()
        return path
    }

    private static func borderPath(
        for presentation: EditorBlockPresentation,
        in rect: CGRect
    ) -> CGPath {
        let radius: CGFloat = 6
        let path = CGMutablePath()

        path.move(to: CGPoint(
            x: rect.minX,
            y: presentation.beginsGroup ? rect.minY + radius : rect.minY
        ))
        path.addLine(to: CGPoint(
            x: rect.minX,
            y: presentation.endsGroup ? rect.maxY - radius : rect.maxY
        ))
        path.move(to: CGPoint(
            x: rect.maxX,
            y: presentation.beginsGroup ? rect.minY + radius : rect.minY
        ))
        path.addLine(to: CGPoint(
            x: rect.maxX,
            y: presentation.endsGroup ? rect.maxY - radius : rect.maxY
        ))

        if presentation.beginsGroup {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
        }

        if presentation.endsGroup {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
        }
        return path
    }
}

enum EditorListMarkerRenderer {
    static func draw(
        _ state: EditorListState,
        ordinal: Int?,
        font: EditorFont,
        in rect: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        if state.kind == .bullet {
            context.setFillColor(EditorColor(editorWhite: 0.32, alpha: 1).cgColor)
            context.fillEllipse(in: rect)
            return
        }

        if state.kind == .numbered {
            let marker = "\(ordinal ?? 1)."
            let markerFont = EditorFontSupport.shared.convert(
                font,
                toSize: min(font.pointSize, 16)
            )
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .right
            let attributes: [NSAttributedString.Key: Any] = [
                .font: markerFont,
                .foregroundColor: EditorColor(editorWhite: 0.32, alpha: 1),
                .paragraphStyle: paragraphStyle
            ]
            let markerHeight = ceil(markerFont.ascender - markerFont.descender)
            (marker as NSString).draw(
                in: CGRect(
                    x: rect.minX,
                    y: rect.midY - markerHeight / 2,
                    width: rect.width,
                    height: markerHeight
                ),
                withAttributes: attributes
            )
            return
        }

        let box = CGPath(
            roundedRect: rect.insetBy(dx: 0.75, dy: 0.75),
            cornerWidth: 4.5,
            cornerHeight: 4.5,
            transform: nil
        )

        if state.isChecked {
            context.setFillColor(EditorColor(editorWhite: 0.46, alpha: 1).cgColor)
            context.addPath(box)
            context.fillPath()

            context.setStrokeColor(EditorColor.white.cgColor)
            context.setLineWidth(2)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: rect.minX + 4, y: rect.midY + 0.1))
            context.addLine(to: CGPoint(x: rect.minX + 7.4, y: rect.maxY - 4))
            context.addLine(to: CGPoint(x: rect.maxX - 3.2, y: rect.minY + 4.1))
            context.strokePath()
        } else {
            context.setFillColor(EditorColor(editorWhite: 0.96, alpha: 1).cgColor)
            context.addPath(box)
            context.fillPath()

            context.setStrokeColor(EditorColor(editorWhite: 0.58, alpha: 1).cgColor)
            context.setLineWidth(1.5)
            context.addPath(box)
            context.strokePath()
        }
    }
}
