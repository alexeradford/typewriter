# Library Architecture

Typewriter owns a managed document library under Application Support. The
library is an index over ordinary `NSDocument` files, not a second document
format or an alternate persistence system.

## Storage

`DocumentLibraryStore` owns three things:

- `Documents/` for documents that are not inside a library folder.
- `Folders/<folder-id>/` for documents assigned to a folder.
- `Catalog.json` for presentation metadata, stable identifiers, ordering, and
  the selected history sort order.

Catalog writes are atomic. At launch, the store reconciles catalog entries
against files on disk and registers managed documents that are not yet indexed.
Files opened from outside the library are copied into managed storage before
`NSDocumentController` opens them, preserving the source file.

The catalog's `topLevelItems` array is the single source of truth for the
headerless upper section. It can contain folder and pinned-document identifiers
in any order. The lower history is derived from every document's creation date,
so pinning or filing a document does not remove it from history.

## AppKit ownership

`LibraryDocumentController` is the application's `NSDocumentController`.
Creating a document reserves its managed URL before a window is made, which
allows the first save and every subsequent autosave to use normal in-place
`NSDocument` persistence without presenting a save panel.

`Document` remains responsible for encoding and decoding RTFD, change
tracking, autosave, and print settings. The library store receives only a small
summary after a successful save: title, preview text, page count, and current
managed path.

Selecting a history row does not close and recreate the window. The destination
document is opened without display, then AppKit's `addWindowController(_:)`
transfers the existing `DocumentWindowController` from the source document to
the destination document. The editor replaces its TextKit content while undo
registration is disabled, and the source document is closed after it no longer
owns a window. Per-document selection and scroll state live on that window
controller and are restored when navigating back. This keeps the window,
sidebar, toolbar, geometry, and editing position stable.
The sidebar remains first responder after this navigation so the active
source-list selection keeps the window's accent color. New-document creation
is the intentional exception and moves focus to the empty editor.

New documents use the same ownership path.
`openUntitledDocumentAndDisplay(false)` asks `NSDocumentController` to create,
register, and file-coordinate the new document without creating UI; the current
window controller is then transferred to it.

“Open in New Tab” is deliberately separate. It creates the destination's own
window controller and uses `NSWindow.addTabbedWindow(_:ordered:)`, so tab
creation happens only when the user explicitly requests it.

## Sidebar

`LibrarySidebarViewController` uses `NSOutlineView` with source-list style
inside an `NSSplitViewController` sidebar item. Its node tree has:

1. Ordered folder and pinned-document rows at the root, with no group header.
2. Relative date groups such as Today, Yesterday, July 6, or April 8 2025.

Folder moves use `NSDocument.move(to:)` while the document is open and a file
move while it is closed. Dragging a document into the upper root pins it;
dragging folders or pinned documents within that root changes their persisted
order. Sorting is available from the bottom sidebar bar. Every visible
representation of the active document is selected together. A General setting
controls whether pinned documents are repeated in date history.
