import Foundation
import Testing
import UIKit
@testable import Typewriter_iOS

@Suite("Shared TextKit editor on iOS")
@MainActor
struct EditorTextSystemTests {
    @Test("UIKit owns a working shared TextKit 2 editing graph")
    func sharedTextKitEditingGraph() throws {
        let system = EditorTextSystem(
            content: NSAttributedString(),
            containerWidth: 320
        )

        system.textView.insertText("Port verification\nSecond paragraph")
        #expect(system.textStorage.string == "Port verification\nSecond paragraph")

        let undoManager = try #require(system.textView.undoManager)
        undoManager.undo()
        #expect(system.textStorage.string.isEmpty)
        undoManager.redo()
        #expect(system.textStorage.string == "Port verification\nSecond paragraph")

        system.textView.setSelectedRange(NSRange(location: 0, length: 4))
        system.formattingController.toggleTrait(.boldFontMask)
        let font = try #require(
            system.textStorage.attribute(.font, at: 0, effectiveRange: nil)
                as? UIFont
        )
        #expect(EditorFontSupport.shared.traits(of: font).contains(.boldFontMask))

        system.textView.setSelectedRange(NSRange(location: 18, length: 0))
        system.listController.toggleList(.checklist)
        #expect(system.listController.selectedListKind == .checklist)

        system.textView.setSelectedRange(NSRange(
            location: system.textStorage.length,
            length: 0
        ))
        system.contentInsertionController.insertTable(rows: 2, columns: 2)
        #expect(system.textStorage.string.contains("\t"))
        #expect(system.contentHeight(ensuringFullLayout: true) > 0)
    }
}
