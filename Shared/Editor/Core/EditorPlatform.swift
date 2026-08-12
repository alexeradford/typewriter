#if canImport(AppKit)
import AppKit

typealias EditorFont = NSFont
typealias EditorColor = NSColor
typealias EditorImage = NSImage
typealias EditorBezierPath = NSBezierPath
typealias EditorFontDescriptor = NSFontDescriptor
typealias EditorFontTrait = NSFontTraitMask
#else
import UIKit

typealias EditorFont = UIFont
typealias EditorColor = UIColor
typealias EditorImage = UIImage
typealias EditorBezierPath = UIBezierPath
typealias EditorFontDescriptor = UIFontDescriptor

struct EditorFontTrait: OptionSet {
    let rawValue: Int

    static let boldFontMask = EditorFontTrait(rawValue: 1 << 0)
    static let italicFontMask = EditorFontTrait(rawValue: 1 << 1)
}
#endif

extension EditorColor {
    convenience init(editorWhite white: CGFloat, alpha: CGFloat) {
#if canImport(AppKit)
        self.init(calibratedWhite: white, alpha: alpha)
#else
        self.init(white: white, alpha: alpha)
#endif
    }

    var editorRGBA: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
#if canImport(AppKit)
        guard let color = usingColorSpace(.deviceRGB) else { return nil }
        return (
            color.redComponent,
            color.greenComponent,
            color.blueComponent,
            color.alphaComponent
        )
#else
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return (red, green, blue, alpha)
#endif
    }
}

final class EditorFontSupport {
    static let shared = EditorFontSupport()

    func familyName(of font: EditorFont) -> String {
#if canImport(AppKit)
        font.familyName ?? font.fontName
#else
        font.familyName
#endif
    }

    func convert(_ font: EditorFont, toFamily family: String) -> EditorFont {
#if canImport(AppKit)
        NSFontManager.shared.convert(font, toFamily: family)
#else
        let descriptor = font.fontDescriptor.withFamily(family)
        return EditorFont(descriptor: descriptor, size: font.pointSize)
#endif
    }

    func convert(_ font: EditorFont, toSize size: CGFloat) -> EditorFont {
#if canImport(AppKit)
        NSFontManager.shared.convert(font, toSize: size)
#else
        font.withSize(size)
#endif
    }

    func traits(of font: EditorFont) -> EditorFontTrait {
#if canImport(AppKit)
        NSFontManager.shared.traits(of: font)
#else
        var traits: EditorFontTrait = []
        let symbolicTraits = font.fontDescriptor.symbolicTraits
        if symbolicTraits.contains(.traitBold) {
            traits.insert(.boldFontMask)
        }
        if symbolicTraits.contains(.traitItalic) {
            traits.insert(.italicFontMask)
        }
        return traits
#endif
    }

    func convert(
        _ font: EditorFont,
        toHaveTrait trait: EditorFontTrait
    ) -> EditorFont {
#if canImport(AppKit)
        NSFontManager.shared.convert(font, toHaveTrait: trait)
#else
        applying(trait, to: font, removing: false)
#endif
    }

    func convert(
        _ font: EditorFont,
        toNotHaveTrait trait: EditorFontTrait
    ) -> EditorFont {
#if canImport(AppKit)
        NSFontManager.shared.convert(font, toNotHaveTrait: trait)
#else
        applying(trait, to: font, removing: true)
#endif
    }

#if !canImport(AppKit)
    private func applying(
        _ trait: EditorFontTrait,
        to font: EditorFont,
        removing: Bool
    ) -> EditorFont {
        var symbolicTraits = font.fontDescriptor.symbolicTraits
        let platformTrait: UIFontDescriptor.SymbolicTraits
        if trait.contains(.boldFontMask) {
            platformTrait = .traitBold
        } else {
            platformTrait = .traitItalic
        }
        if removing {
            symbolicTraits.remove(platformTrait)
        } else {
            symbolicTraits.insert(platformTrait)
        }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(symbolicTraits) else {
            return font
        }
        return EditorFont(descriptor: descriptor, size: font.pointSize)
    }
#endif
}

extension NSTextContainer {
    var editorContainerSize: CGSize {
        get {
#if canImport(AppKit)
            containerSize
#else
            size
#endif
        }
        set {
#if canImport(AppKit)
            containerSize = newValue
#else
            size = newValue
#endif
        }
    }
}
