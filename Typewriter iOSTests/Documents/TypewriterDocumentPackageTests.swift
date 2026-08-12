import Foundation
import Testing
@testable import Typewriter_iOS

@Suite("Shared document package on iOS")
@MainActor
struct TypewriterDocumentPackageTests {
    @Test("iOS writes and reopens the shared document package")
    func packageRoundTrip() throws {
        let content = NSAttributedString(
            string: "Shared package\nRich document",
            attributes: EditorTextSystem.defaultTypingAttributes
        )
        let metadata = TypewriterDocumentMetadata(
            documentID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Shared package",
            titleOverride: nil,
            previewText: "Shared package Rich document",
            pageCount: 2
        )
        let paperSize = PaperSizePreset.a4.size
        let package = try TypewriterDocumentPackage.makeFileWrapper(
            content: content,
            metadata: metadata,
            paperSize: paperSize
        )
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Typewriter-iOS-\(UUID().uuidString)")
            .appendingPathExtension("typewriter")
        defer { try? FileManager.default.removeItem(at: packageURL) }

        try package.write(
            to: packageURL,
            options: .atomic,
            originalContentsURL: nil
        )
        let reopened = try FileWrapper(url: packageURL, options: .immediate)
        let decoded = try #require(TypewriterDocumentPackage.decode(reopened))

        #expect(decoded.content.string == content.string)
        #expect(decoded.metadata == metadata)
        let decodedPaperSize = decoded.documentAttributes?[
            NSAttributedString.DocumentAttributeKey.paperSize
        ] as? CGSize
        let reopenedPaperSize = try #require(decodedPaperSize)
        #expect(abs(reopenedPaperSize.width - paperSize.width) < 0.1)
        #expect(abs(reopenedPaperSize.height - paperSize.height) < 0.1)
    }
}
