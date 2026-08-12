import AppKit

final class AboutWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        window.title = "About Typewriter"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active

        let icon = NSImageView(image: NSImage(systemSymbolName: "text.page.fill", accessibilityDescription: "Typewriter")!)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 58, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [TypewriterTheme.accent]))

        let title = NSTextField(labelWithString: "Typewriter")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Write it. Print it. Keep it.")
        subtitle.font = .systemFont(ofSize: 14, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        let detail = NSTextField(wrappingLabelWithString: "A focused document editor made for turning a thought into a real sheet of paper—without getting in your way.")
        detail.alignment = .center
        detail.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [icon, title, subtitle, detail])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(18, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(stack)
        window.contentView = effect
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: -5),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: effect.leadingAnchor, constant: 42),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -42),
            detail.widthAnchor.constraint(equalToConstant: 330),
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72)
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            icon.wantsLayer = true
            let float = CABasicAnimation(keyPath: "transform.translation.y")
            float.fromValue = -3
            float.toValue = 4
            float.duration = 1.8
            float.autoreverses = true
            float.repeatCount = .infinity
            float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            icon.layer?.add(float, forKey: "float")
        }
    }
}
