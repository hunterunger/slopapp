# Paper research (inspired by Nitro PDF Pro)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-03: **Nitro PDF Pro 26.4 (260400.2455)**, Setapp build, at
> /Applications/Setapp/Nitro PDF Pro.app (read-only). Also its online Mac user guide,
> App Store and Setapp listings, reviews and forum threads, and Apple Preview for contrast.
> We study how it works so we don't reinvent the wheel. We never copy its name, icons,
> artwork, wording, sounds or signature visuals.
>
> Nitro wasn't running. It was opened with a generated 3-page test PDF
> (`/tmp/paper-demo/paper-demo.pdf`: three lines of text per page, a blue rectangle, plus a
> text field, a checkbox and a dropdown on page 1). We read the home window's structure (its
> recents list held only that test file), the full main menu, every toolbar dropdown and all
> three Settings panes, then quit Nitro. No setting was changed, nothing was typed into the
> document and nothing was saved. Not explored: the floating Search, Inspector and Review Tools
> panels. They don't show up to Accessibility when the app is driven from the background (see
> "Couldn't explore"). Their behavior comes from the help docs.
>
> PDFKit behavior was checked with small Swift experiments on this Mac (**macOS 27.2**), which
> is newer than our **macOS 14** floor. Anything only seen on 27 is marked **verify on 14**.
> Sources are in `/tmp/paper-exp/scripts`, not in the repo. Outputs were checked with an
> independent extractor (Poppler `pdftotext` / `pdfimages`, from Homebrew), not only with
> PDFKit.

## The job

Someone has a PDF and needs to do something to it, other than just reading it, in the next five
minutes. Typical cases: a lease to sign and send back, a government form to fill in, a paper
to read with highlights and notes, three scans to combine into one file with the pages in
the right order, two pages to pull out for a colleague, or an account number to black out
before forwarding. Preview handles some of this, but it hides the page tools, can't redact
every occurrence of a word, can't flatten, and saves over the original without being asked.
The paid tools (Nitro, PDF Expert, Acrobat) cost $130–180 a year and come with accounts.
"Done" means the file looks right in any viewer, the edits can't be peeled off when that
matters (signatures, flattened forms, redactions), and the original is untouched unless the
person meant to change it.

**The one interaction that matters: open a PDF, pick a tool with one key, act on the page
(highlight, sign, type into a field, drag a thumbnail), and the result is saved like any Mac
document.** The second one, and the reason to pick Paper over Preview, is: **mark what's
sensitive (including "every occurrence of this text"), apply it, and get a new file in which
that content is provably gone.**

## Who and when

- Signing a contract or permission slip that arrived by email, then sending it back flattened
  so the signature can't be lifted off.
- Filling a fillable form (tax, visa, onboarding). Or typing onto a flat scanned form that has
  no fields.
- Reading and marking up a paper, spec or legal draft: highlights in a few colors, sticky notes,
  strike-throughs, an arrow and a box. Later, jumping between notes in a list.
- Fixing a scan: rotating sideways pages, deleting blanks, reordering. Then merging several
  scans into one file, or splitting a 40-page scan into separate documents.
- Redacting before sharing: an account number, a name everywhere it appears, a signature,
  a photo of an ID card.

Frequency: a few times a week for most people. Readers and reviewers use it daily. A
signing or forms session takes 1–3 minutes. A reading session can last an hour, so it should
stay out of the way. Page surgery and redaction come in bursts. They are rarer, but they're
why people pay.

## How Nitro is laid out (observed)

- **Home window on launch** (default on): a greeting, three big actions (open a file, new from
  a template, import from a scanner), and a Recents list with a list/grid toggle and a
  clear button. It's an extra window between launch and the document. Our version: skip it and
  use the system Open panel and File > Open Recent.
- **Document window** (one per document, system tabs supported):
  - **Toolbar, row 1, left to right:** sidebar toggle with a dropdown for the mode (Thumbnails,
    Table of Contents, Annotations, Attachments, Form Fields; plus Single / Facing /
    Continuous), zoom out/in, Fit Width, an editable scale field ("146%"), an editable page
    field, then four **tool groups, each a button plus a dropdown arrow**: *Drawing*
    (Scribble, Polygon Line, Rectangle, Oval, Line, Rounded Rectangle), *Highlight* (a row of 7
    color swatches + Edit Custom Colors, Underline, Cross Out, Squiggle, Remove), *Markup* (Text,
    Note, Comment, Cloud, Callout, Link, Attach Files, Sound), *Forms* (Text Field, Checkbox,
    Radio, Dropdown, List Box, Signature, Button). The button repeats the last tool used from
    that group. Right side: Review Tools (a library of reusable items), Search, Inspector,
    Compare, Get Signatures (cloud e-sign), Share.
  - **Toolbar, row 2, the "editing bar":** mode buttons (Edit, Select Text, Pointer, Rectangle
    Selection, Measure, Hand), then context formatting controls: font and size, bold, italic,
    underline, text color, four alignments, stroke color, fill bucket, line style, stroke width.
    Mostly disabled until something is selected.
  - **Sidebar:** page thumbnails with the page number under each, and a size slider at the
    bottom. The current page has a darker card behind it.
  - **Canvas:** continuous vertical scroll, pages on a dark backdrop. A small "1 / 3" page
    badge sits in the corner of the current page.
- **Floating panels:** Review Tools / Library (⌘Y: built-in shapes, saved custom items such as
  signature scribbles and images, proofreading marks, stamps including dynamic name/date
  stamps), Inspector (⌥⌘I: tabs for alignment, form element properties, document info and
  permissions), Search (a results list in page order, optionally including comments),
  Magnifier, JavaScript console, Scripts.
- **Page operations are scattered.** Rotate is in View, insert blank page and crop are in Edit,
  insert file is in File, and delete/extract/reorder happen on thumbnails (context menu and
  drag). There is no Pages menu. Splitting is an AppleScript in a Scripts menu. This
  scattering is a lesson for us.

## PDFKit platform facts (experiments on macOS 27.2)

These decide what v1 can promise. Each was checked with `pdftotext`/`pdfimages`, not only by
reopening in PDFKit.

| # | Question | Result | Consequence for us |
|---|---|---|---|
| P1 | Does a **`Redact`-subtype annotation** (`PDFAnnotation(bounds:forType: PDFAnnotationSubtype(rawValue: "Redact"))`) remove content when the document is written? | **Yes, on every write**, even a plain `dataRepresentation()` with no options. It removed **only the glyphs inside the box** ("Account number ▮▮▮ belongs" kept the rest of the line; a box over half a word removed exactly those letters). It also removed **invisible text** (render mode 3, like an OCR layer), and **zeroed the image pixels** inside the box in the embedded image itself (checked with `pdfimages`). Vector fills under it were removed too. | True redaction is possible on PDFKit without our own content-stream editor. It's **undocumented**, so **verify on 14**, and always verify the output (P5). |
| P2 | The `PDFMarkupType.redact` markup (a Highlight annotation with `markupType = .redact`) | **Fake.** It draws a black blob and the text stays extractable. | Never use it. A unit test should guard this. |
| P3 | What does an applied `Redact` annotation look like? | Kept as an annotation, it draws a **grey box with an X** (the "marked for redaction" look). With `.burnInAnnotationsOption` it's baked in looking like that. A black `Square` annotation added in the same pass **is itself redacted away** (removal runs after burn-in). | **Two passes**: (1) write with `Redact` annotations, which removes the content; (2) reopen, delete the leftover `Redact` annotations, add black filled squares, write with burn-in. Result: solid black boxes, no annotations left, nothing extractable. Verified. |
| P4 | Danger: a PDF from another app that already contains **unapplied `Redact` annotations** | PDFKit applies them on our next save. | On open, detect `Redact` annotations and ask before any save. Also: **our own redaction marks must not be `Redact` annotations until the user applies them**, or autosave would apply them early to the original. Keep marks in our model (or as a plain annotation tagged with a private key) until Apply. |
| P5 | How to verify removal | Reopen the written data with a fresh `PDFDocument`. For each mark: `page.selection(for: rect)?.string` is empty, and `findString` finds none of the redacted terms. Plus `pdftotext` in the walkthrough. | The Apply flow verifies before it reports success. If verification fails, fall back to P6 for the affected pages and verify again. If that also fails, don't write. |
| P6 | Fallback: rasterize the page | Render the page at 300 dpi, fill the boxes black, replace it with `PDFPage(image:options:[.mediaBox:])` (macOS 13+). The page has no text at all afterwards. Verified. | A safe fallback, but the page loses selectable text and its size grows (~240 KB per letter page at 300 dpi). Only use it per page, when P1 fails. |
| P7 | `.burnInAnnotationsOption` (macOS 13+) for **flatten** | Highlights, ink, free text, form values (text field, checkbox) were baked in. 0 annotations remain, typed form text is now page text. | Flatten export is one write call. The checkbox "on" appearance looked unchecked in one test: **check widget appearances** in the walkthrough. |
| P8 | `.saveTextFromOCROption` (macOS 13+) | **Did nothing** in a command-line test (instant, no text added) on a synthetic image-only page. | Don't rely on it for OCR. Re-test inside a real app run loop before writing it off. |
| P9 | Vision `VNRecognizeTextRequest` / `RecognizeTextRequest` (macOS 15) on a 1700×2200 page render | Accurate. **~30 s on the first call in each new process** (model load, unsigned CLI), then **0.07 s/page** accurate, 0.03 s fast. | OCR is feasible. Making a searchable PDF means drawing an invisible text layer ourselves (a few hundred lines). Show progress, and expect a slow first page. |
| P10 | Forms: create and fill widgets, persist | `widgetStringValue`, `buttonWidgetState` and choice values save and reload. | Form filling is mostly free with `PDFView`. |
| P11 | Page ops | `exchangePage`, `insert(_:at:)` with `page.copy()` from another document, `removePage`, `rotation` all persist. `outlineRoot` is nil for a document with no outline. | Reorder, rotate, delete, insert, merge and extract are cheap. Merging outlines is up to us (later). |

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else v1.1),
**later**, **skip** (with the reason). "Nitro" describes how the original does it.

### Opening and reading

| # | Feature | How Nitro does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Open PDFs | ⌘O, Open Recent, drag onto the Dock icon, Finder Open With. Also opens images and Word files (it converts them). | **must** | Document-based app, registered for `com.adobe.pdf` with rank *Alternate*, so it shows in Open With but never takes over from Preview on its own. |
| 2 | Home / welcome window | Greeting, three actions, a recents list/grid. On by default. | skip | Extra step on launch. The empty state is the system Open panel plus File > Open Recent. |
| 3 | Page layout | Single page, Facing pages, Continuous, cover page, right-to-left. Set from View and the sidebar dropdown. | **must** (continuous, single) / should (two-up, cover) | `PDFView.displayMode` and `displaysAsBook` make these cheap. |
| 4 | Zoom | Actual size ⌘0, zoom in ⌘+ / out ⌘−, fit ⌥⌘0, fit width ⌥⌘9, an editable % field. Default: fit page. | **must** | Pinch and smart zoom come with `PDFView`. |
| 5 | Thumbnails sidebar | Sidebar mode with a size slider. The current page is highlighted. | **must** | Our own grid (not `PDFThumbnailView`), so we can multi-select, drag-reorder and use a context menu (see 50–58). |
| 6 | Outline sidebar | "Table of Contents" mode. Bookmarks on top, expand/collapse. Editing via Edit > Table of Contents (add entry, child, promote/demote). | **must** (read) / later (edit) | `PDFOutline`. Hide the tab when the document has no outline. |
| 7 | Annotations sidebar | A list of every markup, filterable by type. Click to jump, double-click to edit. | should | Cheap and useful for reviewers. Pairs with 40. |
| 8 | Attachments sidebar | List, add, extract, preview embedded files | later | Rare. |
| 9 | Form fields sidebar | A field list with drag-to-set tab order | skip | Form-authoring feature. |
| 10 | Search | ⌘F opens a panel with results in page order (optionally comments too). ⌘G / ⇧⌘G next/previous. ⌘E use selection, ⌘J jump to selection. | **must** | A sidebar results list with page number and context, matches highlighted on the page. If the document has no text layer, show one line saying so (the scan case) instead of "No results". |
| 11 | Go to page | ⌥⌘G, the toolbar page field, first/last/next/previous, Back ⌘[ / Forward ⌘] | **must** | `PDFView` has history. |
| 12 | Remember last page per document | General setting, on | should | Store per file bookmark in UserDefaults (capped). |
| 13 | Links | Clickable. Optional detection of emails/phone numbers. "Highlight Links" toggle. | **must** (follow) / skip (detect) | `PDFView` follows links. External URLs open in the default browser. |
| 14 | Tabs, multiple windows | Window tabs, Merge All Windows | should | Free with document windows. |
| 15 | Split view of one document | Window > Split vertically/horizontally | later | Handy for long specs. Not v1. |
| 16 | Compare two documents | ⌘K, side by side with differences | later | A big feature on its own. |
| 17 | Magnifier window | ⌥⌘M | skip | System zoom and pinch already cover it. |
| 18 | Dark page appearance | Not seen in Nitro (Preview has it on macOS 26) | later | Could be a simple inverted render. Not v1. |
| 19 | Text-to-speech | Edit > Speech | skip | System Services / Spoken Content cover it. |
| 20 | Full screen / slideshow | Enter Full Screen | should | Free. |
| 21 | Copy text, select all | Select Text tool, ⌘C | **must** | `PDFView`. |
| 22 | Print | ⌘P, page setup, print notes / annotation summary / stamps only | **must** (print) / later (summaries) | `PDFView.print(with:autoRotate:)`. |
| 23 | Show page numbers / labels | View > Page Numbers. Edit > Page Labels. | skip | Thumbnails already show numbers. |

### Annotating

| # | Feature | How Nitro does it | Priority | Notes for us |
|---|---|---|---|---|
| 24 | Highlight text | ⌘5 tool. 7 swatches + 3 custom colors (setting). Works on the selection or as a sticky tool. | **must** | 5 system-ish colors (yellow, green, blue, pink, purple). Applies to the current selection, or stays as a tool to drag across text. |
| 25 | Underline, strike-through | Highlight dropdown | **must** | `.underline`, `.strikeOut`. |
| 26 | Squiggle | ⌥⇧⌘5 | later | PDFKit has no squiggly markup type. Needs a custom subtype. |
| 27 | Remove markup from the selection | ⌥⇧⌘0 | should | Removes markup annotations that intersect the selection. |
| 28 | Text box (typed text on the page) | Text tool ⌘6. Default font Helvetica 12 (setting). | **must** | `.freeText`. Doubles as "type on a flat form". Font size and color in a small inspector. |
| 29 | Sticky note | Add Note ⌘8, edit note ⌘', delete note | **must** | `.text` with a popup. Edit in a popover, not a floating yellow window. |
| 30 | Comment box, cloud, callout | Markup dropdown | later | Callout (box + arrow) is the most useful of the three. |
| 31 | Shapes: rectangle, oval, line, arrow | Drawing dropdown (no dedicated arrow: line + line-end style) | **must** | `.square`, `.circle`, `.line` with end styles. Stroke color, fill, width. Shift constrains. |
| 32 | Polygon, rounded rectangle | Drawing dropdown | later | |
| 33 | Freehand drawing | Scribble ⌘7 | **must** | `.ink` from smoothed `NSBezierPath`. Pressure isn't needed. |
| 34 | Select, move, resize, recolor, delete annotations | Pointer tool + editing bar (stroke, fill, line style/width, font) | **must** | One small contextual inspector (popover or a strip under the toolbar). Arrow keys nudge 1 pt (Nitro's default increment), ⇧ 10 pt. |
| 35 | Annotation author | "Add name to annotations" (on). Name defaults to the Mac user's full name. | should | Use `NSFullUserName()`, with an override in Settings. |
| 36 | Stamps (Approved, Draft, Sign Here, dynamic name/date) | Library > Stamps, custom stamps | later | A date stamp is covered by 44. |
| 37 | Links, file attachments, sound notes | Markup dropdown | skip | Rare. Sound notes are obsolete in most viewers. |
| 38 | Arrange: z-order, lock, grid, snap, guides | Arrange menu, grid every 18 pt, guides on | skip | That's a layout tool, not a PDF annotator. |
| 39 | Measure tool | Tools > Measurement Tool | later | Niche (architecture/print). |
| 40 | Export highlights and notes | Print annotation summary | should | "Copy Highlights & Notes" as Markdown (page number, quoted text, note). A reader feature Preview lacks. |
| 41 | Proofreading marks library | Library | skip | Niche. |
| 42 | Watermark; headers/footers/page numbers; Bates numbering; line numbers | Edit menu | later | "Add Page Numbers" is the most requested of these. v1.1 candidate. |

### Signing

| # | Feature | How Nitro does it | Priority | Notes for us |
|---|---|---|---|---|
| 43 | Create a signature | Draw it with Scribble and save it to the Library. Or import a scan and run "Make Transparent Image" (eyedropper + tolerance). | **must** (draw) / should (image) | A signature sheet: draw with trackpad or mouse on a baseline, Clear / Done. Image import: drop a photo and we knock out the light background (luminance threshold + crop to ink). Stored locally in Application Support, never synced by us. |
| 44 | Place a signature, initials, date | Drag from the Library. Resize with Shift to keep proportions. | **must** (signature) / should (initials, today's date as text) | Toolbar Sign menu lists saved signatures (up to ~5) + "New Signature…". Click to place, drag to resize. It's an ink or stamp annotation, so it stays editable until flattened. |
| 45 | Certificate-based digital signatures, validation | Digital ID signing and signature validation | skip | Out of scope (PKI, PAdES). |
| 46 | Cloud e-sign request ("Get Signatures") | Nitro Sign account | skip | Needs an account and a server. |
| 47 | Signature form fields | Forms dropdown | later | |

### Forms

| # | Feature | How Nitro does it | Priority | Notes for us |
|---|---|---|---|---|
| 48 | Fill interactive (AcroForm) forms | Click a field, type, Tab to the next, click checkboxes/radios. JavaScript calculations on by default. | **must** | `PDFView` does it. We add: a "Highlight Fields" toggle and an info bar "This form has 12 fields" with a Next Field button. |
| 49 | Fill flat (non-interactive) forms | Use the Text tool to type anywhere | **must** | Covered by 28. On scans, the text box snaps its baseline to the click point. |
| 50 | Reset form | Edit > Reset Form… | should | Confirm, undoable. |
| 51 | Detect fields automatically / create fields | "Create Form Fields for Page/Document", the Forms tools | later | Vision rectangle detection could do this later. |
| 52 | AutoFill from Contacts | System AutoFill menu (Preview does this well on macOS 14.2+) | later | Needs the Contacts permission. |
| 53 | Run form JavaScript | Setting, on | skip | PDFKit doesn't run it, and it's a security surface. Note it in the README. |
| 54 | Export/import form data | Extract Form Data (needs an account) | later | |

### Pages and documents

| # | Feature | How Nitro does it | Priority | Notes for us |
|---|---|---|---|---|
| 55 | Reorder pages | Drag thumbnails in the sidebar | **must** | Multi-select + drag, and also ⌥⌘↑/↓ "Move Page Up/Down" so it works without a mouse. |
| 56 | Rotate pages | ⌘R right / ⇧⌘R left (View menu) | **must** | Applies to the selected thumbnails, otherwise the current page. We use ⌘L / ⌘R like Preview. |
| 57 | Delete pages | Thumbnail context menu, Delete | **must** | ⌫ on selected thumbnails, undoable. |
| 58 | Insert pages from a file | File > Insert… ⇧⌘I, after the current page. Or drag a PDF/image from Finder onto thumbnails at the drop point. | **must** | Both. Images become pages sized to fit Letter/A4 by locale. |
| 59 | Combine several files into one | Drag thumbnails between windows, or the "Combine PDFs" AppleScript | **must** | **File > Combine Files…**: an ordered list sheet (add, drag to reorder, remove), then Combine creates a new untitled document. Preview has nothing like it. |
| 60 | Extract pages to a new file | Thumbnail context menu | **must** | "Extract Selected Pages…" creates a new untitled document. Dragging thumbnails to Finder makes a PDF file there (should). |
| 61 | Split into files | AppleScript: one file per page | should | "Split Document…": every page, every N pages, or at each top-level outline entry. Writes into a chosen folder as `name 1–4.pdf`… |
| 62 | Interleave odd/even scans | AppleScript "Merge Every Other" | should | Tiny code, solves a real duplex-scanning pain. Option in Combine: "Interleave (front and back scans)", with the second file reversed. |
| 63 | Reverse page order | Article in the guide | should | Pages > Reverse Order. |
| 64 | Insert blank page | ⌥⌘B, ⌥⇧⌘B again | should | Same size as the current page. |
| 65 | Crop pages | Crop Page/Document to Selection | later | Needs a crop-box UI. |
| 66 | Images and scans to PDF | Opens images, Import from Scanner, Import from iPhone | should (images) / later (scanner, iPhone) | Opening a JPEG/PNG/HEIC makes an untitled PDF. AppKit's Import from iPhone (Continuity Camera) menu item is nearly free: v1.1. |
| 67 | New blank document, templates | ⌘N From Stationery, Blank, Portfolio | skip | Not our job. |
| 68 | Create from HTML/Office | File > New > From HTML; opens .docx | skip | Out of scope. |
| 69 | Portfolios | | skip | Rare, poorly supported elsewhere. |

### Saving, exporting, protecting

| # | Feature | How Nitro does it | Priority | Notes for us |
|---|---|---|---|---|
| 70 | Save, autosave, versions, revert | Autosave and versions on (setting), Revert To, Duplicate ⇧⌘S, Rename, Move To | **must** | Standard document model. See Open question 1 about autosave in place. |
| 71 | Undo/redo everything | ⌘Z / ⇧⌘Z | **must** | Every annotation, page and form action is undoable, including page moves. |
| 72 | Export flattened PDF | File > Export > Flattened PDF… and Mail Document > Flattened | **must** | "Export Flattened Copy…": annotations, signatures and form values are baked in (P7). Never in place. |
| 73 | Export pages as images | Export JPEG/PNG/TIFF | should | Per page, chosen DPI, into a folder. |
| 74 | Export text | Plain text / Rich text | should (plain text) | `PDFDocument.string`. |
| 75 | Export to Word/Excel/PowerPoint | Export menu | skip | Out of scope (conversion engine). |
| 76 | PDF/A export and lock | 8 PDF/A variants. Lock PDF/A on open (on). | skip | PDFKit can't produce conformant PDF/A. We do warn when saving over one (Edge cases). |
| 77 | Reduce file size | Create Optimized PDF… | later | Squish/PDF Squeezer territory. PDFKit has `.optimizeImagesForScreenOption` / `.saveImagesAsJPEGOption` (13.4+) if we add a quick option later. |
| 78 | Open password-protected PDFs | File > Enter Password… | **must** | Unlock sheet. Respect owner permissions (no annotate/print when disallowed) and explain why. |
| 79 | Add password / permissions | Inspector > Document Permissions ⌥⌘4 | should | PDFKit write options (user/owner password, `PDFAccessPermissions` on 12+). In the Export sheet. |
| 80 | Document info / metadata | Inspector > Document Info ⌥⌘3 | should | View/edit title, author, subject, keywords. "Remove metadata" is also part of redaction (85). |
| 81 | Share / mail | Share menu, Mail Document (regular / flattened) | should | `ShareLink`/`NSSharingServicePicker`, with an option to share a flattened copy. |
| 82 | Cloud upload, iCloud integration, accounts | Account menu, Send for Signature, Upload | skip | Files in iCloud Drive just work as files. No accounts. |

### Redaction

| # | Feature | How Nitro does it | Priority | Notes for us |
|---|---|---|---|---|
| 83 | Redact a text selection or a drawn area | Select text or draw a rectangle, then Format > Redact Text > **Block** (black) or **Erase** (blank). Applied immediately. | **must** | Our flow separates *mark* from *apply* (see Flow 6). Marks are reversible, autosave can't apply them, and Apply writes a **new file** by default. |
| 84 | Find and redact | ⇧⌘F: search, then redact the results | **must** | Search terms, case and whole-word options. A list of hits with checkboxes (all on), each with page and context. "Mark Selected". This is the headline feature Preview lacks. |
| 85 | Scrub what search can't see | Nitro's guide says Find and Redact **doesn't** touch metadata. You clear it by hand in the Inspector. | **must** | Apply also: removes annotations and form fields that overlap a mark, strips redacted terms from annotation contents and outline titles, and offers "Remove document metadata" (on by default). |
| 86 | Verify the result | Not offered | **must** | P5. Report: "12 areas on 5 pages removed. Verified: no redacted text remains." On failure, rasterize that page (P6) and say so. |
| 87 | Erase style (white box) | Format > Redact Text – Erase | later | Same machinery, white fill. |
| 88 | Pattern redaction (emails, phone numbers, card numbers) / AI "smart redact" | Smart Redact (AI, account) | later (patterns) / skip (AI) | Regex presets are a natural v1.1 on top of 84. |

### OCR

| # | Feature | How Nitro does it | Priority | Notes for us |
|---|---|---|---|---|
| 89 | OCR a page/document into a searchable text layer | Edit > OCR (page/document). Prompts when opening a scanned document (on). OCRs on text selection over a scan (on). About 20 languages, extra ones downloadable. MRC compression "Better Quality". | later (v1.1) | Vision is accurate and fast once warm (P9), but writing the invisible text layer is our own code, and `.saveTextFromOCROption` didn't work in our test (P8). Spike first. See Open question 3. |
| 90 | Copy text from a scan without saving OCR | (Nitro does it by OCRing on selection) | should | Cheap with Vision: "Copy Text from Page" on an image-only page puts recognized text on the clipboard. Live Text in the canvas would be nicer but isn't PDFView-native. |
| 91 | Rotate & deskew | OCR setting (on), Edit > OCR > Rotate & Deskew | later | |
| 92 | Clear OCR layer, view OCR layer | ⌃⌘O, ⇧⌘O | skip | Power-user forensics. |
| 93 | Batch OCR many files | File > OCR Files… | skip | Not our job in v1. |

### Editing content and other

| # | Feature | How Nitro does it | Priority | Notes for us |
|---|---|---|---|---|
| 94 | Edit existing text, fonts, find and replace | Edit tool ⌘1, Correct Text, Find and Replace ⌥⌘F, Format menu | skip | Out of scope. PDFKit can't edit content streams, and reviewers say even Nitro's version is weak. |
| 95 | Edit/crop/adjust existing images, make transparent | Edit menu | skip | Out of scope (except our signature background knockout). |
| 96 | Add images to a page | Drag an image in | later | Comes almost free after image signatures. |
| 97 | Inspector (object properties) | ⌥⌘I | — | Folded into 34 and 80. |
| 98 | Scripts menu, AppleScript, JavaScript console | Scripts menu, AppleScript dictionary | skip | App Intents (Combine, Extract Pages, Flatten) for Shortcuts are **later**. |
| 99 | Knowledge Assistant (AI help chat), table/form extraction (AI, account) | Help menu, File > Extract | skip | Network, accounts. |
| 100 | Update checks, beta channel, anonymous profile | Update pane (not in the Setapp build) | skip | Slopapp release pipeline. |
| 101 | Window tiling submenu | Window > Move & Resize (system) | — | Free from macOS. |

## Where v1 must beat Preview (and where it doesn't try)

Preview already reads, highlights, adds notes, shapes and text boxes, signs (trackpad/camera),
fills forms with AutoFill, reorders/rotates/deletes pages by dragging thumbnails, and has a
one-box-at-a-time Redact tool (since Big Sur). Duplicating that adds nothing. v1 has to be
clearly better at a few everyday jobs:

| Job | Preview today | Paper v1 |
|---|---|---|
| **Redact** | One drawn box at a time. No search. No verification. Independent tests found it leaves hidden or off-page text and edge fragments behind. Metadata isn't touched. | Mark by search (every occurrence), text selection or area. Review the list. Apply to a **new file**. Overlapping notes, fields and metadata are scrubbed. **Verified** with a report. |
| **Combine and split** | Possible only by dragging thumbnails between windows. Easy to drop pages in the wrong document. No split. | Combine Files… (ordered list, interleave option). Extract selected pages. Split by every N pages or by outline. Drag thumbnails to Finder. |
| **Flatten** | No command. The workaround is Print > Save as PDF. | Export Flattened Copy… and Share Flattened. Annotations, signatures and form values are baked in. |
| **Tools from the keyboard** | Markup toolbar, mostly mouse | ⌘1–⌘9 pick tools, Esc returns to Select. Every page action is in a **Pages menu** with shortcuts. |
| **Saving that doesn't surprise** | Edits land in the original automatically. Destructive results (redaction) also go into the original. | Normal document saving for annotations (see Open question 1). Redaction and flattening **always** create a new file unless the person explicitly chooses to replace. |
| **Reading notes out** | Highlights & Notes sidebar, no export | Annotations list + Copy Highlights & Notes as Markdown (should) |

Not trying to beat Preview at: image viewing, Quartz filters, AutoFill from Contacts, camera
or iPhone signatures, dark page mode. Those are later or never.

## Key flows

### Flow 1: open and read
1. Double-click a PDF where Paper is the default, or use Open With > Paper, drag onto the Dock
   icon, or ⌘O in Paper. Launching Paper with no document shows the Open panel (standard
   document-app behavior). Recent files are in File > Open Recent.
2. The window opens at the last size, **fit width** (Nitro defaults to fit page. Fit width
   reads better on wide Mac screens. A setting). The sidebar shows Thumbnails. It reopens at
   the last page viewed for this file.
3. Scroll is continuous. The toolbar shows the page "3 of 40" (editable) and zoom. ⌥⌘G focuses
   the page field.
4. ⌘F focuses the search field in the toolbar. Return searches. Results appear in the sidebar
   as rows (page number + a line of context). ⌘G / ⇧⌘G step through them. Matches are
   highlighted on the page. Esc clears.
5. The sidebar switches with ⌥⌘1 (hide), ⌥⌘2 Thumbnails, ⌥⌘3 Outline, ⌥⌘4 Annotations
   (Preview's numbering, so Mac users' muscle memory works).

### Flow 2: highlight and annotate
1. With the Select tool (default), select text. A small floating bar appears over the
   selection: 5 highlight colors, underline, strike, note, copy. One click applies. This
   mirrors how people actually work: select, then decide.
2. Or pick the Highlight tool (⌘2, or the toolbar). Every drag across text highlights it until
   Esc. The color choice is remembered.
3. ⌘4 Text box: click to place, type, Esc or a click outside ends editing. ⌘5 Note: click to
   drop, type in a popover.
4. ⌘6 Shapes (the dropdown picks rectangle, oval, line, arrow). ⌘3 Draw (freehand).
5. Clicking an annotation with the Select tool selects it: handles, a contextual style strip
   (color, fill, width, font size), ⌫ deletes, arrows nudge. Everything is undoable.
6. The document shows as edited. It's saved by autosave/⌘S (Open question 1).

### Flow 3: sign
1. Toolbar **Sign** (⌘8 opens its menu). The first time, the menu has only "New Signature…".
2. The sheet has two tabs. **Draw**: a wide canvas with a baseline, draw with trackpad or
   mouse, Clear, Done. **Image**: drop or choose a photo of a signature. We remove the light
   background and crop to the ink, with a preview and a threshold slider. Optional "Initials"
   kind.
3. Done saves it to the local library and returns to the page with the signature under the
   pointer. Click to place, drag the corner to resize (aspect locked), drag to move.
4. "Today's Date" (should) in the same menu places a text box with the localized date.
5. Sharing: File > Share > Flattened Copy, or File > Export Flattened Copy…, so the
   signature can't be lifted.

### Flow 4: fill a form
1. Open the PDF. If it has interactive fields, a slim info bar says "This document has 14 form
   fields" with **Highlight Fields** and **Next Field** (Tab works too).
2. Type into fields. Checkboxes, radios and dropdowns work as PDFKit renders them.
3. If there are no fields (a scan), the info bar doesn't appear. The Text tool (⌘4) types
   anywhere, and the font size defaults to 11 pt so it fits typical form lines.
4. Save. Or Export Flattened Copy… for the version you send.

### Flow 5: page surgery (reorder, rotate, delete, insert, combine, extract, split)
1. Thumbnails sidebar. Click, ⇧-click and ⌘-click select pages. ⌘A selects all when the sidebar
   has focus.
2. Drag to reorder (an insertion line shows where they'll land), or ⌥⌘↑/↓ to move them.
3. ⌘L / ⌘R rotate the selection. ⌫ deletes it (undoable).
4. Insert: drag a PDF or image from Finder onto the sidebar at the drop line, or Pages >
   Insert from File… (⇧⌘I) inserts after the current page.
5. **Combine Files…** (File menu, also the empty-launch Open panel's accessory): a sheet with an
   ordered list of files (Add…, drag in from Finder, drag to reorder, ⌫ to remove), an
   "Interleave pages" checkbox for front/back scans, then **Combine**. A new untitled document
   opens.
6. **Extract Selected Pages…** (⌥⌘E): a new untitled document with copies of those pages.
   The original is unchanged. Dragging thumbnails to Finder writes a PDF there.
7. **Split Document…**: every page / every N pages / at top-level outline entries. Choose a
   folder. Files are named `<name> 1.pdf`… or by outline title. Show in Finder when done.

### Flow 6: redact
1. **Tools > Redact** (⌘9). With the tool active, a drag over text marks those words and a drag
   in empty space marks a rectangle (images, signatures). Marks show as a red outline with a
   translucent hatch, clearly "pending", and can be selected and deleted like annotations.
2. **Find and Redact…** (⇧⌘F): a sidebar panel with a search field (case-sensitive and
   whole-word options). Results come back as a checklist with page and context. **Mark All** /
   **Mark Selected**. Marks appear on every hit.
3. The window shows "7 marks on 3 pages · Apply Redactions…" in an info bar. Saving the
   document keeps the marks pending and the content intact (P4: we don't store them as
   `Redact` annotations).
4. **Apply Redactions…** opens a sheet: what will happen in one sentence ("Marked text and
   images are permanently removed and replaced with black boxes"), a checkbox "Remove
   document metadata (title, author, keywords)" (on), and a destination: **Save as New File**
   (default, named `<name> (redacted).pdf`) or Replace Original (a second confirmation, since
   it can't be undone).
5. Apply runs off the main thread. Pass 1 writes `Redact` annotations, pass 2 draws black boxes
   and burns them in. It also removes overlapping annotations and widgets, scrubs terms from
   notes and outline titles, and clears metadata if chosen.
6. **Verify** (P5) on the written data. On success: a sheet saying "Removed 7 areas on 3 pages.
   Checked: none of the redacted text can be found in the new file." with **Open** and **Show in
   Finder**. If a page fails verification, it's rasterized (P6) and the report says "Page 4 was
   converted to an image to make sure the text is gone; its text can no longer be selected."
   If that also fails: an error, and nothing is written.

### Flow 7: export
- **Export Flattened Copy…** (⌥⇧⌘S is taken by Save As, so this is in File > Export with no
  default shortcut).
- **Export as Images…**: format (PNG/JPEG/HEIC), resolution (72/150/300 dpi), pages (all /
  selection). Writes into a folder.
- **Export Text…** (should): plain `.txt`.
- **Password** (should): in the standard Save/Export panel accessory, "Require password to
  open", plus "Allow printing/copying" checkboxes.

### Flow 8: first run
1. No onboarding, no welcome window. First launch shows the Open panel, like TextEdit.
2. No permission prompts, ever, for core features (see Permissions).
3. Paper does **not** ask to become the default PDF app. Settings > General has a "Make Paper
   the default PDF app" button that calls `NSWorkspace.setDefaultApplication` (macOS 12+)
   when the person chooses to.

## Settings inventory

Nitro's panes (values seen on this Mac; they look like factory defaults but may not be):

| Setting | Default seen | Options | Keep? |
|---|---|---|---|
| Define 100% scale as | 1 point = 1 screen pixel | or size on screen = size on printout | skip (PDFView's default is fine) |
| Initial window size | Screen height | page height, screen height, screen width | skip (remember the last size) |
| Initial sidebar mode | Thumbnails | hidden, thumbnails, TOC, annotations, attachments, form fields | skip (remember the last mode) |
| Default view | Single page | single, facing | skip (View menu, remembered) |
| Default zoom | Fit to Page | 100%, 150%, fit page, fit width | **keep** ("Open documents at": Fit Width / Fit Page / Actual Size) |
| Remember last page viewed | on | | **keep** (on) |
| Enable autosave and versions | on | | depends on Open question 1 |
| Show Home Screen on launch | on | | skip |
| Lock PDF/A documents when opened | on | | skip (warn instead) |
| Enable JavaScript | on | | skip (never run) |
| Enable clicking on detected links | on | | skip |
| Restore all warning alerts (button) | | | keep if we add "don't ask again" anywhere |
| Default font for text tools | Helvetica 12 | font panel | **keep** as "Text box font size" (system font) |
| Keyboard increment | 1 pt | | skip (1 pt, ⇧ = 10 pt) |
| Gridline every / units / show guides | 18 pt / points / on | | skip |
| Automatically switch selection tools | on | | skip (always smart: text under the pointer selects text, otherwise marquee) |
| Keep tools selected after use | off (double-click to lock) | | **keep the behavior**, not the setting: tools stay active until Esc (Open question 4) |
| Lock images | Large enough to fill the page | always, never | skip |
| Custom highlight colors | 3 wells | colors | later |
| Add name to annotations / Name | on / Mac user's full name | | **keep** ("Author name for notes", default `NSFullUserName()`) |
| Disable missing font warning | off | | skip |
| OCR: prompt on scanned docs, OCR on selection, languages, sounds, deskew, MRC level | on / on / English / sounds / on / Better Quality | | later (with OCR) |

Ours (SlopSettings, 480 pt, grouped form): **General**: Open documents at (Fit Width),
Reopen at last page (on), Author name for notes, Make Paper the default PDF app (button).
**About**. Nothing else in v1.

## Menus and shortcuts

Nitro's main menu (observed, abridged to what's relevant):

- **App**: About, Settings ⌘, , Account (Log In), Services, Hide, Quit.
- **File**: New (From Selection ⇧⌘N, From Stationery ⌘N, Blank, Portfolio, From HTML), Open ⌘O,
  Open Recent, Close ⌘W, Close All ⌥⌘W, Save ⌘S, Save As ⌥⇧⌘S, Duplicate ⇧⌘S, Rename, Move To,
  Create Optimized PDF, Export (Word, PowerPoint, Excel, JPEG, PNG, TIFF, Rich Text, Plain
  Text, Flattened PDF, PDF/A ×8), Send for Signature, Revert To, Enter Password…, Mail
  Document (Regular / Flattened), Insert… ⇧⌘I, Import from Scanner, Import from device, Share,
  OCR Files…, Page Setup ⇧⌘P, Print ⌘P.
- **Edit**: Undo/Redo, clipboard, Select All, Edit Note ⌘', Delete Note, Find (Find ⌘F, Find and
  Replace ⌥⌘F, **Find and Redact ⇧⌘F**, Find and Highlight ⌥⇧⌘F, Next ⌘G, Previous ⇧⌘G, Use
  Selection ⌘E, Jump to Selection ⌘J), Insert Blank Page ⌥⌘B / Again ⌥⇧⌘B, Crop Page/Document
  to Selection, Create Links from URLs, Headers/Footers/Page Numbers, Page Labels, Line
  Numbers, OCR (page, document, clear layer ⌃⌘O / ⌃⌥⌘O, deskew), Create Form Fields, Reset
  Form, Attachments, Portfolio, Table of Contents (add ⇧⌘A, child, promote/demote, expand),
  Bookmarks, Watermark, image tools (Make Transparent, Crop, Adjust, Resample, Deskew), Wrap
  Text, Speech, AutoFill.
- **View**: tab bar, Single/Facing/Continuous, Hide Editing Bar ⇧⌘E, OCR Layer ⇧⌘O, Compare
  Documents ⌘K, Actual Size ⌘0, Zoom In ⌘+, Zoom Out ⌘−, Zoom to Fit ⌥⌘0, Zoom to Width ⌥⌘9,
  Highlight Links, Highlight Form Fields, Page Numbers, Right-to-Left, Start with Cover,
  Rotate Left ⇧⌘R / Right ⌘R, Hide Sidebar ⇧⌘D + sidebar modes, Hide Toolbar ⇧⌘B, Customize
  Toolbar, Full Screen.
- **Format**: Font (⌘T, ⌘B/I/U, sizes, kern, ligature, baseline, copy/paste style ⌥⌘C/⌥⌘V),
  Text (alignment, ruler), Highlight (swatches, custom colors, Underline, Cross Out, Squiggle,
  Remove ⌥⇧⌘0, **Redact Text – Block ⌃⌥⇧⌘B**, Redact Text – Erase), Show Colors ⇧⌘C.
- **Go**: next/previous/first/last page, Go to Page ⌥⌘G, in split view, Back ⌘[, Forward ⌘].
- **Tools**: Edit ⌘1, Select Text ⌘2, Select ⌘3, Hand ⌘4, Rectangle Selection, Measurement,
  Highlight ⌘5, Text ⌘6, Scribble ⌘7, Note ⌘8, Comment ⌘9, Cloud, Link, Attach, Sound,
  Polygon, Rectangle, Oval, Line, Rounded Rectangle, Callout, the 7 form field tools.
- **Arrange**: z-order, Lock ⌘L, Unlock All ⇧⌘L, snap/grid, tab order.
- **Window**: system tiling, Split, tabs, Review Tools ⌘Y, JavaScript Console ⌥⌘Y, Scripts ⌥⌘J,
  Inspector ⌥⌘I, Magnifier ⌥⌘M, Alignment ⌥⌘1, Form Element Properties ⌥⌘2, Document Info
  ⌥⌘3, Document Permissions ⌥⌘4.
- **Help**: Help, Knowledge Assistant ⌃⌘/, home page, support, iOS app, legal.
- Plus a **Scripts** menu (script icon) with "Populate Scripts Menu" and "Open Scripts Folder".

**Paper's proposed menus** (standard items omitted; everything below has a toolbar or context
menu twin):

- **File**: Open ⌘O, Open Recent, **Combine Files…** (no shortcut), Close ⌘W, Save ⌘S, Duplicate ⇧⌘S, Rename, Move To, Revert To, **Export
  Flattened Copy…**, **Export as Images…**, Export Text…, Share (Original / Flattened Copy),
  Print ⌘P.
- **Edit**: Undo/Redo, Cut/Copy/Paste/Delete, Select All, Find ⌘F, Find Next ⌘G, Find
  Previous ⇧⌘G, Use Selection for Find ⌘E, **Find and Redact…** ⇧⌘F, Reset Form…, Copy
  Highlights & Notes (should).
- **View**: Single Page, Continuous, Two Pages, Book Mode (cover), Actual Size ⌘0, Zoom In ⌘+,
  Zoom Out ⌘−, Zoom to Fit ⌥⌘0, Zoom to Width ⌥⌘9, Hide Sidebar ⌥⌘1, Thumbnails ⌥⌘2,
  Outline ⌥⌘3, Annotations ⌥⌘4, Highlight Form Fields, Show/Hide Toolbar ⌥⌘T, Full Screen ⌃⌘F.
- **Go**: Next Page, Previous Page, First Page ⌥↑/Home, Last Page ⌥↓/End, Go to Page… ⌥⌘G,
  Back ⌘[, Forward ⌘].
- **Tools** (number keys pick directly, Esc returns to Select): Select ⌘1, Highlight ⌘2,
  Underline/Strike (via the highlight style), Draw ⌘3, Text Box ⌘4, Note ⌘5, Shapes ⌘6
  (last used shape), Rectangle/Oval/Line/Arrow (unbound), ⌘7 left free, Sign ⌘8 (opens the
  signature menu), Redact ⌘9. Highlight color submenu with the 5 colors.
- **Pages** (new menu; Nitro scatters these): Rotate Left ⌘L, Rotate Right ⌘R, Delete Pages ⌫
  (when thumbnails are focused) / ⌘⌫, Move Up ⌥⌘↑, Move Down ⌥⌘↓, Insert from File… ⇧⌘I,
  Insert Blank Page ⌥⌘B, **Extract Selected Pages…** ⌥⌘E, **Split Document…**, Reverse Order,
  **Combine Files…** (also here), **Apply Redactions…**.
- **Window**: system. **Help**: Paper Help (opens the README).

## Permissions and system integration

- **No permissions needed** for any v1 feature: file access comes through the Open panel,
  document opening and drag and drop (sandbox-friendly with `user-selected.read-write`).
  Saving split output into a folder uses the folder the person picked in the panel.
- **Later**: Contacts (AutoFill), Camera (signature from camera / Continuity Camera import).
  Both through `PermissionGate`, only when chosen.
- **Default app**: registered as an Editor for `com.adobe.pdf` with `LSHandlerRank` =
  *Alternate*, so it shows up in Open With without taking over. An explicit button in Settings
  makes it the default.
- **Images**: opens `public.png`, `public.jpeg`, `public.heic`, `public.tiff` as untitled PDFs
  (should).
- **Services / Shortcuts**: none in v1. **Later**: App Intents "Combine PDFs", "Extract Pages",
  "Flatten PDF", "Redact Text in PDF" (powerful for automation, and our core already supports
  them). A Finder Quick Action "Combine in Paper".
- Nitro integrates: Nitro account login (Account menu, `com.gonitro.*` URL schemes for auth),
  cloud e-sign, update checks, an AppleScript dictionary and Scripts menu, scanner import, iOS
  app handoff. We skip all of these.

## UX patterns worth adopting

- **Tool groups that remember the last choice**: each toolbar group is a button plus a
  dropdown. The button repeats the last tool used from that group, so the common case is one
  click. Our Shapes and Highlight buttons work the same way.
- **Numbered tool shortcuts** (⌘1–⌘9) give every tool a key. It matches our design system's
  "number keys pick directly".
- **Select first, then act**: selecting text and then choosing highlight/underline/redact works
  everywhere in Nitro (Format menu). We make it visible with a small bar over the selection.
- **Search results as a list in page order**, with context, rather than a bare "3 of 12" counter.
- **"Find and Redact" and "Find and Highlight"** reuse the same search. One search, many
  actions. We do Find and Redact in v1. Find and Highlight is a natural extra (should, if
  cheap).
- **Flatten as a share option** ("Mail Document > Flattened"): the moment you send is when you
  want it flattened.
- **Interleave front/back scans**: a tiny feature that saves real pain.
- **A sticky tool, with an explicit way out**: Nitro makes tools one-shot unless you double-click.
  We'll keep tools active until Esc, because people highlight several passages in a row.
- **Annotations carry an author name** taken from the Mac account, so a reviewer's notes are
  attributed in Acrobat.
- **Thumbnails as the page-surgery surface** with a size slider. Ours adds a Pages menu so it
  works without a mouse.

## What we won't copy, and what we'll do better

- **Not copying**: the name, icons, the home-screen greeting, wording, the two-row toolbar
  styling, the Library palette art, stamps, sounds, the account/upsell flows (Log In, Get
  Signatures, AI assistant).
- **Doing better**:
  - **No account, no subscription, no network.** The loudest complaints about Nitro since it
    bought PDFpen are forced login activation, a $140–180/yr subscription, double charges,
    and support that doesn't answer (App Store reviews, Michael Tsai's blog, BBB). Paper is
    local, free, and never phones home.
  - **Redaction you can trust and check.** Nitro's own guide says Find and Redact leaves
    metadata for you to clear by hand. Preview's tool was shown to leave hidden text and edge
    fragments. We scrub overlapping notes, fields and metadata, and we verify.
  - **Destructive results never overwrite by surprise.** Redaction and flattening write a new
    file by default (Preview overwrites. Nitro applies redactions to the open document).
  - **Page tools in one place** (a Pages menu) instead of four menus plus AppleScripts.
  - **Simpler chrome**: one toolbar row, plus a contextual style strip only when an annotation
    or text box is selected. Nitro's second row is mostly disabled controls.
  - **No home window** between launch and the document.
  - **Native and fast**: launch < 300 ms, lazy thumbnails, no Electron or web views.
  - **Highlighting keeps text crisp**: an old PDFpen review said its highlights washed out the
    text. PDFKit's highlight blend mode handles this, so check it in light and dark mode.
  - **Honest scope**: we don't pretend to edit text. Reviews say Nitro's text editing is "worse
    than free apps", so a half-done version would hurt more than help.

## Edge cases

The build and test steps must cover these. Most need a generated fixture PDF in the unit
tests.

- **Huge documents**: a 1,000-page, 300 MB scan. Thumbnails render lazily and off the main
  thread. Search is cancellable with progress. Memory stays near budget while scrolling.
  Combine/split of large files streams page by page with progress.
- **Image-only (scanned) PDFs**: search finds nothing, so say "This document has no text to
  search (it looks like a scan)". The redaction text tool falls back to area marks. Find and
  Redact explains it can't find text in scans. With OCR later, offer it.
- **Encrypted PDFs**: a user password shows the unlock sheet. Owner-restricted documents
  (no modify/annotate/print) open read-only with an info bar saying why. Never strip
  protection silently.
- **Digitally signed PDFs**: any save invalidates the signature. On first edit, show an info
  bar: "Editing will invalidate this document's digital signature. Changes will be saved as a
  copy." Then force Save As.
- **PDF/A files**: saving breaks conformance. Info bar on first edit, same Save As approach.
- **PDFs with existing unapplied `Redact` annotations** (from Acrobat): PDFKit would apply them
  on our next save (P4). On open: "This document has 3 pending redactions from another app.
  They'll be applied when you save." Offer Review / Remove Them.
- **XFA (dynamic) forms**: PDFKit shows the "please wait / upgrade your viewer" page. Detect
  it and explain that this form needs Adobe Reader.
- **Form JavaScript** (calculated totals, validation) doesn't run, so totals won't update. The
  README says so. Consider an info bar when a document has JS actions.
- **Merging two copies of the same form**: fields with the same name share a value, so filling
  one fills both. On Combine, warn when field names collide, and offer to flatten the inserted
  copy.
- **Rotated pages** (`/Rotate 90`) and **crop box ≠ media box**: annotation, signature and
  redaction rectangles must be converted to page space correctly. Test redaction on a rotated
  page and on a page whose crop box hides content (content outside the crop box isn't visible,
  so a visual mark can't reach it. "Remove hidden content outside the visible page" is a later
  option).
- **Mixed page sizes** in combine/interleave (A4 + Letter, landscape scans): keep each page's
  size. Thumbnails use the right aspect.
- **Saving without edits must not damage the file**: there's history of PDFKit/Preview saves
  dropping OCR layers (ScanSnap, ABBYY) and stripping visible signatures, and of saves
  ballooning file size. Test: open an invisible-text (OCR-like) fixture, add one highlight,
  save, then the hidden text must still be extractable and the size must stay within ~1.2×.
  Opening and closing with no edits must not write at all.
- **File changed on disk** by another app while open, **iCloud Drive placeholders** (not yet
  downloaded), **read-only locations** (mail attachments, DMG): standard document behavior,
  where saving offers Duplicate.
- **Undo** across page moves, rotations, deletes, combined inserts and annotation edits, after
  autosave too. Redaction apply isn't undoable in place, which is why it writes a new file.
- **Non-Latin text**: search, highlight and redaction for CJK, Arabic/Hebrew (RTL) and
  accented text. Text boxes and signature names in any script. Redaction whole-word matching
  for CJK, where there are no spaces.
- **Ligatures and split words**: "ﬁnance" (a ligature glyph), words hyphenated across lines, and
  text drawn as separate glyph runs. Find and Redact may miss these, so the hit count is shown
  and the person can add area marks. The verifier searches the normalized text.
- **Fonts**: free-text annotations use the system font. Check they render the same in Acrobat
  and Chrome (appearance streams) by reopening the exported file in another viewer.
- **Dark mode**: chrome follows the system, pages stay white. Highlight colors stay legible.
  Light and dark both get screenshotted.
- **Multiple displays / Retina changes**: thumbnails re-render at the right scale.
- **Accessibility**: VoiceOver can name every toolbar control, every thumbnail ("Page 3 of
  12, selected") and every annotation in the Annotations list. Tools work from the keyboard.
  Reduce Motion: no animated page moves.
- **Sleep / quit mid-task**: Combine, Split and Apply Redactions write to a temp file and move
  it into place only at the end, so a quit leaves no half-written output.
- **Empty and weird inputs**: a 0-page PDF, a corrupt/truncated file ("Couldn't open X. It may
  be damaged."), a non-PDF with a `.pdf` extension, a 1×1 pt page, a 200-inch page.

## Our v1 scope

App shape: a **document window app**. It's a new archetype for Slopapp (closest to
"browser/library window"), so see Open question 2. `NavigationSplitView`-style sidebar
(Thumbnails / Outline / Annotations / Search results), a `PDFView` canvas (AppKit,
wrapped), one toolbar row, a contextual style strip, standard document saving. Core logic
(page ops, combine/split/interleave, flatten, redaction apply + verify, signature
background knockout, search-to-marks) lives in `PaperCore` behind protocols, with tests on
generated fixture PDFs.

Must-haves (the test step walks each item):

- [x] **Open**: ⌘O, Open Recent, Finder Open With and Dock drop open PDFs. Password PDFs prompt and unlock. Damaged files show a clear error.
- [x] **Read**: continuous and single-page modes. Zoom in/out/actual/fit page/fit width. Go to page (⌥⌘G, page field). Back/forward. Links work.
- [x] **Sidebar**: Thumbnails (lazy) and Outline (hidden when there's none), switched with ⌥⌘1–3.
- [x] **Search**: ⌘F, a results list with page + context, ⌘G/⇧⌘G, matches highlighted. A clear message on scans.
- [x] **Text markup**: highlight (5 colors), underline, strike-through on selected text, from a selection bar or a sticky tool.
- [x] **Annotations**: text box, sticky note, rectangle, oval, line/arrow, freehand. Select, move, resize, recolor, change width/size, delete. All undoable.
- [x] **Tools from the keyboard**: ⌘1–⌘9 per the menu plan, Esc back to Select. Every tool is in the Tools menu.
- [x] **Sign**: draw a signature, save it (several allowed), place it and resize it on any page.
- [x] **Forms**: fill AcroForm text fields, checkboxes, radios and dropdowns, with Tab order. Values survive save + reopen in Preview.
- [x] **Pages**: reorder by drag and by ⌥⌘↑/↓, rotate ⌘L/⌘R, delete, insert from file (menu and Finder drop) on selected thumbnails. All undoable.
- [x] **Combine Files…**: an ordered list makes a new document.
- [x] **Extract Selected Pages…**: a new document. The original is unchanged.
- [x] **Save**: standard document saving (per Open question 1), Revert To, Duplicate. Saving keeps an OCR-like text layer intact (edge-case fixture).
- [x] **Export Flattened Copy…**: annotations, signatures and form values are baked in, with 0 annotations left (checked by reopening).
- [x] **Redact – mark**: Redact tool marks text and areas. Find and Redact marks all hits from a reviewable list. Marks are reversible and **don't change content on save** (P4).
- [x] **Redact – apply**: Apply Redactions… writes a new file by default. Content under marks is removed (text, invisible text, image pixels). Black boxes. Overlapping annotations and fields removed. Metadata cleared when checked.
- [x] **Redact – verify**: the report confirms nothing redacted is extractable (checked independently with `pdftotext` in the walkthrough). Rasterize fallback per page. No write if verification fails.
- [x] **Print** ⌘P.
- [x] **Settings**: General (open-at zoom, reopen at last page, author name, Make default app button) + About.
- [x] **Within budgets** (first window is borderline, see Build notes): launch < 300 ms, idle memory < 120 MB with a 100-page document open, idle CPU < 0.2%.

Should (in v1 if cheap, in this order): Split Document… · Interleave option in Combine ·
Annotations sidebar + Copy Highlights & Notes as Markdown · Image signatures with background
knockout · Today's date · Remove markup from selection · Two-page/book modes · Insert blank page ·
Reverse order · Export as Images · Export Text · Password protect on export · Document info view/edit ·
Share (original / flattened) · Highlight Form Fields + Next Field bar · Reset Form ·
Copy Text from Page (Vision) on scans · Open images as PDFs · Remember last page · Window tabs/full screen ·
Find and Highlight.

**Explicitly out of scope for v1** (and why):

- **Editing existing text or images** in the PDF (content-stream editing, font matching, reflow).
  PDFKit can't do it, and a weak version is worse than none.
- **OCR to a searchable PDF**: deferred to v1.1 after a spike (P8/P9). v1 only offers Copy
  Text from Page as a should.
- **Certificate-based digital signatures** and signature validation (PKI, PAdES).
- **Conversion** to or from Word/Excel/PowerPoint/HTML, and **PDF/A** output.
- **Creating form fields**, form JavaScript, form data export.
- **Cloud e-sign requests, accounts, sync, AI features.**
- Stamps, watermarks, headers/footers/page numbers, Bates numbering, crop, measure, compare,
  attachments, portfolios, batch processing, AppleScript (some are later, see the inventory).

## Open questions

1. **Saving model.** (a) Standard autosave in place with versions (native, what Nitro does by
   default, recoverable via Revert To), or (b) explicit ⌘S with "Edited" in the title and a
   save prompt on close (what many Preview complainers want)? Recommendation: **(a)** for
   annotations, forms and page edits, because it's the Mac document model and Versions makes
   it safe. Redaction and flattening always write new files regardless. Owner's call.
2. **New archetype.** Paper is a document app (many windows, `NSDocument`-based, closing a
   window doesn't quit). The design system doesn't define this yet. OK to add a "document
   window" archetype section to `docs/design-system.md` as part of the build? Recommendation:
   AppKit `NSDocument` + `PDFView` with SwiftUI for the sidebar, sheets and inspector, because
   SwiftUI's `DocumentGroup` fights with PDFKit's reference model and undo.
3. **OCR in v1 or v1.1?** Vision recognition is easy. Writing a correct invisible text layer
   (positions, rotation, keeping existing content) is roughly a day of careful work plus tests.
   Recommendation: v1.1, with Copy Text from Page in v1.
4. **Sticky tools.** Tools stay active until Esc (better for runs of highlights), unlike Nitro's
   one-shot default. Confirm.
5. **Redaction relies on undocumented PDFKit behavior** (P1). It's verified on macOS 27.2.
   It needs re-checking on macOS 14 before we promise it. If it doesn't hold on 14 or 15,
   options: (a) rasterize redacted pages on those versions (safe, loses text on those pages),
   (b) raise Paper's floor to the first macOS where it holds. Recommendation: (a), with the
   verifier deciding per page automatically.
6. **Default PDF app**: Paper never asks to become the default, and Settings has a button. OK?
7. **Size**: 20 must-have checklist items is at the edge of "one session". If it needs
   trimming, the first cuts are Outline sidebar → should, freehand → should, Print → should
   (Share covers most cases). Redaction, combine/extract and flatten stay: they're why Paper
   exists next to Preview.

## Couldn't explore (and why)

- **Search, Inspector, Review Tools/Library and Find and Redact panels**: they're floating
  panels that didn't appear in the Accessibility tree while Nitro was driven in the
  background (even after `activate`), and we don't use the mouse. Their behavior is taken from
  Nitro's Mac user guide.
- **Thumbnail context menu** (delete/extract pages): needs a right-click (mouse). From docs.
- **Annotating, signing, redacting inside Nitro**: not done on purpose (look, don't touch). The
  library could contain the owner's saved signatures, and editing documents isn't read-only.
- **The Editing settings pane** shows the owner's name in the annotation-author field. It was
  read for structure only, and no screenshot was taken.

## Sources

- Nitro PDF Pro Mac user guide (index): https://www.gonitro.com/user-guide/mac
- Redact text (Mac): https://www.gonitro.com/user-guide/mac/article/redacting-text
- Preferences (Mac): https://www.gonitro.com/user-guide/mac/article/preferences
- Combining and splitting: https://www.gonitro.com/user-guide/mac/article/combinepdfs
- Basic signature: https://www.gonitro.com/user-guide/mac/article/signbasic
- Library: https://www.gonitro.com/user-guide/mac/article/library
- Work with forms: https://www.gonitro.com/user-guide/mac/article/fillforms
- Sidebar: https://www.gonitro.com/user-guide/mac/article/sidebar
- Mac release notes: https://help.gonitro.com/product-details/release-notes/mac
- Mac App Store listing, version history and reviews: https://apps.apple.com/us/app/nitro-pdf-pro-edit-sign/id6477621772?mt=12
- Setapp listing and reviews: https://app.setapp.com/nitro-pdf-pro
- Michael Tsai, "PDFpen, Nitro, and Cleverbridge" (2024): https://mjtsai.com/blog/2024/10/03/pdfpen-nitro-and-cleverbridge
- Michael Tsai, Preview/PDFKit save bugs: https://mjtsai.com/blog/2016/12/21/more-macos-preview-pdf-trouble and https://mjtsai.com/blog/2020/12/16/preview-in-big-sur-destroying-pdfs-again/
- Eclectic Light, "How effective and safe is Preview's redaction tool?": https://eclecticlight.co/2020/12/11/how-effective-and-safe-is-previews-redaction-tool/
- Macworld, redacting with Preview, Acrobat and PDFpen: https://www.macworld.com/article/344869/how-to-redact-text-in-a-pdf-with-the-preview-app-adobe-acrobat-and-pdfpen.html
- Smile (PDFpen) comparison with Acrobat and Preview: https://smile.helpscoutdocs.com/article/227-how-does-pdfpen-compare-to-adobe-acrobat-and-preview
- MacHow2 Nitro PDF Pro review: https://machow2.com/nitro-pdf-pro-for-mac-windows-review/
- Apple Preview User Guide (forms, AutoFill): https://support.apple.com/guide/preview/prvw35725
- PDFKit headers (macOS SDK): `PDFDocument.h` write options (`BurnInAnnotations`, `SaveTextFromOCR`, `SaveImagesAsJPEG`, `OptimizeImagesForScreen`), `PDFAnnotationUtilities.h` (`kPDFMarkupTypeRedact`), `PDFPage.h` (`initWithImage:options:`)

## Owner decisions (2026-11-03)

The open questions above were settled by the owner's defaults. What we did with each:

1. **Saving model: standard autosave with Versions.** Annotations, form entries and page edits
   autosave in place; File > Revert To reaches earlier versions. Redaction and flattening always
   write **new files** (Replace Original needs a second confirmation and first stores the old
   file as a version). Pending redaction marks are never `Redact` annotations: they're plain
   Square annotations named `paper.redaction.*`, so no save can apply them (P4). A PDF that
   already contains `Redact` annotations from another app gets them converted to pending marks
   on open, with an info bar saying so, and the document isn't marked edited, so nothing is
   saved before the person sees the notice. `data(ofType:)` also refuses to write while any
   `Redact` annotation exists (defense in depth).
2. **Document app archetype: yes.** Added "e. Document app" to `docs/design-system.md` §2.
   AppKit `NSDocument` + `PDFView`, SwiftUI inside; closing the last window doesn't quit (so
   Paper has its own small app delegate instead of `SlopAppDelegate`).
3. **OCR: v1.1.** Copy Text from Page (Vision) also moved to v1.1 (see deferred list); it's
   cheap but every hour went into making redaction verifiable.
4. **Tools stay active until Esc (or V).** Built that way; the strip under the toolbar says so.
5. **Redaction verifies itself on every run.** After pass 1 and pass 2 the output is reopened
   and checked: no character centered inside a mark; each removed word occurs fewer times than
   before; no annotation left except links; no outline title mentioning a removed word; and a
   pixel comparison of every marked region before/after (content that looks the same survived).
   Failing pages are rasterized with black boxes and checked again; if that fails, nothing is
   written. Unit tests drive both paths with fakes (a remover that removes nothing, a rasterizer
   that returns the page unchanged).
6. **Default PDF app: never asked.** Registered as Editor with `LSHandlerRank` Alternate.
   Settings > General has "Make Paper the Default" (calls `NSWorkspace.setDefaultApplication`).
   Never clicked during testing.
7. **20 must-haves kept** (none cut). Drag-to-reorder thumbnails and Finder drops are built but
   couldn't be walked with synthetic input (see Build notes). The should-list was trimmed; what
   moved to v1.1 is listed below.

## Build notes (2026-11-03)

### More PDFKit facts (found while building, macOS 27.2)

| # | Fact | What we did |
|---|---|---|
| P12 | `PDFPage.characterBounds(at:)` indexes drift from `page.string` by the number of line breaks before the character. | The verifier gets character boxes from `page.selection(for: NSRange)` instead. |
| P13 | PDFKit **doesn't write outline changes**: new outlines, relabeled or removed entries are all written as the original outline. | Redaction drops the whole outline (rebuilds the document from its pages) when a title contains a removed word, and says so in the report. Outline editing stays out of scope. |
| P14 | `characterIndex(at:)` returns the *nearest* character even over an image. | "Is there text under the pointer" also checks that character's box. |
| P15 | Since macOS 15, PDFView runs Vision on each visible page (`PDFPageAnalyzerV2`, form-field and table detection): ~100 MB and Neural Engine time per page, and it would add fields our undo/form tracking don't know. No public switch. | Turned off through PDFView's `documentAnalysisEnabled`/`formDetectionEnabled` when the setters exist (KVC, guarded by `responds(to:)`, no-op on 14). Footprint with a 100-page document went from 170–190 MB to 85 MB. |
| P16 | Mouse events on pages go to PDFKit's internal document view, so `PDFView.mouseDown` overrides aren't called; text drags run in PDFKit's own tracking loop (local event monitors only see the mouse-down); and the split view's/title bar's click recognizers delay quick clicks to sibling overlay views. | Tools are driven from a window-level event monitor: on mouse-down it asks the canvas whether the current tool claims the point (drawing tools, Redact over non-text, annotations/handles in Select) and then owns the down/drag/up; otherwise PDFKit gets the click, and after the button is released Highlight/Redact apply to the selection and the selection bar appears. |
| P17 | Annotations loaded from a file keep their `/AP` appearance stream; changing bounds or color doesn't regenerate it. | Every geometry/style edit removes `/AP` first so PDFKit redraws from the properties. |
| P18 | PDFKit applies `Redact` annotations on write, so a "foreign redaction" fixture can't be made with PDFKit. | The fixture is a hand-written PDF. |
| P19 | A mark overlapping an image edge leaves black (zeroed) image pixels next to white page: a "region must be one flat color" check wrongly rejects it and rasterizes the page. | Replaced by the before/after pixel comparison in decision 5. A unit test covers the straddling case. |

### Gates

- **Unit tests:** 96 tests in 15 suites (Swift Testing), all passing: text matching (case,
  whole word, CJK), page ordering/interleave/split math, page ops (persisted after write),
  redaction (marks don't change content on save, foreign `Redact` conversion, apply removes
  text/invisible OCR text/image pixels, partial-word boxes, rotated pages, metadata, overlapping
  annotations, outline drop, find-and-redact every occurrence, rasterize fallback, never-success
  on a failed fallback, write failure, P2 fake-redact guard), flatten (0 annotations, form values
  and text boxes baked in, marks excluded), save safety (OCR layer survives a save, size ≤1.2×),
  annotations (multi-line highlight quads persist, shapes, ink, resize scaling, handle math,
  appearance invalidation), signatures (normalize, fit, library cap, file store), document facts,
  search, last-page memory, Markdown notes export. Fixtures are generated (`PaperFixtures`).
- **`scripts/check.sh Paper --perf`:** the final run passed every gate (test, universal
  bundle, smoke, perf, catalog). Perf across runs: launch 125–151 ms, idle CPU 0.011–0.021 %,
  footprint 19 MB with no document and **84.5 MB idle with a 100-page document** (release
  build, `drive stats`), all PASS. **First window is borderline: 583–598 ms on passing runs,
  617–662 ms on three earlier runs.** The first window at launch is the system Open panel (as
  in TextEdit and Preview); measured in-process, `NSOpenPanel()` alone takes ~380 ms on a cold
  launch (AppKit's own sidebar/file-provider setup; only 3 dylibs load, so there's nothing to
  preload). Paper already shows it without the window animation. A home window would pass
  reliably, but the research rejected it as an extra step; left for the owner to call.
- **Accessibility:** no `[unlabeled]` controls in Paper's own UI (document window in every
  sidebar mode and tool, Combine, Settings/About, Apply Redactions, signature and split sheets).
  PDF form fields are labeled from the PDF's `/TU` names; a PDF without them shows unlabeled
  fields (document content, not Paper's controls). The system Open/Save/Print panels have a
  few unlabeled controls of their own.

### Walkthrough (release and debug builds, `/tmp/paper-test/` fixtures, light and dark)

Screenshots in `/tmp/paper-test/shots/` (not in the repo). Real-mouse steps were run only after
60 s without owner input, one action at a time.

| Must-have | Result |
|---|---|
| Open | `open -a` (Open With path), Open panel at launch, File > Open Recent (one menu), password sheet (wrong password message, unlock), damaged and non-PDF files show "could not be opened … It may be damaged or not a PDF" with a suggestion. Dock drop not walked (needs the Dock). |
| Read | Continuous, Two Pages, zoom in/actual/fit/width from the View menu, page field + ⌥⌘G (went to page 5), outline sidebar jumps, reopens at the last page viewed. |
| Sidebar | Thumbnails render lazily and track the current page; Outline tab only when the document has one; Notes list. |
| Search | Toolbar search → results list with page and context; scan says "No Text to Search… It looks like a scan". |
| Text markup | Highlight tool on text (yellow, text stays crisp), selection bar → Underline. |
| Annotations | Text box (click, type, Esc), note (popover), rectangle, freehand; select, move, Shift-arrow nudge, recolor from the strip, resize by handle; Notes list selects them; all undoable. Oval/line/arrow share the shape path (unit-tested), not walked one by one. |
| Keyboard tools | ⌘3 Draw, ⌘9 Redact, ⌘5 Note, Esc → Select, V → Select, ⌘R rotate, ⌘Z ×4 undid rotate/insert/move. |
| Sign | New Signature sheet (draw, Save), click to place, placed selected with handles; stored in `PAPER_DATA_DIR/signatures.json`. |
| Forms | Text field, checkbox, radio, pop-up filled via Accessibility; "Undo Fill Form"; values survive save/reopen (unit test); flattened copy shows them (`pdftotext`, Poppler render). The fixture's PDFKit-made checkbox has no check glyph appearance (fixture limitation; real forms carry their own `/AP`). |
| Pages | Rotate, insert blank, move down (⌥⌘↓/menu), reverse, extract, undo chain. Drag-to-reorder thumbnails: built with SwiftUI `onMove`, **not walkable** (SlopDrive's synthetic drag is too fast to start a list drag session). Insert from File / Finder drop: built, not walked (the Open panel doesn't take synthetic typing; Finder drops aren't allowed by the brief). |
| Combine | Combine Files window: Add Open Documents, list with page counts, interleave toggle (2 files), Combine → untitled "Combined" (A4 landscape + Letter pages kept their sizes). |
| Extract | "pages (page 3)" untitled document, original untouched (`pdfinfo` 3 pages). |
| Save | Autosave wrote annotations and marks; reopened intact; marks stored as Square annotations (`/Redact` count 0 in the file, secret still extractable until Apply). |
| Flatten | `sign (flattened).pdf`: `/Annots` 0, name and pop-up value and signature baked in. |
| Redact mark | Find and Redact "secret-4417" → 3 hits on 3 pages → Mark 3 Results; Redact tool area box over an image; foreign `Redact` file → converted to marks + notice, not marked edited. |
| Redact apply/verify | New file `text (redacted).pdf`: `pdftotext` has no `SECRET-4417`, the rest of each line survives, `strings` finds nothing, `pdfinfo` shows no title/author; report sheet "Removed 3 areas on 3 pages. Checked: none of the redacted text can be found in the new file." Area box: `pdfimages` shows the embedded image's pixels under the box zeroed, page text still selectable. |
| Print | Print sheet with preview of all pages; cancelled. |
| Settings | General (launch at login, open zoom, reopen at last page, author name with the account name as placeholder, default-app button) and About. |

### Design review (§10)

1 pass (open, pick a tool with one key, act) · 2 pass (system controls, accent color for
selection; document content colors are fixed sRGB on purpose so files look the same everywhere)
· 3 pass (every action in a menu with its shortcut) · 4 pass (Esc leaves tools/sheets, ⌘, ⌘Q) ·
5 pass · 6 pass · 7 pass (`ContentUnavailableView` in empty sidebars, DropZone in Combine) ·
8 n/a (no permissions) · 9 pass (undo for every edit; destructive results go to new files) ·
10 pass (no network code; Help opens the README only when chosen) · 11 pass, borderline on
first window (above) · 12 pass · 13 pass (no motion beyond system defaults) · 14 pass (window frame, sidebar
width, tool styles, sidebar mode persist).

### Deferred to v1.1 (from the should list)

Image signatures with background knockout · Remove markup from selection · Export as Images ·
Password protection on export · Document info view/edit · Share menu (original/flattened) ·
Next Field button (the form bar has Highlight Fields and says Tab moves on) · Copy Text from
Page (Vision) · Find and Highlight · thumbnail drag to Finder · OCR (decision 3).

### Risks

- The redaction path relies on undocumented PDFKit behaviour (P1) and was only run on macOS
  27.2. The verifier and the rasterize fallback make a silent failure unlikely, but **verify on
  14**: on a version where P1 doesn't hold, every marked page will be rasterized (text on those
  pages no longer selectable), which the report states.
- P15 uses two private PDFView properties through KVC (guarded). If Apple renames them, Paper
  keeps working with higher memory use.
- Tool input depends on P16's event routing; a future PDFKit change to its tracking loop could
  need a revisit. Drag-reorder in the thumbnail list is untested by automation.
- Restricted (owner-password) PDFs open read-only on purpose; encrypted PDFs keep their user
  password on save but lose a distinct owner password (PDFKit can't write one it doesn't know).

### Test hooks

`PAPER_DATA_DIR` (signature library location), `PAPER_APPEARANCE=light|dark` (screenshots
without changing the system appearance), `PAPER_DEBUG_EVENTS=1` (canvas event log in the temp
directory), `swift run --package-path apps/Paper paper-fixtures /tmp/paper-test/fixtures`.

## Parity pass (2026-11-03)

Governed by `docs/parity-pass.md`: look and work more like Nitro PDF Pro, and don't miss
features. Sources for the look: Nitro's four official Mac App Store screenshots (downloaded to
`/tmp/paper-parity/dl/`, not committed), its Mac user guide (Toolbar, Inspector, Sidebar
articles), and the menus and panes recorded in the research above. Nitro wasn't launched again in
this pass (the screen was locked), so nothing of the owner's was seen.

### Fix first: pending marks lost after save on macOS 26 (CI)

**What CI showed** (GitHub `macos-26-arm64`, macOS 26.6.2, Xcode 26.6):
`pendingMarksDoNotChangeContentOnSave()` found 0 marks after `dataRepresentation()` + reopen,
then crashed the test process with "Index out of range" (the test indexed `marks[0]` after a
failed `#expect`).

**Why.** A mark was a Square annotation identified *only* by its `/NM` (annotation name),
read back through `value(forAnnotationKey: .name)`. Experiments on macOS 27.2 (P20 below)
show that PDFKit's *writer* keeps every key we set, but its *reader* only surfaces the keys its
annotation model knows, and that set differs between releases. On 26 the name didn't come back,
so marks vanished after any save/reopen: the info bar lost them, Apply Redactions said "nothing
marked" (it reads the saved bytes), and Export Flattened Copy would have baked the red boxes in.
Signatures used the same `/NM` tagging and had the same exposure.

**Fix (`PaperCore/AnnotationTags.swift`), independent of PDFKit's model on any version:**

1. **Written redundantly** into standard entries every PDF writer keeps: `/NM`
   (`paper.redaction.<UUID>` as before), `/Subj` ("Pending Redaction" / "Signature", the
   standard comment subject Acrobat shows), and for marks `/Contents` ("Pending redaction", which
   every file saved by Paper 0.1 already has).
2. **Read from the file's own bytes** with CoreGraphics' `CGPDFDocument` (the low-level parser
   PDFKit sits on, unchanged since 10.x): the raw `/Annots` dictionaries of each page. A PDFKit
   annotation is matched to its raw dictionary by page, subtype and `/Rect` (±1 pt). The raw
   parse only runs when PDFKit hands back a Square or Ink annotation it can't identify, so
   ordinary documents pay nothing.
3. **Pinned in memory** as an associated object on the `PDFAnnotation`, so identity never
   depends on PDFKit echoing a key between edits. Page copies (extract, combine, insert) carry it.

Any one signal is enough. `AnnotationTags.open(_:)` replaces `PDFDocument(data:)` wherever
Paper reads back bytes it may have written (document open, unlock, Apply Redactions, flatten,
combine, insert). **Migration:** opening re-tags everything found (including Paper 0.1 files
whose only trace is a Square with `/Contents` "Pending redaction"), and the next save writes the
full set of keys. The crash path is gone: tests use `try #require(marks.first)` and print what
PDFKit and the raw file each hold when it fails, so a future CI failure explains itself.
Tests simulate the macOS 26 behaviour by stripping the keys from reopened annotations
(`AnnotationTagTests`, 9 tests). CI on GitHub still has to confirm on 26.

### More PDFKit facts (macOS 27.2)

| # | Fact | What we did |
|---|---|---|
| P20 | `dataRepresentation()` writes custom annotation keys (`/PaperMark`, `/Subj`, `/IT`, `/NM` all in the bytes), but a reopened annotation's `annotationKeyValues` only shows keys PDFKit models (`/PaperMark`, `/Subj`, `/IT` missing; `/NM`, `/T`, `/Contents` present on 27, `/NM` apparently not on 26). | Tags are redundant and read from the raw file with CGPDF (above). |
| P21 | A `PDFAnnotation` subclass that overrides `draw(with:in:)` (an image stamp) is written with PDFKit's default stamp look, and burn-in loses the image too. There's no public way to set an appearance stream. | Image signatures are traced into Ink (see below). Images on pages stay deferred. |
| P22 | Vision on the scan fixture inside a test process: 0.3 s here (the model was already prepared by the system). P9's ~30 s first call is still the worst case on a fresh Mac. | OCR shows a progress sheet that warns about the first page; real-Vision test gated by `PAPER_VISION_TESTS=1`. |
| P23 | `CGContext.drawPDFPage` copies a page's content stream as-is (vector stays vector) into a new one-page PDF; `setTextDrawingMode(.invisible)` text is found by `PDFPage.string`/search and selection at the drawn position. | `PageRewriter` (OCR text layer, headers and footers). Annotations are moved to the new page; undo swaps the old page back. |

### Gap table

| Nitro feature or design element | Paper now | Notes |
|---|---|---|
| Toolbar: labeled items (icon + label) | **Done** | `iconAndLabel` toolbar: Sidebar · Zoom (−/+) · Fit Width · Scale (editable %, dropdown of steps) · Page (field + "of N") · tool groups · Search · Share · Inspector. |
| Tool groups = button + dropdown, button repeats the last tool | **Done** | Select · Highlight▾ (style, 5 colors, Highlight All Results, Remove Markup) · Draw▾ (freehand, rectangle, oval, line, arrow) · Comment▾ (text box, note, today's date) · Sign▾ (saved signatures, new, from image) · Redact▾ (mark tool, Find and Redact, Apply, Remove All). Nitro's *Forms* group creates form fields: out of scope (see below), so Paper's 4th group is Sign. |
| Second row "editing bar" | **Done** | The style strip is now always shown (View > Hide Editing Bar ⇧⌘E, Nitro's shortcut); controls that don't apply are dimmed, as in Nitro. |
| Inspector (⌥⌘I): Document Info, Permissions, element properties | **Done** | Trailing inspector with Document (edit title/author/subject/keywords, undoable; pages, page size, PDF version, file size, dates, creator, producer, encrypted), Security (current permissions; Save Protected Copy), Selection (kind, page, date, author editable, text, delete). Nitro's Alignment tab: skip (no multi-object layout). |
| Sidebar: thumbnails with numbers, size slider, modes | Done (before) / slider deferred | Size slider: deferred, ~1 h (thumbnail width is fixed at 110 pt). |
| Search panel with results list | Done (before) | Now also **Find and Highlight** (⌥⇧⌘F; "Highlight All N" under the results). |
| OCR to searchable PDF | **Done** | Edit > Recognize Text…: pages without text (default) or the current page; progress sheet with a first-run warning; Stop keeps finished pages; one undo step. Info bar on scans offers it (Nitro prompts on open). |
| OCR on selection / Copy text from a scan | **Done** | Edit > Copy Text from Page (page text, or Vision on a scan). |
| Rotate & deskew, OCR language list, clear OCR layer | Deferred | Deskew ~0.5 day (Vision horizon detection + page rotate); languages are automatic; clearing a layer is power-user. |
| Image signatures ("Make Transparent Image") | **Done** | Signature sheet has Draw / Image tabs; drop or choose a photo, automatic paper threshold (Otsu) with a Thinner–Bolder slider, crop to ink, dust removal. Stored as Ink bands (P21), so place/resize/flatten work as for drawn ones. |
| Export JPEG/PNG/TIFF | **Done** | File > Export as Images…: PNG/JPEG/TIFF/HEIC, 72/150/300 dpi, all or selected pages, into a folder, with progress. |
| Export text | Done (before) | Rich text: skip. |
| Passwords and permissions | **Done** | Save Protected Copy… (open password with verify; permissions password + printing, copying, page changes, comments). Writes a new file and verifies it by reopening. Nitro edits the open document's security; Paper writes a copy so autosave can never lock you out with a typo. |
| Document info editing | **Done** | Inspector > Document. |
| Share / Mail Document (regular, flattened) | **Done** | Toolbar Share button and File > Share > Share… / Share Flattened Copy…. Edited or untitled documents share a fresh copy. |
| Headers, footers, page numbers, Bates | **Done** | Pages > Headers & Footers…: six slots, tokens {page} {pages} {date} {name} {bates}, Bates prefix/start/digits, size, margin, all or selected pages; presets; stamped into page content (prints everywhere); undoable. |
| Remove markup (⌥⇧⌘0) | **Done** | Edit menu and Highlight dropdown. |
| Next-field navigation | Deferred, ~0.5 day | PDFView has no public API to focus a widget's field editor; Tab inside a field works. Needs a spike (synthesized click on the widget). |
| Compare documents (⌘K) | Deferred, 2–3 days | Text diff per page plus a side-by-side view; its own feature. |
| Edit existing text / images | Out of scope | PDFKit can't edit content streams; reviewers rate Nitro's own editor poorly. A weak editor would hurt more than help. |
| Add images to pages | Deferred, ~1 day | Needs our own appearance stream or content stamping (P21). Image signatures cover the main use. |
| Watermark | Deferred, ~2 h | `PageRewriter` makes it cheap (diagonal text, opacity). |
| Crop pages | Deferred, ~0.5 day | Needs a crop-box drag UI. |
| Stamps / Review Tools library | Deferred, ~1 day | Today's date covers the dynamic stamp. |
| Form field creation, form data export | Out of scope | Authoring tool. |
| Squiggle underline, cloud, callout, polygon | Deferred, 2–4 h each | No PDFKit subtype for squiggle; callout is the most useful. |
| Digital ID signatures, Get Signatures, account, AI | Out of scope | PKI, servers, accounts. |
| PDF/A, Office conversion, optimize | Out of scope / deferred | Optimize ~2 h via `.saveImagesAsJPEGOption`. |
| Home screen | Skip (decided before) | The Open panel is the start. |

### Deviations from the design system (and why)

- **Toolbar shows labels** (icon and text) instead of icons only: Nitro's toolbar is labeled,
  and a switcher should find every group where they expect it. Customize Toolbar can turn
  labels off.
- **Editing bar always visible** with dimmed controls: matches Nitro's second row. Hideable.
- **Inspector docked in the window**, not a floating panel as in Nitro: floating panels don't
  follow window tabs or full screen and hide behind other windows. Same tabs, same ⌥⌘I.
- No colour or visual changes: system controls, SF Symbols, accent colour; no Nitro artwork.

### Shared components built in-app (candidates for SlopKit)

`AnnotationTags`/`RawAnnotationReader` (PDF-specific, stays), `PageRewriter` (PDF-specific),
`Clipboard` (env-switchable pasteboard: a SlopKit candidate; Convert has the same idea),
`ShareFiles` (temp share copies: SlopKit candidate), `Snapshots.shoot` (offscreen window PNG:
Convert and Zones have near-copies; a SlopKit `SnapshotHook` would dedupe all three).

### Gates (this pass)

- **Tests:** 134 in 23 suites, all pass (was 96). New: annotation tags (9), image signatures (6),
  OCR (6 + 1 real-Vision test, run once locally with `PAPER_VISION_TESTS=1`: pass), image export
  (5), protection (3), document info (3), text markup (2), headers and footers (3).
- **`scripts/check.sh Paper --perf`**: all pass, twice (plain and `CI=true`), on a busy machine
  (load 6–11): launch 117 ms, first window 570–579 ms (< 600), idle CPU 0.006–0.012 %,
  footprint 19 MB with no document.
- **Offscreen renders** (the screen was locked, so no `scripts/drive` walkthrough): `PAPER_SNAPSHOT`
  renders Paper's own windows. 30 PNGs in `/tmp/paper-parity/shots/` (light and dark): document
  window, inspector Document/Security/Selection, Highlight and Shape tools, Find and Highlight,
  Export as Images, signature Draw and Image tabs, OCR options and progress, Headers & Footers,
  scan notice, and a scan after Recognize Text with search finding "invoice". Reviewed; fixed from
  them: inspector didn't expand offscreen (animation), Security tab shouted "Enter a password"
  before typing, footers right-aligned, image-signature bands showed hairline stripes (now
  overlap 1.5×), search results lacked a visible Highlight All button, snapshot author used the
  account name (now "Sample Reviewer"). PDFKit's page tiles don't draw into offscreen captures,
  so page content shows blank in these images (thumbnails do render); page content is covered by
  unit tests that render pages.

### On-screen checks still owed (need an unlocked screen)

1. `scripts/drive tree` on the release build: no `[unlabeled]` controls (new: tool-group
   segments, scale combo box, inspector panes, new sheets).
2. Tool-group clicks: button part picks the remembered tool, chevron opens the menu under the
   group; Sign button opens the signature menu; selected state follows ⌘1–⌘9.
3. Scale combo: typing 150 + Return and picking from the dropdown both zoom.
4. Share toolbar button and File > Share (picker appears; don't complete a share).
5. Recognize Text with real Vision on `/tmp/paper-test/fixtures/scan.pdf`; time the first page;
   select and highlight recognized text; undo.
6. Image signature: choose a generated image, place, resize (bands stay solid), flatten.
7. Save Protected Copy: `pdfinfo` shows encryption; Preview asks for the password.
8. Export as Images into a `/tmp` folder; Headers & Footers on a fixture, then `pdftotext`.
9. Inspector: edit Title, save, reopen; `pdfinfo` shows the new title.
10. Pending marks survive save/reopen on macOS 14 and 26 (CI covers 26 in unit tests).

## Polish pass (2026-11-05)

Governed by `docs/polish-pass.md` (including the mid-pass Golden Gate addition). Measured on
release builds (`build/Paper.app`, SDK 27 stamp) with `scripts/drive shot` + `scripts/measure`,
light and dark, test data only (`/tmp/paper-test/`, `PAPER_DATA_DIR`, `PAPER_DEFAULTS_SUITE`,
`PAPER_PASTEBOARD`, `PAPER_FAKE_OCR`). Sheets that need a key window were also rendered with the
`PAPER_SNAPSHOT` walk (offscreen; it now covers 22 surfaces per mode). Screenshots:
`/tmp/slopapp-polish/paper/` (`before/`, `b-*.png`, `snap-before/` = before; `after/`,
`tools/`, `snap-after/` with `pair-*.png` light|dark side by side = after).

### Defects fixed (before → after)

| # | Surface | Before | After |
|---|---|---|---|
| 1 | Lint | 4 corner literals (signature pad `8`), 5 colour literals, 15 spacing warnings | `Radius.m`; the colours are generated test art and fixture page content (`// lint:allow`); 0 warnings |
| 2 | Toolbar, default size | A new window was 980 pt wide; at 1240 pt Redact and Share sat in », and with the inspector open Comment, Sign, Redact and Share did | New windows 1280 pt: all 14 default items visible. Fit Width moved into the zoom menu (Actual Size, Fit Page, Fit Width, then percentages; still in Customize Toolbar and ⌥⌘9). Search/Share/Inspector sit after the inspector separator, over the inspector. Tool groups have high visibility priority, zoom/scale/page/share low, so a narrow window loses zoom controls first. Toolbar id bumped to `PaperDocumentToolbar3` so the new default applies |
| 3 | Toolbar, 560 pt minimum, 86-character file name | (overflow order undefined) | Sidebar, », Search, Share, Inspector; title truncates at the end (system); nothing clipped |
| 4 | Scale field | "173%" clipped by its dropdown button (76 pt field) | 92 pt: fits "1600%" |
| 5 | Page item | "of 3" 0 pt from the item's capsule edge, glyphs clipped | 12 pt inset, field and label on one baseline |
| 6 | Bars under the toolbar | Editing bar 32 pt (hairline y = 98), sidebar picker row 36 pt (y = 102); editing bar height changed with the tool | Every bar (sidebar picker, editing bar, inspector picker, Search/Find panel headers, info bars) is 36 pt (`PaperMetrics.barHeight`); hairlines measured at y = 102.0–102.5 in sidebar, canvas and inspector |
| 7 | Separators | SwiftUI `Divider` (1 pt) in 11 places | `Hairline()` (one device pixel); menus keep their separators |
| 8 | Canvas | Page 6 pt from the left edge, 8 pt right, 8 pt top, 4 pt between pages; background the same near-white as the sidebar; fit-width left room for a legacy scroller (21 pt sides after widening margins) | `underPageBackgroundColor`, page shadows on, 12-unit gap on every side and between pages (16 pt at 133 %, 21 pt at 174 %; measured left 16 / right 16 / top 16 / between 17). Fit Width is computed (gap included, scroller only when scrollers take space) and refits when the sidebar or inspector opens. Thumbnail clicks and reopen-at-page no longer put the page flush (0 pt) against the bar |
| 9 | Thumbnails | No selection shown on open (selection empty until the page changed); the list's pill would sit behind the whole row | The page gets a 3 pt ring 3 pt outside it, outer radius 6 = `Radius.s` (concentric with the square page: inner radius = gap), and its number sits in a capsule; list pill turned off (`ListSelectionHighlightRemover`). Inactive window: system-grey ring, unemphasized capsule. Row padding 8 pt so the ring never clips. Shadow 1.5 pt / 25 % |
| 10 | Colour swatches | Selection ring touched the swatch (0 pt gap); `.separator` border invisible on black in dark mode; `.plain` buttons had no pressed or disabled look | 16 pt swatch, 1 pt gap, 2 pt ring (measured 2/1/15.5/1.5/2 px-pairs); `tertiaryLabelColor` hairline; `PressDimmingButtonStyle` (55 % pressed, 40 % disabled) |
| 11 | Editing bar labels | "Width"/"Size" at 13 pt beside 11 pt pop-ups | Callout, secondary, same as the hint. Under 520 pt the labels go; the hint shows whole or not at all (`ViewThatFits`); anything left over clips at the trailing end instead of centring off both sides (it did at 560 pt) |
| 12 | Selection handles | Handles centred on the annotation's corners, 2 pt inside the outline's corners | On the outline's corners (`PaperMetrics.selectionOutset`); outline and handles go system grey when the window isn't key |
| 13 | Selection bar | 1 pt stroke, 10/6 pt padding | Hairline border, 4 pt padding: 28 pt capsule, first swatch centred 14 pt in (concentric with the end cap) |
| 14 | Inspector | Page size, dates and Producer dropped below their labels at 240 pt; empty fields (Subject, passwords) looked like static rows; AX label "Inspector, Inspector pane" | Label and value on one baseline, value wraps beside it; numeric dates; minimum 260 pt; callout text; prompts "None"/"Required"; AX "Inspector pane" |
| 15 | Signature sheet | Sheet grew 40 pt switching Draw → Image; placeholder `.tertiary` (1.9:1); Image preview a pure-white slab in dark mode; no typed signature | Every tab 480 × 200 pt (sheet 520 × 344 in all three); placeholder `.secondary`; preview on the same surface as Draw with label-colour ink; **Type** tab (name + Script/Hand/Marker, traced into ink like an image, `TypedSignature`, 4 tests); previews inset 24 pt |
| 16 | Split sheet | "This document isn't chang…" truncated | Wraps |
| 17 | Redaction progress | "…checking the re…" truncated | 420 pt, wraps |
| 18 | Redaction report | Pale `.green` shield in light mode | `.textGreen` |
| 19 | OCR progress | Proportional digits in "page 1 (1 of 12)" | `.monospacedDigit()` |
| 20 | Headers & Footers | Every box left-aligned; column titles all leading | Text sits where it will on the page (left/centre/right); titles aligned to their columns |
| 21 | Combine Files | Footer 12 pt from the edge vs 20 pt for list and options; with files the status text wrapped between the buttons and "Add Open Documents" truncated to "Add Open…" | Footer 20 pt; status line moved under the interleave option; buttons never truncate |
| 22 | Notes list | Yellow highlighter icon ~1.3:1 on the light sidebar; black-ink icons invisible in dark | Annotation colour kept (it's information) but darkened in light / lightened in dark when it wouldn't read (`NSColor.readableSymbol`) |
| 23 | Locked (password) document | Toolbar tool groups drawn as blank capsules (symbols never set) | Symbols set before the locked early return |
| 24 | Text box editor | Dark mode put the box's black text on `textBackgroundColor` (dark grey) | White at 90 % with an aqua appearance: it sits on the page, which stays white |
| 25 | Settings | Author field explanation missing | Subtitle under the control |
| 26 | Test isolation | With `PAPER_DEFAULTS_SUITE` set, window frame, last pages, split positions, toolbar layout, Settings (`@AppStorage` on `.standard`) and window autosaves still wrote the real domain; the snapshot walk autosaved its highlights into the fixtures | All go to the suite or aren't autosaved in test runs; the walk works on a temporary copy of the fixtures |

### Golden Gate + light/dark

- **Sidebar**: the system sidebar (`NSSplitViewItem(sidebarWithViewController:)`), edge to edge;
  no card. Notes icons keep the annotation's colour (meaningful), made readable per mode.
- **Menus**: decorative symbols removed from the Highlight, Draw, Comment and Redact
  dropdowns; colour swatches (Highlight colours, annotation context menu) and saved-signature
  previews kept. Main menu was already text-only.
- **Toolbar**: standard `NSToolbar` with system glass; no drawn strips. The editing bar is a
  `.bar`-material row under it, as before.
- **Inactive windows**: thumbnail ring and number, swatch rings, annotation outline/handles go
  grey (`appearsActive`, key-window notifications in the overlay). Every on-screen shot in this
  pass is of an inactive window (the owner was using the Mac); the key-window accent states are
  verified in code only.
- **Glass**: system materials only (toolbar, `.bar`, `.thickMaterial` selection bar).
- **Light/dark**: every surface shot in both. Fixed for dark: signature image preview, text
  box editor, black swatch border, notes icon colours. The canvas colour re-resolves on an
  appearance change (`viewDidChangeEffectiveAppearance`); overlay colours are resolved at draw.
  Pages, the page-white thumbnail placeholder and the white signature handles stay white in
  both modes on purpose: they're page content.

### Gates (this pass)

- `scripts/lint.sh Paper`: pass, 0 warnings.
- Tests: 138 in 24 suites, all pass (4 new typed-signature tests).
- `scripts/check.sh Paper --perf`: lint, test, bundle, smoke, catalog pass. Perf: launch
  115–144 ms, idle CPU 0.016–0.029 %, footprint 18.5–19.3 MB, all pass; **first window
  596 ms (pass, load 4.6) and 603–626 ms (fail, four runs at load 5–9)**. The first window is the system
  Open panel (see Build notes: ~380 ms of it is `NSOpenPanel()` itself); nothing in this pass
  touches that path. Same borderline as recorded in the build and parity passes.
- `scripts/drive tree`: no `[unlabeled]` in the document window (thumbnails, Notes, Search,
  each inspector tab, selection) or the signature sheet (all three tabs).
- Window buttons 16 × 16.

### Not done, and why

- **Key-window (active) screenshots and real-pointer hover**: the owner was at the Mac the whole
  pass (HID idle 0–24 s), so Paper was never activated; accent states are code-verified.
  Opening Settings or Combine from the menu activates the app, so those were rendered offscreen
  (snapshot walk) after one light Settings shot.
- **Text box editor in dark**: changed in code; an on-screen check needs a key window.
- **Tool-group chevrons** stay 37 pt wide: macOS 26/27 gives toolbar segments a minimum width
  (`setWidth(14)` is ignored); the default window width was raised instead.
- **Toolbar menus while the app is inactive** show their items disabled without swatches
  (first-responder validation with no key window); with the app active they should show swatches.
  Not checked with the app active (owner present).
- A stray drawing appeared once in the open signature pad during the walkthrough (pointer input
  that wasn't ours); the sheet was cancelled, nothing saved.

### Shared components built in-app (SlopKit candidates)

`ListSelectionHighlightRemover` (turn off a SwiftUI List's selection pill for rows that draw
their own selection), `PressDimmingButtonStyle`, `NSColor.readableSymbol` (SlopKit's
`readableText` is internal; a public "readable on this surface" colour would cover both).

## Feature round: editing, forms, certificates, crop, compare, Office (2026-11-12)

The owner compared Paper with the original and listed gaps users notice: editing existing text
and images, making forms (with calculations), Word export, certificate signatures (and checking
them), crop and compare. This round closes all of them with Apple frameworks only (PDFKit,
CoreGraphics, CoreText, Security, CryptoKit, SecurityInterface for the certificate viewer). It
reverses the inventory's earlier calls on rows 16 (compare), 45 (digital ID signatures),
47 and 51 (signature fields, creating fields), 53 (form JavaScript: Paper now runs the standard
calculations itself and writes them for other viewers, but still never runs a document's own
scripts), 65 (crop), 94 and 95 (editing text and images).

### More PDFKit facts (macOS 27.2)

| # | Fact | What we did |
|---|---|---|
| P24 | `PDFDocument.dataRepresentation()` writes new widgets but never adds them to the catalog's `/AcroForm /Fields` (it doesn't create an `/AcroForm` at all), so Acrobat and other viewers don't treat them as form fields. An existing `/AcroForm` is kept, without the new fields. | `AcroFormWriter` runs after every save as an **incremental update** (Paper's own small PDF object parser and writer, `PDFSyntax`): registers every field, adds `/DA` and `/DR` (Helv, ZaDb). Idempotent, so a second save adds nothing. |
| P25 | PDFKit has no JavaScript action and crashes when `/AA` is set as a dictionary (`-[__NSSingleEntryDictionaryI createDictionaryRef]`). Untouched `/AA` from a file is passed through; it isn't exposed to the annotation model. | Calculations live in Paper's `FormScripts` (read back from the file's `/AA /C` and `/CO` with `PDFSyntax`) and are written by `AcroFormWriter`: `AFSimple_Calculate` for sum/product/average/min/max, Acrobat's `BVCALC … EVCALC` simplified-field-notation form for formulas, `AFNumber_Format`/`Keystroke` for decimals. Scripts Paper doesn't understand are kept and re-written as they were. |
| P26 | For widgets added to a *loaded* document (and any widget PDFKit rewrites after a change), the writer emits `/DA` as an invalid **name**, button `/V` as a string, no `/AS`, a single baked appearance instead of on/off states, empty `/MK` and `/BS`, and separate same-named radio fields. Reopened, radio export values are lost ("plan Yes"). Setting `widgetFieldType` after `fieldName` resets the name to "text0". | `AcroFormWriter.repair` fixes each widget from Paper's in-memory state (`WidgetState`, matched by page and rect): string `/DA`, `/MK` colours, on/off appearance streams (drawn paths) with `/AS`/`/V`, `/Opt`; same-named buttons become one radio group with `/Kids`. This also fixes form *filling* of existing forms, which had the same problem before this round. The field factory sets the type first. |
| P27 | `PDFPage.attributedString` reports the real font when it's installed but **Helvetica** for any font that isn't (the PDF's name is lost). Fill colour is reported. | `ContentScanner` (CGPDFScanner, follows form XObjects) reads each text run's `/BaseFont`, size and baseline; `FontMatcher` uses the installed font, the same family, or the closest serif/sans/mono with matching weight and slant, and says when it's not the document's font. macOS maps some names to stand-ins (Calibri → Carlito); those count as substitutes. |
| P28 | A `Redact` annotation over text also removes **vector fills** under it (a hole in a coloured box) and **zeroes** image pixels (a fully covered image stays in the content as black). | Content edits repaint the removed area with the most common colour around it (`ContentEditor.backgroundColor`), 1 pt past image edges so no anti-aliased outline shows; the scanner ignores images covered by an opaque filled rectangle, so a removed picture's remains can't be selected. |
| P29 | PDFKit never draws a **text field's border** (live or rendered) whatever the property order; only the background. | Saved text fields get an appearance that wraps PDFKit's (keeping its text drawing) and adds the border; the Forms tool outlines every field on screen while authoring. |
| P30 | `NSSharingServicePickerToolbarItem` asks its delegate for items during toolbar validation, not only on click. Paper's handler called `commitEditing()`, which closed any open text editor (text boxes too, before this round) whenever the toolbar validated, and wrote a temporary PDF each time for edited documents. | The toolbar query no longer ends editing; the share copy is cached until the document changes. |

**Checked on macOS 26 in CI** (GitHub runner, macOS 26.7, SDK 26.5). The first CI run failed 10
expectations; a diagnostic run showed page copies, writes, rewrites, in-place redaction and the
content scanner behave the same as on 27. The real differences:

| # | Fact (macOS 26) | What we did |
|---|---|---|
| P31 | A `PDFPage` doesn't keep its document's content alive: a page taken from a document that's then released draws, copies and scans as **empty** (on 27 it still works). | No app path does this (editing works on pages of open documents, and keeps its temporary documents alive while drawing). The new tests had used `doc(…).page(at: 0)!`; they now hold the document. |
| P32 | PDFKit writes a widget's `/AP` and `/MK` as **indirect references** (27 writes them inline), and once a radio button is on it writes the group's parent field itself, **without the radio flags**. | `AcroFormWriter` resolves references before repairing, and gives a radio group's parent the radio flags whatever wrote it (a hand-written test PDF covers the shape). |

Nothing needed an OS gate: all 189 tests pass on macOS 26 and 27 (final CI run 43361354017).

### What was built, and how it fits

| Gap | Paper now | Where |
|---|---|---|
| Edit existing text | **Edit** tool group (⌘7): hover outlines paragraphs and pictures; click a paragraph to edit it in place in a rich-text editor at the page's zoom, fonts/colours/alignment/line spacing matched, on the page's background colour; Esc or a click outside commits. The page is rebuilt: old glyphs removed (P1), area repainted (P28), new text drawn as real text (CoreText, embedded subset), re-wrapped to the paragraph width; one undo step that swaps the page back. Editing bar: the font in use, or a warning naming the missing font and the substitute. Longer text that runs past the paragraph gets a HUD warning. | `ContentScanner`, `TextLayout`, `FontMatcher`, `ContentEditor`, `CanvasController.beginContentEditing` |
| Edit images | Click a picture: handles to resize (aspect kept; Shift stretches), drag to move, Replace Image…, Delete Image (⌫), Add Image… Moving draws the picture from a copy of the page with everything outside it removed, so the result is the original pixels (any colour space, masks) with nothing else leaking. | `ContentEditor.moveImage/replaceImage/deleteImage/addImage` |
| Create form fields | **Forms** tool group: Text Field, Checkbox, Radio Button (new buttons join the last group with a new value), Dropdown, Signature Field; click or drag; fields selectable/movable/resizable only in this tool; editing bar has the name; Inspector > Selection is the field's properties (name/group, tooltip, required, read only, several lines, choices, value when on); **Fields** sidebar (⌥⌘5) lists fields in tab order per page with drag-to-reorder and Order by Position. Every field gets its name as tooltip, so screen readers (and `drive tree`) announce it. | `FormFieldFactory`, `FormFields`, `FieldPane`, `FieldList` |
| Calculated fields | Inspector > Calculation: typed in, sum/product/average/min/max of chosen fields, or a formula with validation ("No field is named …"); decimals. Live in Paper (recalculated with every form change, undone with it, in dependency order); written as standard form scripts (P25). | `FormScripts`, `FormMath`, `FormulaParser`, `FormJavaScript`, `AcroFormWriter` |
| Word / RTF | File > Export as Word Document…: Paper writes the .docx package itself (stored ZIP + WordprocessingML) from the same text blocks as editing, in reading order with pictures between paragraphs; AppKit's own Office writer drops images. Export Text… has Plain Text / Rich Text (RTF). Fonts PDFKit couldn't name keep the PDF's family in Word. | `OfficeExport`, `ZipWriter` |
| Certificate signatures | Sign ▸ Sign with Certificate… (or click an empty signature field): certificate (keychain identities, code-signing-only ones hidden, expired flagged), reason, location, optional handwritten ink; drag the box; save panel for a **new file**; signed and re-verified before the report sheet. CMS SignedData built in Paper (DER) with ESS signing-certificate-v2, SubFilter `ETSI.CAdES.detached`, byte range over an incremental update; appearance drawn as outlines (name) plus standard Helvetica text (details). With no unsaved changes the update is appended to the file on disk, so earlier signatures stay valid (countersigning). | `ASN1`, `CMS`, `PDFSigner`, `SignatureAppearance`, `EditingFlows.finishCertificateSigning` |
| Signature validation | On open: every signature checked with Apple's `CMSDecoder` (independent of Paper's encoder) plus byte-range coverage and trust (SecTrust); info bar summarises (valid / changed after signing / altered / untrusted certificate); Inspector > Security lists each with reason, location, issuer and Show Certificate… (system viewer). | `SignatureValidator`, `SignatureRow` |
| Crop | Crop tool (⌘K, Preview's key; Edit group, Pages menu): drag the area, the rest dims; Crop This Page / Selected Pages / All Pages (Return = this page), Remove Crop; crop box only, so it's undoable and reversible. | `PageCrop`, `DocumentEditor.crop` |
| Compare | File > Compare With… (⌥⌘K): window with both versions side by side (snapshots), word-level diff of the whole text mapped back to pages, removed/added tints, list of differences with ⌘↑/⌘↓. | `DocumentCompare`, `CompareWindowController` |

### Decisions (made in this round, and why)

1. **Edits rewrite the page right away** instead of staying pending until save: undo is a page
   swap, re-editing works on the new text, and nothing old can survive in a save. Same removal
   as redaction, so "the old text is truly gone" holds.
2. **Paragraph-level editing** (lines grouped by size, spacing and overlap; alignment detected),
   not single lines or whole pages: fixing a sentence re-wraps naturally; nothing else moves.
3. **Font honesty over a silent match**: the editing bar names the document's font when Paper
   can't use it. Reusing embedded subset fonts was left out (missing glyphs, broken cmaps).
4. **Moving an image re-draws the original page clipped to it** (after removing everything else)
   rather than decoding the image: exact pixels, no colour-space code, no leaks.
5. **Paper's own incremental writer** (`PDFSyntax`) rather than more PDFKit workarounds: forms
   and signatures need exact bytes, and appending never disturbs earlier signatures.
6. **Signed output is always a new file** (default "name (signed).pdf"), verified before success,
   like redaction. Signing PDFs with an open password is refused with an explanation.
7. **No network for signatures** (no timestamp server, no revocation checks): Slopapp's no-network
   rule; the signing time comes from this Mac and the README says what's missing.
8. **Tool keys**: Edit ⌘7 (the slot the menu plan left free), Crop ⌘K (Preview's), Compare ⌥⌘K;
   Form Fields has no single key (rare task; toolbar group and Tools menu).
9. **Tests never touch the login keychain**: unit tests sign with an in-memory key and
   certificate (`TestSigner`); app runs list identities from `PAPER_SIGNING_KEYCHAIN` only.

### Gates (this round)

- **Unit tests: 188 in 36 suites, all pass** (138 before; 50 new): PDF syntax (parse/serialize,
  classic and stream cross-references, incremental updates, deflate), form fields (every kind
  persists, AcroForm registration, radio grouping across saves, tab order, names, appearances
  with borders, tooltips), calculations (formulas, aggregates, run order, JS round trip, rename,
  written for other viewers and read back), certificate signatures (cert parse, sign + verify
  with CMSDecoder, tampering, later changes, countersigning, existing field, appearance, dates),
  content editing (blocks, text replace with font/colour/baselines, background repaint, image
  move/replace/delete/add, no ghosts, font matching incl. stand-ins), crop, compare, Office
  export (docx read back by AppKit, page breaks, fonts, RTF, CRC32).
- **Independent tools**: Poppler `pdfsig` validates Paper's signatures (ETSI.CAdES.detached,
  "Signature is Valid", countersigned file: first "not total document signed", both valid;
  tampered: "Digest Mismatch"); OpenSSL `cms -verify` on the extracted CMS; `pdfinfo` reports
  `Form: AcroForm` and prints the calculate/format scripts; `pdftotext` shows edited text with no
  trace of the old words; `textutil` reads the .docx in reading order; `pdftoppm` renders the
  signature appearance.
- **`scripts/check.sh Paper --perf`**: lint, icon, test, bundle, smoke, catalog pass. Perf:
  launch 127 ms, idle CPU 0.017–0.019 %, footprint 18.6–19.0 MB pass; **first window
  622–633 ms fail at load 17–22** (nine builders compiling). The first window is the system Open
  panel; this round doesn't touch the launch path (AppDelegate, DocumentController, main
  unchanged). Same borderline as the build, parity and polish passes (596–626 ms at load 5–9).
  No installed copy of Paper was running, so perf measured this build.
- **Accessibility**: `scripts/drive tree` at all 32 walk states: no `[unlabeled]` Paper
  controls; the only unlabeled elements were PDF fields, and fields Paper creates now carry
  their names (tree shows `textField "qty"`, `checkBox "Checkbox 1"`, `popUpButton "Signature 1"`).
- **Lint**: pass, 0 warnings.

### Walkthrough (release build, `/tmp/paper-test/`, light and dark)

The owner was at the Mac for most of the session, so the main walk used the review walk
(`PAPER_SNAPSHOT_ONLY=features` + `PAPER_SNAPSHOT_HANDSHAKE`): Paper drives its own controller
code in both appearances while `scripts/drive shot` captures each state from outside (32 PNGs,
`/tmp/paper-test/shots/walk/`), with a log of results. Real-pointer steps ran only after 60 s
without input, one action per check (`/tmp/paper-test/shots/m*.png`).

| Feature | Result |
|---|---|
| Edit text (walk + real click and typing) | Editor opens over the paragraph (Times New Roman 13 pt, blue, three lines); "untouched" → "unchanged"; committed page shows it in the same font, colour and baselines; undo/redo; `pdftotext` has no "untouched". After fixing P30 and the scroll restore, the canvas offset is identical before and after a commit (walk log). |
| Missing font | Calibri (not embedded, not installed): bar says "“Calibri Bold” isn't on this Mac. Paper uses Carlito Bold, the closest it has." |
| Images (walk + real drag) | Selected with handles and Replace/Delete bar; moved and resized; old spot clean; one image left on the page. |
| Forms (walk + real drag) | Drag created "Text 1"; walk built qty/price/total + checkbox + radio group + dropdown + signature field; total calculated live to 13.50; inspector Field and Calculation sections; Fields sidebar with tab order and the fx badge; saved file: `Form: AcroForm` with scripts. |
| Crop (walk + real drag + Return) | Dimmed outside, Crop This Page/All Pages; crop box `{40, 380, 532, 350}`; thumbnail and fit follow. |
| Certificate signing (walk + full UI) | Sheet lists "Paper Test Signer (until Dec 12, 2026)" from the temporary keychain; Choose Where… → drag box → save panel (test folder) → "Signed … Checked: the signature is valid and covers the whole file", with the untrusted-certificate note; `pdfsig` valid. |
| Validation on open | Signed file: info bar and Inspector > Security "Signed by Paper Test Signer … The certificate isn't from an authority this Mac trusts", reason/location, Show Certificate…; tampered copy: "The document was changed after Paper Test Signer signed it. This signature is no longer valid." |
| Compare | text.pdf vs text-revised.pdf: 3 differences ("public" → "revised", "redaction." → "review.", line removed on page 3), tinted on both sides. |
| Word export | `editable.docx` with heading, paragraph, tinted line, picture and caption in order; one picture after the ghost fix. |

**Not walked with the real pointer** (owner present, then a system automation overlay covered
the screen): hover outlines, resizing an image by its corner, Add/Replace Image (Open panel),
dragging rows in the Fields sidebar, Export as Word through the menu (save panel), Compare With…
through the menu (Open panel), clicking an empty signature field. They share the code paths the
walk and unit tests exercise.

**Signing test identity**: a self-signed certificate (OpenSSL) imported into a temporary keychain
file `/tmp/paper-test/sign/test.keychain-db`; the user keychain search list was checked before
and after creation (unchanged: login only). The keychain and key files were deleted at the end.

### Shared components built in-app (SlopKit candidates)

`ZipWriter` + `CRC32` (stored ZIP; any app exporting packages), `DER` (minimal ASN.1), and the
offscreen-walk handshake in `FeatureWalk.capture` (an outside-screenshot hook other apps' snapshot
walks could share). `PDFSyntax`, `AcroFormWriter`, `CMS`/`PDFSigner` are PDF-specific and stay.

### Risks

- Content edits, like redaction, rely on PDFKit's `Redact` behaviour (P1). On a macOS version
  where it doesn't remove text, an edit would leave the old text under the new (the unit tests
  would fail on that version's CI).
- `AcroFormWriter` matches widgets to Paper's state by page and rectangle; two fields stacked
  exactly on top of each other could swap repairs.
- Signatures from Paper have no trusted timestamp; viewers show the signing time as the
  signer's clock. Acrobat shows Paper's self-signed test certificate as unknown, as expected.
- The incremental writer handles classic and stream cross-references and object streams, but
  not encrypted files (signing them is refused; their forms keep PDFKit's limits).

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (<date>)
| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
