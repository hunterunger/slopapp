# Shorthand research (inspired by TextExpander and Rocket Typist)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-07 (macOS 27.2): **TextExpander** 8.4.x (Smile / TextExpander Inc.) and **Rocket
> Typist** 3.4.x (Witt Software, in Setapp and the Mac App Store). **Neither is installed on
> this Mac**, so everything comes from their websites, help centers, release notes, App
> Store / Setapp reviews and third-party write-ups. Also looked at for behaviour only:
> **Espanso** (open source, GPL-3.0: behaviour and documented options only, never code),
> **Raycast Snippets** (Raycast is installed here but was not driven: its snippet list is
> the owner's personal content; its public manual was used instead) and **macOS Text
> Replacements** (Apple's help pages). Platform notes come from Apple documentation, Apple
> developer forums and this repo (Dictate, Clips, Triggers). We never copy names, icons,
> artwork, wording, sounds or signature visuals.

## The job

People hire a text expander to stop typing the same things over and over: an email
signature, a postal address, a support reply, a code boilerplate, today's date in the right
format, a phrase in a language with awkward characters. They reach for it dozens of times a
day without thinking about it, in whatever app they're in. "Done" feels like nothing at
all: you type a few letters, the whole thing is there, the cursor is where you want to keep
typing, your clipboard is as you left it, and your typing never stuttered.

The one interaction that matters: **type an abbreviation (say `;addr`) anywhere → it is
replaced, in place, by the full text, instantly.** Everything else (the library, groups,
placeholders, search, import) exists to feed that loop or to recover when you've forgotten
an abbreviation.

## Who and when

- Writing email and chat: sign-offs, addresses, phone numbers, "thanks for reaching out"
  replies, meeting links.
- Support and sales work: canned answers with a name or ticket number filled in.
- Developers: shell one-liners, code headers, log statements, commit trailers, a date stamp
  in ISO format.
- Forms: name, email, address typed into web forms many times a week.
- Special characters: `->` to →, accented names, a long product name spelled right.
- Frequency: many times a day, each use under a second. The library is opened a few times a
  week to add or fix a snippet; Settings almost never.

## How the originals and neighbours compare

| | TextExpander | Rocket Typist | Espanso | Raycast Snippets | macOS Text Replacements |
|---|---|---|---|---|---|
| Model | Subscription, account required since v6 (2016) | Free (10 snippets) + one-time Pro; in Setapp | Free, open source | Free in Raycast | Built in |
| Editor | Native app, groups, rich editor with a macro bar | Native app, folders, tags, preview | YAML files, no editor | Raycast command, tags | System Settings list (two fields) |
| Expansion timing | Immediately, or at a delimiter (keep or drop it) | Immediately or after a trigger key | On match; `word: true` for whole words | Immediately, or after a delimiter (keep or drop) | When a word ends, only in Cocoa text views |
| Placeholders | Date/time, date math, clipboard, cursor, selection, keys, nested, fill-ins (line, multi-line, popup, optional), scripts | Date/time (+offsets, custom format), text field, options, nested, clipboard, selection, cursor, keys, JavaScript, AI | Date, clipboard, shell, forms, regex, cursor | Date/time (+offsets, formats, locale), clipboard (+history offset), cursor, selection, uuid, arguments (3), nested, modifiers | None |
| Search by hand | Inline search at the caret (⌘/ by default) | Snippet menu in the menu bar + shortcut | Search bar (⌥Space) | Search Snippets command | None |
| Per-app control | Per group: all apps / all except / only these / none | Per folder prefer/block apps, global exclusions | Per-app config files (`enable: false`) | Disabled Applications (1Password, Keychain Access by default) | Per app: Edit › Substitutions › Text Replacement |
| Sync | Their cloud (account) | iCloud | Files (git, Dropbox) | Raycast cloud (Pro) | iCloud |
| Where it falls short | Price and account for a local job; dated UI; reliability notes in many apps; old "suggestions" feature stored typed phrases in plain text | Free tier tiny; UI hard to learn; slow editing; reviews report lost libraries after updates and a broken UI on macOS 27 | No GUI, YAML only; secure-input "stuck" confusion | Tied to a launcher; some apps need tuned delays; reports of the clipboard being pasted instead of the snippet | Doesn't work in Electron apps, VS Code or JetBrains IDEs; no placeholders, no cursor, no search; very large lists slow typing in Mail, Safari and Chromium |

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with the reason). "TE" = TextExpander, "RT" = Rocket Typist.

### Expansion

| # | Feature | How the originals do it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Abbreviation expands as you type, in any app | TE, RT, Raycast, Espanso all watch the keyboard and replace the abbreviation in place | **must** | Keyboard event tap (see Platform notes). Our matcher runs on our own rolling buffer of typed characters. |
| 2 | Expansion timing | TE: immediately / at a delimiter (keep it) / at a delimiter (drop it). Raycast: the same three. RT: immediate or trigger key | **must** (immediately) / **should** (after a delimiter, keep it) / later (drop delimiter) | Default **immediately**: no extra key, and it fires before macOS's own replacements and autocorrect (they wait for the word to end). "After a space or punctuation" as the second option. |
| 3 | Whole-word rule ("what may come before") | TE per group: any character / not letters or digits / whitespace only. Raycast: "Expand within words" toggle. Espanso `word`, `left_word` | **must** | One global switch, default on: "Only expand at the start of a word" (after a space, punctuation, a new line, or when we don't know what's before the caret). Stops `sig` firing inside "design". |
| 4 | Case handling | TE/RT per snippet: case sensitive / ignore case / adapt to the case typed. Espanso `propagate_case` | **must** (exact) / **should** (adapt) | Exact by default. "Adapt" per snippet: `Addr` → first letter capitalised, `ADDR` → all caps. |
| 5 | Delete the abbreviation, insert the text | Backspaces then type or paste (Espanso: inject vs clipboard, auto picks by length, 100-char threshold) | **must** | Automatic: type short single-line text, paste anything longer or multi-line. See Platform notes. |
| 6 | Restore the clipboard after a paste | TE "Restore clipboard"; RT Auto Paste restoration; Espanso `preserve_clipboard` (300 ms) | **must** | Dictate's `ClipboardSnapshot`: every item and type, temporary write marked transient so Clips skips it, no restore if something else was copied meanwhile. |
| 7 | Cursor lands at a marker | TE, RT, Raycast, Espanso all have one cursor marker | **must** | `{cursor}`; after inserting, post ← the right number of times (typed or pasted alike). One per snippet. |
| 8 | Undo an expansion with Backspace | Espanso `undo_backspace` (default on). TE: none documented | **should** | Backspace straight after an expansion (nothing else pressed, ≤ 2 s, single-line ≤ 200 chars) removes it and puts the abbreviation back. |
| 9 | Pause / resume expansion | TE hotkey "Enable/Disable"; Espanso double-tap toggle key; Raycast master toggle | **must** | Menu item + optional global shortcut (unset by default). Paused = the tap is removed, not just ignored. |
| 10 | Per-app exclusions | TE per group (4 modes) + global; RT folder rules; Raycast list with password managers by default; Espanso per-app files | **must** (global list) / later (per group) | One "Don't expand in" list. Defaults: Shorthand itself, Passwords, Keychain Access, 1Password, Bitwarden. While an excluded app is in front, keystrokes are not even buffered. |
| 11 | Pause in password fields | macOS secure input stops all taps; TE and Espanso show it in the menu bar icon and name the app | **must** | Free from macOS (no events arrive). We also clear the buffer, show "Paused: secure input is on in <App>" and check the focused element isn't a secure text field before any insert. |
| 12 | Sound on expansion | TE "Play sound"; Raycast completion sound | later | Quiet by default (design system). Maybe a system sound option later. |
| 13 | Expand inside Shorthand's own windows | Unclear in originals | skip | Our editor would expand while you type abbreviations. A built-in "Try it" field (see #31) uses the matcher directly. |
| 14 | Multiple abbreviations for one snippet | Espanso `triggers: [...]` | later | Cheap in the model, more UI. |
| 15 | Regex triggers | Espanso | skip | Power-user, hard to explain, larger buffer. |
| 16 | Keyboard-triggered (⌃ key) snippets | Espanso via hex codes | skip | Global shortcut per snippet covers this better (later). |
| 17 | Global shortcut per snippet or group | RT folder / snippet-menu shortcuts | later | KeyboardShortcuts, no tap needed. |

### Placeholders

| # | Feature | How the originals do it | Priority | Notes for us |
|---|---|---|---|---|
| 18 | Date and time | All of them, presets + custom formats | **must** | Presets from the system locale (short, medium, long, ISO 2026-11-07, time). Inserted via an "Insert Placeholder" menu, so nobody has to learn syntax. |
| 19 | Date offsets (date math) | TE "date math"; RT add/subtract; Raycast `offset="+2d"` | **should** | `+1d`, `-1w`, `+3M` style offsets in the placeholder's popover. |
| 20 | Custom date format | TE, RT (Mac), Raycast `format=` | **should** | Unicode pattern field with a live sample. |
| 21 | Clipboard | All of them | **must** | Plain text only. Empty or non-text clipboard inserts nothing. Respects `ConcealedType` (inserts nothing). Reading it can raise macOS's paste-privacy alert (see Permissions). |
| 22 | Cursor position | All of them | **must** | See #7. |
| 23 | Fill-in fields (single line) | TE fill-ins; RT text field + completion dialog with preview; Espanso forms; Raycast arguments (≤ 3, shown in its search bar) | **should** | A small panel near the caret: one field per name, Tab moves, Return inserts, Esc cancels. Same name twice = one field. Risky part is handing focus back (see Platform notes), hence should. |
| 24 | Fill-in choice (popup) | TE popup; RT options (multi-select); Espanso choice/list; Raycast `options=` | **should** | With #23; single choice only. |
| 25 | Fill-in multi-line, optional sections | TE | later | |
| 26 | Selected text | TE, RT (Mac), Raycast | later | Needs ⌘C on the selection before deleting the abbreviation; fiddly ordering. |
| 27 | Nested snippets | TE, RT, Raycast (one level) | later | Cheap once the resolver exists; guard against cycles. |
| 28 | Key presses (Tab, Return, arrows) | TE, RT | later | Useful for forms; dangerous in chat (Return sends). |
| 29 | Scripts (shell, AppleScript, JavaScript) | TE, RT (JS), Espanso (shell) | skip | Security risk with shared snippets (TE itself suggests turning it off), big scope. |
| 30 | AI "smart snippets" | RT (Apple Intelligence / OpenAI), TE AI | skip | No network; not the job. Maybe on-device later. |

### Library and editing

| # | Feature | How the originals do it | Priority | Notes for us |
|---|---|---|---|---|
| 31 | Snippet library window | TE main window with groups; RT editor with folders, tags, preview | **must** | Library archetype: `NavigationSplitView`, sidebar groups, list, detail editor with a live preview and a "Try it" field. |
| 32 | Search the library | TE, RT (title, content, abbreviation), Raycast | **must** | Toolbar search (⌘F) over name, abbreviation and content; case- and accent-insensitive. |
| 33 | Groups / folders | TE groups; RT folders + subfolders + colour tags; Raycast tags | **must** (flat groups) / later (nesting, tags) | One level. Each group can be switched off. Every snippet belongs to exactly one group (there's always a default "Snippets" group), so the model stays simple. |
| 34 | Abbreviation conflict warnings | RT advises distinctive abbreviations; TE nothing visible | **must** | Inline under the field: duplicate (blocks saving), prefix clash in immediate mode ("`;ad` will always fire before `;addr`"), plain-word warning ("could expand while you type normally; starting it with ; helps"). |
| 35 | Snippet name / label | TE label; RT title | **must** | Optional; the list shows the first line when empty. |
| 36 | Create snippet from the clipboard / from a selection | TE hotkey "Create Snippet from Clipboard" | should | Menu item "New Snippet from Clipboard" (reads the clipboard only on click). |
| 37 | Duplicate, delete with undo | Standard | **must** | ⌘D, ⌘⌫ with ⌘Z; Delete Group asks (it holds snippets) and supports undo. |
| 38 | Drag snippets between groups | RT drag sorting | should | |
| 39 | Usage counts, last used, "time saved" | TE statistics; Snippety's comparison lists it | should (count + last used) / skip ("time saved") | Count and date only, stored per snippet; never what was typed around it. Used to sort the search panel. |
| 40 | Rich text, images | TE, RT (Pro) | later | Paste path supports it, but the editor and storage don't in v1. |
| 41 | Snippet suggestions from what you type | TE 5+ watched typing and pasting to suggest snippets; a 2015 analysis found suggestions saved and synced in plain text | skip | Would mean keeping what people type. That's exactly what we promise not to do. |

### Finding a snippet by hand

| # | Feature | How the originals do it | Priority | Notes for us |
|---|---|---|---|---|
| 42 | Quick search panel → insert into the current app | TE inline search at the caret (⌘/); RT snippet menu (menu bar + shortcut) with Auto-Paste; Espanso search bar (⌥Space); Raycast Search Snippets | **should** | `FloatingPanel` in the centre of the active screen, global shortcut (unset by default: ⌘/ is a common app shortcut), type to filter, ↑↓, Return inserts, ⌘1–9, Esc. The app you were in keeps focus. |
| 43 | Snippets in the menu bar menu | RT snippet menu | skip | The search panel does this better; long menus are slow to scan. |

### Import, export, storage, sync

| # | Feature | How the originals do it | Priority | Notes for us |
|---|---|---|---|---|
| 44 | Import macOS Text Replacements | Not offered by Raycast or RT (Raycast offers to override them); Apple's own export is a dragged `.plist` | **must** | Two ways: "Import from This Mac" (AppKit's `NSSpellChecker.userReplacementsDictionary`, no permission, verify on 27) and dropping the plist Apple's System Settings exports. Preview sheet with checkboxes, duplicates unticked. We never edit macOS's list. |
| 45 | Import from TextExpander, Typinator, Espanso, Raycast, CSV | RT imports TE/TypeIt4Me/Typinator/CSV; Raycast imports TE/aText/Espanso/PhraseExpress/JSON | later | Raycast JSON (`name`, `text`, `keyword`) and CSV first; they're simple. |
| 46 | Export / backup | RT CSV/text/PDF/`.rtfolder`; Raycast JSON export | **should** | Export to our JSON; automatic daily backups (last 7) in Application Support. RT reviews about lost libraries make this matter. |
| 47 | Sync across Macs | TE cloud; RT iCloud; Raycast cloud | later | No accounts or network. Later: let people keep the library file in a folder of their choice (iCloud Drive) with safe merging. |
| 48 | Team / shared folders | TE teams; RT shared iCloud folders | skip | Accounts and servers. |
| 49 | iPhone keyboard | RT, TE | skip | Mac only. |

### App, menus, feedback

| # | Feature | How the originals do it | Priority | Notes for us |
|---|---|---|---|---|
| 50 | Menu bar icon shows state | TE red slash when secure input pauses it (8.4.6); Espanso icon change | **must** | Normal / paused / blocked (secure input or missing permission), each with a VoiceOver label. |
| 51 | Status line naming the secure-input app | TE names it ("loginwindow" when it's macOS) | **must** | `kCGSSessionSecureInputPID` from the session dictionary; can name the wrong app when a background app holds it (open radar 48953777), so say "probably". |
| 52 | Reopening the app shows the library / Settings when the icon is hidden | RT: reopening from Finder opens its menu | **must** | `SlopAppDelegate` behaviour (reopen → Settings); we'd rather open the library. |
| 53 | Edit last expanded snippet | TE hotkey | later | Cheap, needs "last expanded" id (memory only). |
| 54 | Shortcuts / App Intents ("Expand snippet", "Pause") | Snippety's comparison: RT lacks it | later | |

**Must-haves, counted: 22** (#1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 18, 21, 22, 31, 32, 33, 34, 35,
37, 44, 50, 51 + #52 is SlopKit behaviour, not counted). Should-haves worth doing in v1 if
the spike goes well: delimiter mode, adapt case, Backspace undo, date offsets and custom
formats, fill-in fields, quick search panel, export and backups, usage counts.

## Key flows

### Flow 1: expand an abbreviation (the main job)
1. Shorthand runs in the menu bar; expansion is on; the person is typing in Mail.
2. They type `;addr`. Each key goes to Mail as normal; Shorthand's tap appends the
   character to its rolling buffer and checks the buffer's end against the abbreviations.
3. On the `r`, the end of the buffer matches `;addr` (and what came before was a space, so
   the whole-word rule holds). The tap hands the match to the main actor; keys pressed from
   now until the insert finishes are held and replayed afterwards, in order.
4. Shorthand checks: the same app is still in front, secure input is off, the focused field
   isn't a password field. It resolves the placeholders (date, clipboard, cursor).
5. It posts five Backspaces, then either types the text (short, single line) or pastes it
   (clipboard saved, text written as transient, ⌘V on the layout's V key, old clipboard put
   back about half a second later unless something else was copied).
6. If there was a `{cursor}`, it presses ← enough times to land there.
7. The held keys are replayed. Total time from the `r` to the text appearing: budgets below.
8. If the person presses Backspace straight away, the expansion is undone and `;addr` is
   back (should).

### Flow 2: first run and permissions
1. First launch: the menu bar icon appears and the library window opens once with an empty
   state ("No snippets yet") and two actions: **New Snippet** and **Import Text
   Replacements…**. No tour.
2. The person adds a snippet (or imports). Only now, with something to expand, the library
   shows a `PermissionGate` row above the list: one sentence ("Shorthand needs to see what
   you type to spot abbreviations, and to type the text for you. Nothing you type is
   stored.") and a button that asks for Accessibility (macOS 27: Privacy & Security ›
   Device Control and Data Access) and opens that pane. If macOS also wants Input
   Monitoring for the keyboard tap, the same row asks for it next (to verify in the spike).
3. The row updates by itself when granted (live re-check); the tap is installed; the menu
   status line says "Expanding". The detail pane's "Try it" field works even before
   permission (it doesn't use the tap), so the person can check the abbreviation right away.
4. If they say no: snippets can still be inserted from the quick search panel by copying
   (clipboard + "Copied" HUD), and the menu says "Needs permission" with a fix-it item.
5. The first time a snippet would read the clipboard (a paste-path expansion, or a
   `{clipboard}` placeholder) and macOS's "Paste from Other Apps" isn't set to Allow, the
   menu and the library show a one-line row explaining it, with a button to that pane. We
   never trigger the system alert in the middle of someone's typing if we can avoid it (see
   Permissions).

### Flow 3: create a snippet
1. Menu bar › New Snippet… (or ⌘N in the library). The library opens with a new snippet
   selected and the Abbreviation field focused. The field suggests starting with `;`.
2. Type the abbreviation; conflict warnings appear under it as you type.
3. Tab to the content; type or paste the text. "Insert Placeholder" (a menu button above the
   editor) adds Date, Time, Clipboard, Cursor, Fill-in field, Choice.
4. The preview under the editor shows the resolved text (sample clipboard text in the
   preview, never the real clipboard: it reads it only if you ask).
5. Changes save as you type (no Save button). The abbreviation is live immediately.
6. "Try it": a one-line field at the bottom of the detail where typing the abbreviation
   expands it, so you know it works without leaving the app.

### Flow 4: import from macOS Text Replacements
1. File › Import Text Replacements… (or the empty state's button).
2. A sheet offers **From This Mac** and **From a File…** (also accepts a dropped plist,
   which is what System Settings › Keyboard › Text Replacements exports when you drag rows
   out).
3. The sheet lists what it found: abbreviation, text, a checkbox. Rows whose abbreviation
   already exists in Shorthand, or that aren't valid abbreviations (contain spaces, too
   long), are unticked with a reason.
4. Import → a "Text Replacements" group with the chosen snippets.
5. A note explains that macOS still applies its own replacements in apps that support them,
   with a button to System Settings › Keyboard so the person can remove duplicates there if
   they like. Shorthand never edits macOS's list.

### Flow 5: forgot the abbreviation (should)
1. Press the search shortcut (set in Settings › Shortcuts) or menu › Search Snippets….
2. A panel appears in the centre of the screen; the app you were typing in keeps focus.
3. Type to filter by name, abbreviation or text; most-used first when the search is empty.
4. Return inserts it where the caret was (same inserter as Flow 1, minus the Backspaces);
   ⌘C copies instead; Esc closes.

### Flow 6: a snippet with fill-in fields (should)
1. Type `;reply`. The snippet has `{field:Name}` and `{choice:Tone|warm|brief}`.
2. Shorthand leaves the abbreviation in place and shows a small panel near the caret (or
   the screen centre if the caret position can't be read) with one row per field and a live
   preview.
3. Tab moves between fields, Return inserts, Esc cancels (nothing changes in the app).
4. On Return the panel closes, focus goes back to the original app and field, then the
   abbreviation is deleted and the text inserted. If focus didn't come back to the same app,
   nothing is typed: the result is copied and a HUD says so (TE added a "replay last
   expansion" key in 8.4.3 for exactly this failure).

### Flow 7: something's blocking expansion
1. A password field in Safari is focused (or Terminal's Secure Keyboard Entry is on).
2. The menu bar icon switches to its blocked state; the menu's status line says "Paused:
   secure input is on, probably in Safari" with a short explanation.
3. As soon as secure input ends, the icon and status return to normal. Nothing typed during
   the pause is buffered or ever seen.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Launch at login | on | | yes (SlopKit) |
| Show in menu bar | on | | yes (SlopKit; reopening the app brings it back) |
| Expand abbreviations | on | | yes (same as the menu's Pause) |
| Expand | Immediately | Immediately / After a space or punctuation | yes (second option is should) |
| Only expand at the start of a word | on | | yes |
| Insert text by | Automatic | Automatic (type short single lines, paste the rest) / Always paste / Always type | yes (Advanced) |
| Put the clipboard back after pasting | on | | yes (Advanced) |
| Undo an expansion with Backspace | on | | should |
| Don't expand in (apps) | Shorthand, Passwords, Keychain Access, 1Password, Bitwarden | add/remove apps | yes (own tab: Apps) |
| Shortcuts: Search snippets | unset | recorder | should |
| Shortcuts: Pause or resume expansion | unset | recorder | yes |
| Backups | daily, keep 7 | | should (Advanced, with "Show Backups in Finder") |
| Import / Export | | buttons | in the library's File menu, not Settings |
| Play a sound | | | later |
| Insertion delays (TE "paste timeout", Espanso pre-paste/restore delays, Raycast "injection delay" / "response time") | | | skip as settings: pick good defaults, adapt per app later if needed |

Tabs: General, Apps, Shortcuts, Advanced, About (SlopKit `SlopSettings`).

## Menus and shortcuts

**Status item menu** (text only, Golden Gate style):
1. Status line: "Expanding" / "Paused" / "Paused: secure input is on, probably in <App>" /
   "Needs permission to expand" (opens the fix).
2. Search Snippets… (shows the global shortcut if set) · New Snippet… · Open Library…
3. Pause Expansion (toggle; shows the shortcut if set)
4. `MenuFooter` (Settings…, About, Quit ⌘Q)

**Library window main menu:**
- File: New Snippet ⌘N, New Snippet from Clipboard ⌥⌘N (should), New Group ⇧⌘N, Import Text
  Replacements…, Import… (later formats), Export… (should), Close ⌘W
- Edit: Undo/Redo, Cut/Copy/Paste, Duplicate ⌘D, Delete ⌘⌫, Find ⌘F (focus search)
- Snippet: Insert Placeholder submenu (Date, Time, Clipboard, Cursor, Fill-in Field, Choice),
  Enable/Disable Group
- Window, Help as standard

**Global shortcuts:** all unset by default (⌘/ and ⌥Space, the originals' defaults, are
used by apps and macOS input switching). `ShortcutRow`s in the Shortcuts tab.

**Quick search panel (should):** ↑↓ move, Return insert, ⌘1–9 insert row 1–9, ⌘C copy, Esc
clear then close.

## Permissions and system integration

| Need | API | Permission | When asked | If refused |
|---|---|---|---|---|
| See keystrokes | `CGEvent.tapCreate` on `keyDown` (+ `flagsChanged`), active tap on its own thread | Accessibility (active taps). A listen-only tap needs Input Monitoring instead; Apple DTS says Accessibility covers listening too. Verify on 27 which TCC service tccd checks for our tap. | Once there's a snippet to expand | No expansion; search panel copies instead |
| Type, Backspace, ⌘V, ← | `CGEvent.post` | Accessibility ("Device Control and Data Access" on macOS 27) | Same moment | Same |
| Mouse clicks (to reset the buffer) | Passive `NSEvent` global monitor for mouse-down | None beyond the above | — | Buffer resets on app switch only |
| Read the clipboard (snapshot before paste; `{clipboard}`) | `NSPasteboard` | "Paste from Other Apps" (macOS 15.4+, enforced on 27.x per Clips research); `accessBehavior` tells us the state | At first need, as an inline row | Automatic mode types instead where it can; long snippets paste without restoring and say so once; `{clipboard}` inserts nothing |
| Secure input state and holder | `IsSecureEventInputEnabled()`, session dictionary `kCGSSessionSecureInputPID` | None | — | — |
| Front app | `NSWorkspace` activation notifications | None | — | — |
| Input source (IME vs layout) | TIS (`TISCopyCurrentKeyboardInputSource`), distributed notification on change | None | — | — |
| Focused field is a password field | AX focused element subrole `AXSecureTextField`, checked only at insert time | Accessibility | — | Rely on secure input |
| Launch at login | `SMAppService` (SlopKit) | None | — | — |
| Text Replacements import | `NSSpellChecker.shared.userReplacementsDictionary` or a user-chosen plist | None (verify) | On click | File route only |

SlopKit's `Permission` enum needs an `.inputMonitoring` case (anchor `Privacy_ListenEvent`,
`CGPreflightListenEventAccess` / `CGRequestListenEventAccess`) if the spike shows it's
needed, and a "Paste from Other Apps" case (Clips needs it too). No App Sandbox (taps and
posting need it off). No network. App Intents later.

## Platform notes (the hard part)

### Listening: the tap

- **Mask: key-down and modifier changes only.** No key-up, no mouse, no scroll. Mouse-down
  resets come from a passive `NSEvent` global monitor, which isn't in the click path.
- **Active, not listen-only,** because we must hold keys typed while an expansion is in
  flight (otherwise a fast typist's next letter lands before our Backspaces and the wrong
  characters get deleted) and, in "drop the delimiter" mode later, swallow the delimiter. An
  active tap is in everyone's typing path, so it follows Triggers' `MouseTap` rules: own
  thread with its own run loop, `.userInteractive`, no allocation, no locks the main thread
  holds for long, no Accessibility/workspace/pasteboard calls in the callback. It decides in
  constant time and returns the event unchanged in the normal case.
- **Callback work per key:** skip if paused, front app excluded, IME active or the event is
  synthetic; otherwise read the produced characters (`keyboardGetUnicodeString`, which
  follows the active layout: Dvorak, AZERTY and friends work), update the buffer, and walk
  a reversed trie of abbreviations from the buffer's end (cost bounded by the longest
  abbreviation, 32). On a match: set "expanding", hand the snippet id to the main actor.
- **Our own events and other apps' synthetic events are ignored.** Everything we post
  carries a marker in `eventSourceUserData`. Events not from the hardware (Dictate typing a
  transcript, Clips' ⌘V, remote-control tools) are skipped too, so we only ever expand what
  the person typed. How to tell hardware from synthetic reliably (source state ID / source
  PID fields) is a spike item.
- **Buffer resets:** expansion, app or window change, mouse-down, arrows/Home/End/Page keys,
  Esc, Forward Delete, ⌥⌫/⌘⌫, any ⌘ or ⌃ combination, Return/Tab (after they've counted as
  a word boundary), input source change, secure input, pause. Backspace removes the last
  buffered character. After a reset we don't know what precedes the caret: treat it as a
  word boundary.
- **Dead keys and input methods.** A dead key (⌥e on US, ^ on French) produces no character
  in the tap and the composed letter only exists inside the app: reset the buffer, so
  abbreviations that need dead keys don't fire (documented; accented letters typed with
  their own key work). When the current input source is an input method (Japanese, Chinese,
  Korean, Vietnamese Telex...), keystrokes are composition, not text: pause matching until a
  plain layout is back. Zed's and Neovide's issue trackers show how easily key handlers
  break IME composition; we stay out of its way entirely.
- **Timeouts and revocation.** On `tapDisabledByTimeout`, re-enable once and log a number;
  repeated timeouts → remove the tap, show a fix-it in the menu. On
  `tapDisabledByUserInput` respect it. Watch Accessibility trust and remove the tap the
  moment it's revoked (Triggers' research: revoking with an active tap can freeze input
  system-wide). Re-check after wake and fast user switching.

### Replacing: Backspaces, then type or paste

- **Backspaces = characters typed for the abbreviation** (+1 for a kept-then-dropped
  delimiter later). Abbreviations are limited to 1–32 characters of letters, digits,
  punctuation and symbols: no whitespace, no emoji or combining sequences, so one Backspace
  is one character in every app.
- **Automatic insertion (recommended default):**
  - *Type* single-line text up to 200 characters with Unicode key events in chunks
    (Dictate's `TextInserter.type`): the clipboard is never touched, no paste-privacy alert,
    nothing to restore.
  - *Paste* anything longer, multi-line (typed Return sends the message in Messages, Slack
    and friends) or containing a Tab: Dictate's approach (`ClipboardSnapshot.capture`,
    `write(transient:)` so Clips skips it, ⌘V on the layout's V key via `virtualKey(for:)`,
    restore after ~450 ms only if `changeCount` is still ours). Paste is one undo step in
    most apps and dodges autocorrect and auto-paired brackets.
  - Settings › Advanced can force always-paste or always-type (and later per app).
- **Guards before inserting:** same front app as when the match fired; secure input off;
  focused element isn't `AXSecureTextField`; app not excluded. Any failure: insert nothing
  and leave the abbreviation as typed.
- **Held keys:** while expanding, the tap swallows real key-downs into a small queue (≤ 64)
  and replays them, in order, after the insert (and feeds them to the buffer). A watchdog
  flushes the queue after 500 ms whatever happens, so keys are never lost.
- **Cursor marker:** count the characters after `{cursor}` and post that many ← presses.
  Editors that auto-indent multi-line pastes can make this land wrong (Espanso documents the
  same); acceptable, documented.
- **Clipboard restore and quitting:** a pending restore is done immediately on
  `applicationWillTerminate`.
- **Shared code.** `ClipboardSnapshot`, `virtualKey(for:)` and Unicode typing now exist in
  Dictate (and a paster in Clips). Shorthand would be the third copy: propose moving them
  into a SlopKit `TextInsertion` piece (owner question).

### Fill-in panel focus (should)

The panel must take key focus to accept typing (a `FloatingPanel` that can become key
without activating the app, as Clips' search panel does). When it closes, the original app
must still be key with the same field focused before we delete and insert: confirm the front
app's pid and focused AX element are the ones we recorded; otherwise copy instead.
Espanso waits 200 ms after its form closes; we should wait for the activation notification
instead of a fixed delay.

### Secure input

When any app enables secure event input (password fields, Terminal's Secure Keyboard Entry,
password managers that leak it), macOS stops delivering keyboard events to all taps, so
Shorthand *cannot* read password fields: the OS guarantees it. We add: clear the buffer
when `IsSecureEventInputEnabled()` turns on (checked on activation changes and a slow 2 s
timer only while secure input is on, never per key), show the blocked state, name the
probable holder, and explain TE's known causes (a background password prompt, Terminal's
Secure Keyboard Entry, right after login or wake: "loginwindow").

### Privacy: what Shorthand keeps

Shorthand sees every keystroke typed while it runs, so we state exactly what happens:

- **In memory only, a rolling buffer of the last 32 typed characters** (the longest
  allowed abbreviation), a fixed-size array owned by the tap thread. It's overwritten as
  you type and cleared on every reset listed above. Nothing else about keystrokes is kept:
  no timings, no counts of keys, no history.
- **While an excluded app is in front, while paused, during secure input and while an
  input method is active, keystrokes aren't buffered at all.**
- **Nothing typed is ever written to disk, logged, sent anywhere or shown.** The log in
  test mode records only timings and decisions ("matched snippet #3", "inserted 41 chars by
  paste"), never characters. No crash reporter, no analytics, no network.
- **What is stored:** your snippets, groups, settings, and per snippet a use count and
  last-used date (should). The held-keys queue and the clipboard snapshot live in memory for
  well under a second.
- The README and the permission row say this in plain words.

### Performance budgets and how to measure

House budgets apply (menu bar app: launch < 300 ms, first icon < 600 ms, idle CPU < 0.2%,
footprint < 50 MB). Typing must never lag, so the input path has its own:

| Path | Budget | How we measure |
|---|---|---|
| Tap callback per key (no match) | p99 ≤ 20 µs, max ≤ 1 ms, zero timeouts | In-process `LatencyStats` histogram (mach time around the callback, numbers only) + `os_signpost` intervals; `CGGetEventTapList` reports our tap's min/avg/max latency and mask, read by a `scripts/perf.sh Shorthand` extension that fails over budget or if the mask has more than key-down + flags-changed. |
| Matcher (trie walk) | p99 ≤ 2 µs with 5,000 abbreviations, zero allocations | Unit benchmark over 1M synthetic keystrokes (loose ×10 assertion in tests, real number logged). |
| Last key of abbreviation → text visible (typed, ≤ 100 chars) | ≤ 30 ms | Signpost from match to last posted event; the test window logs arrival times. |
| Same, pasted | ≤ 120 ms | Same. |
| Clipboard restored | ≤ 600 ms after the paste | Test pasteboard changeCount timeline. |
| Keys typed during an expansion | 100% delivered, in order | Replay test: 20 keys at 15 ms intervals across an expansion; the test window's log must match. |
| CPU while typing (120 wpm for 60 s, replayed in-process) | ≤ 0.5% of one core above idle | `perf.sh`-style sampling during `SHORTHAND_REPLAY`. |
| Idle (not typing) | no wakeups from the input path | `perf.sh` idle CPU; no timers except the 2 s secure-input check while it's on. |

## Testing design: never touch the owner's keyboard or apps

Hard constraint: tests and walkthroughs never type into, read from, or post events to the
owner's real apps, and never read the owner's real Text Replacements or clipboard.

1. **Everything behind protocols** (`ShorthandCore`): `KeyEventSource` (the tap) with a
   scripted fake, `TextInserter` (Backspaces, type, paste, arrows) with a recording fake,
   `PasteboardAccess` (fake in-memory pasteboard), `FrontmostAppSource`,
   `SecureInputState`, `InputSourceState`, `FocusedFieldInspector`, `ReplacementsSource`
   (Text Replacements; fake + fixture plists), `Clock`, `SnippetStore` (temp directory).
   Pure pieces: `RollingBuffer`, `AbbreviationTrie`, `Matcher` (buffer + rules → match),
   `PlaceholderResolver`, `CaseAdapter`, `ConflictChecker`, `InsertionPlanner` (type vs
   paste, Backspace count, ← count), `KeyHoldQueue`, store codec and migrations.
2. **The real callback is testable without posting:** tests construct `CGEvent`s (key-down
   with Unicode strings, flags, synthetic markers) and call the decide function directly.
   Nothing is posted, no tap is created.
3. **Test mode** (env vars, Dictate/Triggers pattern): `SHORTHAND_DATA_DIR` (throwaway
   library and defaults suite), `SHORTHAND_NO_TAP=1`, `SHORTHAND_REPLAY=timeline.json`
   (feeds our own keystroke structs into the real matcher in the running app, in-process),
   `SHORTHAND_INSERT_ONLY_INTO=<bundle id>` (inserter acts only when the test window is in
   front, posting with `postToPid` to that pid; anything else is skipped and logged),
   `SHORTHAND_PASTEBOARD=<name>` (private pasteboard), `SHORTHAND_FAKE_REPLACEMENTS=path`
   (import reads a fixture, never the owner's list), `SHORTHAND_FAKE_APPS=1` (app picker
   shows fake apps), `SHORTHAND_TEST_HOOKS=1`, `SHORTHAND_LOG=path` (timings and decisions,
   never characters). Test snippets contain `slopapp-test` so they can't be mistaken for
   real content.
4. **Throwaway test window:** a tiny target app built from a scratch Swift file into `/tmp`
   (as Dictate's and Triggers' walkthroughs did) with a text view that logs what arrives and
   when. Walkthroughs replay keystrokes in-process and read results from its log and
   `scripts/drive tree`.
5. **Owner idle check:** anything that needs the test window in front waits until the owner
   has been idle ≥ 60 s and aborts if another app comes forward.
6. **What only a human can verify:** the real tap seeing real keys, on the owner's layouts,
   in real apps. Owner hand tests: type an abbreviation in the test window, in TextEdit, in a
   browser field, in an Electron app; secure input pause with a password field; an IME
   switch. Listed in the v1 checklist as "owner hand test".
7. **Guard rail:** `CGEvent.post(tap:)` appears in exactly one production type that test
   mode replaces; `scripts/drive key --global` and `--allow-mouse` are never used.

## Overlap with other Slopapp apps

- **Clips** (clipboard history, pinned items): pinned clips are "paste this again from a
  panel"; Shorthand is "type a few letters, get text with placeholders". Shorthand's
  temporary clipboard writes are marked transient, so they never show up in Clips' history.
  Both have a search panel: neither ships a default global shortcut, so they can't collide.
  Later: "Make Snippet" from a pinned clip, `{clipboard}` reading older Clips entries (skip
  for now: couples the apps).
- **Triggers**: owns gestures, mouse buttons and key-combo shortcuts, and deliberately has
  no keyboard tap, no typed-word triggers and no text insertion (its research marks those as
  Shorthand's). Only Shorthand taps the keyboard.
- **Dictate**: inserts transcripts with synthetic events. Shorthand ignores synthetic
  events, so it never expands inside dictated text, and Dictate's own word replacements stay
  Dictate's. Both share the insertion code (see shared code above).
- **macOS Text Replacements**: imported, never edited. In immediate mode Shorthand fires
  before macOS does (macOS waits for the word to end). In delimiter mode both may act on the
  same abbreviation in Cocoa apps; the import note suggests removing duplicates in System
  Settings.

## UX patterns worth adopting

- **Expansion is invisible when it works and loud only when it can't.** The icon state and a
  named reason ("secure input, probably in Safari") turn the most common support question of
  every text expander into a sentence.
- **Insert placeholders from a menu, show a live preview.** Nobody should have to remember
  syntax; RT's preview-before-insert and TE's macro bar both point this way.
- **A prefix habit.** Suggesting `;` (or any symbol) as the first character keeps
  abbreviations from firing in ordinary words; conflict warnings explain the why.
- **Live immediately.** No Save button, no restart: type an abbreviation and it works.
- **A safe default exclusion list** with password managers (Raycast ships one).
- **"Try it" inside the editor,** so testing a snippet doesn't need TextEdit (RT's
  troubleshooting starts with "try it in TextEdit").
- **Search when memory fails,** inserted where the caret was, focus never stolen.
- **Automatic type-vs-paste**, as Espanso's auto backend does, so short things leave the
  clipboard alone and long things arrive in one piece.

## What we won't copy, and what we'll do better

- Not copying: names, icons, artwork, wording, sounds, macro syntax of any original, signature
  visuals (TE's macro bar look, RT's rocket), paid tiers, accounts, cloud sync, upsells.
- Doing better:
  - **Free, local, no account.** TE's subscription and account for a local job are its top
    complaint since 2016; RT caps the free tier at 10 snippets.
  - **Privacy stated and kept:** a 32-character in-memory buffer, nothing logged, no
    "suggestions" built from what you type (TE's stored suggestions in plain text).
  - **Never lose a library:** atomic writes, daily backups, export (RT reviews describe wiped
    libraries).
  - **No typing lag, measured:** budgets above, checked by tooling, not promised.
  - **Works where macOS's own replacements don't** (Electron apps, VS Code, browsers), and
    imports them in two clicks.
  - **Clear failure states:** permission, secure input, excluded app, IME, each with a
    sentence and a fix, instead of "it just stopped working".
  - **Keys typed during an expansion are never lost or reordered.**
  - **A simple, fast editor:** RT reviews call editing cumbersome; ours is a list and a form
    with autosave and keyboard navigation.
  - **Doesn't pollute clipboard history** (transient marker), and puts the clipboard back
    with every type intact.

## Edge cases

- **Fast typing:** next key pressed during the expansion (held and replayed); abbreviation
  typed in the middle of a burst; autorepeat.
- **Word rule:** abbreviation inside a word (`design` vs `sig`), at the start of a line,
  right after a click (unknown context = boundary), after punctuation.
- **Conflicts:** two snippets with one abbreviation (blocked), prefix clashes in immediate
  mode (warned), disabled group's abbreviations ignored, renamed abbreviation live at once.
- **Case:** Exact vs Adapt with `Addr`, `ADDR`, `aDDR`; content starting with a digit or
  symbol.
- **Placeholders:** empty clipboard, image or file on the clipboard, concealed clipboard,
  huge clipboard (cap at 100,000 chars), `{cursor}` at start/end/absent, two cursors (first
  wins, editor warns), literal braces (`{{`), unknown placeholder (shown as an error in the
  editor, inserted as typed), date presets in non-English locales, offsets across month ends
  and DST.
- **Content:** empty content (can't save), 100 KB of text (paste; cap 100,000 chars),
  multi-line, tabs, RTL text, emoji, combining accents, Windows line endings in imports.
- **Apps:** Electron apps, browsers (Safari, Chrome, Firefox), VS Code/JetBrains
  (auto-pairing and autocomplete), terminals (Return, Secure Keyboard Entry), Messages/Slack
  (Return sends: multi-line goes by paste), remote desktop and VMs (may not accept Unicode
  events: exclude or always paste), apps that block paste, games (exclude).
- **Front app changes** between match and insert (abort), or between fill-in panel and
  insert (copy instead).
- **Secure input:** stuck after wake ("loginwindow"), held by a background app (holder may be
  misnamed), Terminal's Secure Keyboard Entry, password field focused when a match would
  fire.
- **Layouts and IMEs:** Dvorak, AZERTY, QWERTZ, US International with dead keys, switching
  layouts mid-word, Japanese/Chinese/Korean input methods (paused), ⌘V on non-QWERTY layouts.
- **Permissions:** never granted, granted while running (live), revoked while running
  (remove the tap at once, no freeze), "Paste from Other Apps" set to Ask or Deny, ad-hoc
  builds losing the grant on rebuild (`scripts/drive launch --direct`).
- **System:** sleep/wake (tap re-enabled), fast user switching, display sleep, macOS
  re-disabling the tap after a timeout, the app quitting with a clipboard restore pending.
- **Clipboard:** something copied between our write and restore (don't restore), clipboard
  with many types (images, files, rich text) restored exactly, Clips running (skips our
  write).
- **Import:** Text Replacements with spaces in the shortcut, duplicates, empty list, a plist
  that isn't Apple's export, 10,000 entries (people who hit macOS's slowdown), CJK user
  dictionary entries.
- **Library:** 0, 1, 5,000 snippets (search < 16 ms per keystroke), very long names and
  abbreviations, deleting a group with snippets (asks, undo), the library file damaged
  (load the latest backup and say so), two Shorthand instances (second one quits).
- **Accessibility:** VoiceOver names every control and the icon state; Reduce Motion for the
  panels; Full Keyboard Access in the fill-in panel.
- **Light and dark**, inactive window greying, Golden Gate sidebar.

## Our v1 scope

Must-haves (the test step walks these):

- [x] Abbreviations expand as you type, in any app, immediately when the last character is
      typed (owner hand test in the test window, TextEdit, a browser, an Electron app).
      *Replayed through the real engine into the test pad; real keyboard = owner hand test.*
- [x] Whole-word rule on by default; can be turned off.
- [x] Exact-case matching (plus "adapt case" per snippet, a should).
- [x] Automatic insertion: short single lines typed, long or multi-line pasted; Settings can
      force paste or type.
- [x] Clipboard snapshot and restore after a paste, every type intact, temporary write
      marked transient (Clips skips it), no restore if something new was copied.
      *SlopKit `ClipboardPaster`; until "Paste from Other Apps" is allowed, pastes without
      restoring (owner decision).*
- [x] Keys typed during an expansion are held and replayed in order; none lost.
      *Listen-only tap: they're remembered and retyped after the snippet (see build notes).*
- [x] Placeholders: date and time (locale presets), clipboard (plain text, concealed
      respected), cursor position. *Also offsets and custom formats (shoulds).*
- [x] Pause/resume from the menu and an optional global shortcut (tap removed when paused).
- [x] "Don't expand in" app list with the default password-manager entries and Shorthand
      itself; nothing buffered while one is in front.
- [x] Secure input: nothing read, buffer cleared, blocked icon, status line naming the
      probable holder; no insert into `AXSecureTextField`. *AX field check: owner hand test.*
- [x] IME active → matching paused; dead keys reset the buffer; non-US layouts match on
      produced characters; ⌘V uses the layout's V. *Unit-tested; real IME/layouts: hand test.*
- [x] Synthetic events (ours and other apps') never matched.
- [x] Library window: groups sidebar (enable/disable per group), snippet list, detail editor
      with Insert Placeholder menu, live preview, autosave, "Try it" field.
- [x] Toolbar search over name, abbreviation, content (⌘F), case- and accent-insensitive.
- [x] Conflict warnings: duplicate (blocks), prefix clash, plain-word warning.
- [x] Duplicate (⌘D), delete with undo (⌘⌫ / ⌘Z), delete group asks.
- [x] Import from macOS Text Replacements: from this Mac and from an exported plist, preview
      with checkboxes, duplicates unticked, note about macOS's own copies (tested only with
      fixtures; never the owner's list). *"From This Mac" on 27: owner hand test.*
- [x] Menu bar icon states (normal, paused, blocked) with VoiceOver labels; status line;
      `MenuFooter`.
- [x] Permissions asked only when there's a snippet to expand, via `PermissionGate`, live
      re-check; "Paste from Other Apps" explained when first needed; tap removed at once if
      Accessibility is revoked. *Revocation: hand test.*
- [x] Privacy: 32-character in-memory buffer only; test-mode logs contain no typed
      characters (grep the log in the walkthrough); README states it.
- [x] Library stored as JSON in Application Support with atomic writes (+ daily backups).
- [x] Performance: tap callback p99 ≤ 20 µs / max ≤ 1 ms / no timeouts and mask check via
      `CGGetEventTapList`; matcher benchmark; insert latencies; house idle budgets.
- [x] Test mode (env vars above), replay timelines, throwaway test window; walkthrough never
      posts outside the test window.

Should (v1 if the spike and time allow, else v1.1): delimiter mode, adapt case, Backspace
undo, date offsets and custom formats, fill-in field + choice panel, quick search panel,
New Snippet from Clipboard, drag between groups, export + daily backups, use counts.

## Open questions

1. **Insertion default.** Recommend *Automatic* (type single lines ≤ 200 chars, paste the
   rest) over TE-style always-paste: it avoids the macOS 27 paste-privacy alert for most
   expansions and leaves the clipboard alone. OK?
2. **"Paste from Other Apps".** Restoring the clipboard after a paste means reading it,
   which raises macOS's alert unless Shorthand is set to Allow. Ask the person to allow it
   at first need (inline row), or paste long snippets without restoring and say so?
   Recommend: ask, and until allowed, don't restore (never interrupt typing with an alert).
3. **Fill-in fields in v1?** They're the most-loved advanced feature (TE, RT, Espanso,
   Raycast all have them) but bring focus hand-off risk. Recommend: build after the musts,
   ship in v1 only if the focus check works across the hand-test apps; else v1.1.
4. **Default timing:** immediately (recommended) or after a space/punctuation?
5. **Shared insertion code:** move `ClipboardSnapshot`, layout-aware key lookup and Unicode
   typing into SlopKit (touches Dictate and Clips), or copy into Shorthand for now?
6. **Quick search panel in v1** (should) or later? It also gives people without
   Accessibility a way to use snippets (copy).
7. **Placeholder syntax** shown in the editor: plain `{date}` style tokens with a menu to
   insert them (recommended), or rendered tokens (chips) in the editor (nicer, more work)?
8. **Library location:** Application Support only (recommended for v1), or let people pick a
   folder (iCloud Drive) for poor-man's sync now?
9. **Default exclusions:** password managers and Shorthand only, or also terminals and remote
   desktop apps?
10. **Usage counts:** keep a per-snippet count and last-used date (helps search ranking), or
    store nothing at all about use?

## Sources

- TextExpander: [Expansion settings](https://textexpander.com/learn/using/preferences/expansion-settings),
  [Expand based on characters before](https://textexpander.com/learn/using/snippets/expanding-snippets/expand-when),
  [Advanced snippet elements (macros, fill-ins)](https://textexpander.com/help/desktop/specials.html),
  [Hotkeys](https://textexpander.com/learn/using/preferences/hotkey),
  [Inline Search](https://textexpander.com/learn/using/searching-snippets/inline-search),
  [Secure input on macOS](https://textexpander.com/learn/troubleshooting/mac/secure-input-on-macos-why-textexpander-stops-expanding-snippets),
  [Mac release notes](https://textexpander.com/release/mac),
  [Snippet group settings](https://textexpander.com/learn/using/snippet-groups/snippet-group-settings)
- TextExpander reviews and history: [Macworld TextExpander 6 review](https://www.macworld.com/article/227761/textexpander-6-review-a-snippets-subscription-service-thats-priced-too-high.html),
  [TidBITS: subscription one year later](https://tidbits.com/2017/04/05/textexpander-by-subscription-one-year-later/),
  [TidBITS: TextExpander 5 suggestions](https://tidbits.com/2015/05/28/textexpander-5-for-mac-makes-snippet-suggestions/),
  [Analysis of suggestions storage](https://jblevins.org/log/suggestions),
  [G2 reviews](https://www.g2.com/products/TextExpander/reviews),
  [MPU forum: Typinator vs TextExpander](https://talk.macpowerusers.com/t/typinator-vs-textexpander/17281)
- Rocket Typist: [Product page](https://witt-software.com/rockettypist/),
  [Mac guide](https://witt-software.com/en/rockettypist/help/),
  [Abbreviations](https://witt-software.com/en/rockettypist/help/mac/abbreviations/),
  [Settings reference](https://witt-software.com/en/rockettypist/help/mac/settings/),
  [Set up](https://witt-software.com/en/rockettypist/help/mac/setup/),
  [Find and insert](https://witt-software.com/en/rockettypist/help/mac/using-snippets/),
  [Glossary and shortcuts](https://witt-software.com/en/rockettypist/help/mac/reference/),
  [Troubleshooting](https://witt-software.com/en/rockettypist/help/mac/troubleshooting/),
  [Privacy](https://witt-software.com/en/rockettypist/help/mac/privacy/),
  [Setapp listing and reviews](https://setapp.com/apps/rocket-typist),
  [Setapp article](https://setapp.com/news/rocket-typist-is-all-about-text-expansion),
  [Mac App Store listing, version history, reviews](https://apps.apple.com/us/app/rocket-typist/id6463636684),
  [Snippety's comparison (competitor, used with care)](https://snippety.app/compare/rocket-typist)
- Espanso (behaviour only): [Options](https://espanso.org/docs/configuration/options/),
  [Match basics](https://espanso.org/docs/matches/basics/),
  [Forms](https://espanso.org/docs/matches/forms/),
  [App-specific configurations](https://espanso.org/docs/configuration/app-specific-configurations/),
  [Secure Input on macOS](https://espanso.org/docs/troubleshooting/secure-input),
  [Typinator vs Espanso (vendor blog)](https://blog.ergonis.com/hc/articles/27897272054684)
- Raycast: [Snippets manual](https://manual.raycast.com/snippets),
  [Dynamic placeholders](https://manual.raycast.com/dynamic-placeholders),
  [Cursor forum: expansion reliability](https://forum.cursor.com/t/cursor-interfering-with-raycast-snippet-expansion/33460),
  [snippet-explorer issues](https://github.com/raycast/snippet-explorer/issues)
- macOS Text Replacements: [Replace text and punctuation](https://support.apple.com/guide/mac-help/replace-text-punctuation-documents-mac-mh35735/mac),
  [Back up and share text replacements](https://support.apple.com/guide/mac-help/back-up-and-share-text-replacements-on-mac-mchl2a7bd795/mac),
  [`NSSpellChecker.userReplacementsDictionary`](https://developer.apple.com/documentation/appkit/nsspellchecker/userreplacementsdictionary),
  [Dynalist: not in Electron](https://talk.dynalist.io/t/apple-native-text-replacement-not-working-on-macos-desktop-app/6811),
  [JetBrains: not in IDEs or VS Code](https://intellij-support.jetbrains.com/hc/zh-cn/community/posts/31946013281298/comments/31978883723666),
  [AppleVis: large lists slow typing](https://applevis.com/forum/macos-mac-apps/beware-macos-text-replacement-typing-slowdown-apple-mail-text-edit-safari)
- Platform: [Apple forums: listen-only vs default tap permissions](https://developer.apple.com/forums/thread/122492),
  [Apple forums: Input Monitoring list](https://developer.apple.com/forums/thread/828052),
  [Apple forums: does a listen-only tap block events](https://developer.apple.com/forums/thread/734237),
  [CGEventTapOptions](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions),
  [tapDisabledByTimeout](https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbytimeout),
  [Who holds secure input](https://fnordig.de/til/macOS/secure-input.html),
  [Open radar 48953777: secure input PID can be wrong](https://openradar.appspot.com/48953777),
  [Apple forums: macOS 27 "Device Control and Data Access"](https://developer.apple.com/forums/thread/850583),
  [Pasteboard privacy preview (mjtsai)](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4),
  [Zed: keyboard localization](https://zed.dev/blog/keyboard-localization),
  [Neovide: dead keys through IME on macOS](https://github.com/neovide/neovide/issues/1866)
- This repo: `apps/Dictate/Sources/Dictate/TextInserter.swift`,
  `apps/Dictate/Sources/DictateCore/ClipboardSnapshot.swift`,
  `apps/Clips/Sources/ClipsCore/PasteboardType.swift`,
  `apps/Triggers/Sources/Triggers/MouseTap.swift`, `docs/research/triggers.md`
  (tap rules, budgets, testing design), `docs/research/clips.md` (paste privacy, pinned items).

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (<date>)
| Finding | Severity | Decision | Why / fix |
|---|---|---|---|

## Owner decisions (2026-11-07)

- **Expand immediately**, the moment the abbreviation's last letter is typed.
- **Clipboard:** long or multi-line snippets paste; the first time one does, explain and ask for
  "Paste from Other Apps" in context. Until it's allowed, paste without restoring the clipboard.
- **Fill-in fields: v1.1.**
- **Shared code moves to SlopKit:** the clipboard snapshot (marked transient) and layout-aware typing
  and paste used by Dictate and Clips become one SlopKit implementation that all three use.
- Other open questions: take the doc's recommendations.

## Spike results (2026-11-07, macOS 27.2)

### 1. Which permission does a listen-only keyboard tap need?

Probe: a tiny Swift tool (`/tmp/shorthand-test/spike/probe.swift`, not in the repo) that reports
`AXIsProcessTrusted`, `CGPreflightListenEventAccess`, `CGPreflightPostEventAccess`, then creates a
`.listenOnly` and a `.defaultTap` keyboard tap (`keyDown | flagsChanged`) and reads them back with
`CGGetEventTapList`. Its callback only ever read our own marker field, never a key.

| Run | AX trusted | Listen (Input Monitoring) | Post | Listen-only tap | Active tap |
|---|---|---|---|---|---|
| Child of this terminal (inherits its grants) | yes | yes | yes | created, enabled, `options=1`, mask `0x1400` | created, enabled |
| Fresh ad-hoc `.app` (own bundle id) via LaunchServices | no | no | no | not attempted (see below) | not attempted |

- **The tap itself is created only after Accessibility is granted**, so a fresh install never
  triggers macOS's "receive keystrokes" alert on its own. We didn't create a listen-only tap in
  the ungranted bundle on purpose: macOS would put its Input Monitoring alert on the owner's
  screen. `tccd` logged nothing readable for the probe.
- Sources disagree on whether Accessibility alone covers a listen-only tap (Apple DTS says
  listening is the separate ListenEvent service, shown as Input Monitoring; some projects
  report Accessibility implies it on 13+). Nothing published covers 27.
- **Decision (built):** Shorthand needs Accessibility to post keys anyway, so it asks for that
  first. Then it checks `CGPreflightListenEventAccess()` and whether `tapCreate` succeeded; only
  if macOS still refuses does the library show a second row for Input Monitoring
  (`CGRequestListenEventAccess` + `Privacy_ListenEvent`). The row re-checks every second while
  shown and the tap installs the moment it works. **Owner hand test H1** settles which of the
  two macOS 27 actually wants.
- **Synthetic vs hardware:** events created from a `.hidSystemState` source carry
  `eventSourceStateID == 1`; `.combinedSessionState` and `nil` sources carry 0, private sources a
  random ID; every app-created event carries the poster's pid. So: our own events are skipped by
  marker (`eventSourceUserData`), anything with a state ID other than the HID system's is
  "synthetic" and never matched (Dictate's typing, Clips' ⌘V). Hardware events reaching a
  session tap with state ID 1 is the documented behaviour but couldn't be observed without
  reading the owner's keys: **hand test H2** (if nothing expands at all, this is the first
  suspect; the log line `stats` shows `syntheticSkipped`).
- `postToPid` events don't reach session taps (probe saw 0 of its own marked events), which is
  why walkthroughs feed keys into the engine in process instead.

### 2. "Paste from Other Apps" when reading the clipboard back

- A fresh ad-hoc app launched through LaunchServices on this Mac reports
  `NSPasteboard.general.accessBehavior == .alwaysAllow`, as Clips' research found. So on this
  Mac, restore works silently for a new install; on Macs where it's `.ask`, reading another
  app's clipboard data raises macOS's alert.
- Only the **snapshot before pasting** reads another app's data. Our own (transient) write is
  never read back; the restore check uses `changeCount`, which never asks. Writing never asks.
- We couldn't trigger the `.ask` state without changing System Settings (not allowed), and
  reading the real clipboard is off limits, so the alert itself is **hand test H6**.
- **Built per the owner decision:** if `accessBehavior` isn't `.alwaysAllow`, a long snippet
  pastes **without reading the clipboard at all** (no alert mid-typing), the snippet stays on
  the clipboard as a normal copy, a one-time HUD explains it, the menu gets "Allow Paste from
  Other Apps…", and the editor shows the same row under any snippet that pastes or uses
  `{clipboard}`. `{clipboard}` inserts nothing until allowed. Test override:
  `SHORTHAND_PASTE_PRIVACY=asks`.

## Decisions made while building

| Question | Decision | Why |
|---|---|---|
| Active or listen-only tap | **Listen-only** (brief), `tailAppendEventTap`, `keyDown + flagsChanged`, own thread | A listen-only tap is never in anyone's typing path: a stalled Shorthand can't delay, drop or freeze typing, and macOS can't time it out of the event stream. |
| Keys typed during an expansion (the doc assumed holding them) | The engine remembers up to 16 printable keys typed between the match and the insert (memory only, < 0.5 s); the insert deletes them with the abbreviation and retypes them after the snippet, in order. Any other key in that window (arrow, Return, Backspace, a shortcut, a click, synthetic input) drops the expansion and leaves the text as typed. Keys landing while our events are being posted (≈ 1–2 ms for typed snippets) are counted (`interleaved=` in the log) but can't be fixed; documented. | Gets "none lost, in order" without being in the event path. |
| Insert-time password check cost | AX focus query with a 20 ms timeout, connection pre-warmed in the background when an app comes to the front | First query to an app took 50 ms (timeout); pre-warmed it's ~3 ms. |
| Paste write delay | 30 ms (Dictate keeps its 60 ms) | Pasted budget is 120 ms; 30 ms was reliable in every replay. |
| Typing speed | Unicode chunks of 20 UTF-16 units posted back to back (no sleeps; Dictate keeps 4 ms) | Fewer gaps for a fast typist's keys to land inside the snippet. |
| Settings tabs | General, Apps, Shortcuts, Advanced, About, built from SlopKit's tab pieces (`GeneralSettingsTab`, `SettingsForm`, `AboutSettingsTab`) | `SlopSettings` has no slot for an extra tab. |
| Reopen behaviour | Reopening the app opens the library (not Settings) | Research doc #52. |
| Import "From a File…" | SlopKit `DropZone` (click to choose or drop) | One control instead of a button plus a hand-drawn target. |
| Adapt case scope | ASCII and Latin-1 letters fold; other scripts match as written | Keeps the matcher allocation-free; documented. |
| Fill-ins, quick search panel, delimiter mode | Not in this build | Fill-ins v1.1 (owner); search panel and delimiter mode are shoulds (deferred below). |
| App icon | New tile colour **sloe** `#74506A` added to `herbarium.py` (every colour was taken); a rubber stamp (ochre accent) over a card of text lines; rosemary ("for remembrance") printed on the card | The few letters you type stamp the whole thing. Card uses the `base` role so it holds 1.35:1 in dark mode. |

## Build notes (2026-11-07)

### SlopKit consolidation (owner decision)

New in `apps/SlopKit/Sources/SlopKit/TextInsertion/`:

- `ClipboardSnapshot` (moved from DictateCore unchanged: every item and type, transient +
  auto-generated markers).
- `ClipboardPaster`: snapshot → transient write → delay → ⌘V → delay → restore only if
  `changeCount` is still ours; `restore: false` reads nothing; `restorePendingNow()` for quitting.
- `SyntheticKeyboard`: Unicode chunking (20 units, surrogate-safe, Return between lines), keys,
  layout-aware ⌘V/⌘C; destination (`hidEventTap`, `annotatedSession`, `process(pid)`), Dictate's
  suppression-state filter, an optional marker.
- `KeyboardLayout.virtualKey(for:)` (the layout-aware lookup Dictate and Clips each had).
- `PasteboardPrivacy` (Clips' `ClipboardAccess`, which was marked as a SlopKit candidate).
- Tests: `Tests/SlopKitTests/TextInsertionTests.swift` (14: snapshot round trip, transient
  marking, paster restore / newer copy kept / empty clipboard / no-restore / restore on quit,
  chunking, surrogates, newlines, tabs, layout key).

Switched over, behaviour kept identical: **Dictate** `TextInserter` uses
`SyntheticKeyboard(destination: .hidEventTap, permitsLocalEventsWhileSuppressed: true)` and
`ClipboardPaster` (same 60/450 ms, same transient rule; Return keeps inheriting the source's
flags as before); its `ClipboardSnapshot` and `ClipboardTests` moved to SlopKit. **Clips**
`Paster.sendPaste()` uses `SyntheticKeyboard(destination: .annotatedSession)` (same
annotated-session post, same source, ⌘ only); `ClipboardAccess` is now a typealias of
`PasteboardPrivacy`. `scripts/check.sh Dictate Clips`: all lint/icon/test/bundle/smoke pass
(Clips 110 tests). Neither was installed.

### Tests

- ShorthandCore: **76 tests in 12 suites** (rolling buffer, matching and word rule, adapt case,
  duplicates, dead keys, synthetic events, gate, keys typed meanwhile, timeouts, undo, key
  decoding from real `CGEvent`s, rules and conflicts, placeholders incl. locales and month
  ends, library, store and backups/recovery, Text Replacements import incl. 10,000 rows, search,
  expander with recording fakes, benchmark).
- SlopKit: 14 new tests (above).

### Walkthrough (release build, test mode, replayed in process into the throwaway test pad)

The screen stayed **locked for the whole session**, so macOS hid every window from
Accessibility: `scripts/drive tree/shot/menubar` refused. What was verified instead:

- Replays (`SHORTHAND_REPLAY`-style timelines via the `replay` hook) through the real engine,
  keys posted only to the pad's pid, results read from the pad's own log and text file:
  typed snippets, date, cursor marker (34 ← presses, later keys land at the cursor), adapt case
  (`;Hi` → "Hello…"), multi-line paste with clipboard restored, keys typed right after a
  match retyped in order (`…out.abc`), 20 keys at 15 ms across an expansion all delivered in
  order, word rule (`design;sig` stays), word rule off (expands), Backspace undo (`;sig` back),
  excluded front app (nothing), always-type / always-paste, `{clipboard}` (text, concealed →
  empty), paste privacy "asks" (pastes, no read, snippet stays as a normal copy, `{clipboard}`
  empty).
- Secure input for real: with the screen locked, the status line read "Paused: secure input is
  on, probably in loginwindow" and nothing expanded.
- Real tap (launched `--direct`, still confined to the pad): `CGGetEventTapList` shows one tap,
  mask `0x1400` (key-down + flags-changed only), listen-only, enabled. Pause → `taps=0`;
  resume → reinstalled.
- No permission (normal launch): status "Needs permission to expand", no tap, no system alert.
- Logs: `grep` for every snippet text and abbreviation in all logs → 0 hits.
- Offscreen snapshots (`SHORTHAND_SNAPSHOT_DIR`), light and dark: empty library, editor
  (cursor preview, prefix clash, plain-word and unknown-placeholder warnings), import preview
  and start, notices, Settings General/Apps/Advanced. Paths: `/tmp/shorthand-test/snaps/`.
  Offscreen rendering can't draw the split view, toolbar or menus.

### Measurements

| Budget | Result |
|---|---|
| Matcher p99 ≤ 2 µs, 5,000 abbreviations (release, 1M keys) | mean 0.08 µs, p99 ≤ 1 µs, max 17.9 µs |
| Callback path p99 ≤ 20 µs, max ≤ 1 ms (decode a real `CGEvent` + lock + engine + histogram, release, 1M keys) | mean 0.09 µs, p99 ≤ 1 µs, max 9.8 µs |
| Same, during replays on the main thread (cold) | p99 ≤ 20 µs, max 71 µs |
| Tap mask / mode (`CGGetEventTapList`) | `0x1400`, listen-only, enabled; real-key latency: hand test H3 |
| Typed, match → last key posted ≤ 30 ms | 4.0–4.9 ms (3 ms of it the password-field check) |
| Typed, match → arrived in the test pad | 22–34 ms; the pad is a background app on a locked screen receiving events by pid, which adds ~20 ms of delivery (the last replayed key itself took 3 ms) |
| Pasted, match → ⌘V posted ≤ 120 ms | 36 ms (30 ms of it the write delay); arrived in the pad at 45–48 ms |
| Clipboard restored ≤ 600 ms after paste | 450 ms after ⌘V (`clipboard restored` in the log) |
| Keys during an expansion: 100%, in order | 18/18 in order (15 ms intervals); 3/3 retyped in order (same turn as the match) |
| CPU while typing, 120 wpm for 60 s (replay, no echo) | 0.19% of one core (budget 0.5%) |
| Idle (30 s, tap installed) | 0.006%; `perf.sh`: launch 144 ms, first status item 296 ms, idle 0.035%, footprint 21.9 MB (busy machine, load 6) |

### Gates

- `scripts/check.sh Shorthand Dictate Clips --perf`: everything passes except **Clips perf
  memory 53.9 MB**, which is the owner's own running Clips (`/Applications/Slopapp/Clips.app`,
  pid 29971: footprint 53.6 MB) that `perf.sh` latched onto because it shares the bundle id; it
  was not quit. The rebuilt Clips run in its own test mode (`CLIPS_DATA_DIR`, private
  pasteboard) measured 29.2 MB and 0.045% idle CPU.
- `scripts/drive tree` (no `[unlabeled]`), window and status-item screenshots, the on-screen
  walkthrough of the library and menus: **not run, screen locked**. Code review: every
  icon-only control has a label (toolbar New Snippet, New Group, duplicate warning, import
  checkboxes "Import <abbreviation>", text view "Snippet text", fields and pickers named).

### Gap review (v1 scope)

All must-haves are built (see the ticked list above). Shoulds built: adapt case, Backspace
undo, date offsets and custom formats, export + daily backups, use counts, drag between groups
(on-screen untested). Deferred:

| Item | Status | Why |
|---|---|---|
| Fill-in fields and choices | later (v1.1) | Owner decision. |
| Quick search panel (#42) | later (v1.1) | A should; the library, Try It and conflict warnings cover v1. Needs its own focus hand-off work. |
| "After a space or punctuation" timing (#2) | later | Owner chose immediate; one setting less. |
| New Snippet from Clipboard (#36) | later | Would read the clipboard; small, but not needed for v1. |
| `scripts/perf.sh` tap-stats extension | not done | `scripts/` is off limits for app builders; the `stats` test hook logs the same `CGGetEventTapList` numbers. |
| On-screen gates | pending | Screen locked all session. |

### Design review (§10)

Pass from code and snapshots: 1, 2 (light/dark snapshots), 3 (File/Edit/Snippet menus, status
menu), 4, 5, 6, 7 (empty states with one action), 8 (rows only when there's a snippet, live
re-check, exact panes), 9 (delete snippet/group undoable; group delete asks), 10 (no network
code), 11, 13 (no custom animation), 15 (lint), 26 (semantic colours only; `.textOrange` /
`.textRed` for warnings). Pending an unlocked screen: 12 (VoiceOver tree), 14, 16–25
(window buttons, corners, alignment, hairlines, contrast, states, toolbar and sidebar on Golden
Gate, inactive window).

### Owner hand-test list

Use the release build (`build/Shorthand.app`). Add a test snippet such as `;zz` → "hello" first.

1. **H1 permissions:** first launch, add a snippet, press the row's button, grant Accessibility
   only. Does the menu say "Expanding", or does a second row ask for Input Monitoring?
2. **H2 real keys:** type `;zz` in TextEdit, Safari (a text field), an Electron app (VS Code or
   Slack) and Terminal. It should expand the instant you type the last `z`.
3. **H3 latency:** type normally for a few minutes with Shorthand running: no lag, no
   dropped keys; expansions feel instant.
4. **H4 fast typing:** type `;zz` then keep typing without pausing: nothing lost or reordered.
5. **H5 password field:** Safari password field, then Terminal with Secure Keyboard Entry on:
   menu icon turns to the lock, status names the app, nothing expands; back to normal after.
6. **H6 Paste from Other Apps:** a multi-line snippet with the clipboard holding an image: the
   image is back on the clipboard afterwards and Clips' history doesn't show the snippet. If
   macOS is set to Ask, confirm no alert appears mid-typing and the menu offers the fix.
7. **H7 layouts and IMEs:** a Dvorak or AZERTY layout (abbreviation matches what you type;
   long snippets paste), US International dead keys (`´` then `e` never triggers), Japanese
   input (paused while on, menu says so).
8. **H8 revoke:** turn Shorthand off in Accessibility while it runs: typing keeps working
   everywhere, the menu says it needs permission.
9. **H9 Import from This Mac:** the preview lists your Text Replacements (`NSSpellChecker`
   on 27; never read by us).
10. **H10 Dictate and Clips:** dictate into a field and paste from Clips as usual: same
    behaviour as before (they now use the shared SlopKit code). A dictated `;zz` must not
    expand.

## Feature round: fill-ins, formatted snippets, nesting, quick search, imports (2026-11-12)

The owner compared Shorthand with the apps it replaces and listed the gaps people notice:
fill-ins, rich text and images, nested snippets, a quick insertion search, and importing
existing libraries. All five are built into the existing placeholder system, library window
and insertion path (inventory #23, #24, #25 partly, #27, #40, #42, #45 move from should/later
to built).

### How it fits

- **One placeholder language.** New tokens sit next to `{date}`/`{cursor}`: `{field:Name}`,
  `{field:Name=default}`, `{choice:Name|a|b}`, `{optional:Name}…{/optional}` (`=off`),
  `{snippet:;abbr}`. They're in Insert Placeholder (with the name selected, ready to type
  over; Optional Section wraps the selection), checked by the editor (`TemplateCheck`:
  missing or cyclic references, stray or unclosed sections, one name for two kinds), and shown
  in the preview with empty fields as ‹Name›.
- **The parser now keeps UTF-16 source ranges** (`PlaceholderParser.tokens`) and the resolver
  returns `pieces` (text + which snippet and range it came from). That one change carries
  formatting through placeholders and nested snippets: literal text keeps its own runs,
  placeholder output takes the token's formatting, plain snippets inside formatted ones get
  the default document font (`RichText.assemble`).
- **Expander flow.** A match whose snippet (or anything it includes) has fill-ins takes the
  keys typed meanwhile, leaves the tap in its "posting" state and returns `.needsFillIn`.
  The app shows the form; `complete` deletes the abbreviation (+ those keys), inserts,
  retypes the keys; `cancel` leaves everything as typed. If another app came forward, nothing
  is typed and the result is copied (`.targetChanged`), as flow 6 planned. The search panel
  uses `insert(_:)`: no Backspaces, same guards, same form.
- **Formatted snippets** store RTFD in `Snippet.richText` with `content` as its exact plain
  mirror (images are U+FFFC), so matching, search, conflict checks and the old JSON all keep
  working. They always paste (a formatted paste can't be typed), with RTFD, RTF, HTML (images
  as data URLs) and plain text on one pasteboard item, plus PNG/TIFF when the snippet is just
  an image. The clipboard is borrowed and restored exactly like text pastes.
- **Imports** share one sheet and one model (`ImportEntry` → `ImportCandidate` → `apply`,
  groups by name). The Text Replacements API is unchanged on top of it.

### Decisions

| Question | Decision | Why |
|---|---|---|
| Fill-in syntax | `{field:Name=default}`, `{choice:Name\|a\|b}`, `{optional:Name}…{/optional}` | Reads like the existing tokens; no new escaping rules. First choice is preselected (no default marker to learn); TextExpander's `default=` is moved to the front on import. |
| Optional sections' default | On (`=off` to start unticked) | The usual P.S. or disclaimer is wanted most times; one key turns it off. |
| Names | Case- and accent-insensitive, first occurrence defines the control and its default | "Reused names fill once" across nested snippets too; a second `{field:Name}` without a default takes the first one's. |
| Form placement | Below the caret (Accessibility `AXBoundsForRange`), else below the focused field, else screen centre; kept on screen | "Near the insertion point" in Cocoa apps, Safari and Chromium; still sensible in apps that hide the caret. |
| Form keyboard | Text fields take real focus; Tab/Shift-Tab move through every control; a focused choice or section shows the system focus-ring colour and takes ↑↓/←→, a letter (type to select) or Space | AppKit only lets popups and checkboxes take focus with Full Keyboard Access on, so SwiftUI focus alone couldn't Tab onto them (found in the walkthrough). |
| Form dismissal | Esc, Cancel, a click in another app, another app coming forward. Not "lost key": the choice's own menu takes key status | The first build cancelled the form when ↓ opened the popup's menu (walkthrough). |
| Fill-in values | Memory only, never stored or logged | Same promise as typed keys. |
| Nested lookup | By exact abbreviation, any group (a group that's off is the place for parts); depth 8; cycles left out and flagged | Matches how people build signatures from parts; abbreviations are what they already know. |
| Formatted text default font | `NSFont.userFont` (the system's document font) | What RTF readers assume; system UI font names don't travel to the web. Editor-added "text colour" attributes are stripped so text follows the target app and dark mode. |
| Formatted + Always Type | Still pasted | Formatting can't be typed; Settings explains it. |
| Pasted screenshots | TIFF attachments become PNG once, in the editor | TIFF made library files balloon. |
| Search panel contents | Every snippet with text, groups that are off included, snippets without an abbreviation included; most used, then most recent, first | Picking by hand is deliberate; search-only snippets are a real use. |
| Search ranking | Abbreviation (leading `;` ignored) exact, then prefix, then a title word, then anywhere | "sig" should find `;sigf` before a reply that mentions it (walkthrough). |
| Search panel default shortcut | Unset (Settings › Shortcuts and the menu item) | Research doc: ⌘/ and ⌥Space collide with apps and input switching. |
| Search with Shorthand in front or without Accessibility | Copy instead, with a HUD | It can't type; copying still gets the snippet out. |
| Import formats | Text Replacements (this Mac, dragged plist), TextExpander `.textexpander` (XML plist), espanso YAML, CSV, Shorthand JSON | The brief's three plus two cheap, common ones. One drop zone; the format is detected from the contents. |
| TextExpander rich text | Read when the plist has RTF/RTFD data next to the plain text (keys `richText`/`rtf…`, else any key containing "rich"/"rtf"); else plain with a note | TextExpander's schema isn't documented publicly and no TextExpander export was available to check; the plain path is certain. |
| TextExpander script types | `snippetType` 2–7 or a `#!` first line: listed, can't be ticked | Scripts are out of scope (inventory #29). |
| espanso extras | Extra `triggers` become snippets containing `{snippet:first}`; `markdown`, `html`, `image_path` come in formatted; `shell`/`script`/`random` vars and `regex` triggers reported | Keeps one abbreviation per snippet without losing the extra triggers. |
| YAML | A small subset parser in core (`MiniYAML`), no dependency (brief) | Block maps/lists (incl. lists at the key's indent), all scalar styles, block scalars with chomping, flow `[…]`/`{…}`, comments, anchors. |
| Export to other formats | Not built | Shorthand's JSON keeps everything (formatting included); other formats would lose fill-ins and formatting. |
| Test-copy shortcuts | Test mode (and the smoke test) use `test.`-prefixed shortcut names | KeyboardShortcuts always reads `UserDefaults.standard`, which a test copy shares with the installed app (same bundle id). |
| Smoke test | `SLOPAPP_SMOKE_TEST=1` is now a test mode: a throwaway data folder, the test defaults suite, no tap | It used to load the real library (and write that day's backup) with the real settings. |

### Shared pieces built in the app (SlopKit candidates)

- `Sources/Shorthand/RichClipboardPaster.swift`: `ClipboardPaster` for several types at once
  (snapshot, transient write, ⌘V, restore unless something newer was copied, restore on quit).
- `Sources/Shorthand/CaretLocator.swift` (+ `ShorthandCore/CaretPlacement.swift`, pure and
  tested): the caret's screen rect through Accessibility and `FloatingPanel.show(near:)`.

### Build notes

- Tests: **125 in 20 suites** (76 before; new suites: fill-ins/sections/nesting, quick search,
  formatted text, YAML subset, date codes, TextExpander, espanso, other imports; new expander
  tests for the form, search insertion, target change and formatted pastes). The YAML,
  date-code and macro converters, `RichText` (RTFD round trip, assembly, adapted case, HTML
  with data-URL images, image-only pastes, Markdown and HTML import) are all covered.
- Fixtures only under `/tmp/shorthand-test/`: a generated library (`fixtures/library.json`
  with a fill-in reply, a formatted signature with a generated PNG, nested and cyclic
  snippets), `Replies.textexpander`, `espanso/match/base.yml` (+ `$CONFIG/images`), a Text
  Replacements plist and a CSV. Nothing from the owner's libraries was read.
- New test hooks: `search`, `search-query`, `search-pick`, `search-copy`, `insert`, `fill`,
  `fill-insert`, `fill-cancel`, `import-file` (paths under `/tmp/shorthand-test/` only),
  `select` (it was documented but missing), `editor-select-all`.

### Walkthrough (debug and release builds, `--direct` test copy, `SHORTHAND_NO_TAP=1`, keys only into a throwaway pad, private pasteboard)

The screen was unlocked but someone was using the Mac (HID idle 0–9 s), so: no `--allow-mouse`,
no `key --global`, no activating apps. Everything ran through Accessibility presses and keys
posted to Shorthand's own pid. The system is in dark mode (not changed), so on-screen shots
are dark; light mode is from the offscreen snapshots (`SHORTHAND_SNAPSHOT_DIR`).

- **Fill-ins:** replayed ` ;reply` → the form opened under the pad's caret with Name focused;
  typed a name, Tab, ↓ and a letter changed Tone, Tab, Space turned P.S. off (its Note field
  dimmed), Return → the pad got `Hi slopapp-test Ann, … Talk soon.` plus the nested formatted
  signature (23 bold characters and the image as an RTFD attachment), the abbreviation gone,
  the private clipboard back to what it held (`clipboard restored`). Esc → `fill-in
  cancelled`, `;reply` left as typed.
- **Nesting:** `;nest` → `<slopapp-test hello>`; `;loop`/`;loop2` → `ab` (cycle stopped);
  `;sigf` in a group that's off doesn't expand by itself but works when included. The editor
  shows "“;loop2” would include itself…".
- **Formatted:** the formatting bar's Bold (pressed through Accessibility) on the selected
  signature → the next paste had 0 bold characters; again → all bold. Formatted editor and
  preview checked in dark (adaptive text colour) and light (snapshot).
- **Search panel:** opened centred; readable previews (dates resolved, fill-ins as ‹Name›);
  "sig" ranks the signature first; Return pasted it formatted at the pad's caret (no
  Backspaces) and restored the clipboard; ⌘2 typed the second row; ⌘C copied `<slopapp-test
  hello>`; a fill-in snippet picked from search opened the form. With
  `SHORTHAND_ASSUME_TRUSTED=0` a pick is copied instead and the menu offers the permission.
- **Imports:** TextExpander (2 of 3 importable; "A key press (tab) was left out"; the shell
  snippet can't be ticked), espanso (4 of 6; shell variable and regex trigger reported),
  Text Replacements fixture (the spaced shortcut flagged), CSV. Imported snippets then
  expanded in the pad: espanso date + cursor, image (attachment), Markdown bold, the Text
  Replacement, the TextExpander fill-in with "Best" preselected.
- **Try It:** typing ` ;reply` one key at a time opens the same form (as a sheet) and expands
  with the values.
- **`scripts/drive tree`:** 0 `[unlabeled]` in the library, editor (incl. format bar
  segments Bold/Italic/Underline), search panel, fill-in form, import sheet and Settings.
- Status menu: "Insert a Snippet…" between the status line and New Snippet….
- Logs: only counts, timings and decisions (no snippet text, no typed text).
- **Not tested: owner active** — the global "Insert a snippet" shortcut with a real key press
  (needs recording a shortcut and `key --global`); the handler calls the same
  `toggleSearch()` as the menu item and the hook. The real keyboard tap was not installed
  in this round (replays only); the tap code didn't change apart from the panel gate.

### Found and fixed in the walkthrough

| Finding | Fix |
|---|---|
| The form opened with the Tone popup focused | `.defaultFocus` + focus set after the panel is key |
| ↓ on the Tone popup cancelled the form (its menu took key status) | The form no longer closes on losing key; clicks in other apps and app switches cancel it |
| Tab couldn't reach popups/checkboxes without Full Keyboard Access | Own focus handling for choices and sections, with the system focus-ring colour |
| The form's preview collapsed to one line | Reserves four lines (no jump as values change) |
| The search panel showed raw `{field:Name}` | Readable previews; titles from the resolved first line |
| "sig" ranked a reply mentioning `;sigf` above `;sigf` | Ranking ignores the abbreviation's leading symbol; title words count |
| "Tone, Tone" for VoiceOver | Picker labelled once |
| Try It's popover didn't show when the field was scrolled away | Try It's form is a sheet |
| Return in a sheet's text field didn't insert | `onSubmit` on the form's text fields |
| Import column widths | Abbreviation column capped |

### Gap review against the brief

| Ask | Status |
|---|---|
| Fill-ins: text, choices, optional sections; keyboard-first form near the caret; reused names once | Built and walked through |
| Rich text and images, rich where accepted, plain fallback | Built; RTFD/RTF/HTML/plain verified on the pasteboard and in a Cocoa text view. Browsers, Electron and plain-text apps: owner hand test (H11) |
| Nested snippets with cycle detection | Built and walked through |
| Quick insertion search with a global shortcut | Built; the shortcut's real key press is the one thing not tested (owner active) |
| Import TextExpander, espanso, Text Replacements; report what didn't map; export if natural | Built (+ CSV, Shorthand JSON); export stays Shorthand JSON (decision above) |
| Clipboard preserved; tests on a named pasteboard; owner's libraries never read | Yes |
| Test copies never register the owner's shortcuts or expand in their apps | Test mode: `test.` shortcut names, `SHORTHAND_NO_TAP`, `SHORTHAND_INSERT_ONLY_INTO`; smoke runs are test mode now |

Deferred: multi-line fill-in fields (imports become one line, with a note), key presses in
snippets, exporting other formats, TextExpander's newer `.textexpandersettings` backups,
remembering last fill-in values (would mean storing what was typed).

### Owner hand tests added

11. **H11 formatted paste targets:** expand the formatted signature in Mail, Gmail in Safari
    and Chrome, Slack, and Terminal: formatting and logo where the app takes them, plain text
    in Terminal.
12. **H12 fill-in placement:** expand a fill-in snippet in TextEdit, Safari, Chrome, VS Code:
    the form sits under the caret (or the field), and the text lands in the same field.
13. **H13 search shortcut:** set Settings › Shortcuts › Insert a snippet, press it in any app,
    pick with ↓ and Return.
14. **H14 real exports:** import a real TextExpander group file (a rich snippet among them) and
    an espanso `base.yml`, and check the preview's notes.
