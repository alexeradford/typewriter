import AppKit

private enum LibraryCellMetrics {
    // NSTextField's alignment rect is inset two points from its frame. Account
    // for that so the visible field frame retains a ten-point trailing margin.
    static let trailingAnchorInset: CGFloat = 12
}

final class LibraryDocumentCellView: NSTableCellView {
    private let previewView = LibraryDocumentPreviewView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.configureForSidebarTruncation()
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.configureForSidebarTruncation()

        previewView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewView)
        addSubview(titleLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            previewView.centerYAnchor.constraint(equalTo: centerYAnchor),
            previewView.widthAnchor.constraint(equalToConstant: 30),
            previewView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(
                equalTo: previewView.trailingAnchor,
                constant: 7
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -LibraryCellMetrics.trailingAnchorInset
            ),
            titleLabel.bottomAnchor.constraint(
                equalTo: centerYAnchor,
                constant: -1
            ),
            detailLabel.leadingAnchor.constraint(
                equalTo: titleLabel.leadingAnchor
            ),
            detailLabel.trailingAnchor.constraint(
                equalTo: titleLabel.trailingAnchor
            ),
            detailLabel.topAnchor.constraint(
                equalTo: centerYAnchor,
                constant: 2
            )
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(with document: LibraryDocumentItem) {
        titleLabel.stringValue = document.title
        detailLabel.stringValue = document.previewText.isEmpty
            ? "Empty document"
            : document.previewText
        previewView.summary = LibraryDocumentSummary(
            title: document.title,
            previewText: document.previewText,
            pageCount: document.pageCount
        )
        toolTip = document.title
        setAccessibilityLabel(document.title)
        setAccessibilityHelp(
            document.pageCount == 1
                ? "One-page Typewriter document"
                : "\(document.pageCount)-page Typewriter document"
        )
    }
}

final class LibraryFolderCellView: NSTableCellView {
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 21,
            weight: .regular
        )
        symbolView.contentTintColor = .secondaryLabelColor
        symbolView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.configureForSidebarTruncation()
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.configureForSidebarTruncation()

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(symbolView)
        addSubview(titleLabel)
        addSubview(detailLabel)
        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 30),
            symbolView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(
                equalTo: symbolView.trailingAnchor,
                constant: 7
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -LibraryCellMetrics.trailingAnchorInset
            ),
            titleLabel.bottomAnchor.constraint(
                equalTo: centerYAnchor,
                constant: -1
            ),
            detailLabel.leadingAnchor.constraint(
                equalTo: titleLabel.leadingAnchor
            ),
            detailLabel.trailingAnchor.constraint(
                equalTo: titleLabel.trailingAnchor
            ),
            detailLabel.topAnchor.constraint(
                equalTo: centerYAnchor,
                constant: 2
            )
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(with folder: LibraryFolder, documentCount: Int) {
        symbolView.image = NSImage(
            systemSymbolName: "folder.fill",
            accessibilityDescription: "\(folder.name) folder"
        )
        titleLabel.stringValue = folder.name
        detailLabel.stringValue = switch documentCount {
        case 0:
            "Empty folder"
        case 1:
            "1 document"
        default:
            "\(documentCount) documents"
        }
        toolTip = folder.name
        setAccessibilityLabel("\(folder.name) folder")
        setAccessibilityHelp(detailLabel.stringValue)
    }
}

final class LibrarySimpleCellView: NSTableCellView {
    private let symbolView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 13)
        label.configureForSidebarTruncation()
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 14,
            weight: .regular
        )
        symbolView.contentTintColor = .secondaryLabelColor
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)
        addSubview(label)
        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 18),
            symbolView.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -LibraryCellMetrics.trailingAnchorInset
            ),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(title: String, symbolName: String, accessibilityLabel: String) {
        label.stringValue = title
        symbolView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )
        setAccessibilityLabel(accessibilityLabel)
    }
}

final class LibraryHeaderCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.configureForSidebarTruncation()
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -LibraryCellMetrics.trailingAnchorInset
            )
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(title: String) {
        label.stringValue = title
    }
}

final class LibraryDocumentPreviewView: NSView {
    var summary = LibraryDocumentSummary(
        title: "Untitled",
        previewText: "",
        pageCount: 1
    ) {
        didSet {
            needsDisplay = true
        }
    }

    private static let tearJitter: [CGFloat] = [
        0.18, 0.82, 0.36, 0.64, 0.28, 0.73, 0.45, 0.91
    ]

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let visibleStackCount = min(3, summary.pageCount)
        let pageSize = CGSize(width: 21, height: 29)
        let stackOffset: CGFloat = 1.5
        let frontOrigin = CGPoint(
            x: floor((bounds.width - pageSize.width) / 2)
                - CGFloat(visibleStackCount - 1) * stackOffset / 2,
            y: floor((bounds.height - pageSize.height) / 2)
                - CGFloat(visibleStackCount - 1) * stackOffset / 2
        )

        for depth in stride(from: visibleStackCount - 1, through: 0, by: -1) {
            let offset = CGFloat(depth) * stackOffset
            let rect = CGRect(
                x: frontOrigin.x + offset,
                y: frontOrigin.y + offset,
                width: pageSize.width,
                height: pageSize.height
            )
            let path = TornPaperPath.make(
                in: rect,
                cornerRadius: 1.5,
                toothWidth: 3,
                tearHeight: 1.75,
                jitter: Self.tearJitter
            )
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: depth == 0 ? 2.5 : 1,
                color: NSColor.black.withAlphaComponent(0.16).cgColor
            )
            context.addPath(path)
            context.setFillColor(TypewriterTheme.paper.cgColor)
            context.fillPath()
            context.restoreGState()

            context.addPath(path)
            context.setStrokeColor(
                NSColor.separatorColor.withAlphaComponent(0.55).cgColor
            )
            context.setLineWidth(0.5)
            context.strokePath()

            if depth == 0 {
                drawTextPreview(in: rect, clippedTo: path)
            }
        }
    }

    private func drawTextPreview(in pageRect: CGRect, clippedTo path: CGPath) {
        let preview = summary.previewText.isEmpty
            ? summary.title
            : summary.title + "\n" + summary.previewText
        guard !preview.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext.current?.cgContext
        context?.addPath(path)
        context?.clip()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 0.3
        (preview as NSString).draw(
            in: pageRect.insetBy(dx: 2.5, dy: 3.5),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 2.75, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}

private extension NSTextField {
    func configureForSidebarTruncation() {
        alignment = .left
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        cell?.usesSingleLineMode = true
        cell?.truncatesLastVisibleLine = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}
