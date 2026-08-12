import SwiftUI

struct EditorListMenu: View {
    let session: TypewriterEditorSession

    var body: some View {
        Menu("Lists", systemImage: listIcon) {
            Button("Bulleted List", systemImage: "list.bullet") {
                session.toggleList(.bullet)
            }
            Button("Numbered List", systemImage: "list.number") {
                session.toggleList(.numbered)
            }
            Button("Checklist", systemImage: "checklist") {
                session.toggleList(.checklist)
            }
            if session.selectedListKind == .checklist {
                Divider()
                Button(
                    "Toggle Item",
                    systemImage: "checkmark.square",
                    action: session.toggleChecklistItem
                )
            }
        }
        .labelStyle(.iconOnly)
        .frame(minWidth: 44, minHeight: 44)
        .background(
            session.selectedListKind == nil
                ? Color.clear
                : Color.accentColor.opacity(0.14),
            in: .rect(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    session.selectedListKind == nil
                        ? Color.clear
                        : Color.accentColor,
                    lineWidth: 1.5
                )
        }
        .accessibilityAddTraits(
            session.selectedListKind == nil ? [] : .isSelected
        )
    }

    private var listIcon: String {
        switch session.selectedListKind {
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .checklist: "checklist"
        case nil: "list.bullet"
        }
    }
}
