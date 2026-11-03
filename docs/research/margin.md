# Margin research (inspired by SideNotes)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied:
> SideNotes 1.6 (Apptorium; not installed on this Mac) from its product and features pages,
> Mac App Store listing, release notes and reviews, on 2026-11-03. We never copy its name,
> icons, artwork, wording, sounds or signature visuals.

## The job

Margin is scratch paper at the edge of the screen. While working in another app you need
to jot a phone number, keep a to-do list for today, park a snippet you'll paste five times,
or keep a meeting's notes visible next to the call. Opening a full notes app breaks focus;
Margin slides in from the side, takes the text, and slides away. "Done" is the thought
written down within two seconds and the previous app still focused underneath.

The one interaction that matters most: **press a shortcut (or nudge the screen edge), a
panel slides in with your notes, type, press Esc, it's gone and saved.**

## Who and when

- Today's checklist, ticked off through the day.
- A number/address/code from a call, jotted without leaving the call.
- Snippets reused many times (a reply template, a command).
- Notes beside a video call or a lecture.

Frequency: many times a day; each 3–30 seconds.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Panel at the screen edge | Click a thin "open bar" on the side, a "hot side" trigger, the menu bar icon, or a global shortcut (⌃⌥⌘ by default); switch left/right by right-clicking the bar | must (shortcut, icon, side) / should (hot edge) | SlopKit `FloatingPanel` docked to the right edge of the pointer's display, full visible height, ~320 pt wide (resizable). Non-activating: the previous app stays active. Default shortcut ⌥⇧N. Hot edge = pointer pressed against the edge for 0.3 s (global mouse-moved monitor, no permission), off by default. No permanent on-screen bar. |
| 2 | Notes list + editor | Notes stacked as cards in the panel; edit inline | must | A list of notes (title = first line, preview, relative date); select to edit in place; ⌘N new note focused immediately. |
| 3 | Autosave | Implicit | must | Save on every pause (debounced 0.5 s) and on hide/quit. Never a Save button. |
| 4 | Markdown with hidden markup | Markdown rendered with syntax hidden (1.5.1), toggle to show it | must (light styling) / later (hidden markup) | Store plain Markdown. v1 styles headings, bold/italic, lists, code, links in place with the markup dimmed (`.tertiary`), not hidden: simpler and lossless. |
| 5 | Checklists | Tasks; completed move to the bottom (1.6.3) | must | `- [ ]` lines render a clickable checkbox; ⌘↩ toggles the current line. Completed sink to the bottom: should. |
| 6 | Folders | Folders for projects, snippets, links; move notes by shortcut | should | v1: one list. Folders are subfolders on disk (cheap); add if time allows. |
| 7 | Pin and fold notes | Pin to top, collapse long notes (1.6) | should (pin) / later (fold) | |
| 8 | Note colors | Color stripe via a gear button | later | System colors only if we add it. |
| 9 | Search | Built-in search | must | ⌘F filters notes by text, live. |
| 10 | Images, files, file links | Drag in pictures, screenshots, file shortcuts | should | Images saved next to the note (`assets/`) and referenced in Markdown; files as links. |
| 11 | Code blocks, paste-as-code detection | Detects pasted code (1.6.3) | later | Monospaced styling for fenced blocks is in #4. |
| 12 | Quick copy | One-click copy of a note or code/link | should | Hover button + ⌘⇧C copies the whole note. |
| 13 | Move lines up/down | Shortcut (1.6.3) | should | ⌥⌘↑/↓. |
| 14 | Themes, fonts, text size | Built-in themes, theme editor, font choice | skip (themes) / should (text size) | System materials and text styles; ⌘+/⌘− text size. |
| 15 | iCloud sync and iOS app | iCloud sync; mobile app sold separately; local backups | skip (our own sync) | Plain Markdown files in a folder: the user can choose a folder in iCloud Drive and macOS syncs it with zero network code from us. |
| 16 | Shortcuts, AppleScript, URL API, Alfred/Raycast | All of them | later | App Intents "Add to note" later. |
| 17 | Share, print, export as image | Share extension, print, image export | later (Share) / skip (image export) | Notes are already .md files. |
| 18 | Works over full-screen apps | Yes; users wanted auto-hide in full screen | must | `.canJoinAllSpaces` + `.fullScreenAuxiliary`. |
| 19 | Delete with undo | Not described | must | Move note file to the Trash; ⌘Z restores. |
| 20 | Launch at login / Show in menu bar | Launch on startup | must | SlopKit General. Launch at login off by default. |

### Must-haves, counted

1 edge panel (shortcut, icon, side), 2 list + editor, 3 autosave, 4 light Markdown,
5 checklists, 9 search, 18 full-screen, 19 delete + undo, 20 General. Nine.

## Key flows

### Flow 1: jot (main job)
1. In any app, press ⌥⇧N. The panel slides in from the right edge (fade under Reduce
   Motion) in < 100 ms, keyboard focus in the last-edited note with the cursor at its end.
2. Type. Saved continuously.
3. Esc (or ⌥⇧N again, or a click outside) hides it. The previous app is still active.

### Flow 2: new note and checklist
1. Panel open → ⌘N: a new empty note at the top, focused.
2. Type "Today", Return, "- [ ] call bank". The checkbox appears; ⌘↩ ticks it.

### Flow 3: first run
1. Launch: status icon only; the first open shows one welcome note explaining the
   shortcut and checklists (a real note the user can delete).
2. Notes folder defaults to `AppPaths.applicationSupport/Notes`; Settings offers
   "Choose Folder…" (e.g. iCloud Drive) with a one-line explanation.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Shortcut | ⌥⇧N | recorder | must |
| Side | right | left, right | must |
| Open when pointer pushes the screen edge | off | toggle | should |
| Panel width | 320 pt | drag the inner edge | should |
| Notes folder | Application Support/Notes | Choose Folder… | must |
| Text size | system | smaller/larger (⌘−/⌘+) | should |
| Launch at login / Show in menu bar | off / on | toggles | must |

## Menus and shortcuts

Status menu: Show Notes ⌥⇧N · New Note · — · `MenuFooter`. In the panel: ⌘N new, ⌘F
search, ⌘↩ toggle checkbox, ⌘⌫ delete note (undoable), ⌘Z/⇧⌘Z, ⌘B/⌘I bold/italic,
⌥⌘↑/↓ move line, ⌘⇧C copy note, ↑/↓ in the list, Esc hide (or clear search first).

## Permissions and system integration

None required. Files live in the notes folder. If the user picks a folder in iCloud
Drive, we watch it with a file presenter/`DispatchSource` so edits from another Mac show up.

## UX patterns worth adopting

- **Out of the way, never a window to manage**; it lives at the edge and leaves with Esc.
- **Lands where you left off** (cursor at the end of the last note).
- **Markdown as storage**, styled in place, so notes are portable and greppable.

## What we won't copy, and what we'll do better

- Not copying: name, icon, the always-visible side bar, themes, the image export.
- Better: no visible bar eating screen edge by default (a review asked for hotkey-only);
  plain files instead of a database (sync via any folder, no lock-in); no network; undo for
  deletion; focus never stolen from the app underneath when hiding.

## Edge cases

- Multiple displays: open on the pointer's display; remember width per side.
- Full-screen apps, Stage Manager, Mission Control while open.
- Very long notes (1 MB) and many notes (2,000): list loads lazily; search off the main actor.
- File changed on disk by another app or iCloud while open (reload if unedited; keep both if conflicted: write "Note (conflict).md").
- Folder removed/unmounted (iCloud evicted): explain and offer to pick again.
- Non-English input methods (Japanese IME composing when Esc is pressed: Esc must cancel composition, not hide).
- Dark/light, increased contrast, VoiceOver reading checkboxes as checkboxes.
- Quit mid-edit: flush on `applicationWillTerminate`.

## Our v1 scope

- [ ] ⌥⇧N / status icon toggles an edge panel over any app and Space; Esc hides; previous app keeps focus.
- [ ] Notes list + in-place editor; ⌘N; autosave to `.md` files.
- [ ] Light Markdown styling (headings, emphasis, lists, code, links) with dimmed markup.
- [ ] Clickable checkboxes; ⌘↩ toggles.
- [ ] ⌘F search across notes.
- [ ] Delete to Trash with ⌘Z.
- [ ] Notes folder setting (Choose Folder…), external changes picked up.
- [ ] Settings: General (launch at login, show in menu bar, side, folder), Shortcuts, About.
- [ ] Unit tests: Markdown styling ranges, checkbox toggling, note naming/titles, file store (create/rename/delete/conflict), search.

## Open questions

Decisions (owner defaults, 2026-11-03: native, fast, private, no network):

1. **Storage:** plain Markdown files, one per note, in a user-choosable folder. Sync is the
   folder's business (iCloud Drive etc.), not ours.
2. **No always-visible edge bar.** Shortcut and status icon; hot edge is an opt-in setting.
3. **Folders:** should (subfolders on disk); v1 ships one list if time is short.
4. **Default shortcut:** ⌥⇧N.

## Sources

- [SideNotes](https://www.apptorium.com/sidenotes)
- [SideNotes features](https://www.apptorium.com/sidenotes/features)
- [SideNotes on the Mac App Store (version history, reviews)](https://apps.apple.com/us/app/sidenotes-screen-edge-notes/id1441958036?mt=12)
- [AlternativeTo: SideNotes improves Markdown editor, folding, pinning](https://alternativeto.net/news/2026/5/sidenotes-improves-markdown-editor-note-folding-and-pinning-and-more-for-macos-and-ios-users/)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
