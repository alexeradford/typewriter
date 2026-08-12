import SwiftUI

struct EditorFormattingBar: View {
    let session: TypewriterEditorSession
    @Binding var textColor: Color

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                EditorTextStyleMenu(session: session)
                Divider().frame(height: 24)
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
                EditorTextColorPicker(
                    session: session,
                    textColor: $textColor
                )
                Divider().frame(height: 24)
                EditorListMenu(session: session)
                EditorFormatButton(
                    title: "Inline Code",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    isSelected: session.isCodeSnippetSelected,
                    action: session.toggleCodeSnippet
                )
                EditorFormatButton(
                    title: "Code Block",
                    systemImage: "curlybraces.square",
                    isSelected: session.selectedBlockKind == .code,
                    action: session.toggleCodeBlock
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
