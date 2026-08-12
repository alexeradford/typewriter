import AppKit
import Testing
@testable import Typewriter

@MainActor
struct EditorViewStateTests {
    @Test
    func replacingDocumentContentRestoresAndClampsTheSelection() {
        let editor = EditorViewController(
            documentContent: NSAttributedString(string: "First document"),
            pageLayout: EditorPageLayout(printInfo: NSPrintInfo())
        )
        _ = editor.view
        editor.textView.setSelectedRange(NSRange(location: 5, length: 3))
        let savedState = editor.documentViewState

        editor.replaceDocumentContent(
            NSAttributedString(string: "Replacement document"),
            pageLayout: EditorPageLayout(printInfo: NSPrintInfo()),
            restoring: savedState
        )
        #expect(editor.textView.selectedRange() == savedState.selectedRange)

        editor.replaceDocumentContent(
            NSAttributedString(string: "Tiny"),
            pageLayout: EditorPageLayout(printInfo: NSPrintInfo()),
            restoring: savedState
        )
        #expect(
            editor.textView.selectedRange()
                == NSRange(location: 4, length: 0)
        )
    }
}
