# Dual research (inspired by ForkLift)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-03: **ForkLift 4.7.7 (486)**, Setapp build (`com.binarynights.forklift-setapp`,
> by BinaryNights), installed at /Applications/Setapp/ForkLift.app, read-only. Also
> studied: its website and Quick Start Guide, release notes on its blog, Setapp customer
> reviews, forum threads (MacPowerUsers, MacRumors via search) and a long-form review. We
> study how it works so we don't reinvent the wheel. We never copy its name, icons,
> artwork, wording, sounds or signature visuals.
>
> ForkLift wasn't running. It was launched, its main menu was read in full, its Settings
> window was walked pane by pane (switching panes only), and it was quit. No setting was
> changed (the transfer-policy pop-ups were opened and dismissed with Esc; values were
> re-read afterwards and still showed their defaults). The main browser window shows the
> owner's folders, favorites and saved servers, so it was **not** screenshotted or
> transcribed; the "Recent Items", "Favorites", "Bonjour" and "Recent Folders" menus also
> list personal entries, which are left out of this doc. Mouse use was off-limits, so
> dialogs that need a selection (conflict sheet, multi-rename, Get Info) are described
> from the official guide, not from the screen.

## The job

Someone who moves files around a lot (developers, designers, people tidying downloads into
project folders, anyone feeding a NAS or a server) finds Finder slow for it: two windows
to line up, no keyboard way to send "these files over there", no view of what's copying,
no batch rename worth the name. They reach for a **two-pane** file manager: the source on
the left, the destination on the right, and keys that act across them. "Done" feels like:
I selected the files, pressed one key, they're in the other folder, any clashes were
asked about once, and I never touched the mouse. **The one interaction that matters: in the
active pane, select items with the keyboard, press the Copy (or Move) key, confirm, and
watch them land in the other pane, with conflicts asked once and progress visible.**

## Who and when

- Sorting a Downloads folder into project folders: left pane Downloads, right pane the
  project, move a batch at a time.
- Copying a build output, a photo shoot or a set of assets to an external drive or a
  network share, and wanting to see the transfer and know it finished.
- Renaming a batch of files: camera files to `Trip 2026 - 001.jpg`, fixing case, swapping
  a word with find and replace.
- Digging through a project tree with hidden files shown (dotfiles, `.git`), opening the
  current folder in Terminal, copying a path.
- (Later, the original's other half) uploading to an SFTP server or S3 bucket and syncing
  a local folder to it.

Frequency: for its fans it **replaces Finder**, so it's open all day and used dozens of
times; each use is seconds. For lighter users it's a few sessions a week for bulk moves or
renames.

## How the original is built (relevant facts)

- Native AppKit app (storyboards, `NSOutlineView`), macOS 14.6+. Bundles `XADMaster`
  (archives as folders) and `UniversalDetector` (text encoding detection). SFTP is
  **libssh2 1.11.1** (BSD-3) statically linked. A privileged helper
  (`ForkLiftHelper`, a launchd job) does operations that need admin rights.
- Integrations: a "Reveal in ForkLift" Finder Service; an AppleScript dictionary
  (windows, left/right/active tab, `reveal`, `delete`); it registers as a viewer for every
  file type (`*`) so it can be made the default file viewer; a `fldropbox` URL scheme for
  Dropbox auth; an AskPass helper for command-line tools.
- 12 localizations. Settings is a sidebar-style window with seven panes.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with a reason).

### Panes, tabs and layout

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Two side-by-side panes | Left and right file browsers; one is *active* (highlighted), commands act on its selection, the other pane is the target | must | The core. Active pane gets a clear accent focus ring/header tint; the inactive pane's selection is dimmed. |
| 2 | Switch active pane | Tab key (not a menu item); clicking a pane | must | Tab (and ⇧Tab) toggles. Also a menu item "Switch Pane" so it's discoverable. |
| 3 | Single-pane mode | View › Single Pane Mode ⌥⌘P | should | Cheap toggle; copy/move then need a chooser. |
| 4 | Horizontal panes (stacked) | View › Show Horizontal Panes | later | Nice on portrait displays; not core. |
| 5 | Swap panes | View › Swap Panes | must | One line of state; very handy. |
| 6 | Clone pane (other pane shows same folder) | View › Clone Pane ⇧⌘C | must | "Make other pane match this one." Cheap and used constantly. Ours: "Same Folder in Other Pane" ⌘= (⇧⌘C is Finder's "Computer"). |
| 7 | Tabs per pane | Each pane has its own tab bar; New Tab ⌘T; Close Tab; Close Other Tabs ⌥⌘W; ⌃1–⌃5 select; ⌃⇥ / ⌃⇧⇥ next/prev; Show Tab Bar ⇧⌘T | must | Tabs per pane: ⌘T new, ⌘W closes the tab (then the window), ⌃⇥ / ⌃⇧⇥ cycle. Keep it simple: a slim tab strip above each pane, hidden when only one tab. |
| 8 | Move tab to other pane | Window › Move Tab To Other Pane ⌥⇧⌘T; drag tabs between panes | should | Menu command only; tab dragging later. |
| 9 | Pin tab | Window › Pin Tab ⌥⇧⌘P | later | |
| 10 | Multiple windows | New ForkLift Window ⌘N; each window has its own two panes | should | `WindowGroup` with per-window state is nearly free in SwiftUI; ⌘N. |
| 11 | Restore windows and tabs on startup | General setting, on by default | must | Relaunch into the same folders/tabs. Folders that vanished fall back to Home. |
| 12 | Starting directory | General setting (default Home) | should | Only matters on first launch / new window. |
| 13 | Sidebar | Devices (volumes with eject and free space), Favorites (groups), shares, Bonjour, tags, sync presets, rename presets | must (Favorites + Devices) | Sidebar sections: Favorites, Locations (volumes with eject). Clicking opens in the **active** pane. |
| 14 | Sidebar editor / show-hide sections | View › Show Sidebar Editor, Show Devices ⌃D, Show Devices Info | later | Fixed sections in v1. |
| 15 | Toolbar (customizable) | Back/forward, view mode, actions, hidden toggle, search, etc.; Customize Toolbar…; Show Toolbar ⌥⌘T | should | Native `NSToolbar` customization is close to free in SwiftUI (`.toolbar(id:)`). |
| 16 | Path bar per pane | Clickable segments under each pane; Show Path Bar toggle | must | Click a segment to jump; also shows the active pane at a glance. |
| 17 | Status bar per pane | Selection count, selected size, free space on volume | must | "3 of 41 selected, 12.4 MB · 210 GB free". Cheap and loved. |
| 18 | Preview pane (third column) | Show Preview ⇧⌘P: Info (metadata + preview), Activities, Log modes | later | Quick Look (Space) covers v1. |
| 19 | Themes | 9 built-in themes + custom theme editor | skip | Design system: system appearance and the user's accent only. |
| 20 | Show/hide title bar | View › Show Title Bar | skip | Not worth a setting. |
| 21 | Full screen | ⌃⌘F | must | Free with a standard window. |

### Browsing and navigation

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 22 | List view with columns | Name, size, kind, dates (modified, created, added, last opened), tags, owner, group, permissions; resizable, sortable | must | Columns: Name, Size, Kind, Date Modified (default); Date Created/Added as optional columns (should). `NSTableView` for speed with 10k+ rows. |
| 23 | Icon view / column view | ⌘1 / ⌘3 | skip (v1), later | Two-pane managers live in list view; icon/column views multiply work. |
| 24 | Sort by any column | Click header; View › Sort by ⌃⌘1…⌃⌘0; Descending ⌥⌘O | must | Header click; menu items for the 4 main columns. Folders-first option (should). |
| 25 | Group by | Kind/dates/size/tags, ⌃⌥⌘ digits | later | |
| 26 | Per-folder view settings / view options | Show View Options ⌘J; Save View Settings as Defaults; Restore Default ⌥⌘R | later | One global column/sort setting per pane in v1. |
| 27 | Open item | Open = ⌘↓ or double-click; Return renames (Finder style) | must | ⌘↓ / double-click open: folders navigate, files open in default app. **Return renames** (Finder habit) by default. |
| 28 | Enclosing folder | ⌘↑ | must | ⌘↑, and re-select the folder you came from. (No bare-Backspace "up": too close to ⌘⌫ Trash.) |
| 29 | Back / forward history | ⌘[ / ⌘] per pane | must | Per tab history. |
| 30 | Open in new tab / in other pane | ⌥⌘↓ / ⌥⇧⌘↓ | must (other pane), should (new tab) | "Open in other pane" is a two-pane superpower. |
| 31 | Go menu shortcuts | Documents ⇧⌘O, Desktop ⇧⌘D, Downloads ⌥⌘L, Home ⇧⌘H, Library ⌥⇧⌘L, Applications ⇧⌘A, Utilities ⌥⌘U | must | Same as Finder's, so muscle memory carries over. |
| 32 | Go to Folder… | ⇧⌘G sheet with path field, `~` expansion, completion; follows aliases/symlinks | must | Tab-completion of path components (should). |
| 33 | Recent folders | Go › Recent Folders | should | Last 10 per window. |
| 34 | Type-to-select | Typing letters jumps to the first matching name | must | Standard table behavior; make sure it doesn't fight single-key shortcuts. |
| 35 | Quick Select | Edit › Quick Select ⌘S: type a pattern (name, extension, tag) to select/deselect matching items | should | Great for "select all .jpg". Pattern like `*.jpg` or plain substring. ⌘S is odd on a Mac; we'd use a different key (see Menus). |
| 36 | Select all / deselect / invert | ⌘A, ⌥⌘A, Invert Selection | must (⌘A, deselect), should (invert) | |
| 37 | Non-adjacent keyboard selection | Not supported (developer declined Space-to-mark) | should | **Do better**: ⇧↑/⇧↓ extend; Space is Quick Look, so use Insert-style marking with ⌘-click and a "Toggle Selection" key (⌃Space). |
| 38 | Quick Open (command palette) | Esc opens a palette of favorites, devices and menu commands, showing their shortcuts | later | Lovely, but v1 has menus. Esc is reserved for cancel in our design system. |
| 39 | Sync browsing | Go › Sync Browsing ⇧⌘Y: navigating one pane mirrors into the same relative path on the other | later | Useful for comparing trees. |
| 40 | Live refresh | Refresh ⌘R exists; reviewers report having to refresh manually too often | must | **Do better**: FSEvents/dispatch source per visible folder, debounced; ⌘R still there. |
| 41 | Show hidden files | Show Invisible Files ⇧⌘. (toolbar button too) | must | Global toggle, remembered. Same shortcut as Finder. |
| 42 | Folder sizes | File › Calculate Folder Size ⇧⌘S (on demand) | must | On demand for selection, async, cancellable; result shows in the Size column. Auto-calc as an option later. |
| 43 | Archives as folders | Browse zip/tar like folders; setting "Treat archives as folders" (off) | later | Crate exists for archives. |
| 44 | Aliases/symlinks | Show Original; follows them on open | must (follow), should (Show Original) | |
| 45 | Volumes | Devices list with free space; Eject ⇧⌘E | must | Locations in sidebar from `mountedVolumeURLs`; eject via `NSWorkspace.unmountAndEjectDevice`. |
| 46 | iCloud Drive | Shows iCloud Drive, handles placeholders | should | Show it in Locations; show "not downloaded" state via resource values; don't force downloads. |

### File operations

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 47 | Copy to other pane | Commands › Copy to (F5), toolbar, drag with ⌥ | must | **The main action.** F5 and a Mac-friendly shortcut (see Menus). Short confirm sheet showing "Copy 3 items to <folder>" with Return to go (skippable via setting). |
| 48 | Copy to as… | Copy with a new name/destination path | later | |
| 49 | Move to other pane | Commands › Move to (F6) | must | Same-volume = rename (instant); cross-volume = copy then remove source only after success. |
| 50 | Clipboard copy/cut/paste | ⌘C / ⌘X / ⌘V; Move Items Here ⌥⌘V | must | ⌘C copies file URLs (works with Finder); ⌘V copies here; ⌥⌘V moves here (Finder convention). Reviewers say cut/paste was flaky; get it right. |
| 51 | Drag and drop | Between panes, to/from Finder and other apps; ⌥ to copy; "ask for confirmation for drag operations" setting (off) | must | Standard NSDragging: same volume moves, other volume copies, ⌥ forces copy, ⌘ forces move. Drop on a folder row targets that folder. |
| 52 | Conflict handling | Per conflict: Replace, Replace Older, Keep Both, Skip, Stop; folders also Merge (then asks for sub-items); "apply to all" | must | One sheet per batch with "Apply to all"; defaults from Settings (Replace / Resume / Merge policy, all "Ask"). |
| 53 | Transfer queue (Activities) | Live progress list for copy, move, delete, compress, rename; reorder; concurrent limit 5; Log view | must | Bottom drawer per window: one row per job (name, from → to, progress bar, bytes, speed, ETA, pause/cancel). Collapses to a slim bar when idle. |
| 54 | Max simultaneous transfers | Setting, default 5 | should | Default 2 for local disks (parallel copies to one disk slow down). |
| 55 | Auto-retry failed transfers | Setting, off, max 5 retries | later | Matters for remote. |
| 56 | Error handling per file | Reviewers: one error fails the whole transfer | must | **Do better**: an error on one file asks Skip / Skip All / Retry / Stop and the job continues; failures are listed at the end. |
| 57 | Resume policy | For interrupted transfers (mostly remote) | later | |
| 58 | Bandwidth limits | Upload/download limits | skip (v1) | Remote-only concern. |
| 59 | Log | View › Show Logs: record of operations and results | should | Finished jobs stay in the queue drawer (with errors) until cleared; a persistent log is later. |
| 60 | Move to Trash | ⌘⌫; Dock trash; asks nothing | must | `FileManager.trashItem`, undoable (⌘Z puts back). |
| 61 | Delete immediately | ⌥⌘⌫ with confirmation | should | Confirmation dialog naming the count ("can't be undone"). |
| 62 | Empty Trash | ForkLift › Empty Trash ⇧⌘⌫ | skip | Finder does it; no reason to own it. |
| 63 | Undo / redo | Edit › Undo ⌘Z / Redo ⇧⌘Z | must | Undo for: trash, rename (single and batch), move, new folder, duplicate. Copy undo = trash the copies. |
| 64 | New Folder | ⇧⌘N, starts inline rename | must | |
| 65 | New Folder With Selection | ⌃⌘N | should | Cheap, very handy. |
| 66 | New File | ⌥⇧⌘N (empty text file, inline rename) | should | |
| 67 | Duplicate | ⌘D (Finder-style "copy" suffix) | must | Through the same queue for big files. |
| 68 | Make alias / symlink | ⌃⌘A, ⌃⇧⌘A, "…to" other pane | should (symlink in other pane) | |
| 69 | Rename (single, inline) | Return; Tab moves to next item while renaming? | must | Inline edit in the Name cell, base name preselected (not the extension), Esc cancels, Return commits; reject `/` and `:` with a plain message. |
| 70 | Multi-rename (batch) | Return with several selected opens a rename window: stack of rules (change case ×4, replace text incl. regex in name or extension, add text at start/end/position, insert date (modified/created/now), add sequence number); live old→new preview; presets saved to sidebar; drop files on a preset to apply | must (core rules), later (presets) | v1 rules: Replace (plain/regex, name or extension), Add text (prefix/suffix), Number sequence (start, step, padding, position), Change case. Live preview table, conflicts flagged red, one undo step. Two-phase rename for swaps (a→b, b→a). |
| 71 | Quick Look | Space / ⌘Y; Slideshow ⌥⌘Y | must | `QLPreviewPanel`, arrows move the selection while open. |
| 72 | Get Info | ⌘I | should | Driving Finder's info window would need an Automation permission, so show our own small info popover (path, size, dates, permissions, kind) instead. |
| 73 | Open With | Submenu of apps for the file | must | `NSWorkspace.urlsForApplications(toOpen:)`; default app first. |
| 74 | Open in Terminal | ⇧⌘R; Terminal app picker in Settings (Terminal, iTerm, Hyper, Kitty, Warp, Ghostty) | must | Opens the active pane's folder (or the selected folder). Setting: Terminal app (default Terminal; offer installed ones). |
| 75 | Reveal in Finder | File menu | must | `NSWorkspace.activateFileViewerSelecting`. |
| 76 | Copy Path | Submenu: UNIX, URL, percent-decoded URL, Name, Terminal-escaped, Windows | must (UNIX, Name), should (Terminal-escaped) | ⌥⌘C like Finder's "Copy as Pathname". |
| 77 | Tags | Assign color tags, Tags… editor, tags in sidebar, up to 3 tags in list view | later | Show tag dots in the Name cell (should, cheap via resource values). |
| 78 | Edit (text file) | ⌘E opens in the configured editor | later | "Open With" covers it. |
| 79 | Compress / Extract | ⇧⌘M, ⌥⇧⌘M with options; ⇧⌘X / ⌥⇧⌘X | later | "Compress" via `ditto -c -k` is cheap; maybe should. Extraction is Crate's job. |
| 80 | Compare files | Compare… opens two files in FileMerge/Kaleidoscope/Beyond Compare/Araxis | later | |
| 81 | Checksum | Calculate Checksum… | later | |
| 82 | Find | ⌘F: own name search (recursive optional, works remotely) or Spotlight (content, local) | must (filter), should (recursive name search) | v1: ⌘F filters the active pane by name as you type (instant). Recursive search in subfolders is should; Spotlight later. |
| 83 | Print | ⌘P | skip | Print of a file list is rarely used. |
| 84 | Share | System share sheet | should | `NSSharingServicePicker` in the context menu. Cheap. |
| 85 | Context menu | Right-click has the main commands | must | Mirrors File/Commands menus. |
| 86 | Admin-rights operations | Privileged helper for protected locations | skip (v1) | Show a plain error ("You don't have permission to change …") instead. |

### Tools and integrations

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 87 | Remote connections | SFTP, FTP, FTPS, WebDAV(S), S3 (+compatible), Google Drive, Dropbox, OneDrive, Backblaze B2, Rackspace, SMB, AFP, NFS, VNC; Connect ⌘K panel; saved as favorites; per-connection color; private key auth | later (v2: SFTP first) | See "Remote later" below. SMB/AFP/NFS can be mounted by macOS (`NSWorkspace`/Finder "Connect to Server") and then they're just volumes: a cheap **should** is "Connect to Server…" that hands `smb://` URLs to the system. |
| 88 | Remote editing | Edit a remote file locally, upload on save | later | |
| 89 | Sync / Synclets | Compare two folders (one-way or two-way, subfolders, hidden, delete orphans, exclude filter), preview changes, save as favorite | later | Big feature on its own; reviewers judge it hard. |
| 90 | App Deleter | Trashing an app lists its leftover files; setting "Detect application when deleting" (on) | skip | Tidy covers app removal. |
| 91 | Favorites | Add to Favorites, New Favorite…, groups, Add Path to Favorite, iCloud sync of favorites (on) | must (add/remove/reorder), later (groups, iCloud sync) | Sidebar Favorites seeded with Home, Desktop, Documents, Downloads, Applications. Drag a folder in to add; ⌃⌘T "Add to Favorites" (Finder's shortcut). Stored as bookmarks. |
| 92 | Workspaces | Save/update a layout of tabs and locations for both panes | later | Restore-on-launch covers most of the value. |
| 93 | Custom tools | Settings › Tools: shell commands with placeholders, assignable shortcuts; Manage Tools… | later | |
| 94 | Source control | Git status column; Commit/Add/Add All/Push/Pull | skip | Out of scope for a file manager v1; Git apps exist. |
| 95 | Default file viewer | Replaces Finder for "reveal" actions via a terminal command | skip | Risky system change; "Reveal in Dual" Service is the safe version (later). |
| 96 | Finder Service "Reveal in …" | NSServices entry | later | |
| 97 | AppleScript | Dictionary with windows, left/right tabs, reveal, delete | later | |
| 98 | Dropbox share links | Context menu item for files in Dropbox | skip | Dropbox's own app does this. |
| 99 | Text encoding menu | View › Text Encoding (for remote file names) | skip (v1) | Remote-only problem. |
| 100 | Window tiling menu items | Window › Fill/Center/Move & Resize (macOS 15+ system items) | free | System-provided; nothing to build. |
| 101 | Welcome window | Favorites iCloud sync, import from v3, update checks, theme, newsletter | skip | Design system: no onboarding. |
| 102 | Notifications | Asks for notification permission at first run | should (opt-in) | Only post "Copy finished" when the app is in the background and the job took > 10 s; ask the first time that happens. |

## Key flows

### Flow 1: copy files to the other pane (the main job)

As the original does it:

1. Left pane is active (accent-tinted header). Arrow keys move the selection, ⇧↑/⇧↓
   extend it, ⌘A selects all, ⌘S Quick Select types a pattern to select matches.
2. Press **F5** (Copy to). The target is the inactive pane's current folder. (Dragging
   to the other pane does the same; ⌥ forces copy.)
3. The job starts at once (no confirm unless the drag-confirm setting is on). If a name
   exists in the target, a sheet asks: Replace, Replace Older, Keep Both, Skip, Stop, and
   for folders Merge; an "apply to all" checkbox covers the rest of the batch.
4. Progress shows in the Activities list (in the preview pane, ⇧⌘U), with bytes and
   speed; transfers can be reordered. Completed items appear in the target pane.
5. F6 (Move to) is the same, removing the source afterwards.

What we'll do: the same shape. Keys are **F5 / F6** (the Commander tradition the original
ships) plus a ⌘-combo for keyboards without easy F-keys (see Open question 1), the toolbar
and the context menu. Our confirm step is a compact sheet ("Copy 3 items (12.4 MB) to
Projects") where Return confirms and Esc cancels; a setting (and "Don't ask again" in the
sheet) turns it off. Progress goes to the transfer drawer at the bottom of the window.

### Flow 2: first run / onboarding

As the original does it:

1. A welcome window: iCloud favorites sync, import from ForkLift 3, check for updates,
   pick a theme, newsletter.
2. Licensing/trial (not on Setapp).
3. It asks for **Full Disk Access** (to browse Desktop, Documents, Downloads, external
   drives without per-folder prompts) and for **notification** permission.
4. The window opens with both panes on the starting directory (Home).

What we'll do: no welcome window. The first window opens with left = Home, right =
Downloads (so copy has an obvious target), sidebar visible, list view. The first time a
TCC-protected folder (Desktop, Documents, Downloads, iCloud Drive, removable or network
volumes) is listed, macOS shows its own one-time prompt; if the user says no, that pane
shows an inline `PermissionGate`-style empty state ("Dual can't read Desktop. Allow it in
Privacy & Security › Files and Folders, or give Full Disk Access.") with a button to the
exact pane and a live re-check. Full Disk Access is mentioned only there, never up front.

### Flow 3: batch rename

As the original does it:

1. Select several files, press Return (or Commands › Rename / context menu).
2. A rename window shows the files with live old → new names and a list of rules on the
   side. + adds a rule: change case (4 kinds), replace text (optionally regex, name or
   extension), add text (start/end/position), insert date (modified/created/now) at a
   position, add a number sequence.
3. "Rename" applies; presets can be saved as sidebar favorites and files dropped on a
   preset get renamed by it.

What we'll do: Return with **one** item selected starts inline rename; Return with
**several** opens a sheet: rules stacked top to bottom, a preview table below (old → new,
red row and a disabled Rename button on any clash or invalid name), Rename applies as one
undo step. Presets later.

### Flow 4: tidy a folder with the keyboard

1. ⇧⌘D opens Desktop in the active pane, ⇧⌘. shows hidden files.
2. ⌘F types "screenshot": the list filters as you type.
3. ⌘A, ⌘⌫ moves them to the Trash; ⌘Z puts them back.
4. ⇧⌘N makes a folder (inline name), ⌘↓ enters it, ⌘↑ returns with the folder selected.
5. ⇧⌘R opens the current folder in Terminal.

### Flow 5: favorites and locations

1. The sidebar lists Favorites (seeded) and Locations (volumes with free space and an
   eject button).
2. Clicking an entry opens it in the **active** pane; ⌥-click opens it in the other pane
   (ours; the original routes via the active pane).
3. Drag a folder into Favorites to add it, drag to reorder, context menu Remove.

## Settings inventory

Values read from the installed copy (they match the shipping defaults as far as the guide
says; nothing was changed).

| Pane › Setting | Default | Options | Keep? |
|---|---|---|---|
| General › Starting Directory | Home | any folder | **Yes** (General): "New windows open" Home / last used |
| General › Restore windows and tabs on startup | on | toggle | **Yes**, on, no setting needed in v1 (always restore) |
| General › Open remote connections in | Active Pane | Active / other / new tab… | Later (remote) |
| General › Ask for confirmation for drag operations | off | toggle | **Yes**, generalized: "Confirm before copying or moving" (on for keyboard copy/move, off for drags) |
| General › Detect application when deleting (App Deleter) | on | toggle | Skip (Tidy's job) |
| General › Handle archives with ForkLift | on | toggle | Skip |
| General › Treat archives as folders | off | toggle | Later |
| General › Terminal Application | Terminal | Terminal, iTerm, Hyper, Kitty, Warp, Ghostty | **Yes**: list only installed ones |
| General › Compare Tool | FileMerge | FileMerge, Kaleidoscope, Beyond Compare, Araxis | Later |
| General › Sync Favorites to iCloud | on | toggle | Later (and off by default: no network) |
| Shortcuts › every menu command | see Menus | searchable list, per-command recorder, Restore Defaults | Later. v1 uses the menu shortcuts; macOS's own App Shortcuts setting can remap them |
| Transfers › Replace policy | Ask | Ask and others (Replace / Replace older / Skip / Keep both, per the guide) | **Yes**: "When a file already exists": Ask / Keep both / Replace if older / Skip |
| Transfers › Resume policy | Ask | | Later (remote) |
| Transfers › Merge policy | Ask | | **Yes** folded into the above: folders merge by default, asking for clashing files per the file rule |
| Transfers › Limit uploads / downloads | off | toggle + rate | Later (remote) |
| Transfers › Automatically retry failed transfers | off, max retries 5 | toggle + number | Later |
| Transfers › Max. simultaneous transfers | 5 | number | Should, default 2 |
| Tools | empty list | +/−/edit shell commands | Later |
| Editing | empty list | app ↔ extensions map for Edit | Later |
| Themes | Default (follows system) | 9 built-in + custom | Skip (design system) |
| Tags › Show these tags in the sidebar | the 7 system colors | reorder, add | Later |

Ours (v1): **General**: Launch at login (design-system standard; off), New windows open
(Home / last folder), Show hidden files (mirrors ⇧⌘.), Folders first (on), Confirm before
copying or moving (on), Terminal app. **Transfers**: When a file already exists (Ask),
Simultaneous transfers (2), Notify when a long transfer finishes (off). **About**.

## Menus and shortcuts

### The original's main menu (structure and default shortcuts)

- **ForkLift**: About; Settings… ⌘,; Empty Trash… ⇧⌘⌫; Services; Hide ⌘H; Hide Others ⌥⌘H;
  Quit ⌘Q; Quit and Keep Windows ⌥⌘Q.
- **File**: New Window ⌘N; New Folder With Selection ⌃⌘N; New Folder ⇧⌘N; New File ⌥⇧⌘N;
  New Tab ⌘T; Open ⌘O; Open With ▸; Close Window ⌘W; Close All ⌥⇧⌘W; Close Tab; Close Other
  Tabs ⌥⌘W; Eject ⇧⌘E; Calculate Folder Size ⇧⌘S; Show Original; Get Info ⌘I; Open in
  Terminal ⇧⌘R; Reveal in Finder; Copy Path ▸ (UNIX, URL, Percent-Decoded URL, Name,
  Terminal, Windows); Copy URL; Open URL; Tags…; Find ⌘F; Quick Look ⌘Y; Slideshow ⌥⌘Y;
  Print ⌘P.
- **Edit**: Undo ⌘Z; Redo ⇧⌘Z; Cut ⌘X; Copy ⌘C; Paste ⌘V; Move Items Here ⌥⌘V; Delete;
  Select All ⌘A; Deselect All ⌥⌘A; Invert Selection; Quick Select ⌘S.
- **View**: as Icons/List/Columns ⌘1/2/3; Single Pane Mode ⌥⌘P; Show Horizontal Panes;
  Show Sidebar ⌥⌘S; Show Sidebar Editor; Show Title Bar; Show Tab Bar ⇧⌘T; Show Path Bar;
  Show Devices ⌃D; Show Devices Info; Show Preview ⇧⌘P; Show Activities ⇧⌘U; Show Logs;
  Customize Toolbar…; Show Toolbar ⌥⌘T; Refresh ⌘R; Swap Panes; Clone Pane ⇧⌘C; Show
  Invisible Files ⇧⌘. (shortcut list only); Sort by ▸ (Name ⌃⌘1, Kind ⌃⌘2, Date Added ⌃⌘3,
  Date Modified ⌃⌘4, Date Last Opened, Date Created ⌃⌘5, Size ⌃⌘6, Tags ⌃⌘7, Owner ⌃⌘8,
  Group ⌃⌘9, Permissions ⌃⌘0, Descending ⌥⌘O); Group by ▸ (⌃⌥⌘ digits, None ⌃⌥⌘0); Text
  Encoding ▸; Show View Options ⌘J; Restore Default View Settings ⌥⌘R; Save View Settings
  as Defaults; Enter Full Screen ⌃⌘F.
- **Go**: Back ⌘[; Forward ⌘]; Open ⌘↓; Open In New Tab ⌥⌘↓; Open in Other Pane ⌥⇧⌘↓;
  Enclosing Folder ⌘↑; Documents ⇧⌘O; Desktop ⇧⌘D; Downloads ⌥⌘L; Home ⇧⌘H; Library ⌥⇧⌘L;
  Applications ⇧⌘A; Utilities ⌥⌘U; Recent Folders ▸; Connections ▸; Sync Browsing ⇧⌘Y;
  Quick Open ⎋ (plain Esc); Go to Folder… ⇧⌘G; Connect ⌘K.
- **Favorites**: Show Favorites ⌥⌘F; Add to Favorites…; Add Path to Favorite; New
  Favorite…; New Favorite Group…; Save Workspace…; Update Workspace; then the favorites
  tree and Bonjour hosts as submenus.
- **Commands**: Copy to F5; Copy to as…; Move to F6; Move to Trash ⌘⌫; Delete ⌥⌘⌫;
  Extract ⇧⌘X; Extract to ⌥⇧⌘X; Rename ↩ (plain Return); Duplicate ⌘D; Make Alias ⌃⌘A;
  Make Alias to; Make Symlink ⌃⇧⌘A; Make Symlink to; Edit ⌘E; Sync to… ⌥⇧⌘S; Compress ⇧⌘M;
  Compress With Options… ⌥⇧⌘M; Compare…; Calculate Checksum…; Source Control ▸ (Commit,
  Add, Add All, Push, Pull); Manage Tools….
- **Window**: Minimize ⌘M; Minimize All ⌥⌘M; Zoom; system tiling items; Select First…Fifth
  Tab ⌃1…⌃5; Move Tab To Other Pane ⌥⇧⌘T; Pin Tab ⌥⇧⌘P; Show Previous Tab ⌃⇧⇥; Show Next
  Tab ⌃⇥; Bring All to Front; window list.
- **Help**: ForkLift Help ⌘?.
- Not in menus: Tab switches the active pane; Space Quick Look (Finder habit). All
  shortcuts are remappable in Settings › Shortcuts (searchable list, Restore Defaults).
  An optional "Commander" style keymap is reported by third-party lists (unverified here).

### Ours (v1 proposal)

Rule: use Finder's shortcut wherever Finder has the same command, Commander keys where it
doesn't, and **never reuse a Finder shortcut for a different meaning**. Items marked
"(verify)" need a quick collision check against Finder at build time; the final map goes
in the app README.

- **App**: About Dual; Settings… ⌘,; Hide ⌘H; Quit ⌘Q.
- **File**: New Window ⌘N; New Tab ⌘T; New Folder ⇧⌘N; New Folder With Selection ⌃⌘N; New
  File ⌥⇧⌘N (should); Open ⌘↓ (also ⌘O); Open With ▸; Open in Other Pane ⌥⇧⌘↓; Open in New
  Tab ⌥⌘↓ (should); Close Tab ⌘W (closes the window on the last tab); Close Window ⇧⌘W;
  Get Info ⌘I (should); Quick Look Space / ⌘Y; Rename ↩ (one item) / Batch Rename… ↩
  (several); Duplicate ⌘D; Calculate Size ⇧⌘S (verify); Open in Terminal ⇧⌘R; Reveal in
  Finder ⌥⌘R (verify); Copy Path ⌥⌘C (Finder's "Copy as Pathname"); Copy Name; Share…
  (should); Eject ⇧⌘E; Move to Trash ⌘⌫; Delete Immediately… ⌥⌘⌫.
- **Edit**: Undo ⌘Z; Redo ⇧⌘Z; Cut ⌘X; Copy ⌘C; Paste ⌘V; Move Items Here ⌥⌘V; Select All
  ⌘A; Deselect All ⌥⌘A; Invert Selection (no key: ⇧⌘I is Finder's iCloud Drive); Select
  Matching… ⌃S (should); Toggle Selection ⌃Space (should); Find ⌘F (filter).
- **View**: Show/Hide Sidebar ⌃⌘S (Finder's); Show/Hide Hidden Files ⇧⌘.; Show/Hide
  Transfers ⌥⌘U (verify; ⇧⌘U is Finder's Utilities); Single Pane (should, no key); Sort by ▸
  Name, Kind, Size, Date Modified with Finder's ⌃⌥⌘ digits, Reverse Order; Refresh ⌘R; Swap
  Panes ⌘U (verify); Same Folder in Other Pane ⌘= (verify); Enter Full Screen ⌃⌘F. The path
  bar and status line are always on (no toggle).
- **Go**: Back ⌘[; Forward ⌘]; Enclosing Folder ⌘↑; Home ⇧⌘H; Desktop ⇧⌘D; Documents ⇧⌘O;
  Downloads ⌥⌘L; Applications ⇧⌘A; Utilities ⇧⌘U; Library ⌥⇧⌘L (should); Recent Folders ▸
  (should); Go to Folder… ⇧⌘G; Switch Pane ⇥ (also shown as a menu item).
- **Commands**: Copy to Other Pane **F5**; Move to Other Pane **F6**; plus the ⌘-combo
  chosen in Open question 1; Make Symlink in Other Pane (should); Compress (later).
- **Favorites**: Add to Favorites ⌃⌘T (Finder's "Add to Sidebar"); the list of favorites
  (no number keys: ⌘1–⌘4 are Finder's view modes).
- **Window**: Minimize ⌘M; Zoom; Show Next Tab ⌃⇥; Show Previous Tab ⌃⇧⇥; Move Tab to
  Other Pane (should); Bring All to Front.
- **Help**: Dual Help (opens the README).

## Permissions and system integration

| What | Original | Ours (v1) |
|---|---|---|
| Full Disk Access | Asked for up front at first run (to avoid per-folder prompts for Desktop, Documents, Downloads, drives) | **Never asked up front.** macOS prompts once per protected location when we first list it; if denied, the pane shows an inline explanation with an "Open Privacy & Security" button (Files and Folders; Full Disk Access mentioned as the all-in-one option) and re-checks when the app becomes active. |
| Notifications | Asked at first run | Only if the user turns on "Notify when a long transfer finishes" or the first time a > 10 s job finishes in the background (should). |
| Removable / network volumes | Listed in Devices with free space and eject | Listed in Locations; first access triggers the macOS prompt for removable/network volumes. |
| Automation (Apple Events) | Usage string for its command-line tools | None in v1. Open in Terminal uses `NSWorkspace.open(_:withApplicationAt:)` with the folder URL (Terminal, iTerm, Warp, Ghostty all accept a folder), no AppleScript, so no Automation prompt. |
| Privileged helper | launchd helper for admin-rights operations | None. Permission errors are reported plainly. |
| Services | "Reveal in ForkLift" | Later: "Open in Dual". |
| AppleScript | sdef with windows/tabs/reveal/delete | Later. |
| Default file viewer | Optional, replaces Finder for reveal actions | Skip. |
| Document types | Viewer for `*` (so files can be dropped on its Dock icon) | Folder drops on the Dock icon open the folder in the active pane (should; `public.folder` only). |
| Login item | — | Launch at login toggle (design-system standard, off). |
| Sandbox | Not sandboxed | Not sandboxed (a file manager can't work inside the sandbox). Note: ad-hoc-signed dev builds may lose TCC grants after rebuilds; test the denied path on purpose. |

## Platform: what macOS gives us

- **Listing**: `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)` with
  prefetch keys (name, isDirectory, isHidden, isPackage, fileSize/totalFileAllocatedSize,
  contentModificationDate, creationDate, addedToDirectoryDate, localizedTypeDescription,
  tagNames, isSymbolicLink, ubiquitousItemDownloadingStatus). Fast enough for 10k+ entries
  off the main actor; icons via `NSWorkspace.icon(forFile:)` lazily per visible row.
- **Live refresh**: `DispatchSource.makeFileSystemObjectSource` on the folder fd
  (`.write`) or an FSEventStream per visible folder, debounced ~100 ms, diffed so the
  selection and scroll position survive.
- **Copy with progress and cloning**: `copyfile(3)` with `COPYFILE_ALL | COPYFILE_RECURSIVE
  | COPYFILE_CLONE` and a progress callback (`COPYFILE_STATE_STATUS_CB`): APFS same-volume
  copies are instant clones, metadata/xattrs/ACLs preserved, cancellable by returning
  `COPYFILE_QUIT`. `FileManager.copyItem` has no progress, avoid it for big jobs.
- **Move**: `rename(2)` / `FileManager.moveItem` on the same volume (instant, atomic);
  cross-volume = copy, verify, then delete the source (not via the Trash: the copy *is*
  the safe version); any failure leaves the source untouched.
- **Trash with undo**: `FileManager.trashItem(at:resultingItemURL:)` returns the Trash
  location, so undo moves it back. Volumes without a Trash (some network/FAT drives) throw;
  then fall back to "Delete Immediately?" confirmation.
- **Quick Look**: `QLPreviewPanel` with the window as data source/delegate.
- **Volumes**: `FileManager.mountedVolumeURLs(includingResourceValuesForKeys:options:)`,
  `NSWorkspace.didMountNotification`/`didUnmountNotification`, eject with
  `NSWorkspace.unmountAndEjectDevice(at:)`, free space via
  `volumeAvailableCapacityForImportantUsage`.
- **Drag and drop**: `NSFilePromise` not needed (files are real); write file URLs to the
  pasteboard; accept `.fileURL` drops; operation mask by modifier keys and volume.
- **Open With**: `NSWorkspace.urlsForApplications(toOpen:)`, `urlForApplication(toOpen:)`.

## Remote later (v2 feasibility: SFTP)

SFTP is the remote protocol people use most and the one worth doing first. Options,
checked 2026-11-03:

1. **System OpenSSH + our own SFTP protocol layer (recommended to evaluate first).**
   macOS ships `/usr/bin/ssh`. Spawning `ssh -s <host> sftp` (the `sftp` subsystem) and
   speaking SFTP v3 over its stdin/stdout gets `~/.ssh/config`, `known_hosts`, ssh-agent
   and Keychain-stored passphrases, every key type, ProxyJump and 2FA prompts for free, with
   no crypto in our code. SFTP v3 is a small binary protocol (open/read/write/close,
   opendir/readdir, stat/lstat/setstat, rename, remove, mkdir, rmdir, realpath, symlink);
   a few hundred lines plus tests against a local `sshd`. Password auth needs an
   `SSH_ASKPASS` helper (ForkLift ships one too). No new dependency.
2. **swift-nio-ssh (Apple, Apache-2.0, 0.15.1, 2026-10-26)**: low-level SSH transport and
   auth only; **no SFTP**, modern algorithms only (Ed25519, ECDSA P-256/384/521, AES-GCM,
   x25519). Upstream doesn't do RSA user keys, which many servers and users still have.
3. **Citadel (MIT, 0.12.1, 2026-04-04, ~390 stars)**: SFTP client on top of NIOSSH with
   `listDirectory`, `openFile`/`withFile` (read/write), `rename`, `remove`, `rmdir`,
   `createDirectory`, `getAttributes`/`setAttributes`, `getRealPath`; password and key
   auth. RSA relies on a NIOSSH fork; no ssh-agent, `~/.ssh/config` or `known_hosts`
   handling out of the box (we'd build host-key trust ourselves). Smaller project: pin
   exactly and vet before adding to the design-system dependency table.
4. **libssh2 (BSD-3, 1.11.1, 2024-10)**: what ForkLift uses. C, needs a crypto backend
   (OpenSSL/LibreSSL or mbedTLS) built universal; more build and update burden than 1–3.

Architecture to keep v2 cheap: put every file operation behind a `FileSystemProvider`
protocol in `DualCore` from day one (list, stat, read stream, write stream, rename, mkdir,
trash/delete, watch), with `LocalProvider` as the v1 implementation and the transfer queue
talking only to providers. A remote pane is then a new provider plus a Connect sheet and a
Keychain-backed saved-server list. SMB/AFP/NFS don't need providers at all: mount through
the system (`NSWorkspace.open(smb://…)`, i.e. Finder's Connect to Server) and they show up
as volumes.

## UX patterns worth adopting

- **The other pane is the destination.** No "choose a folder" step: the layout itself
  answers "where to?", which is why one key can copy.
- **An obvious active pane.** Commands act on one pane; the visual difference has to be
  unmistakable, and the inactive selection stays visible but muted so you know what's
  waiting there.
- **Finder's shortcuts kept where Finder has the command** (Go menu, ⇧⌘N, ⌘⌫, ⇧⌘G, ⌘↑/⌘↓,
  ⇧⌘.), so switching from Finder costs nothing, and Commander keys (F5/F6) added where
  Finder has no equivalent.
- **A transfer list that stays out of the way.** Progress lives in its own drawer, so you
  keep browsing while copies run; queued jobs can be reordered.
- **Conflict policy set once.** "Ask" by default with "apply to all", and a Settings
  default so repeat users never see the sheet.
- **Live preview for batch rename**, with rules stacked in order, so the result is visible
  before anything changes.
- **Status line with selection size and free space**: answers "will it fit?" without a
  Get Info.
- **Clone pane and swap panes**: tiny commands that remove most "navigate the other pane
  to here" busywork.
- **Open in other pane** (⌥⇧⌘↓): browse with one pane, set up the target with the other.
- **Restore everything on launch**: tabs, folders and active pane come back, so the app
  feels like a workspace, not a window.

## What we won't copy, and what we'll do better

- Not copying: the name, icon, themes and theme editor, the welcome window and newsletter,
  wording, licensing/upgrade flows, the "default file viewer" system hack.
- **Live refresh.** Reviewers complain they often have to refresh by hand. We watch every
  visible folder and update in place, keeping selection and scroll.
- **One bad file doesn't kill a transfer.** Reviewers report a single error failing the
  whole job. We ask Skip / Skip All / Retry / Stop per error, keep going, and list failures
  at the end with Retry.
- **Keyboard selection of non-adjacent items.** The original's developer declined it; we
  offer a toggle-selection key and Select Matching.
- **Cut and paste that works** (reported broken): ⌘X then ⌘V moves, and the source is
  removed only after the copy succeeded.
- **No Full Disk Access ask up front**; per-location prompts from macOS with a clear,
  inline fallback.
- **Native look** with the user's accent and system appearance instead of themes; no
  floating custom chrome. Reviewers call the original's window cramped on laptops: we
  hide the tab strip with one tab, make the sidebar collapsible (⌃⌘S) and default to a
  compact density.
- **Progress always visible** (reviewers: long operations with no sign of work). Any job
  longer than ~300 ms shows in the drawer; folder-size calculation shows a spinner in the
  row.
- **Fast on huge folders**: an `NSTableView`-backed list, metadata prefetched off the main
  actor, icons loaded only for visible rows (reviewers mention slow icon loading on network
  shares: show a generic icon first, swap in when loaded).
- **Same-volume copies are clones** (instant on APFS) and moves are renames.
- **Undo for everything reversible**, including batch rename as one step.
- No network, no iCloud favorites sync, no analytics.

## Edge cases

- **Huge folders** (50k+ entries, e.g. `node_modules`, a photo dump): listing off the
  main actor, first rows within ~100 ms, typing-to-select and filter stay instant; sorting
  doesn't block.
- **Huge files** (> 4 GB) and **many small files** (100k): progress by bytes and by count,
  cancel mid-file leaves no partial file at the target (copy to a temp name, then rename).
- **Same file into same folder** (copy to the pane showing the same folder): treat as
  Duplicate ("copy" suffix), never overwrite itself. **Copy a folder into itself or its
  own subfolder**: refuse with a plain message.
- **Conflicts**: file vs file, folder vs folder (merge), file vs folder of the same name
  (can't merge: Keep Both / Skip / Replace), case-only clashes on case-insensitive APFS
  (`a.txt` vs `A.txt`), Replace Older when dates are equal.
- **Rename**: case-only rename (`photo.JPG` → `photo.jpg`) on a case-insensitive volume
  needs a two-step rename; names with `/` or `:`; leading dot makes a file hidden (warn);
  empty names; > 255 bytes UTF-8; batch rename swaps (a↔b) and chains need temp names;
  extension change prompts like Finder (should); renaming the folder another pane/tab is
  showing updates that pane.
- **Unicode**: NFD names from older HFS+ disks vs NFC typed text (filter and Quick Select
  must normalize); emoji, RTL and CJK names; sort with `localizedStandardCompare` (so
  `file2` < `file10`).
- **Symlinks and aliases**: broken links show and can be deleted; copying copies the link
  (not the target) by default; loops don't hang folder-size calculation.
- **Packages** (`.app`, `.photoslibrary`, `.bundle`): shown as files; ⌘↓ opens them; a
  "Show Package Contents" item enters them (should).
- **Permissions**: unreadable folders (other users' homes, `/private/var/root`) show an
  inline error state, not a crash or empty list; read-only volumes disable write commands;
  locked files (`uchg`) report clearly.
- **TCC denied mid-use** (user revokes access in System Settings): the pane's next refresh
  shows the permission state.
- **Volumes**: ejecting a drive a pane is showing moves that pane to Home with a note;
  a drive unplugged mid-copy fails the job with Retry; network volumes may be slow, so
  never list them on the main actor; volumes with no Trash.
- **iCloud Drive**: placeholders (not downloaded) show their state; copying one triggers
  a download and the job shows it waiting.
- **Source deleted or renamed** by another app while queued: the job reports that item
  as missing and continues.
- **Disk full**: check free space before a big copy; if it runs out anyway, stop that job
  cleanly, remove the partial file, say how much space is needed.
- **App quit mid-transfer**: ⌘Q asks "Stop 2 transfers and quit?"; partial target files
  are removed; source never touched for an unfinished move.
- **Sleep/wake** during a transfer resumes (local copies just continue); volumes may vanish.
- **Multiple windows** each with their own panes; the transfer drawer can be per window,
  but jobs keep running when their window closes (show them in the next window or a menu
  item).
- **Dark/light**, **Increase Contrast** (active-pane indicator mustn't rely on color
  alone: add a header weight/outline), **Reduce Motion**.
- **VoiceOver**: each pane announces itself ("Left pane, Downloads, active"), rows read
  name, kind, size, date; transfer rows read progress.
- **Multiple displays / full screen**: standard window behavior; Quick Look on the
  window's screen.
- **Hidden files**: when hidden files are shown, `.DS_Store` and other dotfiles show too
  (that's what the toggle means). Folder merges resolve `.DS_Store` clashes silently
  (keep the target's) instead of asking (see Open question 6).

## Our v1 scope

The must-haves, as the checklist the test step walks through. Archetype: a **document-less
window app** (`WindowGroup` for multiple windows, each a sidebar + two panes + a transfer
drawer). Core logic (listing, sorting, filtering, conflict resolution, rename rules, the
transfer engine, undo records) lives in `DualCore` behind a `FileSystemProvider` protocol
with a fake for tests.

**Window and panes**
- [ ] A window shows a collapsible sidebar and two side-by-side list panes. First launch:
      left Home, right Downloads. One pane is active, and you can see which at a glance (accent
      header + focus ring); the inactive pane keeps its selection, muted.
- [ ] Tab switches the active pane; clicking a pane activates it; View › Swap Panes and
      View › Same Folder in Other Pane work.
- [ ] Tabs per pane: ⌘T new tab (same folder), ⌘W closes the tab (window on last tab),
      ⌃⇥ / ⌃⇧⇥ cycle; the tab strip hides with one tab.
- [ ] Windows, tabs, folders, active pane, sort and sidebar width restore on relaunch;
      vanished folders fall back to Home.

**Browsing**
- [ ] List view columns: Name (icon), Size, Kind, Date Modified; click a header to sort,
      again to reverse; folders first; natural name sort.
- [ ] Keyboard: ↑/↓ move, ⇧↑/⇧↓ extend, ⌘A / ⌥⌘A, type-to-select, ⌘↓ (and double-click)
      opens (folder enters, file opens in its default app), ⌘↑ goes up and reselects the
      folder you left, ⌘[ / ⌘] back/forward per tab.
- [ ] Go menu: Home, Desktop, Documents, Downloads, Applications, Go to Folder… (⇧⌘G,
      accepts `~` and pasted paths), Open in Other Pane (⌥⇧⌘↓).
- [ ] Path bar per pane with clickable segments; status line per pane: "N items",
      "N of M selected, size", free space on the volume.
- [ ] Show hidden files toggle (⇧⌘.), remembered, applies to both panes.
- [ ] ⌘F filters the active pane by name as you type (Unicode-normalized, case- and
      diacritic-insensitive); Esc clears and returns focus to the list.
- [ ] Calculate size (⇧⌘S) for selected folders: async, cancellable, shows in the Size
      column.
- [ ] Live refresh: changes made by other apps appear within ~0.5 s without losing
      selection or scroll; ⌘R forces a reload.
- [ ] Sidebar: Favorites (seeded Home, Desktop, Documents, Downloads, Applications; add by
      dragging a folder in or ⌃⌘T; reorder by drag; Remove from context menu) and
      Locations (mounted volumes with free space and an eject button). Clicking opens in
      the active pane.

**File operations**
- [ ] Copy to other pane (F5) and Move to other pane (F6), also as toolbar buttons and
      context-menu items; a compact confirm sheet (Return/Esc) that a setting turns off.
- [ ] Drag and drop between panes, to/from Finder and onto folder rows (same volume moves,
      other volume copies, ⌥ copies, ⌘ moves).
- [ ] ⌘C / ⌘X / ⌘V / ⌥⌘V work with file URLs, interoperating with Finder.
- [ ] Transfer engine: `copyfile` with clone + progress; same-volume moves are renames;
      cross-volume moves delete the source only after the copy succeeded; partial targets
      are removed on cancel/failure; copying a folder into itself is refused.
- [ ] Transfer drawer (⇧⌘U to show/hide; appears on its own for jobs > ~300 ms): one row per
      job with name, from → to, progress bar, bytes, items, ETA, Cancel; finished/failed
      jobs stay until cleared; Retry on failed.
- [ ] Conflicts: one sheet per job with Replace, Replace if Older, Keep Both, Skip, Stop
      (+ Merge for folders), "Apply to all"; a Settings default skips the sheet.
- [ ] Per-file errors ask Skip / Skip All / Retry / Stop and the job continues.
- [ ] Move to Trash (⌘⌫) with undo (⌘Z puts back); Delete Immediately (⌥⌘⌫) asks first.
- [ ] New Folder (⇧⌘N, inline name), New Folder With Selection (⌃⌘N), Duplicate (⌘D):
      all undoable.
- [ ] Rename: Return on one item edits inline (base name preselected, Esc cancels,
      invalid names explained, case-only renames work); undoable.
- [ ] Batch rename: Return on several items opens a sheet with stacked rules (Replace
      text with optional regex, Add prefix/suffix, Number sequence with start/step/padding,
      Change case), a live old → new preview, clashes flagged and blocking; applies as one
      undo step; swaps handled.
- [ ] Quick Look (Space / ⌘Y), arrows move through the selection while it's open.
- [ ] Open With ▸ (apps for the file, default first), Reveal in Finder, Copy Path (POSIX
      path; ⌥⌘C) and Copy Name, Open in Terminal (⇧⌘R, app from Settings, no Automation
      prompt), Eject (⇧⌘E).
- [ ] Context menu mirrors the File/Commands menus for the selection.

**Platform and polish**
- [ ] Protected folders: the macOS prompt is the only ask; denial shows an inline state
      with a button to Privacy & Security and a live re-check.
- [ ] Every command is in a menu with its shortcut; final shortcut map recorded in the
      README with no Finder collisions of different meaning.
- [ ] Settings: General (Launch at login, New windows open, Show hidden files, Folders
      first, Confirm before copying or moving, Terminal app), Transfers (When a file already
      exists, Simultaneous transfers), About.
- [ ] Performance: a 50k-item folder lists without beachballing; idle CPU within budget
      with both panes watching folders; memory under 120 MB idle.
- [ ] ⌘Q with running transfers asks first; VoiceOver names panes, rows, buttons; no
      `[unlabeled]` controls.

**Should (only after every must works)**: Single pane mode; Select Matching… (pattern
select); toggle-select key for non-adjacent selection; Invert Selection; Recent Folders;
Open in New Tab; New File; symlink in other pane; Get Info popover; Share; recursive
name search; tag dots in names; Show Package Contents; Move Tab to Other Pane; multiple
windows (⌘N) if not already free; customizable toolbar; "Connect to Server…" handing
`smb://`/`afp://`/`nfs://` to the system; finished-transfer notification.

## Open questions

1. **Copy/Move keys.** F5/F6 is the Commander tradition and what the original ships, but
   many Mac keyboards need fn for F-keys. Accept F5/F6 + toolbar + context menu, or also
   bind a ⌘-combo (candidates: ⌘→/⌘← are free in a file list but feel risky; ⌥⌘C/⌥⌘M clash
   with Finder's "Copy as Pathname"/"Minimize All"; ⇧⌘C is Finder's "Computer")?
   Proposal: F5/F6 plus ⌃⌘C / ⌃⌘M if a check shows Finder doesn't use them. Owner's call.
2. **Return key**: Finder-style Return = rename (proposed, matches the original) vs.
   Commander-style Return = open. Proposal: Return renames, ⌘↓ opens; offer a setting
   later if blind testers trip over it.
3. **Confirm sheet before keyboard copy/move**: on by default (safer, one extra Return) or
   off (faster, matches the original)? Proposal: on, with "Don't ask again" in the sheet.
4. **Should v1 include multiple windows (⌘N)?** SwiftUI makes it nearly free, but it
   complicates where the transfer drawer lives. Proposal: yes, jobs belong to the app
   and every window's drawer shows all of them.
5. **SFTP in v2**: system OpenSSH + own SFTP v3 layer (no dependency, best compatibility)
   vs. Citadel (MIT, pure Swift, weaker RSA/agent/known_hosts story). Proposal: spike
   option 1 when v2 starts. Also: is S3 wanted at all, or SFTP only?
6. **Show `.DS_Store`** when hidden files are on? Proposal: yes (that's what "show hidden"
   means), but conflicts on `.DS_Store` inside folder merges are resolved silently
   (keep target's).
7. **Name**: the roadmap tagline says "with remote servers", but v1 is local only. Ship v1
   with a tagline that doesn't promise remote ("A fast two-pane file manager."), and
   restore the remote wording when SFTP lands?

## Sources

- ForkLift product page: https://binarynights.com/
- ForkLift 4 Quick Start Guide (manual): https://binarynights.com/manual
- Release notes, 4.6.4 (Quick Select, Go to Folder through aliases): https://blog.binarynights.com/2026/06/16/forklift-4-6-4-is-available-brings-improvements-to-file-navigation/
- Release notes, 4.3.3 (Quick Open shortcuts): https://blog.binarynights.com/2025/05/27/forklift-4-3-3-is-available/
- Opening ForkLift with a shortcut / Quick Open on Esc: https://blog.binarynights.com/2025/07/08/how-to-open-forklift-with-a-single-keyboard-shortcut/
- AlternativeTo news on 4.5 (manual refresh complaint in comments), 4.6.3, 4.6.4: https://alternativeto.net/news/2026/2/forklift-4-5-adds-new-metadata-columns-editable-comments-and-several-bug-fixes-for-macos , https://alternativeto.net/news/2026/6/forklift-4-6-3-adds-item-info-overlays-and-navigation-shortcuts/ , https://alternativeto.net/news/2026/6/forklift-4-6-4-improves-file-navigation-with-quick-select-and-aliases/
- Setapp customer reviews: https://setapp.com/apps/forklift/customer-reviews
- MacPowerUsers thread on ForkLift 4: https://talk.macpowerusers.com/t/forklift-4-by-binary-nights-finder-alternative/34693?page=2
- "ForkLift 4, ready or not" review: https://pawelgrzybek.com/forklift-4-ready-or-not/
- Michael Tsai on ForkLift 4: https://mjtsai.com/blog/2023/09/05/forklift-4/
- MacRumors "best Finder alternatives" thread (via search): https://forums.macrumors.com/threads/best-finder-alternatives-file-managers.2258057/page-43
- G2 / SaaSworthy reviews (transfer weight, resource use): https://www.g2.com/products/forklift/reviews , https://www.saasworthy.com/product/forklift/reviews
- swift-nio-ssh (Apache-2.0): https://github.com/apple/swift-nio-ssh
- Citadel (MIT, SFTP on NIOSSH): https://github.com/orlandos-nl/Citadel
- libssh2 (BSD-3): https://github.com/libssh2/libssh2
- The installed app: menus (`scripts/drive tree --menu`), Settings panes (General,
  Shortcuts, Transfers, Tools, Editing, Themes, Tags), Info.plist, bundle contents.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
