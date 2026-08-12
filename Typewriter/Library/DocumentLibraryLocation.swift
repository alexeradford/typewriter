import Foundation

struct DocumentLibraryLocation {
    enum Kind: String, Codable {
        case iCloud
        case localFallback
        case custom
    }

    fileprivate struct Selection: Codable {
        let kind: Kind
        let bookmark: Data?
    }

    private final class UbiquityURLBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: URL?

        func store(_ url: URL?) {
            lock.lock()
            value = url
            lock.unlock()
        }

        func load() -> URL? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    final class SecurityScope {
        let url: URL
        private let isAccessing: Bool

        init(url: URL) {
            self.url = url
            isAccessing = url.startAccessingSecurityScopedResource()
        }

        deinit {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    static let iCloudContainerIdentifier = "iCloud.ca.alexradford.Typewriter"

    let kind: Kind
    let rootURL: URL
    let securityScope: SecurityScope?

    var displayName: String {
        switch kind {
        case .iCloud:
            "iCloud Drive › Typewriter"
        case .localFallback:
            rootURL.path(percentEncoded: false)
        case .custom:
            rootURL.path(percentEncoded: false)
        }
    }

    private static let activeSelectionKey = "DocumentLibrary.ActiveLocation"
    private static let pendingSelectionKey = "DocumentLibrary.PendingLocation"

    static func launchLocations(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> (
        selected: Self,
        migrationSource: Self?,
        hasPendingSelection: Bool,
        activeLocationUnavailable: Bool
    ) {
        let activeSelection = decodeSelection(
            defaults.data(forKey: activeSelectionKey)
        )
        let active: Self
        if let activeSelection {
            guard let resolved = resolve(
                activeSelection,
                fileManager: fileManager
            ) else {
                return (
                    localFallback(fileManager: fileManager),
                    nil,
                    false,
                    true
                )
            }
            active = resolved
        } else {
            active = defaultLocation(fileManager: fileManager)
            persistActiveSelection(for: active, defaults: defaults)
        }

        guard
            let pendingSelection = decodeSelection(
                defaults.data(forKey: pendingSelectionKey)
            ),
            let pending = resolve(
                pendingSelection,
                fileManager: fileManager
            )
        else {
            return (active, nil, false, false)
        }

        if normalized(pending.rootURL) == normalized(active.rootURL) {
            commitPendingSelection(defaults: defaults)
            return (pending, nil, false, false)
        }
        return (pending, active, true, false)
    }

    static func iCloudLocation(
        fileManager: FileManager = .default
    ) -> Self? {
        guard fileManager.ubiquityIdentityToken != nil else { return nil }

        let box = UbiquityURLBox()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.store(
                fileManager.url(forUbiquityContainerIdentifier: nil)
            )
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 8) == .success else {
            return nil
        }
        guard let containerURL = box.load() else { return nil }
        return Self(
            kind: .iCloud,
            rootURL: containerURL.appendingPathComponent(
                "Documents",
                isDirectory: true
            ),
            securityScope: nil
        )
    }

    static func customLocation(for selectedFolder: URL) throws -> Self {
        let rootURL: URL
        if selectedFolder.lastPathComponent.compare(
            "Typewriter",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame {
            rootURL = selectedFolder
        } else {
            rootURL = selectedFolder.appendingPathComponent(
                "Typewriter",
                isDirectory: true
            )
        }
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        return Self(
            kind: .custom,
            rootURL: rootURL,
            securityScope: SecurityScope(url: selectedFolder)
        )
    }

    func scheduleForNextLaunch(
        defaults: UserDefaults = .standard
    ) throws {
        let selection: Selection
        switch kind {
        case .iCloud:
            selection = Selection(kind: .iCloud, bookmark: nil)
        case .localFallback:
            selection = Selection(kind: .localFallback, bookmark: nil)
        case .custom:
            let bookmark = try rootURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            selection = Selection(kind: .custom, bookmark: bookmark)
        }
        let data = try JSONEncoder().encode(selection)
        defaults.set(data, forKey: Self.pendingSelectionKey)
    }

    static func commitPendingSelection(
        defaults: UserDefaults = .standard
    ) {
        guard let pending = defaults.data(forKey: pendingSelectionKey) else {
            return
        }
        defaults.set(pending, forKey: activeSelectionKey)
        defaults.removeObject(forKey: pendingSelectionKey)
    }

    static func clearPendingSelection(
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: pendingSelectionKey)
    }

    private static func defaultLocation(
        fileManager: FileManager
    ) -> Self {
        if let iCloud = iCloudLocation(fileManager: fileManager) {
            return iCloud
        }
        return localFallback(fileManager: fileManager)
    }

    private static func localFallback(
        fileManager: FileManager
    ) -> Self {
        return Self(
            kind: .localFallback,
            rootURL: applicationSupportRoot(fileManager: fileManager)
                .appendingPathComponent("Documents", isDirectory: true),
            securityScope: nil
        )
    }

    private static func persistActiveSelection(
        for location: Self,
        defaults: UserDefaults
    ) {
        let selection = Selection(kind: location.kind, bookmark: nil)
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: activeSelectionKey)
    }

    private static func resolve(
        _ selection: Selection?,
        fileManager: FileManager
    ) -> Self? {
        guard let selection else { return nil }
        switch selection.kind {
        case .iCloud:
            return iCloudLocation(fileManager: fileManager)
        case .localFallback:
            return Self(
                kind: .localFallback,
                rootURL: applicationSupportRoot(fileManager: fileManager)
                    .appendingPathComponent("Documents", isDirectory: true),
                securityScope: nil
            )
        case .custom:
            guard let bookmark = selection.bookmark else { return nil }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return nil
            }
            let scope = SecurityScope(url: url)
            if isStale,
               let refreshed = try? url.bookmarkData(
                   options: [.withSecurityScope],
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ),
               let encoded = try? JSONEncoder().encode(
                   Selection(kind: .custom, bookmark: refreshed)
               ) {
                UserDefaults.standard.set(
                    encoded,
                    forKey: activeSelectionKey
                )
            }
            return Self(kind: .custom, rootURL: url, securityScope: scope)
        }
    }

    static func applicationSupportRoot(
        fileManager: FileManager = .default
    ) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        return (applicationSupport
            ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Typewriter", isDirectory: true)
    }

    private static func decodeSelection(_ data: Data?) -> Selection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Selection.self, from: data)
    }

    private static func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
