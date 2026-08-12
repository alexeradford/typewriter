import AppKit
import XCTest
@testable import Typewriter

final class EditorFontPresentationTests: XCTestCase {
    private var savedDefaultFontFamily: Any?

    override func setUp() {
        super.setUp()
        savedDefaultFontFamily = UserDefaults.standard.object(
            forKey: GeneralPreferences.defaultFontFamilyKey
        )
        UserDefaults.standard.removeObject(
            forKey: GeneralPreferences.defaultFontFamilyKey
        )
    }

    override func tearDown() {
        if let savedDefaultFontFamily {
            UserDefaults.standard.set(
                savedDefaultFontFamily,
                forKey: GeneralPreferences.defaultFontFamilyKey
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: GeneralPreferences.defaultFontFamilyKey
            )
        }
        super.tearDown()
    }

    func testRTFRoundTrippedSystemFontStillPresentsAsSystemBody() throws {
        let source = NSAttributedString(
            string: "Body",
            attributes: [.font: NSFont.systemFont(ofSize: 15)]
        )
        let data = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtfd
            ]
        )
        let decoded = try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.rtfd
            ],
            documentAttributes: nil
        )
        let font = try XCTUnwrap(
            decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )

        XCTAssertEqual(EditorFontPresentation.familyTitle(for: font), "System")
        XCTAssertEqual(
            EditorFontPresentation.matchingTextStyle(for: font),
            .body
        )
    }

    func testNamedFontRetainsItsFamilyPresentation() throws {
        let font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 15))

        XCTAssertEqual(
            EditorFontPresentation.familyTitle(for: font),
            "Menlo"
        )
        XCTAssertNil(EditorFontPresentation.matchingTextStyle(for: font))
    }
}
