# Clips

Clipboard history you can search.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Paste.

**Status:** beta

## What it does

Clips remembers what you copy: text (with its formatting), links, colors, images and
files. Press **⇧⌥V** in any app and a strip of cards slides up along the bottom of the
screen, newest on the left. Type a few letters, press **Return**, and the clip is pasted
into the app you were using. A soft paper flick tells you each copy was saved, and a quiet tap when Clips pastes one
for you. Settings › General turns either off or picks another pair: Paper, Glass, Wood,
Bubble, Snap, Pluck or Classic. They're all Clips' own sounds, made in code, and they stay
quiet when macOS sound effects are off.

- **Cards** show what kind of clip it is, which app it came from and when, over a big
  preview: the text itself, the image, a link with its page title (when the app you copied
  from provided one; Clips never fetches anything), a color swatch, or the file.
- **Search** matches every word you type, ignoring case and accents, and highlights the
  matches. It looks through the first million characters of every clip, the titles you give
  clips, and the text in images (screenshots included): an image card shows the words it
  matched. When a match is further in than a card can show, the card shows the words around it.
- **Text in images** is read on your Mac with Apple's Vision, a moment after you copy, one
  image at a time in a separate helper process that quits when it's done (so Clips stays
  small). Images you copied before this version are read in the background. Right-click an
  image card and choose Copy Text in Image to get the text.
- **Tabs** next to the search: All, your boards, then Text, Links, Images and Files (⌘← ⌘→).
- **Boards** keep the clips you reuse, by name and colour ("Addresses", "Work"). Clips on a
  board are pinned: never removed automatically. ⌘P pins to the first board (Pinned, to
  start with), ⌥⌘1–⌥⌘9 to that board, or drag cards onto a board's tab (or onto + for a new
  one). + or ⇧⌘N makes a board; double-click its tab to rename it, right-click to change its
  colour, move it or delete it (its clips stay in your history). In the History window, drag
  boards in the sidebar to reorder them.
- **Titles and edits**: ⌘R gives a clip a title, shown on its card and searched. ⌘E edits a
  text clip in the preview; what you save is what pastes. Formatted text keeps its
  formatting; text whose only formatting came from a web page is saved as plain text (the
  editor says so). ⌘S or ⌘Return saves, Esc throws the changes away.
- **Several at once**: ⌘-click, ⇧-click, ⇧-arrows or ⌘A select several cards. Return pastes
  them together in the order you copied them (text one per line; all files or all images
  paste as files or images), ⌘C copies them, ⌘P or a board pins them, ⌘⌫ deletes them, and
  you can drag them out together.
- **Paste stack** for filling in forms: press ⇧⌘C in the panel (or Start Paste Stack in the
  menu), copy things in order, then paste: each paste takes the next one, until the last.
  With several cards selected, ⇧⌘C stacks those and pastes the first right away. A small
  list in the top-right corner shows what's next; ✕ or ⇧⌘C stops it. It works with ⌘V,
  Edit › Paste or a right click, and needs no extra permission: Clips hands each clip over
  when an app asks for it. You can set a shortcut that works anywhere in Settings › Shortcuts.
- **Preview** (Space) opens the selected clip big, above the strip.
- **Drag** a card into any app. Drag an image card to the Desktop or a Finder window to save it as a file.
- **History window** (⌘Y in the panel, the ⋯ menu, Window › Clip History, or the menu
  bar icon): browse by kind, board or app, select several clips, copy, pin, title, edit or
  delete them.
- **Trim** spaces and line breaks from both ends of what you copy (Settings › General,
  off by default). Formatting is kept; spaces inside the text are left alone.
- **Pause** recording (⌘T, or for 15 minutes or an hour from the menu), or skip just the
  next copy.
- **Help › Clips Help** explains each feature and lists every key. While the History window
  or Settings is open, the File menu has Show Clips, New Board, Pause Recording, the paste
  stack and Clear History….

## Keyboard (in the panel)

| Key | Action |
|---|---|
| ⇧⌥V | Open or close the panel (change it in Settings › Shortcuts) |
| ← →, ↑ ↓ | Move the selection |
| ⇧← ⇧→, ⇧Home ⇧End | Select several cards |
| ⌘A | Select every card |
| ⌘↑ ⌘↓, Home End | First or last clip |
| Page Up, Page Down | Move a screenful of cards |
| Return / double-click | Paste the selected clip (or copy it, see below) |
| ⇧Return | Paste as plain text |
| ⌘1 – ⌘9 | Paste that card right away (⇧ for plain text); hold ⌘ to see the numbers |
| Space | Preview (while typing a search, press Tab first) |
| Tab | Switch the keyboard between the search and the cards |
| ⌘F | Go to the search |
| ⌘← ⌘→ | Previous or next tab |
| ⌘C | Copy only |
| ⌘O | Open a link or file |
| ⌘P | Pin to the first board, or unpin |
| ⌥⌘1 – ⌥⌘9 | Pin to that board |
| ⇧⌘N | New board |
| ⌘E | Edit the clip's text (and title) |
| ⌘R | Give the clip a title |
| ⇧⌘C | Start a paste stack (with the selected cards, if several), or stop it |
| ⌘⌫ | Delete (⌘Z brings it back) |
| ⌘T | Pause or resume recording |
| ⌘Y | Open the History window |
| ⌘, | Open Settings |
| Esc | Back out one step: the editor, a board's name, the preview, a selection of several, the search; then close |
| ⌘W | Close the panel |

Pinned clips take a second ⌘⌫ to delete. In the History window, ⌘F searches, Delete or
⌘⌫ deletes (asking first for several clips or pinned ones), ⌘C copies, ⌘E edits, ⌘R adds a
title, ⌘P and Clip › Pin to pin, and Edit › Undo (⌘Z) brings deleted clips back.

## Privacy

- Everything stays on your Mac in `~/Library/Application Support/app.slopapp.clips`
  (readable only by you). Clips makes no network connections and has no analytics.
- Passwords and anything else an app marks as private (`org.nspasteboard.ConcealedType`,
  `TransientType`, `AutoGeneratedType`) are skipped without being read.
- Copies made in ignored apps are never recorded. Password managers and Keychain Access
  are ignored out of the box; edit the list in Settings › Privacy.
- The panel and History window are hidden from screen sharing and recordings (switch in
  Settings › Privacy).

## Permissions

- **Accessibility** (optional) lets Clips press ⌘V for you, so Return pastes directly.
  Without it, Return copies the clip and you press ⌘V yourself. Clips asks only from the
  panel or Settings, never at launch.
- **Paste from Other Apps** (macOS 15.4+): if macOS is set to ask before apps read the
  clipboard, Clips says so and links to System Settings › Privacy & Security.

## Not there yet

Search filters by app or date (the History window browses by app), reordering clips within
a board, a paste stack that pastes in reverse, formatted text on the cards (the preview
shows it), a resizable strip, and a switch for iPhone (Universal Clipboard) copies.

## Develop

```sh
scripts/test.sh Clips     # unit tests
scripts/run.sh Clips      # build a debug .app and open it (quits any running Clips first)
scripts/check.sh Clips    # the full gate: tests, release bundle, launch smoke test
```

Logic lives in `Sources/ClipsCore` (tested). Views and wiring live in `Sources/Clips`.

Test without touching your real clipboard or history (all off by default). `--direct`
starts a separate copy beside an installed Clips; without it, `drive launch` hands back the
Clips that's already running and ignores the variables.

```sh
scripts/bundle.sh Clips --debug
scripts/drive launch build/Clips.app --direct \
  --env CLIPS_DATA_DIR=/tmp/clips-test/data \
  --env CLIPS_PASTEBOARD=clips-test \
  --env CLIPS_NO_HOTKEY=1 \
  --env CLIPS_ALLOW_CAPTURE=1
```

| Variable | Effect |
|---|---|
| `CLIPS_DATA_DIR` | Keep the history and rendered sounds in this folder, and Clips' settings in the `app.slopapp.clips.test` defaults domain (so a test run doesn't change them). "Show in menu bar" and the ⇧⌥V shortcut are still shared with your real copy |
| `CLIPS_PASTEBOARD` | Watch and write a private named pasteboard instead of the clipboard |
| `CLIPS_SEED=5000` | Fill an empty test history with synthetic clips (needs `CLIPS_DATA_DIR`) |
| `CLIPS_ALLOW_CAPTURE=1` | Let screenshots see the panel |
| `CLIPS_NO_HOTKEY=1` | Don't register the global shortcut (run a test copy beside a real one) |
| `CLIPS_TEST_BACKDROP=/path` | Image for the test hook `do backdrop` (a wallpaper-like window behind the strip) |
| `CLIPS_LOG=/path` | Log timings (never clipboard content) |
| `CLIPS_APPEARANCE=light\|dark` | Force an appearance |
| `CLIPS_SHOW_PANEL=1` | Open the panel at launch |
| `CLIPS_TEST_HOOKS=1` | Accept `app.slopapp.clips.test.show/hide/search/numbers/select/preview/tab/do` distributed notifications (`show` with object `passive` doesn't take the keyboard; `do` also selects several cards, manages boards, edits, and runs paste stacks; see `Diagnostics.swift`). With `CLIPS_PASTEBOARD`, a paste stack's "paste" is any read of that pasteboard |

`scripts/smoke.sh` (`SLOPAPP_SMOKE_TEST=1`) gets a throwaway history and pasteboard of its own.

Design follows [`docs/design-system.md`](../../docs/design-system.md). Research and build
notes: [`docs/research/clips.md`](../../docs/research/clips.md).
