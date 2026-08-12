#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

enum EditorTextStyle: Int, CaseIterable {
    // Preserve the original raw values because toolbar items use them as stable
    // represented values.
    case body = 0
    case heading = 1
    case title = 2
    case subtitle = 3
    case subheading = 4

    static let menuOrder: [EditorTextStyle] = [
        .title,
        .subtitle,
        .heading,
        .subheading,
        .body
    ]

    var title: String {
        switch self {
        case .body: "Body"
        case .subheading: "Subheading"
        case .heading: "Heading"
        case .subtitle: "Subtitle"
        case .title: "Title"
        }
    }

    var font: EditorFont {
#if canImport(AppKit)
        let systemFont: EditorFont
        switch self {
        case .body: systemFont = .systemFont(ofSize: 15)
        case .subheading: systemFont = .systemFont(ofSize: 16, weight: .medium)
        case .heading: systemFont = .systemFont(ofSize: 18, weight: .semibold)
        case .subtitle: systemFont = .systemFont(ofSize: 20)
        case .title: systemFont = .systemFont(ofSize: 34, weight: .bold)
        }
        guard let family = GeneralPreferences.defaultFontFamily else {
            return systemFont
        }
        return EditorFontSupport.shared.convert(systemFont, toFamily: family)
#else
        switch self {
        case .body:
            EditorFont.preferredFont(forTextStyle: .body)
        case .subheading:
            EditorFont.preferredFont(forTextStyle: .headline)
        case .heading:
            EditorFont.preferredFont(forTextStyle: .title3)
        case .subtitle:
            EditorFont.preferredFont(forTextStyle: .title2)
        case .title:
            EditorFontSupport.shared.convert(
                EditorFont.preferredFont(forTextStyle: .largeTitle),
                toHaveTrait: .boldFontMask
            )
        }
#endif
    }

    var paragraphSpacing: CGFloat {
        switch self {
        case .body: 5
        case .subheading: 8
        case .heading: 12
        case .subtitle: 14
        case .title: 18
        }
    }

}
