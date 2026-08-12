import AppKit

enum LibraryDocumentOpenDisposition {
    case replaceCurrent
    case newTab
}

final class LibrarySidebarViewController: NSViewController {
    private final class Node: NSObject {
        enum Kind {
            case folder(LibraryFolder)
            case dateGroup(Date, String)
            case document(LibraryDocumentItem, DocumentContext)
            case message(String)
        }

        enum DocumentContext {
            case pinned
            case folder(UUID)
            case dated
        }

        let kind: Kind
        var children: [Node]

        init(_ kind: Kind, children: [Node] = []) {
            self.kind = kind
            self.children = children
        }

        var document: LibraryDocumentItem? {
            guard case let .document(document, _) = kind else { return nil }
            return document
        }

        var folder: LibraryFolder? {
            guard case let .folder(folder) = kind else { return nil }
            return folder
        }

        var persistentIdentifier: String {
            switch kind {
            case let .folder(folder):
                "folder.\(folder.id.uuidString)"
            case let .dateGroup(date, _):
                "date.\(date.timeIntervalSinceReferenceDate)"
            case let .document(document, context):
                switch context {
                case .pinned:
                    "pinned.\(document.id.uuidString)"
                case let .folder(folderID):
                    "folder.\(folderID.uuidString).document.\(document.id.uuidString)"
                case .dated:
                    "dated.\(document.id.uuidString)"
                }
            case let .message(message):
                "message.\(message)"
            }
        }
    }

    private enum CellIdentifier {
        static let document = NSUserInterfaceItemIdentifier(
            "Library.DocumentCell"
        )
        static let simple = NSUserInterfaceItemIdentifier(
            "Library.SimpleCell"
        )
        static let folder = NSUserInterfaceItemIdentifier(
            "Library.FolderCell"
        )
        static let header = NSUserInterfaceItemIdentifier(
            "Library.HeaderCell"
        )
    }

    private static let documentPasteboardType = NSPasteboard.PasteboardType(
        "ca.alexradford.Typewriter.library-document"
    )
    private static let folderPasteboardType = NSPasteboard.PasteboardType(
        "ca.alexradford.Typewriter.library-folder"
    )

    private let library: DocumentLibraryStore
    private let outlineView = NSOutlineView()
    private let outlineColumn = NSTableColumn(
        identifier: NSUserInterfaceItemIdentifier("Library")
    )
    private let scrollView = NSScrollView()
    private let addButton = NSButton()
    private let sortButton = NSButton()
    private var roots: [Node] = []
    private var activeDocumentID: UUID?
    private var isRefreshing = false
    private var isFirstRefresh = true
    private var isSynchronizingSelection = false
    private var refreshObservers: [NSObjectProtocol] = []

    var openDocumentHandler: ((
        LibraryDocumentItem,
        LibraryDocumentOpenDisposition
    ) -> Void)?
    var deleteDocumentHandler: ((LibraryDocumentItem) -> Void)?

    init(library: DocumentLibraryStore = .shared) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState
        view = background

        configureOutlineView()
        configureBottomBar(in: background)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: background.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -5)
        ])

        observeRefreshNotification(
            name: .documentLibraryDidChange,
            object: library
        )
        observeRefreshNotification(
            name: .NSCalendarDayChanged,
            object: nil
        )
        observeRefreshNotification(
            name: GeneralPreferences.didChangeNotification,
            object: nil
        )
        refresh()
    }

    deinit {
        for observer in refreshObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setActiveDocument(url: URL?) {
        activeDocumentID = url.flatMap { library.document(at: $0)?.id }
        guard isViewLoaded else { return }
        selectActiveDocument()
    }

    func focusSelection() {
        guard isViewLoaded, let window = view.window else { return }
        window.makeFirstResponder(outlineView)
    }

    private func observeRefreshNotification(
        name: Notification.Name,
        object: Any?
    ) {
        let observer = NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refreshObservers.append(observer)
    }

    private func configureOutlineView() {
        outlineColumn.resizingMask = .autoresizingMask
        outlineColumn.minWidth = 180
        outlineColumn.width = 180
        outlineView.addTableColumn(outlineColumn)
        outlineView.outlineTableColumn = outlineColumn
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outlineView.translatesAutoresizingMaskIntoConstraints = false
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .custom
        outlineView.indentationPerLevel = 14
        outlineView.floatsGroupRows = false
        outlineView.allowsMultipleSelection = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(openSelectedDocument(_:))
        outlineView.registerForDraggedTypes([
            Self.documentPasteboardType,
            Self.folderPasteboardType
        ])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        let contextMenu = NSMenu(title: "Library")
        contextMenu.identifier = NSUserInterfaceItemIdentifier(
            "Library.ContextMenu"
        )
        contextMenu.delegate = self
        outlineView.menu = contextMenu

        scrollView.documentView = outlineView
        outlineView.widthAnchor.constraint(
            equalTo: scrollView.contentView.widthAnchor
        ).isActive = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
    }

    private func configureBottomBar(in root: NSView) {
        addButton.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "Add to Library"
        )
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.imagePosition = .imageOnly
        addButton.target = self
        addButton.action = #selector(showAddMenu(_:))
        addButton.toolTip = "Create a document or folder"
        addButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(addButton)

        sortButton.image = NSImage(
            systemSymbolName: "ellipsis.circle",
            accessibilityDescription: "Library sort options"
        )
        sortButton.bezelStyle = .inline
        sortButton.isBordered = false
        sortButton.imagePosition = .imageOnly
        sortButton.target = self
        sortButton.action = #selector(showSortMenu(_:))
        sortButton.toolTip = "Sort document history"
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sortButton)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: 4),
            addButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            addButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 24),
            sortButton.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -8
            ),
            sortButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            sortButton.widthAnchor.constraint(equalToConstant: 28),
            sortButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func refresh() {
        guard isViewLoaded else { return }
        let expandedIdentifiers = Set<String>(
            (0..<outlineView.numberOfRows)
                .compactMap { row -> String? in
                    guard
                        let node = outlineView.item(atRow: row) as? Node,
                        outlineView.isItemExpanded(node)
                    else {
                        return nil
                    }
                    return node.persistentIdentifier
                }
        )

        roots = makeNodes(from: library.snapshot)
        isRefreshing = true
        outlineView.reloadData()
        expandDefaultNodes(
            preserving: isFirstRefresh ? nil : expandedIdentifiers
        )
        selectActiveDocument()
        isRefreshing = false
        isFirstRefresh = false
    }

    private func makeNodes(from snapshot: LibrarySnapshot) -> [Node] {
        let documentsByID = Dictionary(
            uniqueKeysWithValues: snapshot.documents.map { ($0.id, $0) }
        )
        let foldersByID = Dictionary(
            uniqueKeysWithValues: snapshot.folders.map { ($0.id, $0) }
        )
        let topLevelNodes = snapshot.topLevelItems.compactMap { item -> Node? in
            switch item.kind {
            case .document:
                guard let document = documentsByID[item.itemID] else {
                    return nil
                }
                return Node(.document(document, .pinned))
            case .folder:
                guard let folder = foldersByID[item.itemID] else {
                    return nil
                }
                let children = snapshot.documents
                    .filter { $0.folderID == folder.id }
                    .sorted(by: compareTitles)
                    .map { Node(.document($0, .folder(folder.id))) }
                return Node(.folder(folder), children: children)
            }
        }
        let calendar = Calendar.autoupdatingCurrent
        let historyDocuments = GeneralPreferences
            .showPinnedDocumentsInHistory
            ? snapshot.documents
            : snapshot.documents.filter { $0.pinnedAt == nil }
        let grouped = Dictionary(grouping: historyDocuments) {
            calendar.startOfDay(for: $0.createdAt)
        }
        let days = grouped.keys.sorted {
            snapshot.sortOrder == .oldestFirst ? $0 < $1 : $0 > $1
        }
        let dateNodes = days.map { day -> Node in
            let documents = sorted(
                grouped[day] ?? [],
                using: snapshot.sortOrder
            )
            return Node(
                .dateGroup(day, relativeDateTitle(for: day)),
                children: documents.map { Node(.document($0, .dated)) }
            )
        }

        if let error = library.initializationError, snapshot.documents.isEmpty {
            return topLevelNodes + [Node(.message(error.localizedDescription))]
        }
        return topLevelNodes + dateNodes
    }

    private func sorted(
        _ documents: [LibraryDocumentItem],
        using sortOrder: LibrarySortOrder
    ) -> [LibraryDocumentItem] {
        switch sortOrder {
        case .newestFirst:
            documents.sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt > $1.createdAt
                }
                return compareTitles($0, $1)
            }
        case .oldestFirst:
            documents.sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return compareTitles($0, $1)
            }
        case .titleWithinDay:
            documents.sorted(by: compareTitles)
        }
    }

    private func compareTitles(
        _ lhs: LibraryDocumentItem,
        _ rhs: LibraryDocumentItem
    ) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func relativeDateTitle(for date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = calendar
        formatter.dateFormat = calendar.component(.year, from: date)
            == calendar.component(.year, from: Date())
            ? "MMMM d"
            : "MMMM d yyyy"
        return formatter.string(from: date)
    }

    private func expandDefaultNodes(preserving identifiers: Set<String>?) {
        for root in roots {
            switch root.kind {
            case .folder, .dateGroup:
                if identifiers == nil
                    || identifiers?.contains(root.persistentIdentifier) == true {
                    outlineView.expandItem(root)
                }
            default:
                break
            }
            expandDescendants(
                of: root,
                matching: identifiers
            )
        }
    }

    private func expandDescendants(
        of node: Node,
        matching identifiers: Set<String>?
    ) {
        for child in node.children {
            if identifiers?.contains(child.persistentIdentifier) == true {
                outlineView.expandItem(child)
            }
            expandDescendants(of: child, matching: identifiers)
        }
    }

    private func selectActiveDocument() {
        guard let activeDocumentID else {
            outlineView.deselectAll(nil)
            return
        }
        let rows = flattenedNodes()
            .filter { $0.document?.id == activeDocumentID }
            .map { outlineView.row(forItem: $0) }
            .filter { $0 >= 0 }
        guard !rows.isEmpty else {
            return
        }
        isSynchronizingSelection = true
        defer { isSynchronizingSelection = false }
        outlineView.selectRowIndexes(
            IndexSet(rows),
            byExtendingSelection: false
        )
    }

    private func flattenedNodes() -> [Node] {
        func flatten(_ node: Node) -> [Node] {
            [node] + node.children.flatMap(flatten)
        }
        return roots.flatMap(flatten)
    }

    @objc private func openSelectedDocument(_ sender: Any?) {
        guard
            outlineView.selectedRow >= 0,
            let node = outlineView.item(atRow: outlineView.selectedRow) as? Node,
            let document = node.document
        else {
            return
        }
        requestOpen(document, disposition: .replaceCurrent)
    }

    private func requestOpen(
        _ document: LibraryDocumentItem,
        disposition: LibraryDocumentOpenDisposition
    ) {
        if let openDocumentHandler {
            openDocumentHandler(document, disposition)
            return
        }
        guard let url = library.url(for: document) else { return }
        NSDocumentController.shared.openDocument(
            withContentsOf: url,
            display: true
        ) { _, _, error in
            if let error {
                NSApp.presentError(error)
            }
        }
    }

    @objc private func showAddMenu(_ sender: NSButton) {
        let menu = NSMenu(title: "Add to Library")
        menu.addItem(
            menuItem(
                title: "New Document",
                action: #selector(createDocument(_:)),
                symbolName: "square.and.pencil"
            )
        )
        menu.addItem(
            menuItem(
                title: "New Folder…",
                action: #selector(createFolder(_:)),
                symbolName: "folder.badge.plus"
            )
        )
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.maxY + 3),
            in: sender
        )
    }

    @objc private func createDocument(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }

    @objc private func createFolder(_ sender: Any?) {
        promptForFolderName(
            title: "New Folder",
            message: "Create a folder in your Typewriter Library.",
            initialValue: "New Folder",
            confirmTitle: "Create"
        ) { [weak self] name in
            guard let self else { return }
            do {
                try library.createFolder(named: name)
            } catch {
                present(error)
            }
        }
    }

    @objc private func renameFolder(_ sender: NSMenuItem) {
        guard
            let folderID = sender.representedObject as? UUID,
            let folder = library.snapshot.folders.first(where: { $0.id == folderID })
        else {
            return
        }
        promptForFolderName(
            title: "Rename Folder",
            message: "Choose a new name for “\(folder.name)”.",
            initialValue: folder.name,
            confirmTitle: "Rename"
        ) { [weak self] name in
            guard let self else { return }
            library.renameFolder(folderID, to: name) { [weak self] error in
                if let error {
                    self?.present(error)
                }
            }
        }
    }

    @objc private func deleteFolder(_ sender: NSMenuItem) {
        guard let folderID = sender.representedObject as? UUID else { return }
        do {
            try library.deleteEmptyFolder(folderID)
        } catch {
            present(error)
        }
    }

    @objc private func renameDocument(_ sender: NSMenuItem) {
        guard
            let documentID = sender.representedObject as? UUID,
            let document = library.document(withID: documentID),
            let documentURL = library.url(for: document)
        else {
            return
        }
        promptForName(
            title: "Rename Document",
            message: "Choose a new name for “\(document.title)”.",
            initialValue: document.title,
            placeholder: "Document name",
            confirmTitle: "Rename"
        ) { [weak self] name in
            guard let self else { return }
            let openDocument = NSDocumentController.shared.document(
                for: documentURL
            ) as? Document
            library.renameDocument(
                documentID,
                to: name
            ) { [weak self, weak openDocument] error in
                if let error {
                    self?.present(error)
                    return
                }
                openDocument?.libraryMetadataDidChange()
            }
        }
    }

    @objc private func deleteDocument(_ sender: NSMenuItem) {
        guard
            let documentID = sender.representedObject as? UUID,
            let document = library.document(withID: documentID)
        else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete “\(document.title)”?"
        alert.informativeText =
            "This permanently deletes the document from your Typewriter Library. This action cannot be undone."
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = {
            [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            if let deleteDocumentHandler {
                deleteDocumentHandler(document)
                return
            }
            do {
                try library.deleteDocument(document.id)
            } catch {
                present(error)
            }
        }
        if let window = view.window {
            alert.beginSheetModal(
                for: window,
                completionHandler: handleResponse
            )
        } else {
            handleResponse(alert.runModal())
        }
    }

    @objc private func openDocumentFromMenu(_ sender: NSMenuItem) {
        guard
            let documentID = sender.representedObject as? UUID,
            let document = library.document(withID: documentID)
        else {
            return
        }
        requestOpen(document, disposition: .replaceCurrent)
    }

    @objc private func openDocumentInNewTabFromMenu(_ sender: NSMenuItem) {
        guard
            let documentID = sender.representedObject as? UUID,
            let document = library.document(withID: documentID)
        else {
            return
        }
        requestOpen(document, disposition: .newTab)
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard
            let documentID = sender.representedObject as? UUID,
            let document = library.document(withID: documentID)
        else {
            return
        }
        do {
            try library.setPinned(document.pinnedAt == nil, documentID: documentID)
        } catch {
            present(error)
        }
    }

    @objc private func moveDocumentFromMenu(_ sender: NSMenuItem) {
        guard let documentID = sender.representedObject as? UUID else { return }
        let folderID = sender.identifier.flatMap {
            UUID(uuidString: $0.rawValue)
        }
        move(documentID, toFolder: folderID)
    }

    @objc private func revealDocument(_ sender: NSMenuItem) {
        guard
            let documentID = sender.representedObject as? UUID,
            let document = library.document(withID: documentID),
            let url = library.url(for: document)
        else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func changeSortOrder(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let sortOrder = LibrarySortOrder(rawValue: rawValue)
        else {
            return
        }
        do {
            try library.setSortOrder(sortOrder)
        } catch {
            present(error)
        }
    }

    @objc private func showSortMenu(_ sender: NSButton) {
        sortMenu().popUp(
            positioning: nil,
            at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 2),
            in: sender
        )
    }

    private func move(_ documentID: UUID, toFolder folderID: UUID?) {
        library.moveDocument(documentID, toFolder: folderID) { [weak self] error in
            if let error {
                self?.present(error)
            }
        }
    }

    private func promptForFolderName(
        title: String,
        message: String,
        initialValue: String,
        confirmTitle: String,
        completion: @escaping (String) -> Void
    ) {
        promptForName(
            title: title,
            message: message,
            initialValue: initialValue,
            placeholder: "Folder name",
            confirmTitle: confirmTitle,
            completion: completion
        )
    }

    private func promptForName(
        title: String,
        message: String,
        initialValue: String,
        placeholder: String,
        confirmTitle: String,
        completion: @escaping (String) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: initialValue)
        field.placeholderString = placeholder
        field.frame.size = NSSize(width: 280, height: 24)
        alert.accessoryView = field

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            completion(field.stringValue)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func present(_ error: Error) {
        if let window = view.window {
            window.presentError(error)
        } else {
            NSApp.presentError(error)
        }
    }

    private func sortMenu() -> NSMenu {
        let menu = NSMenu(title: "Sort Documents")
        let current = library.snapshot.sortOrder
        for sortOrder in LibrarySortOrder.allCases {
            let item = NSMenuItem(
                title: sortOrder.title,
                action: #selector(changeSortOrder(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = sortOrder.rawValue
            item.state = sortOrder == current ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func menuItem(
        title: String,
        action: Selector,
        symbolName: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbolName {
            item.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: title
            )
        }
        return item
    }
}

extension LibrarySidebarViewController: NSOutlineViewDataSource {
    func outlineView(
        _ outlineView: NSOutlineView,
        numberOfChildrenOfItem item: Any?
    ) -> Int {
        (item as? Node)?.children.count ?? roots.count
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        child index: Int,
        ofItem item: Any?
    ) -> Any {
        (item as? Node)?.children[index] ?? roots[index]
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        isItemExpandable item: Any
    ) -> Bool {
        guard let node = item as? Node else { return false }
        return !node.children.isEmpty
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        pasteboardWriterForItem item: Any
    ) -> (any NSPasteboardWriting)? {
        guard let node = item as? Node else { return nil }
        let pasteboardItem = NSPasteboardItem()
        if let documentID = node.document?.id {
            pasteboardItem.setString(
                documentID.uuidString,
                forType: Self.documentPasteboardType
            )
            return pasteboardItem
        }
        if let folderID = node.folder?.id {
            pasteboardItem.setString(
                folderID.uuidString,
                forType: Self.folderPasteboardType
            )
            return pasteboardItem
        }
        return nil
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: any NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        let hasDocument = pasteboard.string(
            forType: Self.documentPasteboardType
        ) != nil
        let hasFolder = pasteboard.string(
            forType: Self.folderPasteboardType
        ) != nil

        guard let node = item as? Node else {
            let topLevelCount = library.snapshot.topLevelItems.count
            return (hasDocument || hasFolder)
                && index >= 0
                && index <= topLevelCount
                ? .move
                : []
        }
        switch node.kind {
        case .folder:
            return hasDocument ? .move : []
        default:
            return []
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: any NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        let pasteboard = info.draggingPasteboard
        if item == nil {
            let topLevelItem: LibraryTopLevelItem?
            if let identifier = pasteboard.string(
                forType: Self.documentPasteboardType
            ), let documentID = UUID(uuidString: identifier) {
                topLevelItem = .document(documentID)
            } else if let identifier = pasteboard.string(
                forType: Self.folderPasteboardType
            ), let folderID = UUID(uuidString: identifier) {
                topLevelItem = .folder(folderID)
            } else {
                topLevelItem = nil
            }
            guard let topLevelItem else { return false }
            do {
                try library.moveTopLevelItem(topLevelItem, to: index)
                return true
            } catch {
                present(error)
                return false
            }
        }

        guard
            let identifier = pasteboard.string(
                forType: Self.documentPasteboardType
            ),
            let documentID = UUID(uuidString: identifier),
            let node = item as? Node
        else {
            return false
        }

        switch node.kind {
        case let .folder(folder):
            move(documentID, toFolder: folder.id)
        default:
            return false
        }
        return true
    }
}

extension LibrarySidebarViewController: NSOutlineViewDelegate {
    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? Node else { return nil }
        switch node.kind {
        case let .document(document, _):
            let cell = outlineView.makeView(
                withIdentifier: CellIdentifier.document,
                owner: self
            ) as? LibraryDocumentCellView ?? LibraryDocumentCellView()
            cell.identifier = CellIdentifier.document
            cell.configure(with: document)
            return cell

        case let .folder(folder):
            let cell = outlineView.makeView(
                withIdentifier: CellIdentifier.folder,
                owner: self
            ) as? LibraryFolderCellView ?? LibraryFolderCellView()
            cell.identifier = CellIdentifier.folder
            cell.configure(
                with: folder,
                documentCount: node.children.count
            )
            return cell

        case let .message(message):
            return simpleCell(
                title: message,
                symbolName: "exclamationmark.triangle",
                accessibilityLabel: message
            )

        case let .dateGroup(_, title):
            return headerCell(title: title)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        return switch node.kind {
        case .dateGroup:
            true
        default:
            false
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        shouldSelectItem item: Any
    ) -> Bool {
        (item as? Node)?.document != nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard
            !isRefreshing,
            !isSynchronizingSelection,
            outlineView.selectedRow >= 0,
            let node = outlineView.item(atRow: outlineView.selectedRow) as? Node,
            let document = node.document
        else {
            return
        }
        guard document.id != activeDocumentID else {
            selectActiveDocument()
            return
        }
        requestOpen(document, disposition: .replaceCurrent)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        heightOfRowByItem item: Any
    ) -> CGFloat {
        guard let node = item as? Node else { return 28 }
        return switch node.kind {
        case .document, .folder:
            46.0
        case .dateGroup:
            26.0
        default:
            28.0
        }
    }

    private func simpleCell(
        title: String,
        symbolName: String,
        accessibilityLabel: String
    ) -> LibrarySimpleCellView {
        let cell = outlineView.makeView(
            withIdentifier: CellIdentifier.simple,
            owner: self
        ) as? LibrarySimpleCellView ?? LibrarySimpleCellView()
        cell.identifier = CellIdentifier.simple
        cell.configure(
            title: title,
            symbolName: symbolName,
            accessibilityLabel: accessibilityLabel
        )
        return cell
    }

    private func headerCell(title: String) -> LibraryHeaderCellView {
        let cell = outlineView.makeView(
            withIdentifier: CellIdentifier.header,
            owner: self
        ) as? LibraryHeaderCellView ?? LibraryHeaderCellView()
        cell.identifier = CellIdentifier.header
        cell.configure(title: title)
        return cell
    }
}

extension LibrarySidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard
            menu.identifier?.rawValue == "Library.ContextMenu",
            outlineView.clickedRow >= 0,
            let node = outlineView.item(atRow: outlineView.clickedRow) as? Node
        else {
            return
        }

        if let document = node.document {
            let openItem = menuItem(
                title: "Open",
                action: #selector(openDocumentFromMenu(_:))
            )
            openItem.representedObject = document.id
            menu.addItem(openItem)

            let openInNewTabItem = menuItem(
                title: "Open in New Tab",
                action: #selector(openDocumentInNewTabFromMenu(_:))
            )
            openInNewTabItem.representedObject = document.id
            menu.addItem(openInNewTabItem)
            menu.addItem(.separator())

            let renameItem = menuItem(
                title: "Rename…",
                action: #selector(renameDocument(_:))
            )
            renameItem.representedObject = document.id
            menu.addItem(renameItem)

            let pinItem = menuItem(
                title: document.pinnedAt == nil ? "Pin" : "Unpin",
                action: #selector(togglePin(_:)),
                symbolName: document.pinnedAt == nil ? "pin" : "pin.slash"
            )
            pinItem.representedObject = document.id
            menu.addItem(pinItem)

            let moveMenu = NSMenu(title: "Move to Folder")
            let libraryRoot = menuItem(
                title: "Library",
                action: #selector(moveDocumentFromMenu(_:))
            )
            libraryRoot.representedObject = document.id
            moveMenu.addItem(libraryRoot)
            if !library.snapshot.folders.isEmpty {
                moveMenu.addItem(.separator())
            }
            for folder in library.snapshot.folders {
                let folderItem = menuItem(
                    title: folder.name,
                    action: #selector(moveDocumentFromMenu(_:))
                )
                folderItem.representedObject = document.id
                folderItem.identifier = NSUserInterfaceItemIdentifier(
                    folder.id.uuidString
                )
                folderItem.state = document.folderID == folder.id ? .on : .off
                moveMenu.addItem(folderItem)
            }
            let moveItem = NSMenuItem(
                title: "Move to Folder",
                action: nil,
                keyEquivalent: ""
            )
            moveItem.submenu = moveMenu
            menu.addItem(moveItem)
            menu.addItem(.separator())

            let revealItem = menuItem(
                title: "Show in Finder",
                action: #selector(revealDocument(_:))
            )
            revealItem.representedObject = document.id
            menu.addItem(revealItem)
            menu.addItem(.separator())

            let deleteItem = menuItem(
                title: "Delete…",
                action: #selector(deleteDocument(_:)),
                symbolName: "trash"
            )
            deleteItem.representedObject = document.id
            menu.addItem(deleteItem)
            return
        }

        if let folder = node.folder {
            let renameItem = menuItem(
                title: "Rename Folder…",
                action: #selector(renameFolder(_:))
            )
            renameItem.representedObject = folder.id
            menu.addItem(renameItem)
            let deleteItem = menuItem(
                title: "Delete Empty Folder",
                action: #selector(deleteFolder(_:))
            )
            deleteItem.representedObject = folder.id
            menu.addItem(deleteItem)
            return
        }
    }
}
