import AppKit

MainActor.assumeIsolated {
    let documentController = LibraryDocumentController()
    let application = NSApplication.shared
    let applicationDelegate = AppDelegate()
    application.delegate = applicationDelegate
    withExtendedLifetime(documentController) {
        application.run()
    }
}
