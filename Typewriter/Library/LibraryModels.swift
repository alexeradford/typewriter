import Foundation

struct LibraryDocumentSummary: Equatable {
    let title: String
    let previewText: String
    let pageCount: Int

    init(title: String, previewText: String, pageCount: Int) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = normalizedTitle.isEmpty ? "Untitled" : normalizedTitle
        self.previewText = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pageCount = max(1, pageCount)
    }
}

struct LibraryDocumentItem: Codable, Hashable, Identifiable {
    var id: UUID
    var relativePath: String
    let createdAt: Date
    var title: String
    var titleOverride: String?
    var previewText: String
    var pageCount: Int
    var pinnedAt: Date?
    var folderID: UUID?

    init(
        id: UUID,
        relativePath: String,
        createdAt: Date,
        title: String,
        titleOverride: String? = nil,
        previewText: String,
        pageCount: Int,
        pinnedAt: Date?,
        folderID: UUID?
    ) {
        self.id = id
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.title = title
        self.titleOverride = titleOverride
        self.previewText = previewText
        self.pageCount = pageCount
        self.pinnedAt = pinnedAt
        self.folderID = folderID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case relativePath
        case createdAt
        case title
        case titleOverride
        case previewText
        case pageCount
        case pinnedAt
        case folderID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        title = try container.decode(String.self, forKey: .title)
        titleOverride = try container.decodeIfPresent(
            String.self,
            forKey: .titleOverride
        )
        previewText = try container.decode(String.self, forKey: .previewText)
        pageCount = try container.decode(Int.self, forKey: .pageCount)
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
    }
}

struct LibraryFolder: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var relativePath: String

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        relativePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.relativePath = relativePath ?? name
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case relativePath
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        relativePath = try container.decodeIfPresent(
            String.self,
            forKey: .relativePath
        ) ?? name
    }
}

struct LibraryTopLevelItem: Codable, Hashable {
    enum Kind: String, Codable {
        case document
        case folder
    }

    let kind: Kind
    let itemID: UUID

    static func document(_ id: UUID) -> Self {
        Self(kind: .document, itemID: id)
    }

    static func folder(_ id: UUID) -> Self {
        Self(kind: .folder, itemID: id)
    }
}

enum LibrarySortOrder: String, Codable, CaseIterable {
    case newestFirst
    case oldestFirst
    case titleWithinDay

    var title: String {
        switch self {
        case .newestFirst:
            "Newest First"
        case .oldestFirst:
            "Oldest First"
        case .titleWithinDay:
            "Name Within Day"
        }
    }
}

struct LibrarySnapshot {
    let documents: [LibraryDocumentItem]
    let folders: [LibraryFolder]
    let topLevelItems: [LibraryTopLevelItem]
    let sortOrder: LibrarySortOrder
}

struct LibraryImport {
    let documentID: UUID
    let url: URL
    let copiedIntoLibrary: Bool
}

extension Notification.Name {
    static let documentLibraryDidChange = Notification.Name(
        "Typewriter.DocumentLibraryDidChange"
    )
}
