#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

enum EditorListKind: Equatable {
    case bullet
    case numbered
    case checklist
}

struct EditorListState: Equatable {
    let kind: EditorListKind
    let isChecked: Bool

    fileprivate static let uncheckedChecklistItemNumber = 2
    fileprivate static let checkedChecklistItemNumber = 3

    static let bullet = EditorListState(kind: .bullet, isChecked: false)
    static let numbered = EditorListState(kind: .numbered, isChecked: false)
    static let unchecked = EditorListState(kind: .checklist, isChecked: false)

    static func initialState(for kind: EditorListKind) -> EditorListState {
        switch kind {
        case .bullet: .bullet
        case .numbered: .numbered
        case .checklist: .unchecked
        }
    }

    static func from(_ paragraphStyle: NSParagraphStyle?) -> EditorListState? {
        guard let textList = paragraphStyle?.textLists.last else {
            return nil
        }

        switch textList.markerFormat {
        case .decimal:
            return .numbered
        case .disc:
            switch textList.startingItemNumber {
            case uncheckedChecklistItemNumber:
                return .unchecked
            case checkedChecklistItemNumber:
                return EditorListState(kind: .checklist, isChecked: true)
            default:
                return .bullet
            }
        case .circle, .box:
            return .unchecked
        case .square, .check:
            return EditorListState(kind: .checklist, isChecked: true)
        default:
            return nil
        }
    }
}

enum EditorParagraphStyle {
    static let listIndent: CGFloat = 34
    private static let synthesizedMarkerSlotWidth: CGFloat = 24

    static var body: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 5
        style.lineBreakMode = .byWordWrapping
        return style
    }

    static func list(_ state: EditorListState) -> NSParagraphStyle {
        let style = body.mutableCopy() as! NSMutableParagraphStyle
        style.lineSpacing = 0
        style.paragraphSpacing = 0
        style.firstLineHeadIndent = listIndent
        style.headIndent = listIndent
        style.tabStops = []

        let startingItemNumber: Int
        switch (state.kind, state.isChecked) {
        case (.bullet, _):
            startingItemNumber = 1
        case (.numbered, _):
            startingItemNumber = 1
        case (.checklist, false):
            startingItemNumber = EditorListState.uncheckedChecklistItemNumber
        case (.checklist, true):
            startingItemNumber = EditorListState.checkedChecklistItemNumber
        }
        let markerFormat: NSTextList.MarkerFormat = state.kind == .numbered
            ? .decimal
            : .disc
        let textList = NSTextList(markerFormat: markerFormat, options: 0)
        textList.startingItemNumber = startingItemNumber
        style.textLists = [textList]
        return style
    }

    static func pendingList(_ state: EditorListState) -> NSParagraphStyle {
        let style = list(state).mutableCopy() as! NSMutableParagraphStyle
        let pendingTextIndent = listIndent + synthesizedMarkerSlotWidth
        style.firstLineHeadIndent = pendingTextIndent
        style.headIndent = pendingTextIndent
        return style
    }
}
