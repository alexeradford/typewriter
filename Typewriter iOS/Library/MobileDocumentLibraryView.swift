import SwiftUI

struct MobileDocumentLibraryView: View {
    let library: MobileDocumentLibrary
    let showEditor: () -> Void

    @State private var searchText = ""
    @State private var isImporting = false
    @State private var pendingDeletion: MobileLibraryItem?

    var body: some View {
        Group {
            if filteredItems.isEmpty && !library.isLoading {
                ContentUnavailableView {
                    Label(
                        searchText.isEmpty ? "No Documents" : "No Results",
                        systemImage: searchText.isEmpty
                            ? "doc.text"
                            : "magnifyingglass"
                    )
                } description: {
                    Text(
                        searchText.isEmpty
                            ? "Start writing and your documents will appear here."
                            : "No documents match “\(searchText)”."
                    )
                } actions: {
                    if searchText.isEmpty {
                        Button("New Document", systemImage: "square.and.pencil") {
                            createDocument()
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            } else {
                List(filteredItems) { item in
                    Button {
                        Task {
                            await library.open(item)
                            showEditor()
                        }
                    } label: {
                        MobileDocumentLibraryRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDeletion = item
                        }
                    }
                    .contextMenu {
                        Button("Open", systemImage: "doc.text") {
                            Task {
                                await library.open(item)
                                showEditor()
                            }
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDeletion = item
                        }
                    }
                    .accessibilityIdentifier("library.document.\(item.id.uuidString)")
                }
                .refreshable {
                    await library.refresh()
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search Documents")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("Library Actions", systemImage: "ellipsis") {
                    Button("Import Document", systemImage: "square.and.arrow.down") {
                        isImporting = true
                    }
                }
                Button("New Document", systemImage: "square.and.pencil") {
                    createDocument()
                }
                .accessibilityIdentifier("library.new-document")
            }
        }
        .overlay {
            if library.isLoading && library.items.isEmpty {
                ProgressView("Loading Library")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.typewriterDocument]
        ) { result in
            if case .success(let fileURL) = result {
                Task {
                    await library.importAndOpen(fileURL)
                    showEditor()
                }
            } else if case .failure(let error) = result {
                library.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.title ?? "Document")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let item = pendingDeletion else { return }
                pendingDeletion = nil
                Task { await library.delete(item) }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("This removes the document from your Typewriter Library.")
        }
    }

    private var filteredItems: [MobileLibraryItem] {
        guard !searchText.isEmpty else { return library.items }
        return library.items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.previewText.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func createDocument() {
        library.newDocument()
        showEditor()
    }
}

private struct MobileDocumentLibraryRow: View {
    let item: MobileLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(item.modifiedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !item.previewText.isEmpty {
                Text(item.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Text("^[\(item.pageCount) page](inflect: true)")
                if let folderName = item.folderName {
                    Label(folderName, systemImage: "folder")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
    }
}
