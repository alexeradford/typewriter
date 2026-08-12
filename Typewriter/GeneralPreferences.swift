import AppKit

enum GeneralPreferences {
    static let didChangeNotification = Notification.Name("TypewriterGeneralPreferencesDidChange")
    static let showStatisticsKey = "ShowDocumentStatistics"
    static let showPinnedDocumentsInHistoryKey =
        "ShowPinnedDocumentsInLibraryHistory"
    static let defaultFontFamilyKey = "DefaultFontFamily"

    static var showDocumentStatistics: Bool {
        if UserDefaults.standard.object(forKey: showStatisticsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: showStatisticsKey)
    }

    static var defaultFontFamily: String? {
        let family = UserDefaults.standard.string(forKey: defaultFontFamilyKey) ?? ""
        guard !family.isEmpty, NSFontManager.shared.availableFontFamilies.contains(family) else {
            return nil
        }
        return family
    }

    static var showPinnedDocumentsInHistory: Bool {
        if UserDefaults.standard.object(
            forKey: showPinnedDocumentsInHistoryKey
        ) == nil {
            return true
        }
        return UserDefaults.standard.bool(
            forKey: showPinnedDocumentsInHistoryKey
        )
    }

    static func notifyChanged() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
