import SwiftUI

struct TypewriterTextEditor: UIViewRepresentable {
    let document: TypewriterMobileDocument
    let session: TypewriterEditorSession
    @Binding var isEditing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            document: document,
            session: session,
            isEditing: $isEditing
        )
    }

    func makeUIView(context: Context) -> EditorTextView {
        let textSystem = EditorTextSystem(
            content: document.content,
            containerWidth: 560
        )
        context.coordinator.install(textSystem)

        let textView = textSystem.textView
        textView.backgroundColor = .white
        textView.textColor = EditorColor(editorWhite: 0.09, alpha: 1)
        textView.font = EditorTextStyle.body.font
        textView.typingAttributes = EditorTextSystem.defaultTypingAttributes
        textView.textContainerInset = UIEdgeInsets(
            top: 28,
            left: 24,
            bottom: 72,
            right: 24
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .yes
        textView.smartDashesType = .yes
        textView.smartQuotesType = .yes
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityIdentifier = "typewriter.editor"
        textView.accessibilityLabel = "Document editor"
        return textView
    }

    func updateUIView(_ textView: EditorTextView, context: Context) {
        let contentWidth = max(
            1,
            textView.bounds.width
                - textView.textContainerInset.left
                - textView.textContainerInset.right
        )
        context.coordinator.updateLayout(containerWidth: contentWidth)
        context.coordinator.update(document: document)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: EditorTextView,
        context: Context
    ) -> CGSize? {
        guard
            let width = proposal.width,
            let height = proposal.height
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    final class Coordinator {
        private weak var document: TypewriterMobileDocument?
        private let session: TypewriterEditorSession
        private var isEditing: Binding<Bool>
        private(set) var textSystem: EditorTextSystem?
        private var documentID: UUID
        private var loadedContentRevision: Int
        private var configuredContainerWidth: CGFloat?

        init(
            document: TypewriterMobileDocument,
            session: TypewriterEditorSession,
            isEditing: Binding<Bool>
        ) {
            self.document = document
            self.session = session
            documentID = document.metadata.documentID
            loadedContentRevision = document.contentRevision
            self.isEditing = isEditing
        }

        func install(_ textSystem: EditorTextSystem) {
            self.textSystem = textSystem
            session.attach(textSystem)
            textSystem.migrateLegacyListMarkers()
            textSystem.normalizeStoredCodeBlocks()
            textSystem.normalizeImageAttachments()

            textSystem.formattingController.selectionStateDidChange = { [weak self] in
                self?.session.refreshSelection()
            }
            textSystem.blockController.selectionStateDidChange = { [weak self] in
                self?.session.refreshSelection()
            }
            textSystem.textView.selectionDidChange = { [weak self] in
                self?.session.refreshSelection()
            }
            textSystem.textView.contentDidChange = { [weak self] in
                self?.editorContentDidChange()
            }
            textSystem.textView.editingDidBegin = { [weak self] in
                self?.isEditing.wrappedValue = true
            }
            textSystem.textView.editingDidEnd = { [weak self] in
                self?.isEditing.wrappedValue = false
            }
        }

        func updateLayout(containerWidth: CGFloat) {
            let width = max(1, containerWidth)
            if let configuredContainerWidth,
               abs(configuredContainerWidth - width) < 0.5 {
                return
            }
            configuredContainerWidth = width
            textSystem?.configureContinuousLayout(containerWidth: width)
        }

        func update(document: TypewriterMobileDocument) {
            self.document = document
            guard let textSystem else { return }
            let isDifferentDocument = documentID != document.metadata.documentID
            guard
                isDifferentDocument
                    || loadedContentRevision != document.contentRevision
            else {
                return
            }
            documentID = document.metadata.documentID
            loadedContentRevision = document.contentRevision
            textSystem.replaceContent(with: document.content)
        }

        private func editorContentDidChange() {
            guard let document, let textSystem else { return }
            if let range = textSystem.textView
                .consumePaginationLayoutInvalidationRange() {
                textSystem.invalidatePaginationLayout(from: range)
            }
            let layout = EditorPageLayout(paperSize: document.paperSize)
            let pageCount = layout.pageCount(
                forTextHeight: textSystem.contentHeight()
            )
            document.updateEditorContent(
                textSystem.attributedContent,
                pageCount: pageCount
            )
            loadedContentRevision = document.contentRevision
            session.refreshSelection()
        }
    }
}
