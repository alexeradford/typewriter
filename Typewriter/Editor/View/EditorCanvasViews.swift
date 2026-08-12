import AppKit

final class EditorScrollDocumentView: NSView {
    let pageView: PageCanvasView

    init(pageView: PageCanvasView) {
        self.pageView = pageView
        super.init(frame: NSRect(x: 0, y: 0, width: 760, height: 860))
        wantsLayer = true
        addSubview(pageView)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        pageView.setFrameOrigin(NSPoint(x: floor((bounds.width - pageView.frame.width) / 2), y: 36))
    }
}

final class PageCanvasView: NSView {
    // Torn bottom edge geometry: a run of small triangular "teeth" that make the
    // page look like it was ripped out of a typewriter platen.
    private static let cornerRadius: CGFloat = 4
    private static let toothWidth: CGFloat = 12
    private static let tearHeight: CGFloat = 6

    let textView: EditorTextView
    private(set) var pageLayout: EditorPageLayout
    private(set) var pageCount = 1

    // Per-tooth randomness generated once so the torn edge stays stable across
    // redraws instead of jittering on every layout pass.
    private var tearJitter: [[CGFloat]] = []
    private var suppressPageShadows = false

    init(textView: EditorTextView, pageLayout: EditorPageLayout) {
        self.textView = textView
        self.pageLayout = pageLayout
        super.init(frame: NSRect(origin: .zero, size: pageLayout.paperSize))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        ensureTearJitter()
        addSubview(textView)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        textView.frame = NSRect(
            x: EditorPageLayout.margin,
            y: EditorPageLayout.margin,
            width: pageLayout.contentSize.width,
            height: max(1, bounds.height - (EditorPageLayout.margin * 2))
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for index in 0..<pageCount {
            context.saveGState()
            if !suppressPageShadows {
                context.setShadow(
                    offset: CGSize(width: 0, height: -2),
                    blur: 11,
                    color: NSColor.black.withAlphaComponent(0.13).cgColor
                )
            }
            context.addPath(paperPath(for: index))
            context.setFillColor(TypewriterTheme.paper.cgColor)
            context.fillPath()
            context.restoreGState()
        }
    }

    func update(pageLayout: EditorPageLayout, pageCount: Int) -> Bool {
        let normalizedCount = max(1, pageCount)
        let desiredSize = NSSize(
            width: pageLayout.paperSize.width,
            height: pageLayout.canvasHeight(pageCount: normalizedCount)
        )
        guard self.pageLayout != pageLayout
                || self.pageCount != normalizedCount
                || frame.size != desiredSize
        else {
            return false
        }
        self.pageLayout = pageLayout
        self.pageCount = normalizedCount
        ensureTearJitter()
        setFrameSize(desiredSize)
        needsDisplay = true
        return true
    }

    func pageFrame(at index: Int) -> NSRect {
        pageLayout.pageFrame(at: min(max(0, index), pageCount - 1))
    }

    /// Captures one page without baking its resting shadow into the bitmap.
    /// Print animation supplies a single shared shadow for the assembled stack.
    func shadowlessSnapshot(at index: Int) -> NSImage? {
        let rect = pageFrame(at: index)
        guard let bitmap = bitmapImageRepForCachingDisplay(in: rect) else {
            return nil
        }

        suppressPageShadows = true
        defer {
            suppressPageShadows = false
            needsDisplay = true
        }
        needsDisplay = true
        cacheDisplay(in: rect, to: bitmap)

        let image = NSImage(size: rect.size)
        image.addRepresentation(bitmap)
        return image
    }

    /// Outline of the page: rounded top corners, straight sides, and a jagged
    /// torn edge along the bottom. Coordinates are in the view's flipped space
    /// (y increases downward), so the teeth sit at the bottom of the page.
    private func paperPath(for pageIndex: Int) -> CGPath {
        let pageFrame = pageLayout.pageFrame(at: pageIndex)
        return TornPaperPath.make(
            in: pageFrame,
            cornerRadius: Self.cornerRadius,
            toothWidth: Self.toothWidth,
            tearHeight: Self.tearHeight,
            jitter: tearJitter[pageIndex]
        )
    }

    private func ensureTearJitter() {
        let toothCount = Int(
            (pageLayout.paperSize.width / Self.toothWidth).rounded(.up)
        ) + 2
        while tearJitter.count < pageCount {
            tearJitter.append(
                (0..<toothCount).map { _ in CGFloat.random(in: 0...1) }
            )
        }
    }
}

final class CanvasBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func updateLayer() {
        layer?.backgroundColor = TypewriterTheme.canvas.cgColor
    }
}
