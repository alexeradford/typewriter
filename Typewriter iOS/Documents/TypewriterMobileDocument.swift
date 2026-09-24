import SwiftUI
import UniformTypeIdentifiers
import Combine

extension UTType {
    static let typewriterDocument = UTType(
        exportedAs: "ca.alexradford.typewriter-document",
        conformingTo: .package
    )
}

final class TypewriterMobileDocument: ObservableObject, Identifiable, @unchecked Sendable {
    nonisolated struct Snapshot: @unchecked Sendable {
        let content: NSAttributedString
        let metadata: TypewriterDocumentMetadata
        let paperSize: CGSize
    }

    @Published private(set) var revision = 0
    @Published private(set) var fileURL: URL?
    private(set) var contentRevision = 0
    private(set) var content: NSAttributedString
    private(set) var metadata: TypewriterDocumentMetadata
    private(set) var paperSize: CGSize
    private(set) var savedRevision = 0

    var id: UUID { metadata.documentID }
    var hasUnsavedChanges: Bool { revision != savedRevision }

    init() {
        fileURL = nil
        content = NSAttributedString()
        metadata = TypewriterDocumentMetadata(
            documentID: UUID(),
            createdAt: Date(),
            title: "Untitled",
            titleOverride: nil,
            previewText: "",
            pageCount: 1
        )
        paperSize = PaperSizePreset.letter.size
    }

    init(snapshot: Snapshot, fileURL: URL) {
        self.fileURL = fileURL
        content = snapshot.content.copy() as? NSAttributedString
            ?? NSAttributedString()
        metadata = snapshot.metadata
        paperSize = snapshot.paperSize
    }

    nonisolated static func decode(
        _ fileWrapper: FileWrapper
    ) throws -> Snapshot {
        guard let decoded = TypewriterDocumentPackage.decode(fileWrapper) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey:
                    "This Typewriter document is damaged or uses an unsupported format."
            ])
        }
        let metadata = decoded.metadata ?? TypewriterDocumentMetadata(
            documentID: UUID(),
            createdAt: Date(),
            title: Self.title(from: decoded.content),
            titleOverride: nil,
            previewText: Self.preview(from: decoded.content),
            pageCount: 1
        )
        return Snapshot(
            content: decoded.content,
            metadata: metadata,
            paperSize: Self.paperSize(from: decoded.documentAttributes)
        )
    }

    func snapshot() -> Snapshot {
        Snapshot(
            content: content.copy() as? NSAttributedString ?? NSAttributedString(),
            metadata: metadata,
            paperSize: paperSize
        )
    }

    nonisolated static func fileWrapper(
        for snapshot: Snapshot
    ) throws -> FileWrapper {
        try TypewriterDocumentPackage.makeFileWrapper(
            content: snapshot.content,
            metadata: snapshot.metadata,
            paperSize: snapshot.paperSize
        )
    }

    func markSaved(at fileURL: URL, revision: Int) {
        self.fileURL = fileURL
        savedRevision = max(savedRevision, revision)
    }

    @discardableResult
    func updateEditorContent(
        _ content: NSAttributedString,
        pageCount: Int
    ) -> Int {
        self.content = content.copy() as? NSAttributedString ?? NSAttributedString()
        metadata.title = metadata.titleOverride ?? Self.title(from: content)
        metadata.previewText = Self.preview(from: content)
        metadata.pageCount = max(1, pageCount)
        contentRevision += 1
        revision += 1
        return revision
    }

    func updatePaperSize(_ size: CGSize, contentHeight: CGFloat? = nil) {
        guard paperSize != size else { return }
        paperSize = size
        if let contentHeight {
            metadata.pageCount = EditorPageLayout(paperSize: size).pageCount(
                forTextHeight: contentHeight
            )
        }
        revision += 1
    }

    private nonisolated static func title(
        from content: NSAttributedString
    ) -> String {
        let firstLine = content.string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return String((firstLine ?? "Untitled").prefix(80))
    }

    private nonisolated static func preview(
        from content: NSAttributedString
    ) -> String {
        let value = content.string
            .replacingOccurrences(of: EditorBlockStyle.dividerMarker, with: "")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(value.prefix(240))
    }

    private nonisolated static func paperSize(
        from attributes: NSDictionary?
    ) -> CGSize {
        if let size = attributes?[NSAttributedString.DocumentAttributeKey.paperSize]
            as? CGSize {
            return size
        }
        if let value = attributes?[NSAttributedString.DocumentAttributeKey.paperSize]
            as? NSValue {
            return value.cgSizeValue
        }
        return PaperSizePreset.letter.size
    }
}

extension TypewriterMobileDocument: Hashable {
    static func == (
        lhs: TypewriterMobileDocument,
        rhs: TypewriterMobileDocument
    ) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
