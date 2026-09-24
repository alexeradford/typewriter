# Editor architecture

The editor core is implemented entirely on TextKit 2 and lives in `Shared/`.
`EditorTextSystem` manually assembles `NSTextContentStorage`,
`NSTextLayoutManager`, `NSTextContainer`, and the platform editor view so both
apps use the same attributed-content, formatting, list, block, table, and
layout semantics. AppKit and UIKit retain distinct event bridges and app UI.

The Mac editor must never access `NSTextView.layoutManager`. AppKit documents that
reading that TextKit 1 property permanently switches the text view into
compatibility mode. `EditorTextSystem` observes AppKit's compatibility-mode
notification and asserts in debug builds if an accidental downgrade occurs.

## Boundaries

- `EditorTextSystem` creates and retains the TextKit 2 graph. It is the façade
  for attributed content, layout height, formatting, and list behavior.
- `EditorPlatform` is the narrow AppKit/UIKit adapter for fonts, colors,
  images, paths, font traits, and text-container sizing. Platform conditionals
  belong there unless an API genuinely has different ownership semantics.
- `EditorFormattingController` owns rich-text mutations. Every stored attribute
  edit is validated with `shouldChangeText`, wrapped in an
  `NSTextContentStorage` editing transaction, and completed with
  `didChangeText` so AppKit's undo and change notifications remain balanced.
  Inline code snippets are character-range formatting owned here: a
  monospaced font design and RTF-safe attributed background, independent of
  paragraph block behavior.
- `EditorContentInsertionController` owns native image attachments and table
  insertion. Images imported from the Insert command, pasteboard, or drag and
  drop share page-aware sizing and remain ordinary `NSTextAttachment` values,
  preserving AppKit copy and drag behavior. Tables use RTF-safe tab-delimited
  paragraphs with TextKit 2 grid rendering and keyboard cell navigation.
  `NSTextTable` is deliberately avoided because AppKit makes a text view enter
  TextKit 1 compatibility mode when it encounters one.
- `EditorListController` owns list commands, continuation rules, hit testing,
  legacy marker migration, and checklist state changes. List state has one
  durable source of truth: the paragraph's `NSTextList` metadata. Because
  AppKit removes list metadata from `typingAttributes` on a zero-length
  document, the controller temporarily owns the selected empty paragraph's
  list intent and materializes it into the first attributed insertion. Changes
  that affect custom paragraphs explicitly mark their attributes as edited so
  `NSTextContentStorage` re-fetches them instead of redrawing cached elements.
- `EditorBlockController` owns block-level editing behavior independently of
  inline formatting and lists. Code blocks use a canonical paragraph style and
  attributed background as their RTF-persisted representation, plus monospaced
  typography. Their visible container is drawn by the TextKit 2 layout
  fragment, avoiding `NSTextBlock`, which makes `NSTextView` enter TextKit 1
  compatibility mode when edited. Return continues a nonempty code block;
  Return on an empty code line and Backspace at its start return to a body
  paragraph. The controller normalizes the representation after decoding and
  migrates documents created by the earlier `NSTextBlock` implementation.
  Dividers are dedicated paragraphs containing an invisible marker and a
  canonical RTF-safe paragraph style. Their visible full-width rule is also
  drawn by the layout fragment, so it adapts to editor and print widths.
- `EditorTextLayoutDelegate` vends `EditorListLayoutFragment` instances.
  It also supplies `NSTextListElement` marker attributes that make TextKit's
  native marker invisible while preserving the paragraph font's line metrics.
  The element owns its paragraph terminator, so the delegate removes the
  backing storage's terminator from the element contents to avoid creating an
  extra empty line. Fragments draw the one visible marker using TextKit's
  synthesized marker slot, reserve a small inter-item margin, and center it on
  the corresponding `NSTextLineFragment` line box. A fragment snapshots whether
  it represents an empty paragraph when TextKit vends the element; it never
  re-reads `NSTextParagraph.attributedString` during later layout because an
  invalidated element can temporarily outlive a shortening edit to its backing
  storage. Pending empty items anchor directly to the same list gutter and
  reserve the future marker slot for the caret, so neither moves when typing
  begins.
- Each target owns an `EditorTextView` event bridge. The AppKit bridge routes
  keyboard, pointer, cursor, pasteboard, and accessibility behavior. The UIKit
  bridge routes `UITextInput`, touch, selection, accessibility, and native undo
  behavior. Both delegate editing semantics to the shared controllers and
  contain no document or layout policy.
- Mac `EditorViewController` integrates the shared editor with paginated paper,
  status, toolbar, window, and printing UI. iOS `TypewriterTextEditor` embeds it
  in SwiftUI as a continuous, width-responsive editing surface; paper geometry
  is retained for persistence and page estimates.

## Data flow

`Shared/Documents/TypewriterDocumentPackage` owns the package format for both
targets: `Content.rtfd` plus `Metadata.json`. Document RTFD data is decoded to
`NSAttributedString`, installed into
`NSTextContentStorage`, edited through the formatting, block, and list
controllers, and serialized from `EditorTextSystem.attributedContent`. Legacy
RTF documents remain readable. RTFD is required because plain RTF silently
drops image attachments. Code
blocks and dividers persist as attributed paragraph styles; bullets and
checklist states persist in `NSTextList`. All editor lists use the stable unordered
`disc` layout path; checklist state is encoded in the list's persisted item
metadata. Older `box` and `check` list formats are accepted and normalized on
load. Keeping one TextKit list-element format avoids an AppKit rendering defect
where changing marker formats can hide the entire paragraph.

Normal layout is viewport-driven. `EditorPageLayout` derives the printable
content rectangle from the document's paper size. Full-width exclusion bands
flow rendered lines around page margins. TextKit can still create a zero-width
layout fragment for an empty paragraph inside an excluded band, so the custom
TextKit 2 fragment adjusts only those empty paragraphs. A newline-only fragment
is placed one actual text-line height before the next page's content origin
because it represents the line being closed; the trailing insertion point
therefore begins on the first line of the new page. Edits that add or remove
newlines explicitly invalidate cached fragments from the edit onward so TextKit
cannot reuse a previously snapped placement.

This prevents caret positions inside page margins without moving a multi-line
paragraph as one block, and preserves one attributed-string source of truth.
Page count comes from the document-end insertion rectangle, and geometry
updates are coalesced after text edits rather than observing viewport-sensitive
usage bounds. The controller performs custom scrolling only when page count
actually changes: creation reveals the new page below the window's automatic
top inset, while removal clamps the existing viewport to the smaller canvas.
Printing creates a second, unpaginated TextKit 2 system on macOS and lets
`NSPrintOperation` paginate it using the same paper size and margins.

## Target ownership

- `Shared/Documents` and `Shared/Editor` compile into both app targets.
- `Typewriter/Editor` owns AppKit canvas, event, integration, and print-facing
  behavior.
- `Typewriter iOS/Documents` owns the observable mobile document model.
- `Typewriter iOS/Library` owns coordinated package discovery, opening,
  autosave, import, and deletion for the in-app Library.
- `Typewriter iOS/Editor` owns the UIKit bridge, SwiftUI representable, and
  observable formatting session.

The shared directory can become a framework target later without moving either
app's UI or lifecycle code. Its intended public surface is:

- an editor system or factory that accepts attributed content and container
  width;
- a platform editor-view bridge supplied by each app target;
- attributed-content snapshots;
- formatting, block, and list commands;
- layout-height and content-change callbacks.

Mac page chrome, printer status, toolbar controls, and window ownership remain
in the macOS target. SwiftUI library navigation, compact formatting controls,
coordinated autosave, and file import remain in the iOS target. The iOS app
uses a normal `WindowGroup`; it doesn't opt into the system document-browser
lifecycle.
