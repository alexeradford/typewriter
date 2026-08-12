import SwiftUI

struct EditorDocumentMenu: View {
    @ObservedObject var document: TypewriterMobileDocument
    let session: TypewriterEditorSession

    var body: some View {
        Menu("Document Options", systemImage: "ellipsis.circle") {
            Section("Paper Size") {
                ForEach(PaperSizePreset.allCases, id: \.rawValue) { preset in
                    Button {
                        applyPaperSize(preset)
                    } label: {
                        if document.paperSize == preset.size {
                            Label(preset.displayName, systemImage: "checkmark")
                        } else {
                            Text(preset.displayName)
                        }
                    }
                }
            }
            Section {
                Text("^[\(document.metadata.pageCount) page](inflect: true)")
                Text("^[\(wordCount) word](inflect: true)")
            }
        }
    }

    private var wordCount: Int {
        document.content.string.split(whereSeparator: \.isWhitespace).count
    }

    private func applyPaperSize(_ preset: PaperSizePreset) {
        document.updatePaperSize(
            preset.size,
            contentHeight: session.textSystem?.contentHeight()
        )
    }
}
