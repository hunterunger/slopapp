# Shelf research (inspired by Yoink)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: Yoink
> for Mac 3.7 (Eternal Storms; not installed on this Mac) from its product page, usage
> tips, Mac App Store listing and version history, plus comparisons with Dropover and other
> shelf apps, on 2026-11-03. We never copy its name, icons, artwork, wording, sounds or
> signature visuals.

## The job

Shelf is a temporary parking spot for things you're dragging. Dragging a file from one
place to another is easy when both are visible; it's miserable when the destination is in
another app, another Space, behind a full-screen window, or not open yet. People reach for
a shelf many times a day: start a drag, drop it on the shelf that appears at the screen
edge, go find the destination, drag it back out. "Done" is the file landing where it
should without rearranging a single window.

The one interaction that matters most: **start dragging anything; a slim shelf slides in
at the screen edge; drop; later drag it out of the shelf to its destination.**

## Who and when

- Collecting attachments from Mail and Finder to upload in a browser form.
- Moving a file into a full-screen app or another Space.
- Gathering images from several web pages, then dropping them all into a doc.
- Holding a file you'll reuse several times (a logo dropped into many emails).

Frequency: several times a day; each park/unpark 2–10 seconds.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Shelf appears when a drag starts | Appears on any drag: immediately at the screen edge, only when the cursor nears the edge, or at the cursor | must | Global `NSEvent` monitor for `.leftMouseDragged` (no Accessibility needed for mouse events) + `NSPasteboard(name: .drag).changeCount` check, so window moves and text selection never trigger it. Default: appears at the edge nearest the pointer when a drag starts; hides again if the drag ends without a drop and the shelf is empty. |
| 2 | Holds files and app content | Files from Finder plus text/images/links from apps | must | Files: store a bookmark (`URL.bookmarkData`), not a copy, so moving/renaming the original still resolves. Content (text, images, web links, file promises via `NSFilePromiseReceiver`): written to `AppPaths.applicationSupport/Items/`. |
| 3 | Drag out | Finder semantics; ⌥ forces copy, ⌘ forces move | must | Provide file URLs; the destination decides copy/move as Finder does. Multi-select drags all selected. |
| 4 | Remove after drag-out; lock to keep | Moved-out items leave the shelf unless locked; ⌥-click to lock/unlock all | must | Default removes after a successful drag-out; "Keep" (pin) per item keeps it. |
| 5 | Recall removed items | Long-press the shortcut to bring back moved-out files | should | ⌘Z in the shelf and "Recently Removed" (last 20, in memory). |
| 6 | Show/hide by shortcut | Tap the shortcut (F5 default) | must | Default ⌥⇧S, rebindable. Also a click on the status icon. |
| 7 | Stacks | Multiple files dropped together form one stack, draggable as a group, expandable | should | One row "12 files" with a fan of thumbnails; drag moves all; click expands. |
| 8 | Quick Look | Icon or full previews; pinnable Quick Look panel | must | Space opens `QLPreviewPanel` for the selection; thumbnails via `QLThumbnailGenerator`. |
| 9 | Item actions | Show in Finder, Open With, rename web images/text snippets, Share sheet, AirDrop | must (Open, Show in Finder, Copy, Remove) / should (Share, Rename) | Context menu + keyboard: Return opens, ⌘R reveals, ⌘C copies, ⌫ removes. |
| 10 | Drop onto the status icon | Menu bar icon accepts drops | should | `NSStatusItem` button as a drag destination. |
| 11 | Ignored apps | Shelf won't auto-appear for drags in chosen apps; shortcut still works | should | Default list: none. Useful for design tools that drag constantly (Figma, Photoshop). |
| 12 | Clipboard history | Built-in history with widget, password managers excluded | skip | Clips already does this. |
| 13 | Handoff / iPhone / Continuity Camera / iCloud | Yes, with a separate iOS app | skip | Network/accounts; not the job. Continuity Camera import → later. |
| 14 | Services / Quick Action / Share extension / Terminal `open -a` | "Add to …" service, share extension, `open -a` | later (`open -a Shelf file` works for free) | A Finder Quick Action is a cheap later add. |
| 15 | Trash warning | Warns when an item's original is in the Trash (mutable) | should | Item shows a "missing" or "in Trash" state instead of a broken drag. |
| 16 | Shelf position | Left/right edge, cursor position; multi-display handling | must (edge nearest pointer, on the pointer's display) / should (fixed side setting) | |
| 17 | Clear all | Context menu | must | ⌘⌫ clears (undoable). |
| 18 | Launch at login / Show in menu bar | Yes | must | SlopKit General. Launch at login: off by default. |

### Must-haves, counted

1 auto-appear on drag, 2 files + content, 3 drag out, 4 remove-after-drag + keep,
6 shortcut, 8 Quick Look, 9 basic actions, 16 placement, 17 clear, 18 General. Ten.

## Key flows

### Flow 1: park and unpark (main job)
1. Start dragging a file in Finder. Within ~150 ms of the drag moving, a 96 pt-wide shelf
   (SlopKit `FloatingPanel`, non-activating, `.canJoinAllSpaces` + `.fullScreenAuxiliary`)
   slides in at the screen edge nearest the pointer, vertically centered on it. (Fade only
   under Reduce Motion.)
2. Drop on the shelf. A row appears: thumbnail, name, size. Keep dragging more if you like.
3. Switch apps/Spaces freely; the shelf stays visible until dismissed (Esc when focused,
   the shortcut, or clicking the icon) if it holds items, and auto-shows on the next drag.
4. Drag the row out to the destination. On a successful drop it leaves the shelf (unless
   kept); ⌘Z in the shelf brings it back.

### Flow 2: first run
1. Launch: status icon only. No permission needed.
2. The status menu's top line reads "Drag anything to the screen edge to park it", plus
   Show Shelf (⌥⇧S). That's the whole onboarding.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Show shelf when dragging | on | on / only near the screen edge / off (shortcut only) | must |
| Side | nearest edge | nearest, left, right | should |
| Remove items after dragging out | on | toggle | must |
| Shortcut | ⌥⇧S | recorder | must |
| Ignored apps | none | list | should |
| Launch at login / Show in menu bar | off / on | toggles | must |

## Menus and shortcuts

Status menu: Show Shelf ⌥⇧S · Clear Shelf · — · `MenuFooter`. In the shelf: arrows select,
Space Quick Look, Return open, ⌘R Show in Finder, ⌘C copy, ⌫ remove, ⌘⌫ clear, ⌘Z undo,
⌘A select all, Esc hide.

## Permissions and system integration

None required: mouse-event global monitors and the drag pasteboard don't need
Accessibility. Files are reached through bookmarks; no Full Disk Access. Reading files in
Desktop/Documents/Downloads to make thumbnails may trigger macOS's folder-access prompt
once; that's expected (we only read what the user dropped).

## UX patterns worth adopting

- **Appear only when needed**, at the edge closest to where the hand already is.
- **References, not copies**, so nothing duplicates disk space; content-only drags get a file.
- **Self-cleaning**: items leave once delivered; "keep" is opt-in.
- **Works across Spaces and over full-screen apps**: the whole point.

## What we won't copy, and what we'll do better

- Not copying: name, icon, look of the shelf, sounds, iOS/Handoff features, tipping.
- Better: no clipboard history (privacy; Clips does it); never steals focus (Yoink's
  changelog shows repeated focus-stealing fixes); a clear missing/trashed state; undo for
  every removal; no network.

## Edge cases

- Drags that aren't files: text selections, browser images (file promises that resolve
  late: show a spinner row until written), links (store as `.webloc`), colors.
- Huge drops (500 files): stack them; thumbnails lazy.
- Original moved/renamed (bookmark resolves) vs deleted (missing state, can't drag out).
- External drive ejected while an item is shelved.
- Multiple displays: shelf on the pointer's display; display unplugged while visible.
- Full-screen apps, Stage Manager, Mission Control drags.
- Drag cancelled (Esc) with empty shelf: hide again.
- Drags from the shelf onto itself (ignore); dropping a shelved file into Trash.
- App quit with items: items persist across relaunch (bookmarks + content folder).
- Content files cleaned up when removed (no orphans in Application Support).

## Our v1 scope

- [ ] Shelf appears on file/content drags (drag pasteboard check), at the nearest edge, on the pointer's display, over full-screen apps.
- [ ] Drop files (bookmarks) and content (written to Application Support).
- [ ] Drag out one or many; removed after successful drop unless kept; ⌘Z restores.
- [ ] Quick Look (Space), Open, Show in Finder, Copy, Remove, Clear; all in menus with shortcuts.
- [ ] ⌥⇧S toggles the shelf; status icon toggles too.
- [ ] Missing/trashed item state.
- [ ] Items persist across relaunch.
- [ ] Settings: General (launch at login, show in menu bar, show-on-drag mode, remove after drag), Shortcuts, About.
- [ ] Unit tests: item model, bookmark resolution, content writing, keep/remove rules, undo stack, placement math.

## Open questions

Decisions (owner defaults, 2026-11-03: native, fast, private, no network):

1. **Remove after drag-out:** on by default, with Keep per item and undo.
2. **Clipboard history:** skip (Clips).
3. **Stacks:** should; v1 may show multi-file drops as separate rows.
4. **Default shortcut:** ⌥⇧S (same family as Clips' ⌥⇧V, Dropper's ⌥⇧C).

## Sources

- [Yoink for Mac](https://eternalstorms.at/yoink/mac/)
- [Yoink usage tips](https://eternalstorms.at/yoink/mac/tips/)
- [Yoink on the Mac App Store (version history, reviews)](https://apps.apple.com/us/app/yoink-improved-drag-and-drop/id457622435?mt=12)
- [Mac Power Users: Dropover shelf thread](https://talk.macpowerusers.com/t/dropover-mac-shelf/18201)
- [MacRumors: is Yoink the same as the NeXTSTEP shelf](https://forums.macrumors.com/threads/is-yoink-the-same-thing-as-nextstep-os-shelf.2232293)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
