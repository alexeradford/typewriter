import SwiftUI
import Observation

@MainActor
@Observable
final class TypewriterEditorSession {
    private(set) var selectionRevision = 0
    private(set) var errorMessage: String?
    var isShowingError = false

    @ObservationIgnored
    weak var textSystem: EditorTextSystem?

    var selectedListKind: EditorListKind? {
        _ = selectionRevision
        return textSystem?.listController.selectedListKind
    }

    var selectedBlockKind: EditorBlockKind? {
        _ = selectionRevision
        return textSystem?.blockController.selectedBlockKind
    }

    var isBold: Bool {
        hasTrait(.boldFontMask)
    }

    var isItalic: Bool {
        hasTrait(.italicFontMask)
    }

    var isUnderlined: Bool {
        _ = selectionRevision
        let style = textSystem?.formattingController
            .currentAttributes[.underlineStyle] as? Int ?? 0
        return style != 0
    }

    var isCodeSnippetSelected: Bool {
        _ = selectionRevision
        return textSystem?.formattingController.isCodeSnippetSelected == true
    }

    func attach(_ textSystem: EditorTextSystem) {
        self.textSystem = textSystem
        refreshSelection()
    }

    func refreshSelection() {
        selectionRevision &+= 1
    }

    func apply(_ style: EditorTextStyle) {
        textSystem?.formattingController.apply(style)
        refreshSelection()
    }

    func toggleBold() {
        textSystem?.formattingController.toggleTrait(.boldFontMask)
        refreshSelection()
    }

    func toggleItalic() {
        textSystem?.formattingController.toggleTrait(.italicFontMask)
        refreshSelection()
    }

    func toggleUnderline() {
        textSystem?.formattingController.toggleUnderline()
        refreshSelection()
    }

    func applyTextColor(_ color: Color) {
        textSystem?.formattingController.applyTextColor(UIColor(color))
        refreshSelection()
    }

    func toggleList(_ kind: EditorListKind) {
        textSystem?.listController.toggleList(kind)
        refreshSelection()
    }

    func toggleChecklistItem() {
        guard textSystem?.listController.toggleChecklistAtSelection() == true else {
            return
        }
        refreshSelection()
    }

    func toggleCodeSnippet() {
        textSystem?.formattingController.toggleCodeSnippet()
        refreshSelection()
    }

    func toggleCodeBlock() {
        textSystem?.blockController.toggleCodeBlock()
        refreshSelection()
    }

    func insertDivider() {
        textSystem?.blockController.insertDivider()
        refreshSelection()
    }

    func insertTable() {
        textSystem?.contentInsertionController.insertTable()
        refreshSelection()
    }

    func insertImages(from urls: [URL]) {
        guard let textSystem else { return }
        let scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        do {
            try textSystem.contentInsertionController.insertImages(from: urls)
        } catch {
            present(error)
        }
    }

    func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    func dismissError() {
        isShowingError = false
        errorMessage = nil
    }

    private func hasTrait(_ trait: EditorFontTrait) -> Bool {
        _ = selectionRevision
        guard let font = textSystem?.formattingController
            .currentAttributes[.font] as? EditorFont else {
            return false
        }
        return EditorFontSupport.shared.traits(of: font).contains(trait)
    }
}
