import AppKit

final class TextColorButton: NSColorWell {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        colorWellStyle = .default
        supportsAlpha = false
    }

    required init?(coder: NSCoder) { nil }

    override func activate(_ exclusive: Bool) {
        guard let action else { return }
        sendAction(action, to: target)
    }
}

final class TextColorPaletteViewController: NSViewController {
    struct PaletteColor {
        let name: String
        let color: NSColor
    }

    private static let palette: [PaletteColor] = [
        PaletteColor(name: "Ink", color: NSColor(calibratedWhite: 0.09, alpha: 1)),
        PaletteColor(name: "Graphite", color: NSColor(calibratedWhite: 0.32, alpha: 1)),
        PaletteColor(name: "Red", color: NSColor(calibratedRed: 0.70, green: 0.15, blue: 0.12, alpha: 1)),
        PaletteColor(name: "Orange", color: NSColor(calibratedRed: 0.70, green: 0.36, blue: 0.04, alpha: 1)),
        PaletteColor(name: "Gold", color: NSColor(calibratedRed: 0.55, green: 0.43, blue: 0.02, alpha: 1)),
        PaletteColor(name: "Green", color: NSColor(calibratedRed: 0.14, green: 0.45, blue: 0.28, alpha: 1)),
        PaletteColor(name: "Blue", color: NSColor(calibratedRed: 0.14, green: 0.33, blue: 0.64, alpha: 1)),
        PaletteColor(name: "Indigo", color: NSColor(calibratedRed: 0.32, green: 0.26, blue: 0.65, alpha: 1)),
        PaletteColor(name: "Purple", color: NSColor(calibratedRed: 0.49, green: 0.24, blue: 0.60, alpha: 1)),
        PaletteColor(name: "Rose", color: NSColor(calibratedRed: 0.60, green: 0.24, blue: 0.42, alpha: 1))
    ]

    var onSelectColor: ((NSColor) -> Void)?
    var onShowMoreColors: (() -> Void)?
    var selectedColor: NSColor = TextColorPaletteViewController.palette[0].color {
        didSet { updateSelection() }
    }

    private var swatchButtons: [PaletteSwatchButton] = []

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Text Color")
        heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        for rowStart in stride(from: 0, to: Self.palette.count, by: 5) {
            let buttons = Self.palette[rowStart..<min(rowStart + 5, Self.palette.count)].map { paletteColor in
                let button = PaletteSwatchButton(color: paletteColor.color, name: paletteColor.name)
                button.target = self
                button.action = #selector(selectColor(_:))
                swatchButtons.append(button)
                return button
            }
            grid.addRow(with: buttons)
        }

        let separator = NSBox()
        separator.boxType = .separator

        let moreColors = NSButton(title: "More Colors…", target: self, action: #selector(showMoreColors(_:)))
        moreColors.bezelStyle = .accessoryBarAction
        moreColors.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        moreColors.imagePosition = .imageLeading
        moreColors.alignment = .left

        let stack = NSStackView(views: [heading, grid, separator, moreColors])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            moreColors.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        view = root
        updateSelection()
    }

    @objc private func selectColor(_ sender: PaletteSwatchButton) {
        selectedColor = sender.color
        onSelectColor?(sender.color)
    }

    @objc private func showMoreColors(_ sender: Any?) {
        onShowMoreColors?()
    }

    private func updateSelection() {
        guard isViewLoaded else { return }
        for button in swatchButtons {
            button.isSelected = button.color.isVisuallyEqual(to: selectedColor)
        }
    }
}

private final class PaletteSwatchButton: NSButton {
    let color: NSColor
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    init(color: NSColor, name: String) {
        self.color = color
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setAccessibilityLabel(name)
        toolTip = name
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let ringRect = bounds.insetBy(dx: 1.5, dy: 1.5)
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(roundedRect: ringRect, xRadius: 7, yRadius: 7)
            ring.lineWidth = 2.5
            ring.stroke()
        }

        let swatchRect = ringRect.insetBy(dx: isSelected ? 4 : 2, dy: isSelected ? 4 : 2)
        color.setFill()
        let cornerRadius: CGFloat = isSelected ? 4 : 5.5
        NSBezierPath(roundedRect: swatchRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        NSColor.separatorColor.setStroke()
        let outline = NSBezierPath(
            roundedRect: swatchRect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: cornerRadius - 0.5,
            yRadius: cornerRadius - 0.5
        )
        outline.lineWidth = 1
        outline.stroke()
    }
}

private extension NSColor {
    func isVisuallyEqual(to other: NSColor) -> Bool {
        guard let left = usingColorSpace(.deviceRGB),
              let right = other.usingColorSpace(.deviceRGB) else {
            return isEqual(other)
        }

        let tolerance: CGFloat = 0.005
        return abs(left.redComponent - right.redComponent) < tolerance
            && abs(left.greenComponent - right.greenComponent) < tolerance
            && abs(left.blueComponent - right.blueComponent) < tolerance
            && abs(left.alphaComponent - right.alphaComponent) < tolerance
    }
}
