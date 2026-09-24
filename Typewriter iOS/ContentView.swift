import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: TypewriterMobileDocument
    let save: (TypewriterMobileDocument) async -> Void

    @State private var session = TypewriterEditorSession()
    @State private var isImportingImage = false
    @State private var isEditing = false
    @State private var textColor = Color.primary

    var body: some View {
        @Bindable var session = session

        TypewriterTextEditor(
            document: document,
            session: session,
            isEditing: $isEditing
        )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isEditing {
                    EditorKeyboardFormattingBar(
                        session: session,
                        textColor: $textColor
                    )
                }
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
                if !isEditing {
                    EditorFormattingToolbar(
                        placement: .bottomBar,
                        includesSpacer: true,
                        session: session,
                        textColor: $textColor
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
            .task(id: document.revision) {
                guard document.hasUnsavedChanges else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await save(document)
            }
    }

    private var displayTitle: String {
        document.metadata.title
    }

}

#Preview {
    NavigationStack {
        ContentView(document: TypewriterMobileDocument()) { _ in }
    }
}
