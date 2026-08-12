import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBuilder: AppMenuBuilder?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    private var isOpeningLibraryWindow = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let builder = AppMenuBuilder(delegate: self)
        menuBuilder = builder
        NSApp.mainMenu = builder.makeMainMenu()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        DocumentLibraryStore.shared.snapshot.documents.isEmpty
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let library = DocumentLibraryStore.shared
        if let error = library.initializationError {
            NSApp.presentError(error)
            return
        }
        if let notice = library.startupNotice {
            NSApp.presentError(notice)
        }
        guard NSDocumentController.shared.documents.isEmpty else { return }
        openLibraryWindow()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            openLibraryWindow()
        }
        // We have handled the reopen event. Returning true would ask AppKit to
        // also run its standard document-app behavior, which presents Open.
        return false
    }

    private func openLibraryWindow() {
        guard !isOpeningLibraryWindow else { return }
        let library = DocumentLibraryStore.shared
        if let error = library.initializationError {
            NSApp.presentError(error)
            return
        }
        let recentDocument = NSDocumentController.shared.recentDocumentURLs
            .lazy
            .compactMap { library.document(at: $0) }
            .first
        let document = recentDocument
            ?? library.snapshot.documents.max {
                $0.createdAt < $1.createdAt
            }
        guard
            let document,
            let url = library.url(for: document)
        else {
            NSDocumentController.shared.newDocument(nil)
            return
        }

        if let openDocument = NSDocumentController.shared.document(for: url) {
            openDocument.showWindows()
            openDocument.windowControllers.first?.window?
                .makeKeyAndOrderFront(nil)
            return
        }

        isOpeningLibraryWindow = true
        NSDocumentController.shared.openDocument(
            withContentsOf: url,
            display: true
        ) { [weak self] _, _, error in
            self?.isOpeningLibraryWindow = false
            if let error {
                NSApp.presentError(error)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func application(
        _ app: NSApplication,
        shouldRestoreWindowWithIdentifier identifier: NSUserInterfaceItemIdentifier,
        state: NSCoder,
        completionHandler: @escaping (NSWindow?, Error?) -> Void
    ) -> Bool {
        false
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(sender)
        settingsWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout(_ sender: Any?) {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.showWindow(sender)
        aboutWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quickPrint(_ sender: Any?) {
        currentDocument?.quickPrint()
    }

    @objc func printDocument(_ sender: Any?) {
        currentDocument?.printShowingPanel()
    }

    @objc func exportDocument(_ sender: Any?) {
        guard
            let document = currentDocument,
            let window = document.windowForSheet
        else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(Document.typeIdentifier)
                ?? UTType(filenameExtension: "typewriter")
                ?? .data
        ]
        panel.nameFieldStringValue = document.libraryDisplayTitle
            + ".typewriter"
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Export a copy. The working document remains in your Library."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            document.save(
                to: url,
                ofType: Document.typeIdentifier,
                for: .saveToOperation
            ) { error in
                if let error {
                    window.presentError(error)
                }
            }
        }
    }

    @objc func runPageLayout(_ sender: Any?) {
        guard let document = currentDocument else { return }
        if NSPageLayout().runModal(with: document.printInfo)
            == NSApplication.ModalResponse.OK.rawValue {
            document.pageLayoutDidChange()
        }
    }

    private var currentDocument: Document? {
        NSDocumentController.shared.currentDocument as? Document
    }

}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(quickPrint(_:)),
             #selector(printDocument(_:)),
             #selector(exportDocument(_:)),
             #selector(runPageLayout(_:)):
            currentDocument != nil
        default:
            true
        }
    }
}
