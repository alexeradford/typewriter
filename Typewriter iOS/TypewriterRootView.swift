import SwiftUI

struct TypewriterRootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var library = MobileDocumentLibrary()
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail

    var body: some View {
        @Bindable var library = library

        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            MobileDocumentLibraryView(library: library) {
                preferredCompactColumn = .detail
            }
        } detail: {
            if let document = library.selectedDocument {
                ContentView(document: document, save: library.save)
                    .id(document.id)
            } else {
                ContentUnavailableView(
                    "No Document Selected",
                    systemImage: "doc.text",
                    description: Text("Choose a document from the Library.")
                )
            }
        }
        .task {
            await library.start()
            preferredCompactColumn = .detail
        }
        .onOpenURL { fileURL in
            Task {
                await library.importAndOpen(fileURL)
                preferredCompactColumn = .detail
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active,
                  let document = library.selectedDocument else {
                return
            }
            Task { await library.save(document) }
        }
        .alert(
            "Couldn’t Update the Library",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.dismissError() } }
            )
        ) {
            Button("OK") { library.dismissError() }
        } message: {
            Text(library.errorMessage ?? "Unknown error")
        }
    }
}

#Preview {
    TypewriterRootView()
}
