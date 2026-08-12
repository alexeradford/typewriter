import AppKit

enum TypewriterTheme {
    static let accent = NSColor.systemIndigo
    static let canvas = NSColor.underPageBackgroundColor
    static let paper = NSColor(calibratedRed: 1.0, green: 0.995, blue: 0.975, alpha: 1)
    static let secondaryPaperText = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.66, alpha: 1)
            : NSColor(calibratedWhite: 0.38, alpha: 1)
    }
}
