import AppKit

final class AppMenuBuilder: NSObject, NSMenuDelegate {
    private weak var appDelegate: AppDelegate?

    init(delegate: AppDelegate) {
        appDelegate = delegate
    }

    func makeMainMenu() -> NSMenu {
        let main = NSMenu(title: "Main Menu")
        main.addItem(menuItem(title: "Typewriter", submenu: applicationMenu()))
        main.addItem(menuItem(title: "File", submenu: fileMenu()))
        main.addItem(menuItem(title: "Edit", submenu: editMenu()))
        main.addItem(menuItem(title: "Format", submenu: formatMenu()))
        main.addItem(menuItem(title: "Insert", submenu: insertMenu()))
        main.addItem(menuItem(title: "View", submenu: viewMenu()))
        main.addItem(menuItem(title: "Window", submenu: windowMenu()))
        main.addItem(menuItem(title: "Help", submenu: helpMenu()))
        return main
    }

    private func applicationMenu() -> NSMenu {
        let menu = NSMenu(title: "Typewriter")
        menu.addItem(item("About Typewriter", #selector(AppDelegate.showAbout(_:)), target: appDelegate))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), key: ",", target: appDelegate))
        menu.addItem(.separator())
        menu.addItem(item("Services", nil, submenu: NSMenu(title: "Services")))
        NSApp.servicesMenu = menu.items.last?.submenu
        menu.addItem(.separator())
        menu.addItem(item("Hide Typewriter", #selector(NSApplication.hide(_:)), key: "h"))
        let hideOthers = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Typewriter", #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), key: "n", target: NSDocumentController.shared))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), key: "o", target: NSDocumentController.shared))

        let recent = NSMenu(title: "Open Recent")
        recent.delegate = self
        menu.addItem(item("Open Recent", nil, submenu: recent))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), key: "w"))
        menu.addItem(item("Save Now", #selector(NSDocument.save(_:)), key: "s"))
        menu.addItem(
            item(
                "Export Copy…",
                #selector(AppDelegate.exportDocument(_:)),
                key: "S",
                modifiers: [.command, .shift],
                target: appDelegate
            )
        )
        menu.addItem(item("Revert To Saved", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Page Setup…", #selector(AppDelegate.runPageLayout(_:)), target: appDelegate))
        menu.addItem(item("Print…", #selector(AppDelegate.printDocument(_:)), key: "p", target: appDelegate))
        let quickPrint = item("Quick Print", #selector(AppDelegate.quickPrint(_:)), key: "\r", target: appDelegate)
        quickPrint.keyEquivalentModifierMask = [.command]
        menu.addItem(quickPrint)
        return menu
    }

    private func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), key: "z"))
        let redo = item("Redo", Selector(("redo:")), key: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), key: "V", modifiers: [.command, .option, .shift]))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        menu.addItem(item("Show Fonts", #selector(NSFontManager.orderFrontFontPanel(_:)), key: "t", target: NSFontManager.shared))
        menu.addItem(item("Show Colors", #selector(NSApplication.orderFrontColorPanel(_:)), key: "c", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Bold", #selector(DocumentWindowController.toggleBold(_:)), key: "b"))
        menu.addItem(item("Italic", #selector(DocumentWindowController.toggleItalic(_:)), key: "i"))
        menu.addItem(item("Underline", #selector(DocumentWindowController.toggleUnderline(_:)), key: "u"))
        menu.addItem(.separator())
        menu.addItem(item("Numbered List", #selector(DocumentWindowController.toggleNumberedList(_:)), key: "7", modifiers: [.command, .shift]))
        menu.addItem(item("Bulleted List", #selector(DocumentWindowController.toggleBulletedList(_:)), key: "8", modifiers: [.command, .shift]))
        menu.addItem(item("Checklist", #selector(DocumentWindowController.toggleChecklist(_:)), key: "9", modifiers: [.command, .shift]))
        menu.addItem(
            item(
                "Toggle Checklist Item",
                #selector(DocumentWindowController.toggleChecklistItem(_:)),
                key: "\r",
                modifiers: [.command, .shift]
            )
        )

        let alignment = NSMenu(title: "Alignment")
        alignment.addItem(item("Align Left", #selector(NSText.alignLeft(_:)), key: "[", modifiers: [.command, .shift]))
        alignment.addItem(item("Center", #selector(NSText.alignCenter(_:)), key: "|", modifiers: [.command, .shift]))
        alignment.addItem(item("Align Right", #selector(NSText.alignRight(_:)), key: "]", modifiers: [.command, .shift]))
        alignment.addItem(item("Justify", #selector(NSTextView.alignJustified(_:))))
        menu.addItem(item("Alignment", nil, submenu: alignment))
        return menu
    }

    private func insertMenu() -> NSMenu {
        let menu = NSMenu(title: "Insert")
        menu.addItem(item("Image…", #selector(DocumentWindowController.insertImage(_:))))
        menu.addItem(item("Table", #selector(DocumentWindowController.insertTable(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Code Block", #selector(DocumentWindowController.toggleCodeBlock(_:))))
        menu.addItem(item("Divider", #selector(DocumentWindowController.insertDivider(_:))))
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(
            item(
                "Toggle Sidebar",
                #selector(NSSplitViewController.toggleSidebar(_:)),
                key: "s",
                modifiers: [.command, .control]
            )
        )
        menu.addItem(.separator())
        menu.addItem(item("Show Toolbar", #selector(NSWindow.toggleToolbarShown(_:))))
        menu.addItem(item("Customize Toolbar…", #selector(NSWindow.runToolbarCustomizationPalette(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control]))
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = menu
        return menu
    }

    private func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Typewriter Help", #selector(AppDelegate.showAbout(_:)), key: "?", target: appDelegate))
        NSApp.helpMenu = menu
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Open Recent" else { return }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs.prefix(10) {
            let title = DocumentLibraryStore.shared.document(at: url)?.title
                ?? url.deletingPathExtension().lastPathComponent
            let recentItem = NSMenuItem(title: title, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            recentItem.representedObject = url
            recentItem.target = self
            recentItem.toolTip = url.path
            menu.addItem(recentItem)
        }
        if menu.items.isEmpty {
            let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            menu.addItem(.separator())
            menu.addItem(item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)), target: NSDocumentController.shared))
        }
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    private func menuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        result.submenu = submenu
        return result
    }

    private func item(
        _ title: String,
        _ action: Selector?,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        result.target = target
        return result
    }

    private func item(_ title: String, _ action: Selector?, submenu: NSMenu) -> NSMenuItem {
        let result = item(title, action)
        result.submenu = submenu
        return result
    }
}
