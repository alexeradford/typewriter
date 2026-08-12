import AppKit

final class DocumentToolbarController: NSObject, NSToolbarDelegate {
    private enum Item {
        static let style = NSToolbarItem.Identifier("Typewriter.TextStyle")
        static let font = NSToolbarItem.Identifier("Typewriter.FontFamily")
        static let fontFamily = NSToolbarItem.Identifier("Typewriter.FontFamilyPicker")
        static let fontSize = NSToolbarItem.Identifier("Typewriter.FontSizePicker")
        static let traits = NSToolbarItem.Identifier("Typewriter.FontTraits")
        static let lists = NSToolbarItem.Identifier("Typewriter.Lists")
        static let codeBlock = NSToolbarItem.Identifier("Typewriter.CodeBlock")
        static let color = NSToolbarItem.Identifier("Typewriter.TextColor")
        static let testPrintAnimation = NSToolbarItem.Identifier("Typewriter.TestPrintAnimation")
        static let quickPrint = NSToolbarItem.Identifier("Typewriter.QuickPrint")
    }

    private let editor: EditorViewController
    private let stylePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let traitControl = NSSegmentedControl()
    private let listControl = NSSegmentedControl()
    private let blockControl = NSSegmentedControl()
    private let colorButton = TextColorButton()
    private let colorPaletteController = TextColorPaletteViewController()
    private let colorPopover = NSPopover()
    private var customSizeItem: NSMenuItem?

    var quickPrintHandler: (() -> Void)?
    var testPrintAnimationHandler: (() -> Void)?
    var insertImageHandler: (() -> Void)?
    var insertTableHandler: (() -> Void)?
    var restoreEditorFocus: (() -> Void)?

    init(editor: EditorViewController) {
        self.editor = editor
        super.init()
        configureControls()
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "Typewriter.DocumentToolbar.Library")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        return toolbar
    }

    func refreshSelectionState() {
        let attributes = editor.currentAttributes
        if let font = attributes[.font] as? NSFont {
            let family = EditorFontPresentation.familyTitle(for: font)
            if fontPopUp.item(withTitle: family) != nil {
                fontPopUp.selectItem(withTitle: family)
            } else {
                fontPopUp.selectItem(at: 0)
            }
            selectFontSize(font.pointSize)
            let traits = NSFontManager.shared.traits(of: font)
            traitControl.setSelected(traits.contains(.boldFontMask), forSegment: 0)
            traitControl.setSelected(traits.contains(.italicFontMask), forSegment: 1)
            let style = EditorFontPresentation.matchingTextStyle(for: font)
            selectTextStyle(style)
        }
        traitControl.setSelected((attributes[.underlineStyle] as? Int ?? 0) != 0, forSegment: 2)
        if let color = attributes[.foregroundColor] as? NSColor {
            colorButton.color = color
            colorPaletteController.selectedColor = color
        }
        let listKind = editor.textSystem.listController.selectedListKind
        listControl.setSelected(listKind == .bullet, forSegment: 0)
        listControl.setSelected(listKind == .numbered, forSegment: 1)
        listControl.setSelected(listKind == .checklist, forSegment: 2)
        traitControl.setSelected(
            editor.textSystem.formattingController.isCodeSnippetSelected,
            forSegment: 3
        )
        blockControl.setSelected(
            editor.textSystem.blockController.selectedBlockKind == .code,
            forSegment: 0
        )
        for segment in 1..<blockControl.segmentCount {
            blockControl.setSelected(false, forSegment: segment)
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            Item.style, Item.font,
            .space,
            Item.color,
            .space,
            Item.traits, Item.lists,
            .space,
            Item.codeBlock,
            .space,
            Item.testPrintAnimation,
            Item.quickPrint,
            .flexibleSpace
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Item.style, Item.font, Item.traits, Item.lists, Item.codeBlock,
            Item.color, Item.testPrintAnimation, Item.quickPrint,
            .toggleSidebar, .sidebarTrackingSeparator, .space, .flexibleSpace
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if !flag {
            return customizationPaletteItem(identifier)
        }

        switch identifier {
        case Item.style:
            return item(identifier, label: "Style", view: stylePopUp)
        case Item.font:
            return fontItemGroup(identifier)
        case Item.traits:
            return item(identifier, label: "Text Style", view: traitControl)
        case Item.lists:
            let toolbarItem = item(identifier, label: "Lists", view: listControl)
            toolbarItem.menuFormRepresentation = listsMenuItem()
            return toolbarItem
        case Item.codeBlock:
            let toolbarItem = item(identifier, label: "Insert", view: blockControl)
            toolbarItem.menuFormRepresentation = insertMenuItem()
            return toolbarItem
        case Item.color:
            return item(identifier, label: "Text Color", view: colorButton)
        case Item.testPrintAnimation:
            let toolbarItem = NSToolbarItem(itemIdentifier: identifier)
            toolbarItem.label = "Test Animation"
            toolbarItem.paletteLabel = "Test Print Animation"
            toolbarItem.toolTip = "Preview the page animation without printing"
            toolbarItem.image = NSImage(
                systemSymbolName: "play.rectangle",
                accessibilityDescription: "Test Print Animation"
            )
            toolbarItem.target = self
            toolbarItem.action = #selector(testPrintAnimation(_:))
            return toolbarItem
        case Item.quickPrint:
            let toolbarItem = NSToolbarItem(itemIdentifier: identifier)
            toolbarItem.label = "Quick Print"
            toolbarItem.paletteLabel = "Quick Print"
            toolbarItem.toolTip = "Send directly to the selected printer (Command–Return)"
            toolbarItem.image = NSImage(systemSymbolName: "printer.filled.and.paper", accessibilityDescription: "Quick Print")
            toolbarItem.target = self
            toolbarItem.action = #selector(quickPrint(_:))
            return toolbarItem
        default:
            return nil
        }
    }

    private func customizationPaletteItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        let presentation: (label: String, symbolName: String)
        switch identifier {
        case Item.style:
            presentation = ("Style", "textformat")
        case Item.font:
            presentation = ("Font", "textformat.size")
        case Item.traits:
            presentation = ("Text Style", "bold.italic.underline")
        case Item.lists:
            presentation = ("Lists", "list.bullet")
        case Item.codeBlock:
            presentation = ("Insert", "plus")
        case Item.color:
            presentation = ("Text Color", "paintpalette")
        case Item.testPrintAnimation:
            presentation = ("Test Print Animation", "play.rectangle")
        case Item.quickPrint:
            presentation = ("Quick Print", "printer.filled.and.paper")
        default:
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = presentation.label
        item.paletteLabel = presentation.label
        item.image = NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: presentation.label
        )
        return item
    }

    private func configureControls() {
        for style in EditorTextStyle.menuOrder {
            stylePopUp.addItem(withTitle: style.title)
            stylePopUp.lastItem?.representedObject = style.rawValue
        }
        stylePopUp.addItem(withTitle: "Custom")
        selectTextStyle(.body)
        configure(stylePopUp, width: 100, label: "Text style", action: #selector(styleChanged(_:)))

        fontPopUp.addItem(withTitle: "System")
        let families = NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        fontPopUp.addItems(withTitles: families)
        configure(fontPopUp, width: 112, label: "Font family", action: #selector(fontChanged(_:)))

        let fontSizes: [Double] = [10, 11, 12, 13, 14, 15, 16, 18, 20, 21, 24, 28, 32, 34, 40, 48]
        for size in fontSizes {
            sizePopUp.addItem(withTitle: fontSizeTitle(CGFloat(size)))
            sizePopUp.lastItem?.representedObject = size
        }
        configure(sizePopUp, width: 60, label: "Font size", action: #selector(sizeChanged(_:)))

        traitControl.segmentCount = 4
        traitControl.trackingMode = .selectAny
        traitControl.setImage(NSImage(systemSymbolName: "bold", accessibilityDescription: "Bold"), forSegment: 0)
        traitControl.setImage(NSImage(systemSymbolName: "italic", accessibilityDescription: "Italic"), forSegment: 1)
        traitControl.setImage(NSImage(systemSymbolName: "underline", accessibilityDescription: "Underline"), forSegment: 2)
        traitControl.setImage(NSImage(
            systemSymbolName: "chevron.left.forwardslash.chevron.right",
            accessibilityDescription: "Code snippet"
        ), forSegment: 3)
        traitControl.setToolTip("Toggle code snippet", forSegment: 3)
        traitControl.target = self
        traitControl.action = #selector(traitsChanged(_:))
        traitControl.setAccessibilityLabel("Text styles")
        traitControl.widthAnchor.constraint(equalToConstant: 138).isActive = true

        listControl.segmentCount = 3
        listControl.trackingMode = .selectAny
        listControl.setImage(NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Bulleted list"), forSegment: 0)
        listControl.setImage(NSImage(systemSymbolName: "list.number", accessibilityDescription: "Numbered list"), forSegment: 1)
        listControl.setImage(NSImage(systemSymbolName: "checklist", accessibilityDescription: "Checklist"), forSegment: 2)
        listControl.setToolTip("Bulleted list", forSegment: 0)
        listControl.setToolTip("Numbered list", forSegment: 1)
        listControl.setToolTip("Checklist", forSegment: 2)
        listControl.target = self
        listControl.action = #selector(listChanged(_:))
        listControl.setAccessibilityLabel("Lists")
        listControl.widthAnchor.constraint(equalToConstant: 114).isActive = true

        blockControl.segmentCount = 4
        blockControl.trackingMode = .selectAny
        blockControl.setImage(NSImage(
            systemSymbolName: "text.rectangle",
            accessibilityDescription: "Code block"
        ), forSegment: 0)
        blockControl.setImage(NSImage(
            systemSymbolName: "minus",
            accessibilityDescription: "Divider"
        ), forSegment: 1)
        blockControl.setImage(NSImage(
            systemSymbolName: "photo",
            accessibilityDescription: "Image"
        ), forSegment: 2)
        blockControl.setImage(NSImage(
            systemSymbolName: "tablecells",
            accessibilityDescription: "Table"
        ), forSegment: 3)
        blockControl.setToolTip("Insert or remove code block", forSegment: 0)
        blockControl.setToolTip("Insert divider", forSegment: 1)
        blockControl.setToolTip("Insert image", forSegment: 2)
        blockControl.setToolTip("Insert table", forSegment: 3)
        blockControl.target = self
        blockControl.action = #selector(blockChanged(_:))
        blockControl.setAccessibilityLabel("Insert")
        blockControl.widthAnchor.constraint(equalToConstant: 132).isActive = true

        colorButton.color = EditorTextSystem.defaultTypingAttributes[.foregroundColor] as? NSColor ?? .textColor
        colorButton.target = self
        colorButton.action = #selector(showColorPalette(_:))
        colorButton.setAccessibilityLabel("Text color")
        colorButton.toolTip = "Choose text color"
        colorButton.widthAnchor.constraint(equalToConstant: 42).isActive = true

        colorPaletteController.onSelectColor = { [weak self] color in
            self?.applyTextColor(color)
        }
        colorPaletteController.onShowMoreColors = { [weak self] in
            self?.showSystemColorPanel()
        }
        colorPopover.behavior = .transient
        colorPopover.contentViewController = colorPaletteController
    }

    private func configure(_ popUp: NSPopUpButton, width: CGFloat, label: String, action: Selector) {
        popUp.target = self
        popUp.action = action
        popUp.setAccessibilityLabel(label)
        popUp.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func item(_ identifier: NSToolbarItem.Identifier, label: String, view: NSView) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.view = view
        return item
    }

    private func fontItemGroup(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(itemIdentifier: identifier)
        group.label = "Font"
        group.paletteLabel = "Font"
        group.controlRepresentation = .expanded
        group.subitems = [
            item(Item.fontFamily, label: "Font Family", view: fontPopUp),
            item(Item.fontSize, label: "Font Size", view: sizePopUp)
        ]
        return group
    }

    private func insertMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Insert", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Insert")

        let imageItem = NSMenuItem(
            title: "Image…",
            action: #selector(insertImageFromMenu(_:)),
            keyEquivalent: ""
        )
        imageItem.target = self
        submenu.addItem(imageItem)

        let tableItem = NSMenuItem(
            title: "Table",
            action: #selector(insertTableFromMenu(_:)),
            keyEquivalent: ""
        )
        tableItem.target = self
        submenu.addItem(tableItem)
        submenu.addItem(.separator())

        let codeBlockItem = NSMenuItem(
            title: "Code Block",
            action: #selector(toggleCodeBlockFromMenu(_:)),
            keyEquivalent: ""
        )
        codeBlockItem.target = self
        submenu.addItem(codeBlockItem)

        let dividerItem = NSMenuItem(
            title: "Divider",
            action: #selector(insertDividerFromMenu(_:)),
            keyEquivalent: ""
        )
        dividerItem.target = self
        submenu.addItem(dividerItem)

        menuItem.submenu = submenu
        return menuItem
    }

    private func listsMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Lists", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Lists")

        let bulletItem = NSMenuItem(
            title: "Bulleted List",
            action: #selector(toggleBulletedListFromMenu(_:)),
            keyEquivalent: ""
        )
        bulletItem.target = self
        submenu.addItem(bulletItem)

        let numberedItem = NSMenuItem(
            title: "Numbered List",
            action: #selector(toggleNumberedListFromMenu(_:)),
            keyEquivalent: ""
        )
        numberedItem.target = self
        submenu.addItem(numberedItem)

        let checklistItem = NSMenuItem(
            title: "Checklist",
            action: #selector(toggleChecklistFromMenu(_:)),
            keyEquivalent: ""
        )
        checklistItem.target = self
        submenu.addItem(checklistItem)

        menuItem.submenu = submenu
        return menuItem
    }

    private func selectTextStyle(_ style: EditorTextStyle?) {
        if let style,
           let item = stylePopUp.itemArray.first(where: {
               ($0.representedObject as? Int) == style.rawValue
           }) {
            stylePopUp.select(item)
        } else {
            stylePopUp.selectItem(withTitle: "Custom")
        }
    }

    private func selectFontSize(_ size: CGFloat) {
        let numericSize = Double(size)
        if let item = sizePopUp.itemArray.first(where: {
            $0 !== customSizeItem
                && abs(($0.representedObject as? Double ?? -Double.greatestFiniteMagnitude) - numericSize) < 0.01
        }) {
            if let customSizeItem {
                sizePopUp.menu?.removeItem(customSizeItem)
                self.customSizeItem = nil
            }
            sizePopUp.select(item)
            return
        }

        if let customSizeItem {
            sizePopUp.menu?.removeItem(customSizeItem)
        }
        let title = fontSizeTitle(size)
        let item = customSizeItem ?? NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.title = title
        item.representedObject = numericSize
        let insertionIndex = sizePopUp.itemArray.firstIndex {
            ($0.representedObject as? Double ?? .greatestFiniteMagnitude) > numericSize
        } ?? sizePopUp.numberOfItems
        sizePopUp.menu?.insertItem(item, at: insertionIndex)
        customSizeItem = item
        sizePopUp.select(item)
    }

    private func fontSizeTitle(_ size: CGFloat) -> String {
        "\(String(format: "%g", size)) pt"
    }

    @objc private func styleChanged(_ sender: NSPopUpButton) {
        if let rawValue = sender.selectedItem?.representedObject as? Int,
           let style = EditorTextStyle(rawValue: rawValue) {
            editor.apply(style: style)
        }
        finishCommand()
    }

    @objc private func fontChanged(_ sender: NSPopUpButton) {
        guard let family = sender.titleOfSelectedItem else { return }
        sender.indexOfSelectedItem == 0 ? editor.applySystemFont() : editor.applyFontFamily(family)
        finishCommand()
    }

    @objc private func sizeChanged(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject as? Double else { return }
        editor.applyFontSize(CGFloat(value))
        finishCommand()
    }

    @objc private func traitsChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: editor.toggleTrait(.boldFontMask)
        case 1: editor.toggleTrait(.italicFontMask)
        case 2: editor.toggleUnderline()
        case 3: editor.toggleCodeSnippet()
        default: return
        }
        finishCommand()
    }

    @objc private func listChanged(_ sender: NSSegmentedControl) {
        let kind: EditorListKind
        switch sender.selectedSegment {
        case 0: kind = .bullet
        case 1: kind = .numbered
        case 2: kind = .checklist
        default: return
        }
        editor.toggleList(kind)
        finishCommand()
    }

    @objc private func toggleBulletedListFromMenu(_ sender: NSMenuItem) {
        editor.toggleList(.bullet)
        finishCommand()
    }

    @objc private func toggleNumberedListFromMenu(_ sender: NSMenuItem) {
        editor.toggleList(.numbered)
        finishCommand()
    }

    @objc private func toggleChecklistFromMenu(_ sender: NSMenuItem) {
        editor.toggleList(.checklist)
        finishCommand()
    }

    @objc private func blockChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            editor.toggleCodeBlock()
        case 1:
            sender.setSelected(false, forSegment: 1)
            editor.insertDivider()
        case 2:
            sender.setSelected(false, forSegment: 2)
            insertImageHandler?()
        case 3:
            sender.setSelected(false, forSegment: 3)
            insertTableHandler?()
        default:
            return
        }
        finishCommand()
    }

    @objc private func toggleCodeBlockFromMenu(_ sender: NSMenuItem) {
        editor.toggleCodeBlock()
        finishCommand()
    }

    @objc private func insertDividerFromMenu(_ sender: NSMenuItem) {
        editor.insertDivider()
        finishCommand()
    }

    @objc private func insertImageFromMenu(_ sender: NSMenuItem) {
        insertImageHandler?()
    }

    @objc private func insertTableFromMenu(_ sender: NSMenuItem) {
        insertTableHandler?()
        finishCommand()
    }

    @objc private func showColorPalette(_ sender: TextColorButton) {
        if colorPopover.isShown {
            colorPopover.performClose(sender)
            return
        }

        colorPaletteController.selectedColor = colorButton.color
        colorPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    @objc private func systemColorChanged(_ sender: NSColorPanel) {
        editor.applyTextColor(sender.color)
        colorButton.color = sender.color
        colorPaletteController.selectedColor = sender.color
    }

    private func applyTextColor(_ color: NSColor) {
        colorPopover.performClose(nil)
        editor.applyTextColor(color)
        colorButton.color = color
        finishCommand()
    }

    private func showSystemColorPanel() {
        colorPopover.performClose(nil)
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = colorButton.color
        panel.setTarget(self)
        panel.setAction(#selector(systemColorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func quickPrint(_ sender: Any?) {
        quickPrintHandler?()
    }

    @objc private func testPrintAnimation(_ sender: Any?) {
        testPrintAnimationHandler?()
    }

    private func finishCommand() {
        refreshSelectionState()
        restoreEditorFocus?()
    }
}
