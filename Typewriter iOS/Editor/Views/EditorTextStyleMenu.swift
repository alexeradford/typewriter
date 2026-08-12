import SwiftUI

struct EditorTextStyleMenu: View {
    let session: TypewriterEditorSession

    var body: some View {
        Menu("Text Style", systemImage: "textformat.size") {
            ForEach(EditorTextStyle.menuOrder, id: \.rawValue) { style in
                Button(style.title) {
                    session.apply(style)
                }
            }
        }
        .labelStyle(.iconOnly)
        .frame(minWidth: 44, minHeight: 44)
    }
}
