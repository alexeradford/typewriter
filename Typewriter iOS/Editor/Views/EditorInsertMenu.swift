import SwiftUI

struct EditorInsertMenu: View {
    let session: TypewriterEditorSession
    @Binding var isImportingImage: Bool

    var body: some View {
        Menu("Insert", systemImage: "plus") {
            Button("Image", systemImage: "photo") {
                isImportingImage = true
            }
            Button("Table", systemImage: "tablecells", action: session.insertTable)
            Button("Divider", systemImage: "minus", action: session.insertDivider)
            Button(
                "Code Block",
                systemImage: "curlybraces.square",
                action: session.toggleCodeBlock
            )
        }
    }
}
