import AppKit
import XCTest
@testable import Typewriter

final class LibrarySidebarCellLayoutTests: XCTestCase {
    func testDocumentCellKeepsLongTextInsideItsTrailingInset() {
        let cell = LibraryDocumentCellView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 46)
        )
        cell.configure(with: LibraryDocumentItem(
            id: UUID(),
            relativePath: "Documents/example.typewriter",
            createdAt: Date(),
            title: String(repeating: "Long document title ", count: 12),
            previewText: String(repeating: "Long preview ", count: 20),
            pageCount: 2,
            pinnedAt: nil,
            folderID: nil
        ))

        cell.layoutSubtreeIfNeeded()

        let labels = cell.subviews.compactMap { $0 as? NSTextField }
        XCTAssertEqual(labels.count, 2)
        for label in labels {
            XCTAssertLessThanOrEqual(
                label.frame.maxX,
                cell.bounds.maxX - 9.5
            )
        }
    }

    func testFolderCellKeepsLongTextInsideItsTrailingInset() {
        let cell = LibraryFolderCellView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 46)
        )
        cell.configure(
            with: LibraryFolder(
                id: UUID(),
                name: String(repeating: "Long folder name ", count: 12),
                createdAt: Date()
            ),
            documentCount: 100
        )

        cell.layoutSubtreeIfNeeded()

        let labels = cell.subviews.compactMap { $0 as? NSTextField }
        XCTAssertEqual(labels.count, 2)
        for label in labels {
            XCTAssertLessThanOrEqual(
                label.frame.maxX,
                cell.bounds.maxX - 9.5
            )
        }
    }
}
