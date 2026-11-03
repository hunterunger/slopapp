# Paper

Read, annotate and edit PDFs.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Nitro PDF Pro.

**Status:** alpha

Paper is a document app for the PDF jobs Preview makes awkward: redacting every occurrence of
a name or number and proving it's gone, combining and splitting files, flattening a signed form
before you send it, and doing all of it from the keyboard. No account, no subscription, no
network.

## What it does

- **Read**: continuous or single-page view, two pages, zoom (fit width, fit page, actual
  size), thumbnails, outline, go to page, back/forward, links, search with a results list.
- **Mark up**: highlight, underline and strike through text (five colors), text boxes (also
  for typing on flat forms), sticky notes, rectangles, ovals, lines, arrows and freehand
  drawing. Select, move, resize, recolor and delete. Everything is undoable.
- **Sign**: draw a signature or initials once, place them on any page, resize them.
- **Fill forms**: text fields, checkboxes, radio buttons and pop-ups, with Tab between fields.
- **Pages**: reorder by dragging thumbnails or with ⌥⌘↑/↓, rotate, delete, insert from a file
  or a Finder drop, insert blank pages, reverse, extract to a new document, split into files.
- **Combine Files…**: an ordered list of PDFs and images becomes one document, with an option
  to interleave front and back scans.
- **Export Flattened Copy…**: annotations, signatures and form entries become part of the page.
- **Redact**: mark text or areas with the Redact tool, or find every occurrence with Find and
  Redact. Marks stay pending (and saving never applies them) until you choose Apply
  Redactions…, which writes a **new file** by default, removes the content under the marks
  (text, hidden OCR text, image pixels), flattens notes and fields, optionally clears the
  document information, and **checks the result** before saving it. If a page can't be
  verified, it's turned into an image and checked again; if that fails, nothing is written.

## Saving

Paper saves like any Mac document app: autosave with versions (File > Revert To), Duplicate,
Rename, Move To. Redaction and flattening never change your file unless you explicitly choose
to replace it (and confirm). PDFs whose owner restricts printing, copying or changes open
read-only, because saving them would remove those restrictions. Password-protected PDFs keep
their password when saved.

## Keyboard

| Action | Shortcut |
|---|---|
| Select, Highlight, Draw, Text Box, Note, Shapes, Sign, Redact | ⌘1 ⌘2 ⌘3 ⌘4 ⌘5 ⌘6 ⌘8 ⌘9 |
| Back to Select | Esc or V |
| Delete selected annotation | ⌫ |
| Nudge selected annotation | arrows (⇧ for 10 pt) |
| Find, next, previous, use selection | ⌘F, ⌘G, ⇧⌘G, ⌘E |
| Find and Redact | ⇧⌘F |
| Rotate left / right | ⌘L / ⌘R |
| Delete pages | ⌘⌫ (⌫ in the thumbnails) |
| Move pages up / down | ⌥⌘↑ / ⌥⌘↓ |
| Insert from file / blank page | ⇧⌘I / ⌥⌘B |
| Extract selected pages | ⌥⌘E |
| Go to page | ⌥⌘G |
| Sidebar: hide, thumbnails, outline, notes | ⌥⌘1 ⌥⌘2 ⌥⌘3 ⌥⌘4 |
| Zoom: actual size, in, out, fit, width | ⌘0, ⌘+, ⌘−, ⌥⌘0, ⌥⌘9 |
| Copy highlights & notes as Markdown | ⌥⇧⌘C |

## Permissions and privacy

Paper needs no permissions. Files come through the Open panel, Finder and drag and drop.
Signatures are stored on this Mac only, in `~/Library/Application Support/app.slopapp.paper`.
Paper never asks to become the default PDF app; Settings has a button if you want it.

## Not there yet (on purpose)

- Editing the existing text or images of a PDF.
- OCR to make scans searchable (planned for 1.1).
- Certificate-based digital signatures.
- Form JavaScript (calculated totals don't update) and dynamic XFA forms.
- Stamps, watermarks, page numbers, crop, compare.

## Develop

```sh
scripts/test.sh Paper     # unit tests
scripts/run.sh Paper      # build a debug .app and open it
scripts/check.sh Paper    # the full gate: tests, release bundle, launch smoke test
swift run --package-path apps/Paper paper-fixtures /tmp/paper-test/fixtures   # test PDFs
```

Logic lives in `Sources/PaperCore` (tested). The app (`Sources/Paper`) uses AppKit's document
architecture with a `PDFView` canvas and SwiftUI for the sidebar, bars and sheets.
Test hooks: `PAPER_DATA_DIR` points the signature library somewhere else (tests use
`/tmp/paper-test`), `PAPER_APPEARANCE=light|dark` forces an appearance for screenshots, and
`PAPER_DEBUG_EVENTS=1` logs canvas events to `paper-events.log` in the temporary directory.

Design follows [`docs/design-system.md`](../../docs/design-system.md) (archetype 2e, document app).
