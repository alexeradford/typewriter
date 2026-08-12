#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

enum EditorListNewlineAction {
    case consume
    case continueList(from: EditorListState)
}

struct EditorListMarkerTarget: Equatable {
    let paragraphLocation: Int
    let rect: CGRect
}

final class EditorListController: EditorListPresentationProviding {
    private unowned let textView: EditorTextView
    private unowned let textLayoutManager: NSTextLayoutManager
    private unowned let textContentStorage: NSTextContentStorage
    private var pendingEmptyParagraphList: (location: Int, state: EditorListState)?

    private var textStorage: NSTextStorage {
        guard let storage = textContentStorage.textStorage else {
            preconditionFailure("TextKit 2 content storage lost its backing text storage")
        }
        return storage
    }

    init(
        textView: EditorTextView,
        textLayoutManager: NSTextLayoutManager,
        textContentStorage: NSTextContentStorage
    ) {
        self.textView = textView
        self.textLayoutManager = textLayoutManager
        self.textContentStorage = textContentStorage
    }

    var selectedListKind: EditorListKind? {
        let kinds = selectedParagraphRanges().map { listState(for: $0)?.kind }
        guard let first = kinds.first, let kind = first else { return nil }
        return kinds.allSatisfy { $0 == kind } ? kind : nil
    }

    var isChecklistAtSelection: Bool {
        let paragraph = paragraphRange(containing: textView.selectedRange().location)
        return listState(for: paragraph)?.kind == .checklist
    }

    func listPresentation(
        at documentLocation: Int
    ) -> EditorListPresentation? {
        if let pendingPresentation = pendingListPresentation(
            at: documentLocation
        ) {
            return pendingPresentation
        }

        let paragraph = paragraphRange(containing: documentLocation)
        guard paragraph.location < textStorage.length else { return nil }
        let style = textStorage.attribute(
            .paragraphStyle,
            at: paragraph.location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        guard let state = EditorListState.from(style) else { return nil }
        return EditorListPresentation(
            state: state,
            ordinal: state.kind == .numbered
                ? numberedOrdinal(for: paragraph)
                : nil
        )
    }

    func insertionMaterializingPendingList(
        _ insertion: Any,
        replacementRange: NSRange
    ) -> Any {
        let insertionLocation = replacementRange.location == NSNotFound
            ? textView.selectedRange().location
            : replacementRange.location
        guard
            let pendingEmptyParagraphList,
            pendingEmptyParagraphList.location == insertionLocation
        else {
            return insertion
        }

        let attributedInsertion: NSMutableAttributedString
        if let attributedString = insertion as? NSAttributedString {
            attributedInsertion = attributedString.mutableCopy()
                as! NSMutableAttributedString
        } else if let string = insertion as? String {
            attributedInsertion = NSMutableAttributedString(
                string: string,
                attributes: textView.typingAttributes
            )
        } else {
            return insertion
        }

        guard attributedInsertion.length > 0 else { return insertion }
        attributedInsertion.addAttribute(
            .paragraphStyle,
            value: EditorParagraphStyle.list(pendingEmptyParagraphList.state),
            range: NSRange(location: 0, length: attributedInsertion.length)
        )
        return attributedInsertion
    }

    func completePendingListInsertion(at insertionLocation: Int) {
        guard
            let pendingEmptyParagraphList,
            pendingEmptyParagraphList.location == insertionLocation,
            insertionLocation < textStorage.length,
            listState(
                for: paragraphRange(containing: insertionLocation),
                includingPendingState: false
            ) == pendingEmptyParagraphList.state
        else {
            return
        }
        self.pendingEmptyParagraphList = nil
        textView.typingAttributes[.paragraphStyle] = EditorParagraphStyle.list(
            pendingEmptyParagraphList.state
        )
    }

    func selectionDidChange() {
        guard let pendingEmptyParagraphList else { return }
        let selection = textView.selectedRange()
        guard
            selection.length == 0,
            selection.location == pendingEmptyParagraphList.location
        else {
            self.pendingEmptyParagraphList = nil
            refreshLayout(for: [
                NSRange(
                    location: pendingEmptyParagraphList.location,
                    length: 0
                )
            ])
            return
        }
    }

    func clearPendingEmptyParagraphList() {
        let previousLocation = pendingEmptyParagraphList?.location
        pendingEmptyParagraphList = nil
        if let previousLocation {
            refreshLayout(for: [
                NSRange(location: previousLocation, length: 0)
            ])
        }
    }

    func refreshSelectedParagraphLayout() {
        refreshLayout(for: selectedParagraphRanges())
    }

    func toggleList(_ kind: EditorListKind) {
        let paragraphs = selectedParagraphRanges()
        guard !paragraphs.isEmpty else { return }

        let removesList = paragraphs
            .map { listState(for: $0) }
            .allSatisfy { $0?.kind == kind }
        let newState: EditorListState? = removesList
            ? nil
            : EditorListState.initialState(for: kind)
        let newStyle: NSParagraphStyle
        if let newState {
            newStyle = EditorParagraphStyle.list(newState)
        } else {
            newStyle = EditorParagraphStyle.body
        }

        let originalSelection = textView.selectedRange()
        let storedParagraphs = paragraphs.filter { $0.length > 0 }
        if let affectedRange = union(of: storedParagraphs) {
            performAttributeEdit(in: affectedRange, actionName: "Change List") {
                for paragraph in storedParagraphs {
                    textStorage.addAttribute(
                        .paragraphStyle,
                        value: newStyle,
                        range: paragraph
                    )
                }
            }
        }

        if paragraphs.contains(where: { $0.length == 0 }) {
            if let emptyParagraph = paragraphs.first(where: { $0.length == 0 }),
               let newState {
                pendingEmptyParagraphList = (
                    location: emptyParagraph.location,
                    state: newState
                )
            } else {
                pendingEmptyParagraphList = nil
            }
            textView.typingAttributes[.paragraphStyle] = newState.map {
                EditorParagraphStyle.pendingList($0)
            } ?? EditorParagraphStyle.body
        } else {
            pendingEmptyParagraphList = nil
            updateTypingParagraphStyle(newStyle)
        }
        textView.setSelectedRange(originalSelection)
        refreshLayout(for: paragraphs)
    }

    func prepareForNewline() -> EditorListNewlineAction? {
        let paragraph = paragraphRange(containing: textView.selectedRange().location)
        guard let state = listState(for: paragraph) else { return nil }

        let body = paragraph.length > 0
            ? (textView.string as NSString).substring(with: paragraph)
            : ""
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if paragraph.length > 0 {
                performAttributeEdit(in: paragraph, actionName: "End List") {
                    textStorage.addAttribute(
                        .paragraphStyle,
                        value: EditorParagraphStyle.body,
                        range: paragraph
                    )
                }
            }
            pendingEmptyParagraphList = nil
            textView.typingAttributes[.paragraphStyle] = EditorParagraphStyle.body
            refreshLayout(for: [paragraph])
            return .consume
        }

        return .continueList(from: state)
    }

    func completeNewline(from sourceState: EditorListState) {
        let newState = EditorListState.initialState(for: sourceState.kind)
        let style = EditorParagraphStyle.list(newState)
        let paragraph = paragraphRange(containing: textView.selectedRange().location)

        if paragraph.length > 0 {
            performAttributeEdit(in: paragraph, actionName: "Continue List") {
                textStorage.addAttribute(.paragraphStyle, value: style, range: paragraph)
            }
        }
        pendingEmptyParagraphList = (
            location: paragraph.location,
            state: newState
        )
        textView.typingAttributes[.paragraphStyle] = EditorParagraphStyle.pendingList(
            newState
        )
        refreshLayout(for: [paragraph])
    }

    func removeListAtParagraphStart() -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }

        let paragraph = paragraphRange(containing: selection.location)
        guard selection.location == paragraph.location else { return false }
        guard listState(for: paragraph) != nil else { return false }

        if paragraph.length > 0 {
            let didChange = performAttributeEdit(in: paragraph, actionName: "End List") {
                textStorage.addAttribute(
                    .paragraphStyle,
                    value: EditorParagraphStyle.body,
                    range: paragraph
                )
            }
            guard didChange else { return false }
        }

        pendingEmptyParagraphList = nil
        textView.typingAttributes[.paragraphStyle] = EditorParagraphStyle.body
        refreshLayout(for: [paragraph])
        return true
    }

    func markerTarget(at viewPoint: CGPoint) -> EditorListMarkerTarget? {
        let containerPoint = CGPoint(
            x: viewPoint.x - textView.textContainerOrigin.x,
            y: viewPoint.y - textView.textContainerOrigin.y
        )
        let lookupPoint = CGPoint(
            x: EditorParagraphStyle.listIndent + 1,
            y: containerPoint.y
        )
        guard
            let fragment = textLayoutManager.textLayoutFragment(for: lookupPoint)
                as? EditorListLayoutFragment,
            fragment.listState?.kind == .checklist,
            let markerRect = fragment.markerRectInContainer,
            markerRect.insetBy(dx: -6, dy: -5).contains(containerPoint),
            let paragraph = paragraphRange(for: fragment)
        else {
            return nil
        }

        return EditorListMarkerTarget(
            paragraphLocation: paragraph.location,
            rect: markerRect.offsetBy(
                dx: textView.textContainerOrigin.x,
                dy: textView.textContainerOrigin.y
            )
        )
    }

    @discardableResult
    func toggleChecklist(_ target: EditorListMarkerTarget) -> Bool {
        let paragraph = paragraphRange(containing: target.paragraphLocation)
        guard
            let state = listState(for: paragraph),
            state.kind == .checklist
        else {
            return false
        }

        let newState = EditorListState(kind: .checklist, isChecked: !state.isChecked)
        let style = EditorParagraphStyle.list(newState)
        if paragraph.length > 0 {
            guard performAttributeEdit(in: paragraph, actionName: "Toggle Checklist Item", {
                textStorage.addAttribute(.paragraphStyle, value: style, range: paragraph)
            }) else {
                return false
            }
        } else {
            pendingEmptyParagraphList = (
                location: paragraph.location,
                state: newState
            )
            textView.typingAttributes[.paragraphStyle] = EditorParagraphStyle.pendingList(
                newState
            )
        }

        if textView.selectedRange().location >= paragraph.location,
           textView.selectedRange().location <= NSMaxRange(paragraph) {
            textView.typingAttributes[.paragraphStyle] = paragraph.length == 0
                ? EditorParagraphStyle.pendingList(newState)
                : style
        }
        refreshLayout(for: [paragraph])
        return true
    }

    func toggleChecklistAtSelection() -> Bool {
        let paragraph = paragraphRange(containing: textView.selectedRange().location)
        guard
            let state = listState(for: paragraph),
            state.kind == .checklist
        else {
            return false
        }

        let target = EditorListMarkerTarget(
            paragraphLocation: paragraph.location,
            rect: .zero
        )
        return toggleChecklist(target)
    }

    func visibleChecklistMarkerRects() -> [CGRect] {
        guard let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange else {
            return []
        }

        var rects: [CGRect] = []
        textLayoutManager.enumerateTextLayoutFragments(
            from: viewportRange.location,
            options: [.ensuresLayout]
        ) { [textView] fragment in
            guard viewportRange.intersects(fragment.rangeInElement) else { return false }
            guard
                let listFragment = fragment as? EditorListLayoutFragment,
                listFragment.listState?.kind == .checklist,
                let markerRect = listFragment.markerRectInContainer
            else {
                return true
            }
            rects.append(markerRect.offsetBy(
                dx: textView.textContainerOrigin.x,
                dy: textView.textContainerOrigin.y
            ))
            return true
        }
        return rects
    }

    func migrateLegacyMarkers() {
        guard textStorage.length > 0 else { return }

        var trailingState: EditorListState?
        textContentStorage.performEditingTransaction {
            textStorage.beginEditing()
            var location = 0
            while location < textStorage.length {
                let nsString = textStorage.string as NSString
                let paragraph = nsString.paragraphRange(
                    for: NSRange(location: location, length: 0)
                )
                let line = nsString.substring(with: paragraph)
                if let style = textStorage.attribute(
                    .paragraphStyle,
                    at: paragraph.location,
                    effectiveRange: nil
                ) as? NSParagraphStyle,
                   let state = EditorListState.from(style),
                   let format = style.textLists.last?.markerFormat,
                   format != .disc {
                    textStorage.addAttribute(
                        .paragraphStyle,
                        value: EditorParagraphStyle.list(state),
                        range: paragraph
                    )
                }
                let legacyState: EditorListState?
                if line.hasPrefix("•\t") {
                    legacyState = .bullet
                } else if line.hasPrefix("☐\t") {
                    legacyState = .unchecked
                } else if line.hasPrefix("☑\t") {
                    legacyState = EditorListState(
                        kind: .checklist,
                        isChecked: true
                    )
                } else {
                    legacyState = nil
                }

                guard let legacyState else {
                    location = NSMaxRange(paragraph)
                    continue
                }

                let inheritedAttributes = attributesFollowingLegacyMarker(
                    at: paragraph.location
                )
                textStorage.replaceCharacters(
                    in: NSRange(location: paragraph.location, length: 2),
                    with: ""
                )
                let updatedParagraph = NSRange(
                    location: paragraph.location,
                    length: max(0, paragraph.length - 2)
                )
                if updatedParagraph.length > 0 {
                    textStorage.addAttributes(
                        inheritedAttributes,
                        range: updatedParagraph
                    )
                    textStorage.addAttribute(
                        .paragraphStyle,
                        value: EditorParagraphStyle.list(legacyState),
                        range: updatedParagraph
                    )
                } else {
                    trailingState = legacyState
                }
                location = NSMaxRange(updatedParagraph)
            }
            textStorage.endEditing()
        }

        if let trailingState {
            pendingEmptyParagraphList = (
                location: textStorage.length,
                state: trailingState
            )
            textView.typingAttributes[.paragraphStyle] =
                EditorParagraphStyle.pendingList(trailingState)
        }
        refreshSelectedParagraphLayout()
    }

    private func paragraphRange(for fragment: EditorListLayoutFragment) -> NSRange? {
        guard let contentManager = fragment.textLayoutManager?.textContentManager else {
            return nil
        }
        let location = contentManager.offset(
            from: contentManager.documentRange.location,
            to: fragment.rangeInElement.location
        )
        guard location != NSNotFound else { return nil }
        return paragraphRange(containing: location)
    }

    private func paragraphRange(containing location: Int) -> NSRange {
        let nsString = textView.string as NSString
        guard nsString.length > 0 else {
            return NSRange(location: 0, length: 0)
        }
        if location == nsString.length,
           isNewline(nsString.character(at: nsString.length - 1)) {
            return NSRange(location: nsString.length, length: 0)
        }
        return nsString.paragraphRange(
            for: NSRange(location: min(location, nsString.length - 1), length: 0)
        )
    }

    private func selectedParagraphRanges() -> [NSRange] {
        let nsString = textView.string as NSString
        if nsString.length == 0 {
            return [NSRange(location: 0, length: 0)]
        }

        let selection = textView.selectedRange()
        if selection.length == 0,
           selection.location == nsString.length,
           isNewline(nsString.character(at: nsString.length - 1)) {
            return [NSRange(location: nsString.length, length: 0)]
        }

        let safeLocation = min(selection.location, nsString.length - 1)
        let effectiveSelection = NSRange(
            location: safeLocation,
            length: min(selection.length, nsString.length - safeLocation)
        )
        let fullRange = nsString.paragraphRange(for: effectiveSelection)
        var result: [NSRange] = []
        var cursor = fullRange.location
        while cursor < NSMaxRange(fullRange) {
            let paragraph = nsString.paragraphRange(
                for: NSRange(location: cursor, length: 0)
            )
            result.append(paragraph)
            let next = NSMaxRange(paragraph)
            guard next > cursor else { break }
            cursor = next
        }
        return result
    }

    private func listState(
        for paragraph: NSRange,
        includingPendingState: Bool = true
    ) -> EditorListState? {
        if includingPendingState,
           paragraph.length == 0,
           let pendingState = pendingListPresentation(
               at: paragraph.location
           )?.state {
            return pendingState
        }

        let style: NSParagraphStyle?
        if paragraph.location < textStorage.length {
            style = textStorage.attribute(
                .paragraphStyle,
                at: paragraph.location,
                effectiveRange: nil
            ) as? NSParagraphStyle
        } else {
            style = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        return EditorListState.from(style)
    }

    private func pendingListPresentation(
        at documentLocation: Int
    ) -> EditorListPresentation? {
        guard
            let pendingEmptyParagraphList,
            pendingEmptyParagraphList.location == documentLocation
        else {
            return nil
        }

        let selection = textView.selectedRange()
        guard
            selection.length == 0,
            selection.location == documentLocation,
            paragraphRange(containing: documentLocation).length == 0
        else {
            return nil
        }
        let state = pendingEmptyParagraphList.state
        return EditorListPresentation(
            state: state,
            ordinal: state.kind == .numbered
                ? numberedOrdinal(
                    for: paragraphRange(containing: documentLocation)
                )
                : nil
        )
    }

    private func numberedOrdinal(for paragraph: NSRange) -> Int {
        guard paragraph.location > 0 else { return 1 }

        let nsString = textView.string as NSString
        var ordinal = 1
        var cursor = paragraph.location
        while cursor > 0 {
            let previous = nsString.paragraphRange(
                for: NSRange(location: cursor - 1, length: 0)
            )
            guard
                previous.location < cursor,
                listState(
                    for: previous,
                    includingPendingState: false
                )?.kind == .numbered
            else {
                break
            }
            ordinal += 1
            cursor = previous.location
        }
        return ordinal
    }

    @discardableResult
    private func performAttributeEdit(
        in range: NSRange,
        actionName: String,
        _ mutation: () -> Void
    ) -> Bool {
        guard textView.shouldChangeText(in: range, replacementString: nil) else {
            return false
        }

        textContentStorage.performEditingTransaction {
            textStorage.beginEditing()
            mutation()
            textStorage.endEditing()
        }
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        return true
    }

    private func updateTypingParagraphStyle(_ style: NSParagraphStyle) {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return }
        textView.typingAttributes[.paragraphStyle] = style
    }

    private func attributesFollowingLegacyMarker(
        at location: Int
    ) -> [NSAttributedString.Key: Any] {
        let bodyLocation = location + 2
        if bodyLocation < textStorage.length {
            var attributes = textStorage.attributes(
                at: bodyLocation,
                effectiveRange: nil
            )
            attributes.removeValue(forKey: .paragraphStyle)
            return attributes
        }
        var attributes = textView.typingAttributes
        attributes.removeValue(forKey: .paragraphStyle)
        return attributes
    }

    private func union(of ranges: [NSRange]) -> NSRange? {
        ranges.reduce(nil) { result, range in
            result.map { NSUnionRange($0, range) } ?? range
        }
    }

    private func refreshLayout(for paragraphs: [NSRange]) {
        if let storedRange = union(
            of: paragraphs.filter { $0.length > 0 }
        ) {
            textStorage.edited(
                .editedAttributes,
                range: storedRange,
                changeInLength: 0
            )
        }

        let documentStart = textContentStorage.documentRange.location
        for paragraph in paragraphs {
            let startOffset = min(paragraph.location, textStorage.length)
            let endOffset = min(NSMaxRange(paragraph), textStorage.length)
            guard
                let startLocation = textContentStorage.location(
                    documentStart,
                    offsetBy: startOffset
                ),
                let endLocation = textContentStorage.location(
                    documentStart,
                    offsetBy: endOffset
                ),
                let textRange = NSTextRange(
                    location: startLocation,
                    end: endLocation
                )
            else {
                continue
            }
            textLayoutManager.invalidateLayout(for: textRange)
            textLayoutManager.ensureLayout(for: textRange)
        }

        textLayoutManager.textViewportLayoutController.layoutViewport()
#if canImport(AppKit)
        textView.needsDisplay = true
        textView.window?.invalidateCursorRects(for: textView)
#else
        textView.setNeedsDisplay()
#endif
    }

    private func isNewline(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(character) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }
}
