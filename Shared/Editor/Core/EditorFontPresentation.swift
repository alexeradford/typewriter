#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

enum EditorFontPresentation {
    static func familyTitle(for font: EditorFont) -> String {
        isSystemFont(font)
            ? "System"
            : EditorFontSupport.shared.familyName(of: font)
    }

    static func matchingTextStyle(for font: EditorFont) -> EditorTextStyle? {
        EditorTextStyle.allCases.first { style in
            let preset = style.font
            guard abs(font.pointSize - preset.pointSize) < 0.01 else {
                return false
            }
            if font.fontName == preset.fontName {
                return true
            }
            return isSystemFont(font)
                && isSystemFont(preset)
                && EditorFontSupport.shared.traits(of: font)
                    == EditorFontSupport.shared.traits(of: preset)
        }
    }

    static func isSystemFont(_ font: EditorFont) -> Bool {
        if systemFontNames.contains(font.fontName) {
            return true
        }
        return rtfSystemFontNames.contains(font.fontName)
    }

    private static let systemFontNames: Set<String> = {
        Set(systemFontVariants.map(\.fontName))
    }()

    // RTF does not retain AppKit's private system-font names. Derive the
    // fallback names from AppKit itself so toolbar presentation follows the
    // current OS rather than assuming a particular backing font family.
    private static let rtfSystemFontNames: Set<String> = {
        var names = Set<String>()
        for font in systemFontVariants {
            if let name = roundTrippedFontName(font) {
                names.insert(name)
            }
        }
        return names
    }()

    private static let systemFontVariants: [EditorFont] = {
        let weights: [EditorFont.Weight] = [
            .ultraLight, .thin, .light, .regular, .medium,
            .semibold, .bold, .heavy, .black
        ]
        let manager = EditorFontSupport.shared
        return weights.flatMap { weight -> [EditorFont] in
            let upright = EditorFont.systemFont(ofSize: 15, weight: weight)
            let italic = manager.convert(
                upright,
                toHaveTrait: .italicFontMask
            )
            return [upright, italic]
        }
    }()

    private static func roundTrippedFontName(_ font: EditorFont) -> String? {
        let source = NSAttributedString(
            string: "x",
            attributes: [.font: font]
        )
        guard
            let data = try? source.data(
                from: NSRange(location: 0, length: source.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.rtfd
                ]
            ),
            let decoded = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.rtfd
                ],
                documentAttributes: nil
            ),
            let decodedFont = decoded.attribute(
                .font,
                at: 0,
                effectiveRange: nil
            ) as? EditorFont
        else {
            return nil
        }
        return decodedFont.fontName
    }
}
