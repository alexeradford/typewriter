import AppKit

enum PrintPreferences {
    static let didChangeNotification = Notification.Name("TypewriterPrintPreferencesDidChange")
    static let printerNameKey = "DefaultPrinterName"
    static let animatePrintKey = "AnimateQuickPrint"
    static let paperSizeKey = "DefaultPaperSize"

    static var selectedPrinterName: String? {
        let value = UserDefaults.standard.string(forKey: printerNameKey) ?? ""
        return value.isEmpty ? nil : value
    }

    static var shouldAnimatePrint: Bool {
        if UserDefaults.standard.object(forKey: animatePrintKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: animatePrintKey)
    }

    static var defaultPaperSize: PaperSizePreset {
        guard
            let value = UserDefaults.standard.string(forKey: paperSizeKey),
            let preset = PaperSizePreset(rawValue: value)
        else {
            return .letter
        }
        return preset
    }

    static func configuredPrintInfo(from source: NSPrintInfo) -> NSPrintInfo {
        let result = source.copy() as! NSPrintInfo
        if let selectedPrinterName,
           NSPrinter.printerNames.contains(selectedPrinterName),
           let printer = NSPrinter(name: selectedPrinterName) {
            result.printer = printer
        }
        result.topMargin = 54
        result.bottomMargin = 54
        result.leftMargin = 54
        result.rightMargin = 54
        result.horizontalPagination = .fit
        result.verticalPagination = .automatic
        result.isHorizontallyCentered = true
        result.isVerticallyCentered = false
        return result
    }

    static func notifyChanged() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
