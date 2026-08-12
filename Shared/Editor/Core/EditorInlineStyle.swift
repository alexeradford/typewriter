#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

enum EditorInlineNavigationDirection {
    case backward
    case forward
}

enum EditorInlineStyle {
    static let codeSnippetBackgroundColor = EditorColor(
        editorWhite: 0.90,
        alpha: 1
    )

    static func applyingCodeSnippet(to font: EditorFont) -> EditorFont {
        guard let descriptor = font.fontDescriptor.withDesign(.monospaced) else {
            return EditorFont.monospacedSystemFont(
                ofSize: font.pointSize,
                weight: .regular
            )
        }
#if canImport(AppKit)
        return EditorFont(descriptor: descriptor, size: font.pointSize)
            ?? EditorFont.monospacedSystemFont(
                ofSize: font.pointSize,
                weight: .regular
            )
#else
        return EditorFont(descriptor: descriptor, size: font.pointSize)
#endif
    }

    static func removingCodeSnippet(from font: EditorFont) -> EditorFont {
        guard let descriptor = font.fontDescriptor.withDesign(.default) else {
            return EditorFont.systemFont(ofSize: font.pointSize)
        }
#if canImport(AppKit)
        return EditorFont(descriptor: descriptor, size: font.pointSize)
            ?? EditorFont.systemFont(ofSize: font.pointSize)
#else
        return EditorFont(descriptor: descriptor, size: font.pointSize)
#endif
    }

    static func isCodeSnippetBackground(_ color: EditorColor?) -> Bool {
        guard
            let lhs = color?.editorRGBA,
            let rhs = codeSnippetBackgroundColor.editorRGBA
        else {
            return false
        }
        return abs(lhs.red - rhs.red) < 0.02
            && abs(lhs.green - rhs.green) < 0.02
            && abs(lhs.blue - rhs.blue) < 0.02
            && abs(lhs.alpha - rhs.alpha) < 0.02
    }
}
