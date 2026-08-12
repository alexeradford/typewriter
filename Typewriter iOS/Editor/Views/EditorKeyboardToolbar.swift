import SwiftUI

struct EditorKeyboardToolbar: View {
    let session: TypewriterEditorSession
    @Binding var isImportingImage: Bool

    var body: some View {
        HStack(spacing: 0) {
            EditorFormatButton(
                title: "Bold",
                systemImage: "bold",
                isSelected: session.isBold,
                action: session.toggleBold
            )
            EditorFormatButton(
                title: "Italic",
                systemImage: "italic",
                isSelected: session.isItalic,
                action: session.toggleItalic
            )
            EditorFormatButton(
                title: "Underline",
                systemImage: "underline",
                isSelected: session.isUnderlined,
                action: session.toggleUnderline
            )
            Spacer()
            EditorListMenu(session: session)
            EditorInsertMenu(
                session: session,
                isImportingImage: $isImportingImage
            )
        }
    }
}
