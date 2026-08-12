import AppKit

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar

        let general = GeneralSettingsViewController()
        general.title = "General"
        let generalItem = NSTabViewItem(viewController: general)
        generalItem.label = "General"
        generalItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")

        let printing = PrintingSettingsViewController()
        printing.title = "Printing"
        let printingItem = NSTabViewItem(viewController: printing)
        printingItem.label = "Printing"
        printingItem.image = NSImage(systemSymbolName: "printer", accessibilityDescription: "Printing")

        let storage = StorageSettingsViewController()
        storage.title = "Storage"
        let storageItem = NSTabViewItem(viewController: storage)
        storageItem.label = "Storage"
        storageItem.image = NSImage(
            systemSymbolName: "externaldrive",
            accessibilityDescription: "Storage"
        )

        tabs.addTabViewItem(generalItem)
        tabs.addTabViewItem(storageItem)
        tabs.addTabViewItem(printingItem)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 360))
        window.center()
        self.init(window: window)
    }
}

private final class StorageSettingsViewController: NSViewController {
    private let locationLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 320))

        let heading = NSTextField(labelWithString: "Document Library")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        locationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        locationLabel.textColor = .secondaryLabelColor
        locationLabel.lineBreakMode = .byTruncatingMiddle
        updateCurrentLocation()

        let explanation = NSTextField(
            wrappingLabelWithString:
                "iCloud Drive keeps self-contained Typewriter documents available to your other Macs and future Typewriter apps. You can instead place a Typewriter folder inside Documents, another local folder, or another file provider."
        )
        explanation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        explanation.textColor = .secondaryLabelColor

        let useICloudButton = NSButton(
            title: "Use iCloud Drive",
            target: self,
            action: #selector(useICloudDrive(_:))
        )
        useICloudButton.bezelStyle = .rounded

        let chooseButton = NSButton(
            title: "Choose Folder…",
            target: self,
            action: #selector(chooseFolder(_:))
        )
        chooseButton.bezelStyle = .rounded

        let revealButton = NSButton(
            title: "Show in Finder",
            target: self,
            action: #selector(showInFinder(_:))
        )
        revealButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [
            useICloudButton,
            chooseButton,
            revealButton
        ])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isHidden = true

        let stack = NSStackView(views: [
            heading,
            locationLabel,
            explanation,
            buttons,
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(18, after: explanation)
        stack.setCustomSpacing(14, after: buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: 28
            ),
            stack.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -28
            ),
            stack.topAnchor.constraint(
                equalTo: root.topAnchor,
                constant: 28
            ),
            locationLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        view = root
    }

    @objc private func useICloudDrive(_ sender: Any?) {
        guard let location = DocumentLibraryLocation.iCloudLocation() else {
            presentErrorMessage(
                "iCloud Drive is unavailable",
                detail:
                    "Sign in to iCloud and turn on iCloud Drive, then try again."
            )
            return
        }
        schedule(location)
    }

    @objc private func chooseFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message =
            "Choose where Typewriter should create or use its Typewriter folder."

        let handleResponse: (NSApplication.ModalResponse) -> Void = {
            [weak self] response in
            guard
                response == .OK,
                let selectedURL = panel.url,
                let self
            else {
                return
            }
            do {
                schedule(
                    try DocumentLibraryLocation.customLocation(
                        for: selectedURL
                    )
                )
            } catch {
                present(error)
            }
        }

        if let window = view.window {
            panel.beginSheetModal(
                for: window,
                completionHandler: handleResponse
            )
        } else {
            handleResponse(panel.runModal())
        }
    }

    @objc private func showInFinder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([
            DocumentLibraryStore.shared.rootURL
        ])
    }

    private func schedule(_ location: DocumentLibraryLocation) {
        do {
            try location.scheduleForNextLaunch()
            statusLabel.stringValue =
                "Typewriter will copy the Library to \(location.displayName) the next time it opens. The current location remains as a backup."
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.isHidden = false
        } catch {
            present(error)
        }
    }

    private func updateCurrentLocation() {
        locationLabel.stringValue =
            "Currently using: \(DocumentLibraryStore.shared.locationDisplayName)"
    }

    private func present(_ error: Error) {
        view.window?.presentError(error)
    }

    private func presentErrorMessage(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

private final class GeneralSettingsViewController: NSViewController {
    private let defaultFontPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statisticsCheckbox = NSButton(
        checkboxWithTitle: "Show word and character counts in document windows",
        target: nil,
        action: nil
    )
    private let pinnedHistoryCheckbox = NSButton(
        checkboxWithTitle: "Show pinned documents in document history",
        target: nil,
        action: nil
    )

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 292))
        configureDefaultFontPopUp()

        let defaultFontLabel = NSTextField(labelWithString: "Default font:")
        defaultFontLabel.alignment = .right
        defaultFontLabel.setContentHuggingPriority(.required, for: .horizontal)

        let defaultFontExplanation = NSTextField(
            wrappingLabelWithString: "Used for new text and the Body, Header, and Title presets."
        )
        defaultFontExplanation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        defaultFontExplanation.textColor = .secondaryLabelColor

        let fontGrid = NSGridView(views: [
            [defaultFontLabel, defaultFontPopUp],
            [NSView(), defaultFontExplanation]
        ])
        fontGrid.rowSpacing = 7
        fontGrid.columnSpacing = 12
        fontGrid.xPlacement = .fill
        fontGrid.column(at: 0).xPlacement = .trailing
        fontGrid.column(at: 1).xPlacement = .fill

        statisticsCheckbox.state = GeneralPreferences.showDocumentStatistics ? .on : .off
        statisticsCheckbox.target = self
        statisticsCheckbox.action = #selector(statisticsChanged(_:))

        let explanation = NSTextField(
            wrappingLabelWithString: "Document statistics appear unobtrusively beneath the page while you type."
        )
        explanation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        explanation.textColor = .secondaryLabelColor

        pinnedHistoryCheckbox.state =
            GeneralPreferences.showPinnedDocumentsInHistory ? .on : .off
        pinnedHistoryCheckbox.target = self
        pinnedHistoryCheckbox.action = #selector(pinnedHistoryChanged(_:))

        let pinnedHistoryExplanation = NSTextField(
            wrappingLabelWithString:
                "Pinned documents always remain in the upper Library section."
        )
        pinnedHistoryExplanation.font = .systemFont(
            ofSize: NSFont.smallSystemFontSize
        )
        pinnedHistoryExplanation.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            fontGrid,
            statisticsCheckbox,
            explanation,
            pinnedHistoryCheckbox,
            pinnedHistoryExplanation
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.setCustomSpacing(20, after: fontGrid)
        stack.setCustomSpacing(18, after: explanation)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            fontGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            defaultFontPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            defaultFontExplanation.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
            explanation.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            pinnedHistoryExplanation.widthAnchor.constraint(
                lessThanOrEqualToConstant: 440
            )
        ])
        view = root
    }

    private func configureDefaultFontPopUp() {
        defaultFontPopUp.addItem(withTitle: "System Font")
        defaultFontPopUp.lastItem?.representedObject = ""
        for family in NSFontManager.shared.availableFontFamilies.sorted(by: {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }) {
            defaultFontPopUp.addItem(withTitle: family)
            defaultFontPopUp.lastItem?.representedObject = family
        }
        let selectedFamily = GeneralPreferences.defaultFontFamily ?? ""
        if let item = defaultFontPopUp.itemArray.first(where: {
            ($0.representedObject as? String) == selectedFamily
        }) {
            defaultFontPopUp.select(item)
        }
        defaultFontPopUp.target = self
        defaultFontPopUp.action = #selector(defaultFontChanged(_:))
        defaultFontPopUp.setAccessibilityLabel("Default font")
    }

    @objc private func defaultFontChanged(_ sender: NSPopUpButton) {
        let family = sender.selectedItem?.representedObject as? String ?? ""
        UserDefaults.standard.set(family, forKey: GeneralPreferences.defaultFontFamilyKey)
        GeneralPreferences.notifyChanged()
    }

    @objc private func statisticsChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: GeneralPreferences.showStatisticsKey)
        GeneralPreferences.notifyChanged()
    }

    @objc private func pinnedHistoryChanged(_ sender: NSButton) {
        UserDefaults.standard.set(
            sender.state == .on,
            forKey: GeneralPreferences.showPinnedDocumentsInHistoryKey
        )
        GeneralPreferences.notifyChanged()
    }
}

private final class PrintingSettingsViewController: NSViewController {
    private let printerPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let paperSizePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let printerDetailLabel = NSTextField(labelWithString: "")
    private let animationCheckbox = NSButton(
        checkboxWithTitle: "Animate the page when using Quick Print",
        target: nil,
        action: nil
    )

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 278))
        reloadPrinters()
        configurePaperSizes()
        printerPopUp.target = self
        printerPopUp.action = #selector(printerChanged(_:))
        printerPopUp.setAccessibilityLabel("Quick Print printer")

        let printerLabel = NSTextField(labelWithString: "Quick Print printer:")
        printerLabel.alignment = .right
        printerLabel.setContentHuggingPriority(.required, for: .horizontal)
        let paperSizeLabel = NSTextField(labelWithString: "New document size:")
        paperSizeLabel.alignment = .right
        paperSizeLabel.setContentHuggingPriority(.required, for: .horizontal)

        printerDetailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        printerDetailLabel.textColor = .secondaryLabelColor
        printerDetailLabel.maximumNumberOfLines = 2

        animationCheckbox.state = PrintPreferences.shouldAnimatePrint ? .on : .off
        animationCheckbox.target = self
        animationCheckbox.action = #selector(animationChanged(_:))

        let commandHint = NSTextField(
            wrappingLabelWithString: "Command–Return sends the document directly to this printer without showing the print dialog."
        )
        commandHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        commandHint.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [paperSizeLabel, paperSizePopUp],
            [printerLabel, printerPopUp],
            [NSView(), printerDetailLabel]
        ])
        grid.rowSpacing = 7
        grid.columnSpacing = 12
        grid.xPlacement = .fill
        grid.yPlacement = .center
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        let options = NSStackView(views: [grid, animationCheckbox, commandHint])
        options.orientation = .vertical
        options.alignment = .leading
        options.spacing = 15
        options.setCustomSpacing(20, after: grid)
        options.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(options)
        NSLayoutConstraint.activate([
            options.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            options.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            options.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            grid.widthAnchor.constraint(equalTo: options.widthAnchor),
            printerPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 270),
            paperSizePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 270),
            commandHint.widthAnchor.constraint(lessThanOrEqualToConstant: 450)
        ])
        view = root
        updatePrinterDetail()
    }

    private func reloadPrinters() {
        printerPopUp.removeAllItems()
        printerPopUp.addItem(withTitle: "System Default")
        printerPopUp.lastItem?.representedObject = ""
        for name in NSPrinter.printerNames.sorted() {
            printerPopUp.addItem(withTitle: name)
            printerPopUp.lastItem?.representedObject = name
        }
        let selected = PrintPreferences.selectedPrinterName ?? ""
        if let item = printerPopUp.itemArray.first(where: { ($0.representedObject as? String) == selected }) {
            printerPopUp.select(item)
        } else {
            printerPopUp.selectItem(at: 0)
            UserDefaults.standard.set("", forKey: PrintPreferences.printerNameKey)
        }
    }

    private func configurePaperSizes() {
        for preset in PaperSizePreset.allCases {
            paperSizePopUp.addItem(withTitle: preset.displayName)
            paperSizePopUp.lastItem?.representedObject = preset.rawValue
        }
        paperSizePopUp.selectItem(
            withTitle: PrintPreferences.defaultPaperSize.displayName
        )
        paperSizePopUp.target = self
        paperSizePopUp.action = #selector(paperSizeChanged(_:))
        paperSizePopUp.setAccessibilityLabel("New document paper size")
    }

    @objc private func paperSizeChanged(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject as? String else {
            return
        }
        UserDefaults.standard.set(value, forKey: PrintPreferences.paperSizeKey)
        PrintPreferences.notifyChanged()
    }

    @objc private func printerChanged(_ sender: NSPopUpButton) {
        let name = sender.selectedItem?.representedObject as? String ?? ""
        UserDefaults.standard.set(name, forKey: PrintPreferences.printerNameKey)
        PrintPreferences.notifyChanged()
        updatePrinterDetail()
    }

    @objc private func animationChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: PrintPreferences.animatePrintKey)
        PrintPreferences.notifyChanged()
    }

    private func updatePrinterDetail() {
        if let name = PrintPreferences.selectedPrinterName {
            printerDetailLabel.stringValue = "Pinned to \(name)."
        } else if !NSPrintInfo.shared.printer.name.isEmpty {
            printerDetailLabel.stringValue = "Currently using the system default: \(NSPrintInfo.shared.printer.name)."
        } else {
            printerDetailLabel.stringValue = "macOS will use the available default printer."
        }
    }
}
