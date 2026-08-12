import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: TypewriterMobileDocument
    let fileURL: URL?

    @State private var session = TypewriterEditorSession()
    @State private var isImportingImage = false
    @State private var textColor = Color.primary

    var body: some View {
        @Bindable var session = session

        TypewriterTextEditor(document: document, session: session)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EditorFormattingBar(
                    session: session,
                    textColor: $textColor
                )
            }
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditorInsertMenu(
                        session: session,
                        isImportingImage: $isImportingImage
                    )
                    EditorDocumentMenu(
                        document: document,
                        session: session
                    )
                }
                ToolbarItemGroup(placement: .keyboard) {
                    EditorKeyboardToolbar(
                        session: session,
                        isImportingImage: $isImportingImage
                    )
                }
            }
            .fileImporter(
                isPresented: $isImportingImage,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    session.insertImages(from: urls)
                case .failure(let error):
                    session.present(error)
                }
            }
            .alert(
                "Couldn’t Complete That Action",
                isPresented: $session.isShowingError
            ) { } message: {
                Text(session.errorMessage ?? "Unknown error")
            }
            .onChange(of: session.isShowingError) { _, isShowing in
                if !isShowing {
                    session.dismissError()
                }
            }
    }

    private var displayTitle: String {
        fileURL?.deletingPathExtension().lastPathComponent
            ?? document.metadata.title
    }

}

#Preview {
    NavigationStack {
        ContentView(document: TypewriterMobileDocument(), fileURL: nil)
    }
}
