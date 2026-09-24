import SwiftUI

struct EditorFormattingToolbar: ToolbarContent {
    let placement: ToolbarItemPlacement
    let includesSpacer: Bool
    let session: TypewriterEditorSession
    @Binding var textColor: Color

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: placement) {
            EditorTextStyleMenu(session: session)
            toolbarButton(
                title: "Bold",
                systemImage: "bold",
                isSelected: session.isBold,
                action: session.toggleBold
            )
            toolbarButton(
                title: "Italic",
                systemImage: "italic",
                isSelected: session.isItalic,
                action: session.toggleItalic
            )
            toolbarButton(
                title: "Underline",
                systemImage: "underline",
                isSelected: session.isUnderlined,
                action: session.toggleUnderline
            )
        }

        if includesSpacer {
            ToolbarSpacer(.fixed, placement: placement)
        }

        ToolbarItemGroup(placement: placement) {
            EditorTextColorPicker(
                session: session,
                textColor: $textColor
            )
            EditorListMenu(session: session)
            moreFormattingMenu
        }
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    }
}
