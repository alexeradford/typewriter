#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

nonisolated struct TypewriterDocumentMetadata:
    Codable,
    Equatable,
    Sendable {
    static let currentVersion = 1

    var version = currentVersion
    let documentID: UUID
    let createdAt: Date
    var title: String
    var titleOverride: String?
    var previewText: String
    var pageCount: Int
}

nonisolated enum TypewriterDocumentPackage {
    static let contentFilename = "Content.rtfd"
    static let metadataFilename = "Metadata.json"

    struct DecodedContent {
        let content: NSAttributedString
        let documentAttributes: NSDictionary?
        let metadata: TypewriterDocumentMetadata?
    }

    static func makeFileWrapper(
        content: NSAttributedString,
        metadata: TypewriterDocumentMetadata,
        paperSize: CGSize
    ) throws -> FileWrapper {
        let contentWrapper = try content.fileWrapper(
            from: NSRange(location: 0, length: content.length),
            documentAttributes: documentAttributes(paperSize: paperSize)
        )
        contentWrapper.preferredFilename = contentFilename

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let metadataWrapper = FileWrapper(
            regularFileWithContents: try encoder.encode(metadata)
        )
        metadataWrapper.preferredFilename = metadataFilename

        let package = FileWrapper(directoryWithFileWrappers: [:])
        package.addFileWrapper(contentWrapper)
        package.addFileWrapper(metadataWrapper)
        return package
    }

    nonisolated static func decode(
        _ wrapper: FileWrapper
    ) -> DecodedContent? {
        if wrapper.isDirectory,
           let children = wrapper.fileWrappers,
           let contentWrapper = children[contentFilename] {
            var attributes: NSDictionary?
            guard let content = decodeRTFD(
                contentWrapper,
                documentAttributes: &attributes
            ) else {
                return nil
            }
            let metadata = children[metadataFilename]?
                .regularFileContents
                .flatMap(decodeMetadata)
            return DecodedContent(
                content: content,
                documentAttributes: attributes,
                metadata: metadata
            )
        }

        guard
            let data = wrapper.regularFileContents,
            let legacy = decodeLegacy(data)
        else {
            return nil
        }
        return DecodedContent(
            content: legacy.content,
            documentAttributes: legacy.documentAttributes,
            metadata: nil
        )
    }

    nonisolated static func decodeLegacy(
        _ data: Data
    ) -> DecodedContent? {
        for documentType in [
            NSAttributedString.DocumentType.rtfd,
            NSAttributedString.DocumentType.rtf
        ] {
            var attributes: NSDictionary?
            if let content = try? NSAttributedString(
                data: data,
                options: [.documentType: documentType],
                documentAttributes: &attributes
            ) {
                return DecodedContent(
                    content: content,
                    documentAttributes: attributes,
                    metadata: nil
                )
            }
        }
        return nil
    }

    static func metadata(at documentURL: URL) -> TypewriterDocumentMetadata? {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: documentURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return nil
        }
        let metadataURL = documentURL.appendingPathComponent(
            metadataFilename,
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: metadataURL) else {
            return nil
        }
        return decodeMetadata(data)
    }

    static func updateMetadata(
        at documentURL: URL,
        title: String,
        titleOverride: String?
    ) {
        guard var metadata = metadata(at: documentURL) else { return }
        metadata.title = title
        metadata.titleOverride = titleOverride
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(metadata) else { return }
        let metadataURL = documentURL.appendingPathComponent(
            metadataFilename,
            isDirectory: false
        )
        try? data.write(to: metadataURL, options: .atomic)
    }

    private nonisolated static func decodeMetadata(
        _ data: Data
    ) -> TypewriterDocumentMetadata? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            TypewriterDocumentMetadata.self,
            from: data
        )
    }

    private static func documentAttributes(
        paperSize: CGSize
    ) -> [NSAttributedString.DocumentAttributeKey: Any] {
        var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtfd,
            .paperSize: paperSize
        ]
#if canImport(AppKit)
        attributes[.leftMargin] = EditorPageLayout.margin
        attributes[.rightMargin] = EditorPageLayout.margin
        attributes[.topMargin] = EditorPageLayout.margin
        attributes[.bottomMargin] = EditorPageLayout.margin
#else
        attributes[.paperMargin] = NSValue(uiEdgeInsets: UIEdgeInsets(
            top: EditorPageLayout.margin,
            left: EditorPageLayout.margin,
            bottom: EditorPageLayout.margin,
            right: EditorPageLayout.margin
        ))
#endif
        return attributes
    }

    private nonisolated static func decodeRTFD(
        _ wrapper: FileWrapper,
        documentAttributes: inout NSDictionary?
    ) -> NSAttributedString? {
#if canImport(AppKit)
        return NSAttributedString(
            rtfdFileWrapper: wrapper,
            documentAttributes: &documentAttributes
        )
#else
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Typewriter-\(UUID().uuidString)")
            .appendingPathExtension("rtfd")
        do {
            try wrapper.write(
                to: temporaryURL,
                options: .atomic,
                originalContentsURL: nil
            )
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            return try NSAttributedString(
                url: temporaryURL,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: &documentAttributes
            )
        } catch {
            return nil
        }
#endif
    }
}
