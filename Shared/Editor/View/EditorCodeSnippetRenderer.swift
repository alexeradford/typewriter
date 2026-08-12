#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Draws the continuous presentation surface for inline code snippets.
///
/// The stored background-color attribute remains the portable rich-text
/// representation. Rendering it here lets the visual surface include trailing
/// whitespace and a small amount of breathing room at the run boundaries,
/// which TextKit's glyph background drawing does not guarantee.
enum EditorCodeSnippetRenderer {
    private static let horizontalInset: CGFloat = 3
    private static let verticalInset: CGFloat = 1
    private static let cornerRadius: CGFloat = 3

    static func draw(
        lineFragments: [NSTextLineFragment],
        context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setFillColor(
            EditorInlineStyle.codeSnippetBackgroundColor.cgColor
        )
        for lineFragment in lineFragments {
            drawCodeSnippetRuns(in: lineFragment, context: context)
        }
    }

    private static func drawCodeSnippetRuns(
        in lineFragment: NSTextLineFragment,
        context: CGContext
    ) {
        let attributedString = lineFragment.attributedString
        let lineRange = lineFragment.characterRange
        guard lineRange.length > 0 else { return }

        attributedString.enumerateAttribute(
            .backgroundColor,
            in: lineRange
        ) { value, range, _ in
            guard EditorInlineStyle.isCodeSnippetBackground(
                value as? EditorColor
            ) else {
                return
            }

            let start = lineFragment.locationForCharacter(
                at: range.location
            ).x
            let end = lineFragment.locationForCharacter(
                at: NSMaxRange(range)
            ).x
            let bounds = lineFragment.typographicBounds
            let rect = CGRect(
                x: min(start, end) - horizontalInset,
                y: bounds.minY + verticalInset,
                width: abs(end - start) + (horizontalInset * 2),
                height: max(0, bounds.height - (verticalInset * 2))
            )
            guard rect.width > 0, rect.height > 0 else { return }

            let path = CGPath(
                roundedRect: rect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
        }
    }
}
