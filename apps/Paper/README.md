# Paper

Read, annotate and edit PDFs.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Nitro PDF Pro.

**Status:** alpha

Paper is a document app for the PDF jobs Preview makes awkward: fixing a sentence or swapping
a picture in a PDF, building a fillable form with totals that add themselves up, signing with a
certificate, redacting every occurrence of a name or number and proving it's gone, comparing two
versions, combining and splitting files, and doing all of it from the keyboard. No account, no
subscription, no network.

## What it does

- **Read**: continuous or single-page view, two pages, zoom (fit width, fit page, actual
  size), thumbnails, outline, go to page, back/forward, links, search with a results list.
- **Mark up**: highlight, underline and strike through text (five colors), text boxes (also
  for typing on flat forms), sticky notes, rectangles, ovals, lines, arrows and freehand
  drawing. Select, move, resize, recolor and delete. Everything is undoable.
- **Find and Highlight**: search, then highlight every result in one step.
- **Edit text and images** (⌘7): click a paragraph and type. Paper matches the paragraph's
  font, size, colour, alignment and line spacing, re-wraps it within its width, and when you're
  done the old text is **removed from the page** (not covered up) and the new text is real,
  searchable text. If the document's font isn't on this Mac, the editing bar says so and names
  the closest font Paper uses instead. Click a picture to move it, resize it by a corner,
  replace it with another image or delete it; **Add Image…** puts a new one on the page. Each
  edit is one undo step.
- **Crop** (⌘K): drag over the part of the page to keep, then crop this page, the selected pages
  or all pages (pages of other sizes keep the same margins). Nothing outside the crop is deleted,
  so Remove Crop brings it back.
- **Sign**: draw a signature or initials, or import a photo or scan of one (the paper is
  removed and the ink traced). Place them on any page, or click an empty signature field, and
  resize them.
- **Sign with Certificate…**: a digital signature with a certificate from your keychain (or a
  smart card the keychain can use). Pick the certificate, an optional reason and location, and
  whether it shows your handwritten signature; drag where it appears (or click an empty
  signature field). Paper writes a **new signed file** (PAdES-style CMS signature, SHA-256),
  appended to the document so earlier signatures stay valid, and checks it before saying it's
  done. Opening a signed PDF shows whether each signature is valid, whether the file changed
  after signing, and whether the certificate comes from an authority this Mac trusts
  (Inspector > Security, with the certificate viewer).
- **Compare With…** (⌥⌘K): a second window with both versions side by side, removed words
  tinted in the original and added words in the other, and a list of every difference that
  scrolls both to it (⌘↑/⌘↓ step through).
- **Recognize Text (OCR)**: makes scanned pages searchable and selectable with an invisible
  text layer. It runs on this Mac with Apple's Vision; the very first page can take up to a
  minute while macOS prepares it. **Copy Text from Page** reads a scan without changing it.
- **Fill forms**: text fields, checkboxes, radio buttons and pop-ups, with Tab between fields.
- **Make forms**: the Forms tool adds text fields, checkboxes, radio buttons (same group name =
  one choice), dropdowns and signature fields to any PDF; click for the standard size or drag to
  draw one. Name them, set a tooltip, required, read-only and multi-line in the inspector, and
  set the order Tab moves through them in the **Fields** sidebar (drag, or Order by Position).
  **Calculated fields** add up (or multiply, average, minimum, maximum) other fields, or follow a
  formula like `qty * price + shipping`, with a chosen number of decimals. Paper calculates as
  you type, and saves the rule as a standard form script, so Acrobat and other viewers that run
  form scripts calculate too. Paper also writes the form structure other apps need (fields
  registered in the document's form, radio groups, check states), which PDFKit leaves out.
- **Pages**: reorder by dragging thumbnails or with ⌥⌘↑/↓, rotate, delete, insert from a file
  or a Finder drop, insert blank pages, reverse, extract to a new document, split into files.
- **Combine Files…**: an ordered list of PDFs and images becomes one document, with an option
  to interleave front and back scans.
- **Headers & Footers…**: page numbers, Bates numbers, dates or any text in six positions.
- **Export**: a flattened copy (annotations, signatures and form entries become part of the
  page), images of the pages (PNG, JPEG, TIFF, HEIC at 72–300 dpi), a **Word document**
  (.docx: paragraphs in reading order with their fonts, sizes, bold, italic, colours and
  alignment, pictures in place, one Word page per PDF page), plain or rich text (RTF), or a
  **protected copy** with an open password and/or printing and copying restrictions.
- **Inspector** (⌥⌘I): edit the title, author, subject and keywords; see page size, PDF
  version and file size; the security panel; details of the selected annotation.
- **Share**: the document or a flattened copy, from the toolbar or File > Share.
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
| Edit text and images / Crop | ⌘7 / ⌘K |
| Finish editing text, cancel a crop or placement | Esc |
| Crop the page to the drawn area | Return |
| Compare with another version | ⌥⌘K |
| Back to Select | Esc or V |
| Delete selected annotation | ⌫ |
| Nudge selected annotation | arrows (⇧ for 10 pt) |
| Find, next, previous, use selection | ⌘F, ⌘G, ⇧⌘G, ⌘E |
| Find and Highlight / Find and Redact | ⌥⇧⌘F / ⇧⌘F |
| Remove markup from the selection | ⌥⇧⌘0 |
| Show inspector / hide editing bar | ⌥⌘I / ⇧⌘E |
| Rotate left / right | ⌘L / ⌘R |
| Delete pages | ⌘⌫ (⌫ in the thumbnails) |
| Move pages up / down | ⌥⌘↑ / ⌥⌘↓ |
| Insert from file / blank page | ⇧⌘I / ⌥⌘B |
| Extract selected pages | ⌥⌘E |
| Go to page | ⌥⌘G |
| Sidebar: hide, thumbnails, outline, notes, fields | ⌥⌘1 ⌥⌘2 ⌥⌘3 ⌥⌘4 ⌥⌘5 |
| Zoom: actual size, in, out, fit, width | ⌘0, ⌘+, ⌘−, ⌥⌘0, ⌥⌘9 |
| Copy highlights & notes as Markdown | ⌥⇧⌘C |

## Permissions and privacy

Paper needs no permissions. Files come through the Open panel, Finder and drag and drop.
Signatures are stored on this Mac only, in `~/Library/Application Support/app.slopapp.paper`.
Signing with a certificate uses the keychain: macOS may ask whether Paper can use the
certificate's private key. Paper lists certificates but never exports or copies keys, and only
offers certificates that aren't limited to code signing.
Paper never asks to become the default PDF app; Settings has a button if you want it.

## Not there yet (on purpose)

- **Editing text is per paragraph, not a page layout tool.** Edited text re-wraps within its
  paragraph's width, but nothing else on the page moves: a longer paragraph runs over what's
  below it (Paper warns you). Text on rotated pages and vertical text can't be edited (rotate
  the page upright first). Text in a font that isn't on this Mac is edited in the closest font
  Paper has, and the editing bar says which; Paper doesn't reuse fonts embedded in the PDF yet.
  The area under edited text is repainted with the colour around it, so text over a photo or
  gradient gets a flat patch.
- **Images**: Paper moves, resizes, replaces and deletes whole pictures. Cropping or adjusting a
  picture, and text drawn on top of a picture (which moves with it), are not handled.
- Form fields: list boxes, push buttons, field formats other than numbers (dates, phone numbers),
  validation scripts, and running other apps' custom form scripts (Paper keeps them; it runs
  only the calculations it understands). Dynamic XFA forms.
- Signatures: timestamps from a time-stamp server and long-term validation data (they need the
  network), signing password-protected PDFs, and cloud signing requests. A PDF with
  signatures that you edit in Paper loses them on save (the info bar says so); sign a copy.
- Compare looks at text only (not pictures or layout) and compares the whole text, not a
  side-by-side page overlay.
- Word export: columns and tables become plain paragraphs; headers, footnotes and links aren't
  rebuilt. PowerPoint and Excel export.
- Stamps and watermarks.

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
`PAPER_DEFAULTS_SUITE=<name>` keeps preferences out of the real ones, `PAPER_PASTEBOARD=<name>`
sends copies to a private pasteboard, and `PAPER_SNAPSHOT=<folder>` with
`PAPER_SNAPSHOT_FIXTURES=<fixtures folder>` (plus `PAPER_FAKE_OCR=1`) renders the document
window and sheets offscreen to PNGs in light and dark, then quits. Real-Vision OCR tests run with
`PAPER_VISION_TESTS=1 swift test --package-path apps/Paper`.
`PAPER_SNAPSHOT_ONLY=features` walks only editing, forms, crop, certificate signing and compare
(writing the files it makes and a log into the snapshot folder); with
`PAPER_SNAPSHOT_HANDSHAKE=<folder>` each state waits for an outside screenshot
(`<name>.ready` → `<name>.done`). `PAPER_SIGNING_KEYCHAIN=<path>` lists signing certificates
from that keychain file only, so tests never touch the login keychain; unit tests sign with a
key made in memory (`TestSigner`).

Design follows [`docs/design-system.md`](../../docs/design-system.md) (archetype 2e, document app).
