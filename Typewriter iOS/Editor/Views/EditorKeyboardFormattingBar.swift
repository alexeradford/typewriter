import SwiftUI

struct EditorKeyboardFormattingBar: View {
    let session: TypewriterEditorSession
    @Binding var textColor: Color

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    primaryFormattingGroup
                    secondaryFormattingGroup
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .accessibilityIdentifier("editor.keyboard-formatting-bar")
    }

    private var primaryFormattingGroup: some View {
        HStack(spacing: 4) {
            EditorTextStyleMenu(session: session)
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
        }
        .font(.system(size: 20, weight: .medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }

    private var secondaryFormattingGroup: some View {
        HStack(spacing: 4) {
            EditorTextColorPicker(
                session: session,
                textColor: $textColor
            )
            EditorListMenu(session: session)
            moreFormattingMenu
        }
        .font(.system(size: 20, weight: .medium))
        .controlSize(.large)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }

    private var moreFormattingMenu: some View {
        Menu("More Formatting", systemImage: "ellipsis") {
            Button {
                session.toggleCodeSnippet()
            } label: {
                Label(
                    "Inline Code",
                    systemImage: session.isCodeSnippetSelected
                        ? "checkmark"
                        : "chevron.left.forwardslash.chevron.right"
                )
            }
            Button {
                session.toggleCodeBlock()
            } label: {
                Label(
                    "Code Block",
                    systemImage: session.selectedBlockKind == .code
                        ? "checkmark"
                        : "curlybraces.square"
                )
            }
        }
        .labelStyle(.iconOnly)
        .frame(minWidth: 44, minHeight: 44)
    }
}
