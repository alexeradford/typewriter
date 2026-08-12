#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

struct EditorPageLayout: Equatable {
    nonisolated static let margin: CGFloat = 54
    nonisolated static let pageGap: CGFloat = 28

    let paperSize: CGSize

    init(paperSize: CGSize) {
        self.paperSize = CGSize(
            width: max(240, paperSize.width),
            height: max(320, paperSize.height)
        )
    }

#if canImport(AppKit)
    init(printInfo: NSPrintInfo) {
        self.init(paperSize: printInfo.paperSize)
    }
#endif

    var contentSize: CGSize {
        CGSize(
            width: paperSize.width - (Self.margin * 2),
            height: paperSize.height - (Self.margin * 2)
        )
    }

    var textPageStride: CGFloat {
        contentSize.height + (Self.margin * 2) + Self.pageGap
    }

    func canvasHeight(pageCount: Int) -> CGFloat {
        paperSize.height * CGFloat(max(1, pageCount))
            + Self.pageGap * CGFloat(max(0, pageCount - 1))
    }

    func pageFrame(at index: Int) -> CGRect {
        CGRect(
            x: 0,
            y: CGFloat(index) * (paperSize.height + Self.pageGap),
            width: paperSize.width,
            height: paperSize.height
        )
    }

    func pageIndex(forTextOffsetY offsetY: CGFloat) -> Int {
        max(0, Int(floor(max(0, offsetY) / textPageStride)))
    }

    func pageCount(forTextHeight textHeight: CGFloat) -> Int {
        pageIndex(forTextOffsetY: max(0, textHeight - 1)) + 1
    }

    func snappedLineFragmentRect(
        for proposedRect: CGRect,
        closingLineHeight: CGFloat
    ) -> CGRect {
        let pageOffset = proposedRect.minY.truncatingRemainder(
            dividingBy: textPageStride
        )
        guard pageOffset >= 0 else { return proposedRect }

        let crossesPageBottom = pageOffset + proposedRect.height
            > contentSize.height
        guard pageOffset >= contentSize.height || crossesPageBottom else {
            return proposedRect
        }

        var snappedRect = proposedRect
        // A newline-only fragment represents the line being closed, while the
        // insertion point after that newline belongs to the following line.
        // Park the closing fragment immediately before the next page so the
        // trailing insertion point begins at that page's content origin.
        snappedRect.origin.y += textPageStride
            - pageOffset
            - closingLineHeight
        return snappedRect
    }

    func exclusionPaths(pageCapacity: Int) -> [EditorBezierPath] {
        guard pageCapacity > 1 else { return [] }
        let excludedHeight = (Self.margin * 2) + Self.pageGap
        return (1..<pageCapacity).map { pageIndex in
            let y = CGFloat(pageIndex - 1) * textPageStride
                + contentSize.height
            return EditorBezierPath(rect: CGRect(
                x: 0,
                y: y,
                width: contentSize.width,
                height: excludedHeight
            ))
        }
    }
}

enum PaperSizePreset: String, CaseIterable {
    case letter
    case a4
    case legal

    var displayName: String {
        switch self {
        case .letter: "US Letter"
        case .a4: "A4"
        case .legal: "US Legal"
        }
    }

    var size: CGSize {
        switch self {
        case .letter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .legal: CGSize(width: 612, height: 1008)
        }
    }
}
