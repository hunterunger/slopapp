# Clips research (inspired by Paste)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: Paste
> 6.3.6 (build 16375, Setapp edition, bundle `com.wiheads.paste-setapp`; installed copy at
> /Applications/Setapp/Paste.app, read-only) + its help center, update log, App Store /
> Setapp listings, reviews and forum threads, on 2026-11-02, on macOS 27.2. Setapp now lists
> 7.0.4; features after 6.3.6 are noted from the update log. We study how it works so we
> don't reinvent the wheel. We never copy its name, icons, artwork, wording, sounds or
> signature visuals.
>
> Paste is the owner's daily clipboard manager and was running throughout. It was not quit
> and no setting was toggled. Its panel and history were **never opened**: no global hotkey,
> no "New Text Item", no click on its status item (which opens the panel). Only the
> Settings window was opened, from the app's main menu (Paste > Settings…), and closed
> afterwards on the pane it opened on. Panel behaviour below comes from the official docs,
> the app's own UI strings (read from its bundle, not copied) and reviews.

> **Parity pass (2026-11-03):** the owner asked for Clips to look and work much more like
> Paste, with its copy sound. That supersedes the "centred list + preview pane" panel, the
> "no sounds" decision and the "won't copy the strip" notes below. See
> [Parity pass](#parity-pass-2026-11-03) at the end.

## The job

Clips remembers everything you copy so you can get it back later. People reach for it
many times a day: "I copied that link ten minutes ago and have copied five things since",
"paste that address I use every week", "I need this as plain text, not with the web page's
fonts". Done feels like: **press a shortcut, type two or three letters, press Return, and
the thing is in the app you were typing in**, with the cursor never leaving that app. It
also has to feel safe. A clipboard history is a log of passwords, codes and private
messages, so leaving out secrets and keeping everything on the Mac matter as much as the
features.

The one interaction that matters: **shortcut → panel appears instantly in the centre of
the screen with the newest clip selected → type to filter → Return pastes into the
frontmost app (⇧Return as plain text, ⌘C copies only) → panel is gone.** The newest clip
is what ⌘V already gives you, so the most common path is shortcut, ↓ once or twice (or
⌘2/⌘3), Return. The search path (shortcut, a few letters, Return) is next. Both must take
well under a second.

## Who and when

- Re-pasting something copied a few minutes ago after copying other things since (the
  most common use by far).
- Finding a link, command, tracking number or snippet from earlier today or last week by
  typing a word from it.
- Pasting formatted text from a browser or doc as plain text into an email, chat or code.
- Keeping a handful of always-needed snippets (address, boilerplate reply, a hex color,
  a terminal command) pinned so they never age out.
- Grabbing an image or file copied earlier and pasting or dragging it into a chat or doc.

Frequency: dozens of times a day, each use 1–3 seconds. Settings are touched once at
setup and rarely after. The owner has used Paste daily for years and has rebound its
activation shortcut, so the hotkey choice matters to them.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason).

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Record clipboard history | Background agent (`LSUIElement`), saves text, links, images, files and colors on every copy | must | Poll `NSPasteboard.general.changeCount` on a ~0.5 s timer with tolerance (design system §8). Reading `changeCount` and `types` doesn't trigger the macOS pasteboard alert; only reading contents does. Store in SwiftData; images as external storage. |
| 2 | Keep formatting, paste any type | Stores the full item; pastes with original formatting by default | must | Store every representation we understand (plain, RTF, HTML, RTFD, URL, file URLs, PNG/TIFF/JPEG/HEIC) and write them all back, so the target app picks its best one. |
| 3 | Global shortcut opens the panel | ⇧⌘V default, rebindable; clearing it doesn't disable the app (menu icon still opens it) | must | `KeyboardShortcuts` + `ShortcutRow`. Default **⇧⌥V** (see "Hotkey" below and Open questions). Show "shortcut unavailable" in the menu if registration fails. |
| 4 | Panel layout | Full-width strip along the bottom of the active display; horizontal cards, newest first, each with a content preview, source-app identity and relative time; resizable height, compact mode | must (our own) | **Not the horizontal strip.** `FloatingPanel` centred on the active screen: search field on top, vertical list on the left, preview pane on the right. Non-activating, so the target app keeps focus. |
| 5 | Search as you type | Typing anywhere in the panel searches titles, content and metadata (and text in images); results update live; Return moves into results, Return again pastes | must | Search field always focused; ↑/↓ move the selection while typing, Return pastes. Case- and diacritic-insensitive substring over an in-memory index of each clip's text (first ~64 KB). < 16 ms per keystroke at 10 000 clips. |
| 6 | Paste into the frontmost app (direct paste) | Puts the item on the clipboard and sends ⌘V to the frontmost app; needs Accessibility; without it, Return just copies | must | Same mechanism: write item, hide panel, post ⌘V with `CGEvent` (needs `AXIsProcessTrusted`). Check trust on every paste; fall back to copy + HUD + inline permission row. |
| 7 | Paste vs copy setting | "Paste Items": to the active app (default) or to the clipboard only | must | General setting "After choosing a clip: Paste into the active app / Copy to the clipboard". ⌘C in the panel always copies only. |
| 8 | Paste as plain text | ⇧Return or context menu per item; ⇧⌘1–9 for quick paste; global "always plain text" switch; plain-text modifier rebindable to ⌘/⇧/⌃/⌥ | must | ⇧Return and context menu; "Always paste as plain text" switch (off). Fixed modifier (⇧), no rebinding. |
| 9 | Quick paste by number | ⌘1–⌘9 paste the nth item in the current list; modifier rebindable | must | ⌘1–⌘9 with a small number badge on the first nine rows. Bare digits go to the search field, so we don't follow the design system's "1–9 pick directly" here (noted deviation). |
| 10 | Keyboard navigation | ←/→ move, ⌘↑/⌘↓ first/last, ⇧←/→ extend selection, ⌘A select all, Tab switches search ↔ results, Esc dismisses | must | ↑/↓ move, ⌘↑/⌘↓ first/last, Page Up/Down, Esc clears the search first, then dismisses. Multi-select later. |
| 11 | Preview | Selected item shows a preview; Space opens a larger Quick Look (text, images, PDFs, links in a built-in browser) | must | Always-visible preview pane: full text (scrollable), image fitted, file icon + name + folder + "missing" state, link host + full URL, color swatch + value; plus metadata line (source app, time, size/characters). Larger Quick Look (⌘Y) = should. |
| 12 | Pinned items / Pinboards | Named, colored pinboards; pin via context menu or drag; items in one board at a time; pinned items never expire; ⌘←/⌘→ switch boards; ⇧⌘N new board; shared boards via iCloud | must (pinned) / later (boards) | v1: one "Pinned" group: ⌘P pins/unpins, pinned clips show in their own section at the top of the panel when the search is empty and are exempt from retention and Clear History. Named boards later. |
| 13 | History retention | "Keep History": Day / Week / Month / Year / Forever (default Month); shortening asks before deleting older items; pinned items kept | must | Same five choices, default 1 month. Prune on launch and hourly, never on the hot path. Shortening shows a confirmation with the count. |
| 14 | Erase history | Settings button, confirmation, pinned items survive | must | "Clear History…" in the status menu and Settings; confirmation (it can't be undone); pinned survive. |
| 15 | Delete one item | Delete key, Undo ⌘Z | must | ⌘⌫ deletes the selected clip (⌫ belongs to the search field); ⌘Z undoes while the panel is open. |
| 16 | Skip concealed / transient content | "Ignore confidential content" (detected passwords) and "Ignore transient content" switches; Apple Passwords excluded by default | must | Always skip items carrying `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType` and the legacy markers (1Password, TypeIt4Me, Typinator, Butler/TextExpander). Check `types` before reading contents, so a secret is never even read. On by default; concealed skip isn't a toggle. |
| 17 | Ignore apps | Privacy → Ignore Applications list (+/−), checks the frontmost app at copy time; built-in exclusions aren't shown in the list | must | List with defaults pre-filled and visible (Apple Passwords, Keychain Access, 1Password, Bitwarden, KeePassXC, Dashlane, Proton Pass; verify bundle IDs). Prefer `org.nspasteboard.source` when present, else the frontmost app. |
| 18 | Pause recording | ⌘T or menu: Pause, or for 15 min / 30 min / 1 h / 3 h / 8 h; "Paused until …" state | should | Status menu "Pause" submenu (15 min, 1 hour, Until resumed) + "Ignore Next Copy" (borrowed from other managers). Icon shows the paused state. |
| 19 | De-duplicate | Not documented for history; stack drops duplicates | must | Same content copied again (hash of the primary representation) moves the existing clip to the top instead of adding a copy. Pasting from Clips does the same. |
| 20 | Source app | Each card shows the app it came from; search filters by app | should | Store bundle ID; show the app icon in rows and the name in the preview. Filter by app = later. |
| 21 | Type filters | Filters by content type, app, device, date range, pinboard; suggestions appear in the search field | should | Type filter in the search bar: All, Text, Links, Images, Files, Colors (⌘⌥1…6 or a pop-up). App/date filters later. |
| 22 | Colors | Six-digit hex (with `#` or containing a–f) becomes a color item with a swatch | should | Same rule (it avoids treating numbers as colors). Swatch in row and preview. |
| 23 | Library / history window | None on Mac (everything lives in the panel) | should | `NavigationSplitView` (archetype c): sidebar All / Pinned / Text / Links / Images / Files / Colors, list, detail; toolbar search; "Show History Window" in the menu. Good for browsing and cleanup without the pressure of the hot path. |
| 24 | Drag out of the panel | Drag a card into any app | should | `onDrag` with `NSItemProvider` for files, images and text. |
| 25 | Open link / file, reveal | ⌘O opens selected link or file; Reveal in Finder for files | should | ⌘O opens; context menu "Show in Finder" for files. |
| 26 | Edit before paste | ⌘E edits text in place (formatting kept), Writing Tools, image rotate, extract text from image | later | v1.1: plain-text edit in the history window that saves as a new clip. |
| 27 | Rename / label items | ⌘R or click title | later | Useful once pinned snippets grow. |
| 28 | New text item | ⌘N creates a text item by hand | later | Cheap once editing exists; mainly for pinned snippets. |
| 29 | Paste stack / sequential paste | ⇧⌘C starts a stack: every copy goes into it, ⌘V pastes them one by one in order; direction toggle | later | Needs Accessibility and an event tap or ⌘C interception. Niche. |
| 30 | Multi-select, paste together | ⌘/⇧-click or ⇧-arrows, Return pastes all | later | Join with newlines for text. |
| 31 | Text in images (OCR) search | Searches recognised text inside screenshots | later | Vision on device, off the main actor, after capture. Nice, costs CPU. |
| 32 | Hide from screen sharing | "Show during screen sharing" switch (on by default) | should | `NSWindow.sharingType = .none` on the panel when off. Default open question; verify it's honoured by ScreenCaptureKit on macOS 27 and how it affects `scripts/drive shot`. |
| 33 | Shortcuts / App Intents | Create Item, Create Pinboard, Get Item at Index, Get Latest Item | later | "Get clip at index" and "Copy clip" are cheap with AppIntents. |
| 34 | URL scheme | `paste://` | later | Not needed for v1. |
| 35 | Link previews | Downloads page title/image for links (switch on by default; warns it can trigger one-time links) | skip | Network on capture, privacy risk. Show host and URL only. |
| 36 | iCloud sync, iPhone/iPad apps, shared pinboards, Teams | CloudKit sync, iOS keyboard, share extension | skip | No network, Mac only. |
| 37 | Intelligent suggestions, MCP server, Writing Tools | Apple Intelligence suggestions (asks for Screen Recording), local MCP server for AI tools | skip | Out of scope; Screen Recording for a clipboard app is a big ask. |
| 38 | Sound effects | Copy and paste sounds (on by default) | skip | Design system: no sounds. |
| 39 | Analytics, crash reporting | Bundles PostHog and Sentry frameworks | skip | No telemetry, ever. A selling point. |
| 40 | Paywall, trial, rating and "upvote" prompts, what's new, social links | Many in-app upsell and review screens | skip | Not who we are. |

### Hotkey

Paste's default is ⇧⌘V. For ours:

- **⇧⌘V**: taken by Paste (if both run, one silently loses), and Chrome / Google Docs / Slack
  use it for "paste as plain text".
- **⌥⌘V**: Finder uses it to *move* a copied file ("Move Item Here"). Taking it globally
  breaks a real Finder action. Avoid.
- **⌥⇧⌘V**: "Paste and Match Style" in Apple's apps. Avoid.
- **⇧⌥V** (recommended default): no common app binding; on a US layout it types "◊", which
  nobody needs. Caveats: Option-only hotkeys misbehaved on macOS 15.0–15.1 (Paste warns
  about this in its recorder), and Option-character hotkeys may not fire while a password
  field has secure input (Maccy documents this). Both acceptable.
- **⌃⌥V**: the safe fallback the design system prefers if ⇧⌥V turns out to collide.

Handle conflicts: if `KeyboardShortcuts` can't register the shortcut, the status menu shows
"Shortcut unavailable" with "Choose Shortcut…" opening the Shortcuts tab. The recorder
already refuses combos used by menu items or system shortcuts.

## Key flows

### Flow 1: paste something from history (the main job)
1. The user is typing in any app (say Mail). Clips has been recording in the background.
2. Press the global shortcut. Paste: a full-width strip slides up from the bottom of the
   display in use. Ours: a centred panel appears within one frame, without taking focus
   from Mail. The newest clip is selected; the search field has the caret.
3. Optional: type a few letters. The list filters live; the first match is selected and
   the preview pane updates. ↑/↓ change the selection.
4. Press Return. Paste: puts the item on the clipboard, hides, sends ⌘V to the frontmost
   app. The pasted item moves to the top of history. Variants: ⇧Return = plain text;
   ⌘1–9 = paste that row directly; ⌘C = copy only (then the user pastes with ⌘V
   themselves); double-click = Return.
5. Esc (or clicking outside) dismisses without doing anything. In Paste, Esc while
   searching first clears the search.
6. Without Accessibility permission, step 4 only copies. Paste shows a one-time prompt
   asking whether to paste directly to the named app, with "Allow Access" (opens System
   Settings) or "Not Now, Copy to Clipboard". Ours: copy, show a "Copied" HUD with "Press
   ⌘V to paste", and keep a one-line row at the bottom of the panel ("Allow Clips to paste
   for you" + "Open Settings…") until the permission is granted.

### Flow 2: first run / onboarding
1. Paste (per its docs and UI strings): a short setup asks how to open Paste (activation
   shortcut), how long to keep history (with a warning that unlimited uses disk space),
   whether to open at login, whether to turn on iCloud sync, and on recent macOS asks for
   clipboard access ("Allow Pasteboard Access"). Accessibility is asked the first time you
   paste. The setup is followed by trial, plan and review prompts.
2. Ours (proposal; no tour): the status item appears. The first launch opens the panel once
   in its empty state, centred: one line saying copies show up here, the shortcut to open
   it, and, only if needed, a "Clipboard access" row (see Permissions). Copy anything and
   it appears in the list live. Launch at login is on by default (it's useless otherwise;
   the toggle is in General).
3. Accessibility is asked only the first time the user pastes (Flow 1, step 6).

### Flow 3: pin a snippet
1. Paste: right-click a card → Pin → choose a pinboard (or drag the card onto a pinboard
   tab). The item stays in history too; pinboards never expire.
2. Ours: select a clip, ⌘P (or context menu "Pin"). A pin glyph appears; the clip moves to
   the Pinned section at the top when the search is empty. ⌘P again unpins.

### Flow 4: keep a secret out of history
1. A password manager copies a password with the concealed marker → Clips sees the marker
   in `types` and doesn't read or store it. Nothing appears in the list.
2. An app on the ignore list copies anything → skipped.
3. A browser extension copies a password without a marker → it *is* recorded (Paste has
   the same gap). The user can delete it (⌘⌫), add the browser to the ignore list, or use
   "Ignore Next Copy" beforehand.
4. Pause from the status menu for a period; the icon shows paused; nothing is recorded.

### Flow 5: clean up
1. Settings → General → Keep history: shorten it → confirmation shows how many clips will
   be deleted → older unpinned clips go.
2. Status menu → "Clear History…" → confirm → all unpinned clips gone.

## Settings inventory

Observed in Paste 6.3.6 (Settings window: sidebar with General, Privacy, Shortcuts,
Subscription, plus a Help Center link). Defaults are from the docs where the observed value
may be the owner's own choice.

| Setting | Default | Options | Keep? |
|---|---|---|---|
| General → Open at login | on (onboarding) | switch | yes: "Launch at login", on |
| General → iCloud sync | off until set up | switch + last-synced time | no (no network) |
| General → Sound effects | on | switch | no |
| General → Paste Items | To active app | To active app / To clipboard (with a small illustration) | yes, as "After choosing a clip" |
| General → Always paste as Plain Text | off | checkbox | yes, off |
| General → Keep History | Month | slider: Day, Week, Month, Year, Forever | yes, as a pop-up, default 1 month |
| General → Erase History… | n/a | button + confirm (pinned kept) | yes, "Clear History…" |
| Privacy → Show during screen sharing | on | switch | yes (default: open question) |
| Privacy → Generate link previews | on | switch | no (network) |
| Privacy → Ignore confidential content | opt-in switch | switch | no switch: always skip concealed |
| Privacy → Ignore transient content | on | switch | no switch: always skip transient/auto-generated |
| Privacy → Ignore Applications | empty list shown (Apple Passwords excluded silently) | +/− list of apps | yes, with visible defaults |
| Shortcuts → Activate Paste | ⇧⌘V | recorder + clear | yes, "Open Clips", ⇧⌥V |
| Shortcuts → Activate Paste Stack | ⇧⌘C | recorder + clear | later (with the stack) |
| Shortcuts → Show next / previous Pinboard | ⌘→ / ⌘← | recorders | later (with boards) |
| Shortcuts → Quick Paste | ⌘ + 1…9 | pop-up of single modifier keys | fixed ⌘, no setting |
| Shortcuts → Plain Text mode | ⇧ | pop-up of single modifier keys | fixed ⇧, no setting |
| Shortcuts → Reset shortcuts to default… | n/a | button + confirm | no (one shortcut) |
| Subscription | n/a | plan info, Manage… | no |
| Intelligence (7.x, per docs) | on where available | Suggestions switch | no |

Ours, by design-system tab:

- **General**: Launch at login; Show in menu bar; After choosing a clip (Paste into the
  active app / Copy to the clipboard); Always paste as plain text; Keep history (1 day, 1
  week, 1 month, 1 year, Forever); Clear History…; Hide from screen sharing (should).
- **Shortcuts**: Open Clips (recorder). A static list of the in-panel keys below it.
- **Advanced → Privacy**: Ignored apps (list with defaults, +/−); "Ignore clips from other
  devices" (Universal Clipboard, `com.apple.is-remote-clipboard`, off); status rows for
  Clipboard access and Accessibility with "Open Settings…" buttons.
- **About**.

## Menus and shortcuts

**Paste's main menu** (it's an agent app, so this shows only while its window is key):
- App menu: About, New Text Item ⌘N, Settings… ⌘,, Help ▸ (Getting Started, Keyboard
  Shortcuts, Help Center, Product Updates, Feature Request, Contact Support), a social
  link, Pause ▸ (Pause ⌘T, Pause for 15 min / 30 min / 1 h / 3 h / 8 h), Quit ⌘Q.
- File: Close ⌘W, Close All ⌥⌘W. Edit: standard. Window: Minimize.
- Status item: not readable through Accessibility here (`drive` found no menu bar item);
  per the docs clicking it opens the panel, with Pause available from it. Not clicked.

**Paste's in-panel shortcuts** (docs): Esc dismiss; ←/→ next/previous; ⌘↑/⌘↓ first/last;
⇧←/⇧→ extend selection; ⌘A select all; Return paste; ⇧Return paste plain; ⌘1–9 quick
paste; ⇧⌘1–9 quick paste plain; ⌘C copy; Space Quick Look; ⌘O open; ⌘R rename; ⌘E edit;
⌘N new text item; Delete delete; ⌘Z undo; ⌘F search / again for all filters; Tab switch
search ↔ results; ⌘G jump to the item's place in its list; ⇧⌘N new pinboard; ⌘←/⌘→
previous/next pinboard; ⌘T pause; ⌘, settings; ⌘Q quit.

**Ours, status item menu** (`.menu` style): status line ("Recording" / "Paused until
3:40 PM" / "Clipboard access is off") → Open Clips (⇧⌥V shown) → Show History Window →
Pause ▸ (15 Minutes, 1 Hour, Until Resumed / Resume) → Ignore Next Copy → Clear History…
→ `MenuFooter` (Settings… ⌘,, About Clips, Quit ⌘Q). No clip contents in the menu (the
menu bar is visible when screen sharing; the panel is the one place content shows).

**Ours, in the panel**:

| Key | Action |
|---|---|
| type | filter |
| ↑ / ↓, ⌘↑ / ⌘↓, Page Up / Down | move selection |
| Return / double-click | paste (or copy, per setting) |
| ⇧Return | paste as plain text |
| ⌘1 … ⌘9 | paste row 1–9 |
| ⌘C | copy only, dismiss, "Copied" HUD |
| ⌘P | pin / unpin |
| ⌘⌫ | delete clip (⌘Z undoes) |
| ⌘O | open link / file (should) |
| ⌘Y | larger Quick Look (should) |
| ⌘⌥1 … ⌘⌥6 or Tab | type filter (should) |
| Esc | clear search, then dismiss |
| ⌘, | Settings (dismisses panel) |

## Permissions and system integration

- **Clipboard access ("Paste from Other Apps", macOS 15.4+, enforced on 27.x).** Reading
  another app's pasteboard contents in the background can raise a system alert; the
  alert's "Allow" only lasts once. The lasting fix is System Settings → Privacy & Security
  → Paste from Other Apps → Clips: Allow. Paste added an onboarding page for this.
  Reading `changeCount` and `types` (and the `detect…` APIs) doesn't trigger the alert.
  Plan: read `NSPasteboard.general.accessBehavior` (macOS 15.4+) at launch and on app
  activation. If it's `.alwaysAllow`, record normally. If it's `.ask`/`.default`, show the
  "Clipboard access" row (one sentence + "Open Settings…") in the panel's empty state and
  the menu status line, and record anyway (the user may answer the alert). If it's
  `.alwaysDeny`, read nothing and say so. SlopKit's `Permission` enum needs a new case for
  this pane (exact `x-apple.systempreferences` anchor to verify on macOS 27).
- **Accessibility** (to post ⌘V): asked the first time the user pastes, never at launch.
  `AXIsProcessTrusted()` checked before every paste; if missing or revoked (Paste's docs
  say macOS updates sometimes turn it off), copy instead and show the inline row. On
  macOS 27 the pane is called "Device Control and Data Access". Note for testing: ad-hoc
  signed dev builds lose the grant on each rebuild; use `scripts/drive launch --direct`.
- **Launch at login**: `SMAppService` via SlopKit's `LaunchAtLogin`, on by default.
- **Global hotkey**: `KeyboardShortcuts` (Carbon hotkeys, no permission needed).
- **Screen sharing**: optional `sharingType = .none` on the panel.
- **Not used**: Screen Recording (Paste's AI suggestions need it), network, iCloud, URL
  scheme, Services, App Intents (later).

## UX patterns worth adopting

- **The panel never steals focus.** The app you were typing in stays frontmost, so the
  paste lands exactly where the caret was. That is the whole trick; keep it.
- **Typing just searches.** No need to click a search field or press ⌘F first.
- **Number shortcuts on the first nine items**, with the number visible on each item, so
  muscle memory forms ("the thing I copied before last is ⌘2").
- **Re-used items rise to the top**, so the list stays ordered by relevance in practice.
- **Pinned items are exempt from expiry and from clearing.** People trust a short
  retention more when they know the snippets they care about are safe.
- **Shortening retention asks first and says it can't be undone**, and clearing keeps
  pinned items.
- **One modifier means "plain text" everywhere** (Return, number keys, menu).
- **A separate "copy only" path** (⌘C) for when you don't want an automatic ⌘V.
- **Pause with a duration** that resumes on its own, so people don't forget recording is
  off.
- **The colour rule** (six hex digits count as a colour only with `#` or a letter a–f) avoids
  turning order numbers into colour swatches.
- **The permission is asked in context**: the first paste explains why it needs
  Accessibility, and everything still works (copy only) if the user says no.

## What we won't copy, and what we'll do better

- Not copying: the name, the "P" icon, the horizontal card strip along the bottom of the
  screen, card visuals and colours, sounds, wording, onboarding illustrations, paywall/trial
  flows, rating prompts.
- **Vertical list + preview pane.** A centred list reads faster than a horizontal strip
  (eyes scan down, more items fit, long lines aren't clipped into cards) and the preview
  shows the whole clip. Forum users ask for "list" views and a "normal preview".
- **Fast, always.** Reviews complain about search failing or the app hanging during
  searches after updates. Budget: panel visible < 50 ms after the hotkey (keep the panel
  alive after first use and only refresh its data; pre-load the newest ~200 rows),
  < 16 ms per search keystroke, idle CPU < 0.2%, footprint < 50 MB.
- **Private by default.** Paste ships PostHog and Sentry, makes link previews by default
  (fetching URLs you copied, which can trigger one-time links), keeps "ignore confidential"
  as an opt-in switch, and hides its built-in exclusions. We: no network at all, concealed
  and transient content always skipped (checked from `types` before reading the data),
  default ignore list visible and editable, nothing leaves the Mac.
- **Honest about clipboard access.** Tell the user when macOS is blocking reads instead
  of silently recording nothing.
- **Free and quiet.** No subscription (the most common complaint in forums), no trial
  nags, no sounds, no what's-new.
- **Safe default hotkey** that doesn't fight Paste, Finder's move or Paste and Match Style.

## Edge cases

- **Content types**: plain text; rich text from a browser (HTML + RTF + plain); a single
  URL (classify as link); multiple files from Finder (file URLs + icon image + names:
  classify as files, don't store the icon); image only (screenshot to clipboard);
  image + text (Pages, Keynote: classify by priority files > image-only > link > color >
  text, keep all representations); a colour hex; whitespace-only or empty (skip);
  clipboard cleared (changeCount changes, no items: ignore).
- **Huge inputs**: a 20 MB log or a 50 MP image. Store up to a cap (proposal: 50 MB per
  clip; larger is skipped and logged), index only the first ~64 KB of text, truncate rows
  to one line, decode images to thumbnails off the main actor, never hold full images in
  memory.
- **Files that moved or were deleted** after copying: preview shows "not found";
  pasting writes the URL anyway (target app decides) or is disabled with a reason.
- **Our own writes**: when Clips puts a clip on the pasteboard, tag it with
  `org.nspasteboard.source = app.slopapp.clips` and bump the existing clip instead of
  recording a duplicate.
- **Rapid copies** (two copies within one poll interval): only the last is seen. Accept
  (same as every polling manager); document it.
- **Password managers without markers** / browser extensions: recorded; mitigations in
  Flow 4. Apple Passwords' menu bar extra copies are attributed to the frontmost app, so
  rely on the concealed marker, not the ignore list.
- **Universal Clipboard** items from iPhone (`com.apple.is-remote-clipboard`): recorded by
  default, switch to ignore.
- **Paste target**: the panel is non-activating, so the frontmost app gets ⌘V. If the
  user came from the history window (Clips active), remember the previously active app,
  re-activate it, wait for activation, then post ⌘V. Secure input (password field
  focused): posting may be blocked; fall back to copy + HUD. Non-QWERTY layouts (Dvorak,
  AZERTY, "Dvorak – QWERTY ⌘"): post the key code that produces "v" in the current layout.
- **Permissions revoked mid-use** (Accessibility or clipboard access): detected on the
  next paste / app activation; switch to copy-only or "not recording" with a visible
  reason; no crash, no silent failure.
- **Multiple displays**: open on the screen with the frontmost window (where the paste
  will land), falling back to the screen with the mouse. **Full-screen spaces**: panel
  must appear over full-screen apps (`.fullScreenAuxiliary`, `.canJoinAllSpaces`, already
  in `FloatingPanel`).
- **Sleep / wake, fast user switching**: the timer keeps working; on wake re-read
  `changeCount` once. Retention pruning runs after wake, off the main actor.
- **Retention change** while thousands of clips exist: delete in batches off the main
  actor; the panel stays responsive.
- **Database**: first launch with no store; store corrupted (move it aside, start fresh,
  tell the user once); disk full (stop recording, say so in the menu).
- **Non-English text**: CJK, RTL (Arabic, Hebrew), emoji, combining characters; search is
  diacritic- and case-insensitive with `localizedStandardContains` semantics.
- **Light/dark, Reduce Motion, Increase Contrast**; VoiceOver labels on rows ("Link,
  example.com, from Safari, 5 minutes ago, pinned"); no unlabeled icon buttons.
- **App quit or crash mid-paste**: the item is already on the system clipboard, so ⌘V
  still works.
- **Two clipboard managers running** (Paste and Clips): both record (fine) and shortcuts
  must not collide (default ⇧⌥V vs Paste's ⇧⌘V).

## Our v1 scope

- [x] Records text, rich text, links, images and files from the general pasteboard by
      polling `changeCount` (~0.5 s), storing all representations in SwiftData (images as
      external storage); idle CPU < 0.2%.
- [x] Skips concealed, transient, auto-generated and legacy-marker items without reading
      their contents; skips items from apps on the ignore list (visible defaults:
      password managers); skips empty/whitespace items.
- [x] Copying the same content again moves the existing clip to the top (no duplicates),
      including clips pasted from Clips.
- [x] Global shortcut (default ⇧⌥V, recorder in Settings → Shortcuts) opens a centred,
      non-activating search panel on the active screen in < 50 ms with the newest clip
      selected; "shortcut unavailable" shown in the menu if it can't register.
- [x] Panel: search field (typing filters live), vertical list (type icon or thumbnail,
      one-line preview, source app icon, relative time, ⌘1–9 badges), preview pane
      (text / image / file / link / color + metadata), empty state, "no matches" state.
- [x] Keyboard: ↑/↓, ⌘↑/⌘↓, Return pastes, ⇧Return pastes plain text, ⌘1–9 paste,
      ⌘C copies only (HUD), ⌘P pin, ⌘⌫ delete with ⌘Z undo, Esc clears then dismisses;
      click outside dismisses; double-click pastes.
- [x] Direct paste into the frontmost app via ⌘V when Accessibility is granted; otherwise
      copy + HUD + inline "Allow Clips to paste for you" row opening the right Settings
      pane; re-checked on every paste.
- [x] Clipboard access: detects macOS's "Paste from Other Apps" state, explains it in one
      sentence with an "Open Settings…" button, and never fails silently.
- [x] Pinned clips: pin/unpin, pinned section on top when not searching, exempt from
      retention and Clear History.
- [x] Retention: 1 day / 1 week / 1 month (default) / 1 year / Forever, pruning off the
      main actor, confirmation when shortening deletes clips.
- [x] Clear History… (menu + Settings) with confirmation; pinned clips kept.
- [x] Status menu: status line, Open Clips, Pause ▸ (15 min, 1 hour, until resumed),
      Ignore Next Copy, Clear History…, footer; icon shows paused state.
- [x] Settings: General (launch at login on, show in menu bar, after choosing a clip,
      always paste as plain text, keep history, Clear History…), Shortcuts, Advanced
      (ignored apps, permission status), About.
- [x] Within budgets: launch < 300 ms, icon < 600 ms, footprint < 50 MB with 5 000 clips
      including images; search keystroke < 16 ms at 10 000 clips.
- [x] VoiceOver names every row and control; light/dark and Reduce Motion checked.
- [x] No network traffic, no telemetry.

**Should (v1 if cheap, else 1.1):** type filters; colour detection with swatches; history
window (library archetype); drag out of the panel; ⌘O open / Show in Finder; ⌘Y Quick
Look; hide from screen sharing; ignore Universal Clipboard switch.

## Open questions

1. **Default shortcut.** Recommendation: ⇧⌥V (⌥⌘V would break Finder's "Move Item Here").
   The owner currently opens Paste with a custom ⌥⌘Space binding (macOS's default use of
   that combo is the Finder search window). Should Clips default to ⇧⌥V, or should the
   owner's build just record their preferred combo on first run?
2. **First run.** Open the panel once in its empty state (shortcut hint + permission rows),
   or stay fully silent with only the status item? Proposal: open once.
3. **History window in v1?** It's "should" here. It helps cleanup and browsing images, but
   v1 works without it.
4. **Hide from screen sharing default.** Paste shows its panel during screen sharing by
   default. Privacy argues for hiding by default; it may also hide the panel from our own
   screenshot tooling. Proposal: off by default (shown), switch in General.
5. **Size cap and limits.** Proposal: skip single clips over 50 MB; no count limit beyond
   retention. OK?
6. **Universal Clipboard.** Record items arriving from the owner's iPhone by default
   (proposal) or skip?
7. **Image text search (OCR)** is a Paste highlight and a real "find that screenshot"
   win, at a CPU cost. Later, or should?

## Decisions (build step, 2026-11-02)

The owner was asleep; these were decided during the build. Each is easy to revisit.

| Question | Decision | Why |
|---|---|---|
| Default shortcut | **⇧⌥V** | Clear of ⇧⌘V (Paste, and Paste and Match Style) and ⌥⌘V (Finder Move). The owner can record ⌥⌘Space in Settings → Shortcuts. |
| First run | **Silent** (status item only) | Design system §1.4: no onboarding. The panel explains itself (empty state, inline permission rows). |
| History window in v1 | **Yes** (library archetype) | Cheap once the panel's pieces existed; it's where cleanup (multi-select delete, by-app browsing) happens. |
| Hide from screen sharing | **On by default**, switch in Privacy | People open clipboard history while sharing a screen to paste something: that's exactly when it leaks. A missing panel in a screenshot is the safer failure. `CLIPS_ALLOW_CAPTURE=1` lets tests screenshot it. |
| Size cap | Skip clips over **50 MB**; rich text over 10 MB keeps only plain text; at most **10,000** unpinned clips | Keeps memory and search bounded. Retention is the main limit. |
| Universal Clipboard | **Recorded** (no switch yet) | They're the user's own copies. Switch deferred. |
| OCR in images | **Later** | CPU cost, and v1 is about the everyday flow. |
| Storage | **SQLite** (system `libsqlite3`), not SwiftData | Incremental writes, payload blobs loaded only on paste, no Swift 6 concurrency friction, fast cold load (5,000 clips in ~120–350 ms in the background). |
| Esc | Clears a search first, then closes | Spotlight-style. Done with an app-level key monitor because SlopKit's `FloatingPanel` closes on Esc before its key handler runs. |
| Quick paste | **⌘1–9** (not bare digits) | The search field has focus, so digits must type. Deliberate exception to design system §2d. |
| Pinned clips | Stay in date order with a pin mark; **Pinned** filter (Tab) lists them. Re-confirmed in blind test round 2 (F5) | Keeps "shortcut → Return pastes the newest copy" **and** "⌘1 is the newest copy" true. A pinned group on top would either push the newest copy to ⌘4 or need numbering that skips rows. Pinned clips are one Tab away, using one moves it to the top, and pins are exempt from retention and Clear History. Revisit if real use shows people hunting for pins. |
| Launch at login | **Off** by default, toggle in General | Turning it on would change the owner's login items during testing. Revisit for release. |
| Panel list | AppKit `NSTableView` inside the SwiftUI panel | A SwiftUI lazy list grew memory with every open (57 MB after 6 uses at 5,000 clips) and redrew slowly; the table reuses ~15 cells. |
| Showing the panel | Panel stays ordered in, transparent and off-screen, between uses | Ordering a window in cost ~40 ms on its own; moving a parked one is near-free. |
| Pasteboard polling | Fixed 0.5 s | Costs 0.05% CPU. An idle-time slowdown was tried and removed: it coalesced scripted copies and saved almost nothing. |
| Naming other apps | Settings may name a running clipboard manager in a shortcut-conflict warning | Functional, factual, and the name comes from the conflict table, not marketing. |

## Sources

- Installed Paste 6.3.6 (Setapp), read-only: main menu, Settings panes (General, Privacy,
  Shortcuts, Subscription), Info.plist, bundled frameworks, App Intents metadata and
  English UI strings (read for feature discovery only).
- Help center: [index](https://pasteapp.io/help),
  [Paste on Mac](https://pasteapp.io/help/paste-on-mac),
  [Keyboard shortcuts](https://pasteapp.io/help/keyboard-shortcuts),
  [What Paste captures](https://pasteapp.io/help/what-paste-captures),
  [Exclude apps](https://pasteapp.io/help/exclude-apps),
  [Paste directly to other applications](https://pasteapp.io/help/paste-directly-to-other-applications),
  [History retention](https://pasteapp.io/help/control-history-retention),
  [Paste as plain text](https://pasteapp.io/help/paste-as-plain-text),
  [Quick Paste](https://pasteapp.io/help/quick-paste-with-numbered-shortcuts),
  [Paste Stack](https://pasteapp.io/help/using-paste-stack),
  [Search and filters](https://pasteapp.io/help/search-and-filters),
  [Pinboards](https://pasteapp.io/help/organize-with-pinboards),
  [Edit and label items](https://pasteapp.io/help/edit-items-before-pasting),
  [Intelligent Clipboard](https://pasteapp.io/help/intelligent-clipboard),
  [Where Paste stores data](https://pasteapp.io/help/where-paste-stores-your-data),
  [Stop Paste popping up](https://pasteapp.io/help/stop-paste-popping-up),
  [Copy & paste not working](https://pasteapp.io/help/copy-paste-not-working)
- [Paste updates log](https://pasteapp.io/updates)
- [App Store listing and reviews](https://apps.apple.com/us/app/paste-limitless-clipboard/id967805235)
- [Setapp listing](https://setapp.com/apps/paste)
- [Product Hunt: Paste 6](https://www.producthunt.com/p/paste/paste-6)
- [MakerStack review (2026)](https://makerstack.co/reviews/paste-review/)
- [MacRumors forum: replacing Paste](https://forums.macrumors.com/threads/what-clipboard-manager-do-you-recommend-to-replace-paste.2470509/)
- [Maccy README](https://github.com/p0deje/Maccy) (comparison: ignore types, check
  interval, hotkey caveats)
- [nspasteboard.org marker types](https://nspasteboard.org/)
- Pasteboard privacy: [Michael Tsai](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4/),
  [Apple: `NSPasteboard.accessBehavior`](https://developer.apple.com/documentation/AppKit/NSPasteboard/accessBehavior-86972),
  [Clipsody PR on macOS 27 handling](https://github.com/tillackt/clipsody/pull/15)
- macOS built-in history (baseline): [MacMost: Spotlight clipboard history](https://macmost.com/how-to-use-the-spotlight-clipboard-history-in-macos-tahoe.html)

## Build notes (steps 3–4, 2026-11-02)

### What was built

`apps/Clips`: `ClipsCore` (pure, tested: capture policy, clip builder, search, history,
retention, SQLite store, change tracking, formatting, synthetic data) and the app
(menu bar item, search panel, History window, Settings with General / Shortcuts / Privacy /
About). Test hooks are environment variables, all off by default (see
`Sources/Clips/Diagnostics.swift`): `CLIPS_DATA_DIR`, `CLIPS_PASTEBOARD`, `CLIPS_SEED`,
`CLIPS_LOG`, `CLIPS_APPEARANCE`, `CLIPS_SHOW_PANEL`, `CLIPS_ALLOW_CAPTURE`, `CLIPS_TEST_HOOKS`.

### Gap review: v1 scope

| v1 item | Status | Evidence |
|---|---|---|
| Records text, rich text, links, images, files (0.5 s poll) | Done | Private pasteboard: text, rich (HTML kept), link, color, 2 files, PNG all captured and pasted back with the right types. Real general pasteboard (`--direct`): captured, source app = frontmost (TextEdit). |
| Skips concealed / transient / auto-generated / legacy markers without reading; ignore list; empty | Done | Log shows `skipped reason=marked(…Concealed…)`, `…Transient…`; `org.nspasteboard.source = com.1password.1password` skipped as ignored app. Unit tests for every marker. |
| Copying again moves to top, incl. clips pasted from Clips | Done | Unit tests; own writes are tracked by change count and not re-recorded. |
| Shortcut ⇧⌥V opens a centred non-activating panel < 50 ms, newest selected | Done | Real global hotkey with TextEdit frontmost: first show after launch 14.8 ms (55 ms before pre-creating the field editor), then 8–11 ms; at 5,000 clips 19–42 ms (first show after launch 30–42 ms). TextEdit stayed frontmost throughout. Registration failures can't be detected (Carbon reports success even when another app holds the combo; verified with a probe), so Settings warns about known conflicts instead (verified with ⇧⌘V while Paste runs). |
| Panel: search, list (icon/thumbnail, title, age, pin, ⌘1–9), preview, empty + no-match states | Done | Screenshots light/dark: text, color swatch, image preview, files, empty filter, no results. |
| Keyboard: arrows, ⌘↑/↓, Return, ⇧Return, ⌘1–9, ⌘C, ⌘P, ⌘⌫ + ⌘Z, Esc, Tab filters, double-click, click outside | Done | All walked with posted keys. Found and fixed an undo race (⌘Z right after ⌘⌫ could miss the payload). |
| Direct paste with Accessibility; otherwise copy + HUD + inline explanation | Done | `--direct`: Return and ⇧Return pasted into a TextEdit doc under /tmp/clips-test. Normal launch: Return copied to the general pasteboard, HUD shown, panel shows the Accessibility row with Open Settings…. |
| Clipboard access ("Paste from Other Apps") detected and explained | Done, partly unverified | Reads `accessBehavior`; notices in panel, menu, Settings with a link to `Privacy_Pasteboard` (anchor found in the System Settings bundle). On this Mac both launches reported "allowed", so the "asks"/"denied" rows were only checked in code, not on screen. |
| Pinned: pin/unpin, exempt from retention and Clear History | Done (no pinned-on-top section, see Decisions) | Unit tests + walkthrough. |
| Retention 1 day … Forever, confirmation when shortening deletes clips | Done | Unit tests; confirmation dialog in General. |
| Clear History… (menu + Settings), pinned kept, confirmation | Done | Code path walked; the alert itself was not clicked through on the real history. |
| Status menu: status line, Show, Pause ▸, Ignore Next Copy, Clear History…, footer; paused icon | Done | Walked; paused icon screenshot checked. |
| Settings tabs | Done | General / Shortcuts / Privacy / About, light screenshots. |
| Budgets | Done | See below. |
| VoiceOver names, light/dark, Reduce Motion | Done | `drive tree`: no `[unlabeled]` in panel, History, any Settings tab. No animations in the panel. |
| No network | Done | No networking code. |

Also built (should-haves): type filters, color swatches, History window (sidebar by kind
and by app, multi-select, ⌘C, ⌫/⌘⌫ delete with Edit › Undo), hide from screen sharing.

### Performance

| Metric | Result | Budget |
|---|---|---|
| Launch (`perf.sh`, median of 3) | 169 ms | < 300 ms |
| First status item | 333–367 ms | < 600 ms |
| Idle CPU (0.5 s polling) | 0.047–0.076 % | < 0.2 % |
| Footprint, empty history | 31.7 MB | < 50 MB |
| Footprint, 5,000 clips, after 10 open/search/close cycles | 46.5 MB (stable) | < 50 MB |
| Search, 5,000 clips | 0.3–1.6 ms per keystroke | < 16 ms |
| Load 5,000 clips (background) | 120–350 ms | — |
| Capture (copy → stored) | 0.6–11 ms (image) | — |

### Design checklist (§10)

| # | Item | Result |
|---|---|---|
| 1 | Main job in one shortcut | Pass: ⇧⌥V → Return |
| 2 | Native look, light + dark | Pass: system materials (Liquid Glass panel), accent selection, no hex colours (colour swatches show clip content) |
| 3 | Keyboard + menus | Pass: all panel actions on keys and in the right-click menu; History has a Clip menu |
| 4 | Esc / ⌘, / ⌘Q | Pass (⌘, from the panel opens Settings) |
| 5 | Settings General + About | Pass |
| 6 | Copy | Pass |
| 7 | Empty states | Pass: no clips, no matches, empty filter, no selection |
| 8 | Permissions only when needed | Pass: Accessibility asked inline, never at launch; clipboard access explained only when macOS restricts it |
| 9 | Destructive actions undoable | Pass: delete undoable (⌘Z / Edit › Undo); Clear History and shortening retention confirm first |
| 10 | No network | Pass |
| 11 | Budgets | Pass |
| 12 | VoiceOver names | Pass |
| 13 | Reduce Motion | Pass: no animations |
| 14 | Window state | Pass: History is a SwiftUI `Window` scene (size remembered); panel is fixed-size by design |

### Deferred

Drag out of the panel, ⌘O / Show in Finder, Quick Look (⌘Y), Universal Clipboard switch,
paste stack, edit before paste, OCR, pinboards with names, "Pinned on top" option.

### Known risks

- **Paste from Other Apps on a fresh install.** If macOS reports "ask", every read raises a
  system alert until the user allows Clips; the panel and menu say how. Not seen on this Mac.
- **Pasteboard data is read off the main thread** (so a 30 MB screenshot never blocks the
  UI). NSPasteboard behaved correctly in every test; if it ever misbehaves, move
  `SystemPasteboard.snapshot` back to the main actor.
- **Hotkey collisions can't be detected** (macOS doesn't report them); Clips warns for
  known clipboard managers and common app shortcuts only.
- **Ad-hoc signed builds lose Accessibility on each rebuild**; test direct paste with
  `scripts/drive launch build/Clips.app --direct`.
- The parked panel shows up in `scripts/drive windows Clips` at (-20000, …) when closed.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-03)

Triage by the coordinator, fixes by the builder. All accepted findings fixed.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 History: a search hides the selected clip, but the detail pane keeps showing it with live Pin/Delete/Copy; Delete removed the hidden clip | major | Accept | Selection now follows the visible results: every search/filter change drops selected clips that aren't listed, and every action (buttons, Clip menu, right-click) only acts on visible selected clips. Verified: select "hello world", search "bold" → "No Clip Selected", Clip › Pin/Delete disabled. |
| F2 Deletes can't be undone; ⌘Z undoes search typing instead | minor | Accept | Edit › Undo now prefers deleted clips ("Undo Delete", ⌘Z) over text undo, app-wide; restored clips keep their pin. Panel ⌘Z does the same. History asks before deleting several clips or a pinned one ("Delete 2 clips?", "You can undo this with ⌘Z."); the panel asks for a second ⌘⌫ on a pinned clip (inline notice, 4 s). Verified ⌘Z with typed text in the History search field restores the clip and leaves the search text alone. |
| F3 History has no ⌘F / Edit › Find | minor | Accept | Edit › Find… (⌘F) focuses the History search field. |
| F4 Clearing the History search with the field's clear button left the list filtered | minor | Investigate → fixed | Reproduced in spirit: SwiftUI's `.searchable` field didn't report every change (setting its value through Accessibility didn't reach the binding). Replaced with an `NSSearchField` that reports typing, the clear button and AX changes. Verified: AX press on the clear button restores all rows. |
| Perf: 0.3–0.7 s per search query (CLIPS_SEED=5000) | — | Investigated | Measured query change → main thread idle again. Panel was 22–59 ms: every keystroke rebuilt all table cells, and AppKit recomputed the key-view loop for each new row. Now cells are refilled in place and the panel doesn't recompute the loop: **median 28 ms, p90 34 ms**. History used SwiftUI `List`, 30–83 ms, and exposed all 5,000 rows to Accessibility (that's what made the tester's tool slow). Now an `NSTableView` like the panel: **median 26 ms, p90 33 ms** (one 90 ms outlier with keys arriving faster than typing). |
| F5 Rich-text previews show plain text | nit | Accept | Clips with RTF (TextEdit, Notes, Pages, Mail…) preview formatted, with Dark Mode color mapping. HTML-only clips (most web copies) stay plain on purpose: AppKit's HTML import can fetch remote resources. |
| F6 History image thumbnail wider than the icon column, touching the title | nit | Accept | Fixed by the table rewrite: thumbnails scale to fit a 24 pt square. |
| F7 Highlight matched text in results | nit | Accept | Matched words are bold in row titles, panel and History (case/accent-insensitive, `SearchText.highlights`, unit-tested). |
| F8 Footer says "⌘P Pin" when the clip is pinned | nit | Accept | Says "Unpin" for a pinned selection (Clip menu too). |

**Gates after the round:** 47 unit tests pass; bundle and smoke pass; no `[unlabeled]` controls
(panel, History); panel show at 5,000 clips 17–38 ms; footprint 44.8 MB after 10
open/search/close cycles at 5,000 clips. `perf.sh` launch 148–153 ms, first icon 325–343 ms,
footprint 32–33 MB. **Idle CPU couldn't be judged this round:** the Mac was running other
builders' work (load average 13–17). Clips measured 0.065 % in one run, 0.24–0.48 % in
others, and the same spread with polling switched off entirely. The control (Awake, which
doesn't poll at all) measured 0.16–0.20 % under the same load. Earlier at normal load Clips
measured 0.047–0.076 %. `perf.sh` also failed twice at launch ("no running app matches")
under that load: an environment flake, reproduced with plain launch/quit loops, no crash.
The final `check.sh Clips --perf` passed (all budgets); an immediate re-run measured idle
CPU 0.200 % (just over) at load average 8–13. Re-run `perf.sh Clips` on a quiet machine.

Round decisions: History list is now AppKit (`HistoryTable.swift`) for speed and a sane
Accessibility tree; History search is an own `NSSearchField`; Undo is an app-level command
that prefers clip deletions.

### Round 2 (2026-11-03)

No blockers or majors: exit criterion met. Polish round for the minors and nits.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 Search doesn't find text beyond the start of long clips (216k characters, "ENDMARK" not found) | minor | Accept | Search now covers the first **1,000,000** characters of every clip (`Clip.searchLimit`); rows and previews still show the first 10,000. Long text is stored in a new `full_text` column (schema v2, backfilled from stored clips on first launch). The preview says "Showing the first 10,000 of N characters. The whole text is pasted." and adds "Search covers the first 1,000,000 characters." when that applies. Verified with a 216,341-character clip: "endmark" finds it. Unit tests for both limits and for reloading. |
| F2 History only reachable from the status menu (⌘Y only while it's open) | minor | Accept | ⌘Y in the panel opens History; Window › Clip History (⌘Y) works whenever Clips is active. The window action is captured from the menu bar icon at launch, so it works before the status menu was ever opened. |
| F3 Return while the Help alert was open copied a clip from the hidden panel | minor | Accept | Cause: AppKit can hand key status to the parked (invisible) panel when another of our windows or an alert closes. Now the panel's key handler ignores everything unless the panel is showing, and a parked panel that becomes key is taken off screen at once. Verified: close History, press Return and ⌘C → nothing copied; the next ⇧⌥V show still takes ~22 ms. |
| F4 Help › Clips Help | nit | Accept | Opens the app's README on GitHub (`Brand.repoURL` + `/tree/main/apps/Clips`); replaces the "Help isn't available" alert. Not clicked in testing (it would open the default browser). |
| F5 Pinned clips sink with age in All | nit | Accept (design call): keep | See Decisions: pinned on top would break "⌘1 / Return = newest copy". Pinned filter is one Tab away. |
| F5b Matches beyond the visible row width aren't visible | nit | Accept | When the first match isn't in what the row shows, the panel row shows the words around it ("…go here **ENDMARK** tail words") and the History row shows them as its second line, matches in bold (`ClipText.snippet`, unit-tested). |
| AX: "Remove App" button 10×1 in Settings › Privacy | nit | Accept | Both list buttons are 16×16 now. |
| AX: empty first row in the History sidebar | nit | Accept | Came from an untitled `Section`; removed. |

**Gates after the round:** 50 unit tests pass; `check.sh Clips --perf` passes (load-robust
`perf.sh`, load average 9.6): launch 150 ms, first icon 336 ms, idle CPU 0.037 % (lowest of
3 × 5 s windows; median 0.050 %), footprint 38.0 MB. At 5,000 clips: panel show 17–38 ms,
search median 34 ms / p90 41 ms, footprint settles at 42–43 MB after use. No `[unlabeled]`
controls.

**Shipped as beta 0.2.0** (`app.json`).


## Parity pass (2026-11-03)

Owner's request: "Redesign Clips to look more like Paste. It should also have the sound
effect when copying." Governed by [`docs/parity-pass.md`](../parity-pass.md).

**How Paste was studied this time.** Paste is the owner's running clipboard manager, so its
panel was never opened (no ⇧⌘V, no status-item click) and no history was seen or captured.
Its look came from the official site and help center only: hero and feature images from
pasteapp.io and the "Paste on Mac" help page, downloaded to `/tmp/clips-parity/` (not
committed). Menus and Settings were already inventoried in the research step above.

What those show: a strip across the bottom of the display (Paste 7: inset, rounded, glass);
a top bar with a search icon, the history tab (clock icon) and coloured-dot pinboard tabs
in the middle, "…" on the right; square-ish cards in a horizontal timeline, newest first,
each with a header (type word over relative time, the source app's icon on the right; in
6.x a solid header band in the app's colour) over a large preview (text, full-bleed image
with "W × H", link with page image + title + address, file icon + path, a colour) and a
small footer ("65 characters"); a ring around the selected card; Space for Quick Look;
←/→ to move; ⌘1–9 shown on cards while ⌘ is held; sounds on copy.

### What changed

| Feature / design item | Status | Notes |
|---|---|---|
| Panel = full-width strip along the bottom of the active screen | Done | Inset 8 pt from the usable area (above the Dock), Liquid Glass via SlopKit's `FloatingPanel`, slides up 18 pt in 0.14 s (none with Reduce Motion). Non-activating as before. |
| Top bar: search + tabs centred, "…" menu right | Done | Search capsule (always present, keeps the caret), tabs All · Pinned · Text · Links · Images · Files, clip count and a "…" menu (Open History, Pause ▸, Settings…, Clear History…). Left side: key hints, or the one notice that matters (storage, pinned-delete confirm, clipboard access, Accessibility, paused + Resume). |
| Cards: header (type, relative time, app icon), big preview, footer | Done | Text (first ~700 characters, wrapped; or the words around a deep match), image (full-bleed, sharp 480 px decode, "W × H" chip), link (site monogram tile, page title, short address), colour (full swatch, hex chip), file(s) (icon, name, folder, "Not found"). Footer: "N characters". |
| Link titles | Done | From `public.url-name` (Safari, Mail…) or the text of a single `<a>` in copied HTML. Stored (schema v3 `title` column), searchable. Never fetched. |
| Selection ring, keyboard ←/→ (and ↑/↓), ⌘↑/⌘↓/Home/End, Page Up/Down | Done | Accent-coloured ring outside the card. |
| ⌘1–⌘9 quick paste, numbers shown while ⌘ is held | Done | Accent badges bottom-right of the first nine cards. |
| Quick Look (Space) | Done | A larger preview (660×440) above the strip, centred; follows the selection; Space/Esc closes. Rich text rendered there. Space types a space while a search is being typed: Tab first (Paste's model), or open it from the right-click menu. |
| Tab switches search ↔ cards | Done | Paste's model. The caret hides and the search outline drops while the cards have the keyboard; typing goes back to search. (Previously Tab cycled filters.) |
| ⌘←/⌘→ previous/next tab | Done | Paste uses these for pinboards. |
| ⌘O open link/file, Show in Finder | Done | Keys + right-click menu. (Deferred before.) |
| Drag a card out | Done | Text, links, colours, files and images. An image card offers a file (a promise Finder and the Desktop turn into `Image <date> at <time>.png`) plus the image data for apps. (Deferred before.) |
| ⌘T pause/resume, ⌘F back to search | Done | |
| Vertical mouse wheel scrolls the strip sideways | Done | |
| Paste / copy / plain text / pin / delete + undo / Esc | Kept | Same behaviours as before, same keys. |
| **Copy sound** | Done | On by default. Plays a macOS system sound (Pop default; Tink, Bottle, Morse, Purr) through AudioToolbox, so it uses the "Play sound effects through" device at the alert volume. Only for copies that were recorded: skipped, ignored, concealed, paused and Clips' own writes never reach it. Silent when System Settings › Sound › "Play user interface sound effects" is off. Throttled to one per 0.2 s. Settings › General: "Play sound when copying" + "Sound" (choosing one previews it). |
| History window | Kept | See decisions. |
| Named, coloured pinboards (+, drag onto a tab, ⇧⌘N) | Deferred (M–L, ~1 day) | Needs a board model, schema, tab editing, drag targets. "Pinned" stands in. |
| Rename (⌘R) / edit (⌘E) / new text item (⌘N) | Deferred (S–M each) | The new `title` column is the first half of rename. |
| Multi-select (⇧←/→, ⌘A) and paste together | Deferred (M) | |
| Paste stack (⇧⌘C) | Deferred (L) | Needs an event tap. |
| Search filter tokens (app, date range, device) | Deferred (M) | Tabs cover type; History covers app. |
| Text in images (OCR) | Deferred (M) | CPU cost. |
| Formatted text on the cards | Deferred (S–M) | Needs the payload per card while scrolling; Quick Look shows it. |
| Resizable strip / compact mode | Deferred (M) | |
| Paste sound on paste | Skipped | The brief: no sound for Clips' own pastes. |
| Link previews (page images), iCloud, iOS | Skipped | Network. |

### Decisions

| Question | Decision | Why |
|---|---|---|
| Keep the History window? | **Keep**, reachable from ⌘Y, the strip's "…" menu, Window › Clip History and the status menu | Paste has nothing like it, but it doesn't compete with the strip: it's for bulk cleanup (multi-select delete), browsing by app, and reading long clips. Folding those into the strip would need multi-select and filters first (deferred). |
| Card header colour | ~~Soft wash of the source app's icon colour~~ **Superseded 2026-11-06** (owner: "still missing a bit of the design aesthetic from Paste"): a solid band in the app's colour, see "Paste-closer round" | |
| Link "image" | **Monogram tile** (first letter of the site, a system colour picked by hashing the host) | Paste downloads page images; Clips never touches the network. |
| Search field | **Always visible** capsule (Paste shows an icon that expands) | Typing searches at once either way; a fixed field avoids layout jumps and is clearer. |
| Space | Quick Look when the search is empty or the cards have the keyboard; otherwise a space | Multi-word searches need spaces; Tab gets to the cards as in Paste. |
| ←/→ while searching | Always move the selection | "Type, arrow, Return" is the main flow; the query is short. |
| Tab labels | All, Pinned, Text, Links, Images, Files | Our filters stand in for pinboards; "All" keeps the History window's wording. |
| Number badges | Only while ⌘ is held | As in Paste; keeps the cards clean. VoiceOver labels always include "Command N". |
| Strip placement | Screen with the mouse, above the Dock. ~~Inset 8 pt~~ 16 pt since 2026-11-06 (a floating slab) | Matches "the display you're working on". |
| Card accessibility | One button per card with a full label ("Link, AppKit \| Apple Developer Documentation, developer.apple.com, from Safari, 2 min ago, Command 6"); AXPress selects (like a click) | Return pastes; an accidental AX press shouldn't paste. |
| Sound default | ~~On, Pop~~ **Superseded 2026-11-07**: on, Clips' own synthesized "Snap" (see "Sound round") | Pop felt nothing like Paste's sound. |

### Deviations from the design system (and why)

- **Sound effect** (§ "no sounds"): the owner asked for it. System sound only, on by
  default with a switch, respects the system UI-sounds setting.
- **Custom card visuals** (tinted headers, full-bleed images, site colours): matching
  Paste's card layout needs coloured, content-first cards. All colours are system or
  derived from the clip/app; no hardcoded palette beyond the system colours.
- **Panel placement and shape**: a screen-wide strip at the bottom instead of a centred
  panel, per the parity pass.
- **Search highlight** uses the system find-highlight colour with black text (readable in
  both appearances).

### Gates (parity pass)

- **Unit tests: 77 pass** (was 50): new suites for the copy sound policy (fake player:
  on/off, system UI-sound switch, throttling, chosen sound, sounds exist), strip geometry
  (visible range, hit testing, reveal, page size), the keyboard model (every panel key),
  link titles (url-name, single anchor, none for bare URLs, text never titled, kept on
  re-copy, stored in the database), card text (kind names, footers, hosts, short URLs,
  monograms).
- **`scripts/check.sh Clips`: pass** (SlopKit + Clips tests, release bundle, smoke, catalog).
- **`scripts/check.sh Clips --perf` was not run.** `perf.sh` quits whatever runs from
  `build/Clips.app`, and a Clips instance I didn't start (pid 10182, launched 16:42 from
  `build/Clips.app` with no test environment, likely someone's live copy) was running the
  whole session. The same measurements on a copy of the release build (`/tmp/clips-test/
  Clips.app`, launched directly, empty history, load average ~5): launch 98–107 ms, first
  menu bar icon 323–355 ms, idle CPU 0.11 % over 15 s, footprint 33 MB. Run the official
  gate once that instance can be quit.
- **5,000 clips** (seeded, release build, 10 cycles of show → type 10 keystrokes → hide):
  show 16–27 ms (cold shows after 75 s unused: 17–20 ms; one 196 ms outlier right after
  an idle wait, not reproduced in 3 tries); search settled per keystroke median 13 ms,
  p90 23 ms, max 35 ms. Budgets: < 50 ms each. Pass.
- **Footprint after use at 5,000 clips: 63 MB** (the pre-redesign build, measured the same
  way on the same machine today: 55 MB; right after launch both are ~51–52 MB, so the old
  "< 50 MB at 5,000" note no longer held either). The extra is window-server memory for a
  screen-wide glass strip on this 2,544-pt-wide display (~9–11 MB "unmapped") after
  searching; card labels now draw into one layer per card (CoreAnimation 6.8 → 1.3 MB),
  the hidden panel parks 900 pt wide, spare cards are released and decoded images trimmed
  when the strip closes. Idle (never shown) footprint is unaffected.
- **Walkthrough** (release build, private pasteboard `app.slopapp.clips.test`, data in
  `/tmp/clips-test`, every panel step only after ≥ 60 s of owner idle): captured text,
  rich text, links with and without title, colour, two images, one and three files (one
  missing) → each played the sound (log `copy sound played`); a concealed item was
  skipped with no sound; Clips' own ⌘C / Return / ⌘2 / ⇧Return writes played none; with
  "Play sound when copying" off a copy was recorded silently, on again it played (the
  shared defaults were restored afterwards). Strip, ←/→, Space Quick Look (files, image,
  rich text), search highlight + snippet, Tab → Space while searching, Esc order (preview
  → search → close), ⌘→ to Pinned (empty state and with a pin), ⌘P, ⌘C, ⌘2, ⇧Return,
  ⌘⌫ on a pinned clip asks for a second press, ⌘T pause notice + Resume, no-results
  state, ⌘Y History, Settings › General. Sounds themselves weren't listened to (no
  audio check possible here); the player call is logged and unit-tested.
- **Not tested by hand:** dragging a card out (needs the real mouse and a drop target),
  ⌘O / Open Link / Show in Finder (would open the owner's browser or Finder), the
  slide-in animation's feel, real direct paste with ⌘V (the private pasteboard makes
  Return copy), and the global shortcut (never pressed; ⇧⌘V never touched).
- **`drive tree`: no `[unlabeled]`** in the strip, cards, Quick Look or Settings.

Screenshots (in `/tmp/clips-parity/shots/`, not committed): `final-strip-light.png`,
`numbers-light.png` (⌘ held), `strip-dark.png`, `pinned-dark.png`, `quicklook-light-1.png`
(files), `ql-image-dark-1.png` / `-2.png` (image preview over the strip),
`search-ql-light-2.png` (search highlight + rich text preview), `tab-ql-light-2.png`
(cards focused, previewing while searching), `final-paused-light.png`,
`final-nomatch-light.png`, `history-light.png`, `settings-general-light.png`.
(`strip-light.png` and `pinned-empty-light.png` show two bugs fixed since: a system focus
ring inside the search capsule, and the centre group sliding left when the left side was
empty.)

Code: `ClipsCore/Strip.swift` (geometry + keyboard model), `ClipsCore/CopySound.swift`
(sound policy), `Clips/ClipStrip.swift` (recycling strip), `Clips/ClipCardView.swift`
(card), `Clips/AppTint.swift` (app colour), `Clips/SoundPlayer.swift` (AudioToolbox),
`Clips/PanelView.swift` + `PanelController.swift` (strip, top bar, Quick Look). Removed:
`Clips/ClipTable.swift` (the list) and the panel's preview pane.

## Polish pass (2026-11-05)

Brief: [`docs/polish-pass.md`](../polish-pass.md) ("very close attention to detail"). Finish,
not features. The owner's own Clips (build/Clips.app, pid 40930) was quit for the session so a
test copy could run without fighting it for the hotkey, the bundle path and the perf gate; its
defaults were exported first (`/tmp/clips-test/polish/defaults-backup.plist`) and the polished
build was relaunched with `open` at the end. Every screenshot uses synthetic test data
(`CLIPS_DATA_DIR=/tmp/clips-test/polish/data`, 40 seeded clips + fixtures written to the private
pasteboard `app.slopapp.clips.test`: rich text, code, a 136-character unbroken word, colour,
titled link, two images, one, three and a missing file). Nothing touched the real clipboard.

**How it was measured.** The owner was at the Mac on and off (and the screen locked twice), and
a shown strip takes the keyboard. So the test hooks gained a passive mode: `show` with object
`passive` shows the strip without making it key, plus `select`, `preview`, `tab` and `do`
(pause, pin, delete, focus, and `backdrop`). A window shot of a glass panel has no backdrop,
which falsifies vibrant colours, so `do backdrop` puts a plain window of our own behind the
strip and preview; `shot --screen --rect` limited to that rectangle then shows the real
composite and nothing of anyone else's. Text colours were read as the darkest/dominant pixel
in each text's region (line samples cut through anti-aliasing).

### Defects (before → after)

| # | Surface | Before | After |
|---|---|---|---|
| 1 | Cards | Corners rendered **square** (0 pt; the 13 pt layer radius never clipped because AppKit owns `masksToBounds` via `clipsToBounds`, off since macOS 14) inside an 18 pt selection ring | Card radius 10 = `Radius.nested(in: 22, padding: 12)`, read from `floatingPanelCornerRadius`; ring 15 pt, 5 pt outside. `measure corners`: concentric, gap 7.0 pt along the edges, 7.1 pt at the curve |
| 2 | Strip insets | Card 18 pt from the left edge, 15 pt from the bottom, 15 pt below the search field; search 12 pt from the top; 14 pt between cards | 12 pt (`Spacing.m`) everywhere: edge → bar, bar → cards, edges → cards, card → card. Panel 286 → 280 pt tall. Geometry moved into `ClipsCore.StripGeometry` with tests |
| 3 | Panel radii | `FloatingPanel(cornerRadius: 22)` and Quick Look `18` (literals, different) | Both `PanelMetrics.cornerRadius = Radius.xxl`; everything inside derives from it |
| 4 | Card text colours | Body labels resolved the glass's **vibrant** colours and drew them flat: body text #4D4D4D, secondary #999999 on white (2.9:1) | Card colours resolved against plain aqua/darkAqua: body #272727, secondary #808080 (3.9:1, the system floor); dark #DCDCDC / #999999 on #1C1C1C (6.0:1) |
| 5 | Search placeholder | Drew solid #181818 on glass, darker than the secondary tabs beside it (#646464); a styled `prompt:` was ignored | Own `.secondary` placeholder at the field's text origin; composited it matches "Pinned" |
| 6 | Foot row | Count text centre at h−11.5, size chip h−17, ⌘ badge h−15 | One centre line (h−15) for all three, 6 pt from the bottom |
| 7 | ⌘ badge | Radius 6, 6 pt into a 13 pt corner | `Radius.nested(in: cardRadius, padding: 6)` = 4, concentric |
| 8 | Size / hex chip | Radius 8 on an 18 pt chip (not a capsule); 50 % black → white text 3.9:1 over a white image | Capsule (height/2); 60 % black → 5.7:1 |
| 9 | Tabs | Pills 26 pt tall next to a 28 pt search capsule | 28 pt, same top/bottom edges and centre line |
| 10 | ⋯ menu | Glyph 16.5 pt from the right edge; hints 13 pt from the left | Hit area kept at 28 pt, overhangs 4 pt: glyph 12.5 pt from the edge |
| 11 | Contrast | "Not found" `.systemOrange` (≈2:1), preview "Missing" `.orange`, Settings warnings `.orange`, storage error `.red`, "Space to close" and "Not installed" `.tertiary` (≈1.9:1) | `.textOrange` / `.textRed`; `.secondary` |
| 12 | Link monogram | Bright site colours (yellow, mint) on their 16 % wash | Darkened 40 % in light mode (dark mode unchanged) |
| 13 | Hover | No hover state on cards | Neutral ring where the selection ring goes, 0.12 s fade (none with Reduce Motion) |
| 14 | Selection | Ring was a bare CALayer, so showing it faded in over an implicit 0.25 s, lagging the arrow keys | Instant (actions disabled); only hover fades |
| 15 | Preview | Image radius literal 6; colour swatch radius 14 + 1 pt border; rich text started 17 pt in (12 inset + 5 line padding) vs 16 pt for plain text | Image `Radius.nested(in: panel, padding: 16)` = 6; swatch `Radius.l` + 0.5 pt hairline; rich text at 16 pt |
| 16 | Preview, files | Missing file: "Missing", centred on the two-line block | "Not found" (same as the card) on the name's baseline |
| 17 | History | Detail action bar inset 12 pt under content inset 16 pt; list colour swatch 1 pt border, radius literal 4 | 16 pt leading edge for both; 0.5 pt hairline, `Radius.xs` |
| 18 | Copy | Status menu "Open History…" (ellipsis, but it asks nothing) vs "Open History" in the strip menu | "Open History" in both |
| 19 | Card header | Fixed label offsets (7/24 pt) | Kind + age centred as a pair from font metrics (cap top 11.5 pt, last line 11.5 pt from the header's bottom) |

`scripts/lint.sh Clips`: 8 radius literals and 2 spacing warnings → clean.

### Gates

- **Unit tests: 80 pass** (was 77; new `StripGeometry` suite: even insets, card and ring
  concentric with the panel, a radius never vanishes).
- **`scripts/check.sh Clips --perf`: pass** on the final code (lint, tests, bundle, smoke,
  catalog; load 1.8): launch 148 ms, first status item 317 ms, idle CPU 0.037 %, footprint
  35.4 MB.
- **5,000 clips** (hooks only): show 38–43 ms, search settled median 43 ms, p90 48 ms. The
  parity build (`/tmp/clips-test/Clips.app`) measured the same in the same conditions (show
  ~41 ms, median 45, p90 53): the display was asleep and the screen locked, which slows both
  against the parity pass's 16–27 ms / 13 ms. No regression from this pass; re-time awake.
- **`drive tree`: no `[unlabeled]`** in the strip (every state, light and dark), preview and
  Settings.
- **Window buttons 16×16** (Settings, About panel).

### Screenshots

`/tmp/slopapp-polish/clips/` (not committed). Before: `before-strip-light.png`. After, light
and dark (`final-light-*`, `final-dark-*`): `strip`, `strip-composited` (over our own backdrop:
the true colours), `numbers` (+ `numbers-composited`), `cards-focused`, `search`, `nomatch`,
`pinned-empty`, `pinned-one`, `pinned-delete`, `paused`, `images`, and the preview for each
kind `ql-text`, `ql-long`, `ql-rich`, `ql-code`, `ql-color`, `ql-link`, `ql-image`,
`ql-file1`, `ql-files3`, `ql-missing-file` (+ `final-dark-ql-image-composited`).
`final-light-about-panel.png`. Intermediate rounds: `r1`–`r10`.

### Not done, and why

- **Settings tabs and the History window weren't re-shot on the stamped build.** Both need
  Clips activated, which is only safe with the owner away; when they were, the screen was
  locked (an hour, twice), and macOS hides windows from Accessibility then. Their fixes
  (#11, #15, #17) were made from the code and the parity-pass shots; the AX tree showed no
  unlabeled controls and 16×16 buttons. Re-shoot `windows.sh` in `/tmp/clips-test/polish/tools`
  when the Mac is awake.
- **Status menu**: checked by its AX tree only (a shot of a system menu alone comes out blank).
  It's a standard NSMenu; the fix was the "Open History" ellipsis.
- **Hover ring and its fade**: needs the real mouse; not exercised. Code path: tracking area per
  card, `.activeAlways` because the strip never activates Clips.
- **Card body text set in a monospaced font for code**: a feature, not finish; deferred.

### SlopKit notes (not changed here)

- `NSColor.readableText(_:)` is internal, so AppKit views can't get `.textOrange` without
  `NSColor(Color.textOrange)`. A public NSColor variant would help AppKit-drawn apps.
- Any AppKit label inside `FloatingPanel`'s glass resolves the vibrant colour variants
  (`labelColor` 70 % black, secondary lighter still); on an opaque inner surface (a card) they
  draw a shade too light. Worth a helper or a note in `FloatingPanel`'s docs.
- A glass `FloatingPanel` captured with `drive shot` has no backdrop, so vibrant text reads
  wrong in the shot (the search placeholder looked black). Measure text over a backdrop.


## Paste-closer round (2026-11-06)

Owner: "Clips is still missing a bit of the design aesthetic from Paste." Studied from
Paste's public marketing images only (the coordinator's `scratchpad/paste/hero.png`,
`card1.png`); Paste itself was never opened and no clipboard was captured. Nothing of Paste's
name, icon, wording or assets is used.

### Decisions

| Question | Decision | Why |
|---|---|---|
| Card header | **Solid band in the source app's colour** with bold white type (14 pt bold type word, 11 pt medium time line, both pure white) | The owner asked for Paste's confident colour; supersedes the soft wash. |
| Header contrast | `ClipsCore.HeaderColor`: darken the app colour only until white reaches **4.5:1** (what the small time line needs). Colours lighter than luminance 0.55 (yellows) and oranges that would need > 30 % darkening (they turn brown) keep their bright colour with **dark type** instead (≥ 4.5:1). Dark mode: white-type colours sit 12 % deeper. No app / grey icon: system grey (darkened to 4.5:1) | Readable at every colour without muddying them. Messages and Safari land on Apple's own accessible variants (#23873C, #0070EA). |
| App colour | Hue of the icon's dominant bucket, saturation lifted to ≥ 70 % (brightness ≥ 75 %) before the contrast step | Icon averages are paler than the colour people know an app by. |
| App icon | **44 pt**, overhanging the card's top (2 pt) and right (4 pt) edges, cropped by the card's corner | As in the reference; the crop is the card's own rounded clip. |
| Panel | A floating glass slab: **16 pt** from the screen's edges and the Dock, **24 pt radius** = card radius 12 (`Radius.l`) + inset 12, system glass (`FloatingPanel`, so the Appearance clear/tinted slider applies) | Concentric by construction, ≈ the reference's radius. |
| Cards | **216 × 216 pt**, radius 12, **16 pt** apart (`Spacing.l`), 12 pt from the panel's edges; white (content background) body; soft shadow instead of an outline (light: 14 % black, 4 pt blur, 2 pt down; dark: 45 %, 2 pt blur, plus a hairline edge since shadows barely read there) | Roomier and squarer, as asked. |
| Card text | 13 pt primary; a first line that reads like a heading ("Address:", a short title line followed by more text) is semibold (`ClipText.headingLength`, tested) | Matches the reference's "Address:" cards. |
| Top bar | Centred calm search capsule (quaternary fill, no focus outline: the caret shows focus) + **text pill tabs** (selected = filled capsule, semibold; widths reserved so nothing shifts); ⋯ at the far right. **Removed**: the left key hints and the clip count | The reference's calm, centred bar. The hints live in the search field's and ⋯'s help tags; the count and the selected clip's actions (Paste in …, as Plain Text, Preview, Pin, Delete) are in the ⋯ menu. No coloured dots: they mean pinboards, which Clips doesn't have yet. |
| ⋯ menu | AppKit button whose menu is built when it opens | A SwiftUI `Menu` naming the selection rebuilt itself on every keystroke. |
| Scroller | Hidden (it drew over the cards) | Trackpad, wheel and keys scroll. |
| Preview | Content on a text-background surface 8 pt in, concentric (16 pt radius) | Readable over any wallpaper at the clearest glass setting (Golden Gate rule). |
| Test data | Synthetic history and fixtures attributed to real Apple apps (Safari, Messages, Mail, Notes, Photos, Xcode, Finder, Preview, Music, Books, Maps, TextEdit) by bundle ID; fixtures declare their app with `org.nspasteboard.source` | So the header colours show. Only the apps' names and icons are used. |

### Before → after

| | Before (polish pass) | After |
|---|---|---|
| Header | 20 % wash, dark 13 pt semibold text, 30 pt icon | Solid app colour, white 14 pt bold / 11 pt medium (≥ 4.5:1; dark type ≥ 4.5:1 on yellows/oranges), 44 pt cropped icon |
| Panel | 8 pt from the screen, radius 22, reads as a bar | 16 pt from the screen, radius 24, floating glass slab |
| Cards | 224 × 216, radius 10, 12 pt gaps, 0.5 pt outline, 12 pt text | 216 × 216, radius 12, 16 pt gaps, soft shadow, 13 pt primary text with heading line |
| Top bar | Key hints left, accent-outlined search, icon tabs, "51 clips" | Centred calm search + text pills, ⋯ only |
| Scroller | Drawn over the cards | None |
| Ring | 3 pt accent, 2 pt gap, radius 15 | 3 pt accent, 2 pt gap, radius 17 (concentric: 24 − 7) |

### Speed (5,000 clips, hooks only, same data and conditions, two runs each)

| | Parity build | This build |
|---|---|---|
| Show, cold / warm | 51 / 29–36 ms | 39–48 / 8–28 ms |
| Search settled, median / p90 / max | 32–37 / 39–43 / 50–58 ms | 34–37 / 43–44 / 51–53 ms |

First version of this round had a 102 ms cold first search: the ⋯ `Menu` rebuilding, and
cold icon loads for apps the first screenful didn't show. Fixed with the AppKit menu and by
warming every history app's icon and colour while the panel prewarms. The machine was slower
today than during the parity pass (13 ms medians then), for both builds.

### Golden Gate + light/dark

- Menus: every menu (status menu, ⋯, card and History context menus) is text only. ✓
- History: system `NavigationSplitView` sidebar (edge to edge, accent-tinted symbols), standard
  unified toolbar, NSTableView selection (greys when inactive). Shot active and inactive.
- Glass: the strip and preview are SlopKit `FloatingPanel` (system glass). Readable text on glass
  is the top bar (system vibrant labels) and the preview header; card and preview content sit
  on opaque surfaces.
- Light and dark: every strip state and preview shot in both over a wallpaper-like backdrop
  (`v2-light-*`, `v2-dark-*`). Header colours, shadows and the card edge resolve per
  appearance and update on appearance change (`viewDidChangeEffectiveAppearance`). The only
  fixed colours drawn are the chip's 60 % black (over pictures) and the header inks (white or
  black, chosen per header colour by contrast).

### Gates (Paste-closer round)

- **Unit tests: 89 pass** (was 80): header colour (white type ≥ 4.5:1 on every white-type
  colour, darkens only as far as needed, yellows and oranges keep their colour with dark
  type in both modes, dark mode deeper, contrast maths), heading detection, the 24/12/16
  strip geometry and its overflow bounds.
- **`scripts/check.sh Clips --perf`: pass** on the final code (lint, tests, bundle, smoke,
  catalog): idle CPU 0.046 %, footprint 33.8 MB (launch 168 ms and first status item 396 ms
  on the run before the last hook changes).
- **`drive tree`: no `[unlabeled]`** in the strip, Settings (every tab) and History; window
  buttons 16×16.

### Screenshots (`/tmp/slopapp-polish/clips/`, not committed)

- `compare-paste-light-dark.png`: the reference strip (`card1.png`) above ours, light and dark.
- Strip and states, composited over our own wallpaper-like backdrop window (the system's
  Ventura Graphic thumbnail, light and dark): `v2-{light,dark}-strip`, `-numbers`,
  `-cards-focused`, `-search`, `-nomatch`, `-pinned-empty`, `-images`, `-paused`,
  `-pinned-delete`, `-strip-end`.
- Preview per kind: `v2-{light,dark}-ql-*` (short, link-messages, note-heading, image-photos,
  long-mail, rich-textedit, code-xcode, color, link-safari, link-music, quote-books,
  unknown-app, link-maps, image-preview, file-missing, files3, file1).
- History active: `v2-{light,dark}-history-selected.png` (accent sidebar symbols and
  selection); inactive: `v2-{light,dark}-history-inactive.png`.
- Settings, every tab, inactive: `v2-{light,dark}-settings-{General,Shortcuts,Privacy,About}-inactive.png`.

### Not done, and why

- **Settings active-window shots**: every attempt lost to the owner coming back within
  seconds (Settings needs Clips activated, which is only allowed while they're away). The
  inactive shots cover every tab in both modes; the window is SlopKit's standard tabs.
- **Pinboard dots** in the tabs: they mean user pinboards, which are still deferred.
- **Link page images** (the reference shows page previews): need the network; the monogram tile stays.
- **Hover ring**: needs the real mouse; not exercised.

### Session notes

- The owner's Clips was off for **about 34 minutes** (21:04–21:39), then twice for a few
  seconds (relaunching it with the right sound setting; the final gate's perf run). A test
  copy then ran beside it from a separate app copy with `CLIPS_NO_HOTKEY=1`.
- Twice, every running Clips (the test copy, and once the owner's) disappeared with no crash
  report; most likely quit from the menu bar while two Clips icons were showing. The owner's
  copy was relaunched each time; Clips' defaults were restored from the backup and verified
  identical at the end.
- New test-only switches: `CLIPS_NO_HOTKEY=1`, `CLIPS_TEST_BACKDROP=/path`, hook actions
  `do history|settings|history-passive|settings-passive|backdrop|nobackdrop` (passive ones
  open the window without activating Clips, so a scripted shot can't take anyone's typing).
- Fix found on the way: with the menu bar icon hidden, ⌘Y / Open History did nothing (the
  window action is captured by the icon); it now falls back to the Window menu's command.


## Sound round (2026-11-07)

> Playback, Settings and Migration below are **superseded by "Sound pairs round"** (same
> day): six new pairs, Paper the default, the old Snap/Tock kept as Classic, macOS sounds gone.

Owner: "Clips needs the sound effect similar to Paste. This is a feature I use all the time."
Paste's two sounds were measured read-only by the coordinator (duration, level, envelope,
spectrum); nothing of them is copied, bundled, resampled or derived. Clips' sounds are
synthesized in code from our own parameters (`ClipsCore/SoundSynthesis.swift`).

### Decisions

| Question | Decision | Why |
|---|---|---|
| Copy and paste sounds | **Our own synthesized sounds, inspired by the feel of Paste's**: "Snap" when a copy is recorded, a soft "tock" when Clips pastes or copies a clip for you | The owner uses the sound all the time; Pop (1.6 s, 450–700 Hz with bounces) was far too heavy. |
| Snap | 0.20 s, peak −18 dBFS. Tick at 2 ms: damped 5.3 kHz sine (τ 3 ms) + 1.85 kHz partial at 0.45 (τ 4.5 ms) + a 4 kHz-high-passed noise burst at 0.35 (τ 1.2 ms), 0.6 ms raised-cosine attack. Swish from 82 ms: noise band-passed 7–11.5 kHz, 12 ms attack, 40 ms decay, 12 dB below the tick. 15 ms fade-out, 30 Hz DC block | "tik…shh", a card snapping and sliding, at Paste-like level, with different frequencies and timing. |
| Tock | 0.08 s, peak −12 dBFS. Damped sine gliding 970 → 880 Hz (glide τ 12 ms), τ 6 ms, 1.2 ms attack, plus a 2.9 kHz click at 0.18 (τ 0.7 ms). 10 ms fade-out | Soft and short, a little lower and rounder than the reference. |
| Playback | Rendered once to AIFF (16-bit mono 44.1 kHz) in `~/Library/Caches/app.slopapp.clips/Sounds/` (`snap-v1`, `tock-v1`; the test data folder under `CLIPS_DATA_DIR`), played as AudioToolbox system sounds; sound IDs created at launch | Same device and volume as UI sounds; no latency on the first copy; no idle work. Bump `SystemSoundPlayer.version` when the synthesis changes. |
| Settings | General: "Play sound when copying" (on) → "Copy sound" (Snap, then Pop, Tink, Bottle, Morse, Purr); "Play sound when pasting" (on). Choosing a copy sound previews it; turning the paste sound on previews it | The system sounds stay for anyone who picked one; one paste sound reads tidier than a second picker. |
| When the paste sound plays | Return, ⇧Return, ⌘1–⌘9, double-click, the card and ⋯ menus, History's Copy, a card dragged into an app. Not ⌘V in other apps (Clips doesn't see it) | "Clips did it for you." Clips' own pasteboard write never counts as a copy, so no Snap on top. |
| Rules kept | System Settings' "Play user interface sound effects" off → silent; throttle 0.2 s per kind | As before. |
| Migration | No saved `copySound` (the owner's settings) → Snap. A saved choice ("Pop" …) is kept. No saved `playsPasteSound` → on | Nobody loses an explicit choice. |

### Measured (the `analyze` tool, 5 ms RMS windows, dB)

Copy, ours (0.200 s, peak −18.0 dBFS) vs the reference (0.207 s, peak −18.4):

```
ours  0–40 ms  -29 -35 -47 -58 -68 -78 -87 -96      | gap -120 … | 80 ms -62 -45 -40 -38 -40 -41 -43 -43 -45 -45 -46 -48 … -59 -64 -78 -120
ref   0–40 ms  -53 -46 -49 -42 -27 -32 -38 -46      | gap -46 … -61 | 100 ms -38 -44 -43 -43 -44 -45 -44 -46 -44 -46 -48 … -60 -62 -66
spectrum: ours tick 5.3 kHz + 1.85 kHz, swish centroid ~9.5 kHz; ref tick 6.7 + 2.6 kHz, swish ~10.7 kHz
```

Paste, ours (0.080 s, peak −12.0 dBFS) vs the reference (0.080 s, peak −10.4):

```
ours  -18 -22 -29 -36 -43 -51 -58 -65 -72 -79 -86 -92 -106 -120   (centroid ~900 Hz, gliding to 883 Hz)
ref   -65 -16 -22 -30 -46 -58 -71 -84 -97 -110 -119 -120          (centroid ~1,000 Hz)
```

Same shapes (one bright tick, a quiet gap, a soft high swish ~20 dB down; one fast low
tock), our own frequencies and timing. Ours tick right away (2 ms) where the reference
ramps in over ~20 ms, and the tock decays ~6 dB per 5 ms against the reference's ~10, so it
rings slightly longer and softer. Nobody listened to them (no audio check is possible here):
these numbers and the unit tests are the evidence.

Verified in the built app (test copy, private pasteboard, test data): the files are written
on first launch and are byte-identical to a standalone render; a recorded copy logs
`copy sound played sound=Snap`; Return and ⌘2 in the strip log `paste sound played` with
no copy sound after.

Tests: **97 pass** (was 89): synthesis deterministic, lengths, peaks, no clipping, no DC,
silent ends, the copy envelope's two events and the paste envelope's single fast decay,
AIFF header; the policy (copy and paste switches, system switch, separate throttles, chosen
sound, previews, migration, Clips' own write isn't a copy).

Gate and install (2026-11-07):

- **`scripts/check.sh Clips --perf`: pass**, run with the installed copy quit: launch 160 ms,
  first status item 412 ms, idle CPU 0.029 %, footprint 31.9 MB. Pre-creating the two
  sound IDs at launch costs nothing measurable (31.3–31.5 MB with, 31.5–32.5 without).
- Caught on the way: with another Clips running (the installed one), `open build/Clips.app`
  hands over to the running copy (same bundle ID) instead of starting the build. A first
  gate run therefore "failed" at 60 MB by measuring the owner's own copy, and its reopen
  opened that copy's Settings (closed again). Run perf and smoke with Clips quit.
- Installed with `ditto build/Clips.app /Applications/Slopapp/Clips.app`, `lsregister -f`
  on it, `lsregister -u build/Clips.app` (and the two old test copies); downtime 53 s
  (the gate ran inside it). Clips' defaults were restored from the backup: no sound keys,
  so Snap and both sounds are on.

## Sound pairs round (2026-11-07)

Owner listened to six alternative pairs the coordinator synthesized (reference generator
`synth.swift`, renders `alt/{1-paper … 6-pluck}-{copy,paste}.wav`, in the coordinator's
scratchpad) and picked **#1 Paper**. All six are ported into ClipsCore; the first pair stays
as Classic.

### Decisions

| Question | Decision | Why |
|---|---|---|
| Choices | Settings › General › **Sound**: Paper (default), Glass, Wood, Bubble, Snap, Pluck, then a separator and Classic | The owner's list. Short names of our own. Classic sits apart: it's the old pair, not one of the new family. |
| What a choice is | A pair: one copy sound and one paste sound | The six were designed as pairs; one picker reads tidier than two. |
| Picker visibility | Shown while either "Play sound when copying" or "…when pasting" is on; picking one previews its copy sound | The choice affects both sounds; previews as the brief asks. On/off switches and their previews unchanged. Volume unchanged: system-sound playback at the alert volume, as before (there was never a slider). |
| macOS sounds (Pop, Tink …) | Removed | Not in the owner's list; the new pairs are all loudness-matched and short. |
| Migration | New key `soundChoice` (never written until someone picks). No key → Paper. Old `copySound` "Snap" (only written when someone picked it) → Classic. Old "Pop" … → Paper. `playsCopySound` / `playsPasteSound` unchanged, so off stays off. Nothing is written back at launch | "Never changed it" → Paper; someone who picked the old Snap keeps that sound; the macOS sounds have no equivalent. The owner had no sound keys → Paper. |
| Synthesis | `ClipsCore/SoundPairs.swift`: the reference's building blocks (`partial`, `noise`, `pluck`, `mix`, `lowpass`, `room`, `finish`) with the same arithmetic order; copy −30 dB RMS of the active part (samples > 5 % of peak), paste −27 dB, peak guard −6 dBFS, 44.1 kHz | "Match the reference closely." |
| Determinism | Each sound has its own fixed xorshift64 seed: the reference generator's state where it started that sound | Deterministic, and the output equals the reference renders (below) instead of merely resembling them. |
| Cache | `<choice>-<copy|paste>-v2.aiff` (`SoundPairs.version = 2`); on first prepare, any `.aiff` in the folder without the current `-vN` suffix is deleted (the old `snap-v1` / `tock-v1`) | Stale files can never be played; bump the version when any synthesis changes. |
| Threading | `SystemSoundPlayer.prepare(choice)` renders the pair and creates its sound IDs on a serial utility queue, at launch and when the choice changes. `play` is a lock-protected dictionary lookup + `AudioServicesPlaySystemSound`. If an ID isn't ready (a preview of a pair just picked) `play` waits on the same queue: one render, never two | Before this round `prepare()` ran on the main thread; now it's really off it. Copy/paste hot path unchanged. Each render is 0.3–0.7 ms (release). |
| Test isolation | With `CLIPS_DATA_DIR`, settings live in the `app.slopapp.clips.test` defaults domain | A walkthrough that picks sounds must never write the owner's settings (the last rounds had to restore them from a backup). |
| Test hook | `do copy`: copies the selected card as Return does with direct paste off | Lets a script trigger the paste sound without keyboard focus or ⌘V. |

### Fidelity (vs the reference renders)

Sample-by-sample against the 24-bit reference WAVs: max difference **5.96e-8** for all 12
sounds (half a 24-bit step: identical before quantisation); same lengths. The `analyze`
tool shows identical 5 ms RMS envelopes and spectra for the app's 16-bit AIFFs (only the
last tail window, at −92 vs −93 dB, differs from quantisation). Levels: every copy sound
−30.00 dB active RMS, every paste −27.00; peaks −13.4 to −20.2 dBFS (guard never engaged).

### Gates (Sound pairs round)

- **Unit tests: 110 pass** (was 97). New `SoundTests.swift`: determinism (all 14), loudness
  ±1 dB (all six pairs), peak guard (each sound ≤ −6.02 dBFS, and a synthetic spike clamped
  to exactly 0.5), clean (no DC, silent ends, short), lengths, every sound distinct
  (pairwise unequal, normalized correlation < 0.9), characters (Paper has no tonal peak;
  Glass/Wood/Pluck ring at 2093/1320/784 Hz; Bubble rises for copy and falls for paste),
  default Paper, migration (none → Paper, old Snap → Classic, old Pop … → Paper, new key
  wins, unknown falls back), sound off stays off, versioned unique file names; the chime
  policy tests moved here and use pairs.
- **`scripts/check.sh Clips`: pass** (lint, tests, release bundle, smoke, catalog).
  **Perf** (`scripts/perf.sh Clips --no-bundle`, installed copy quit; busy machine, load
  4.5): launch 167 ms, first status item 432 ms, idle CPU 0.033 %, footprint 34.5 MB. A first
  `check.sh --perf` run with the installed copy still running "failed" at 63.6 MB: it
  measured the owner's copy again (same bundle ID hand-over, see the last round), and opened
  its Settings, closed again with an AX press on its close button.
- **Walkthrough** (release build, `--direct`, `CLIPS_DATA_DIR=/tmp/clips-test/sounds/data`,
  private pasteboard, `CLIPS_NO_HOTKEY`, test hooks, passive windows only: the owner was
  typing the whole time, so nothing took keyboard focus and no mouse was used):
  - Fresh domain: Settings shows Sound = Paper; only `paper-{copy,paste}-v2.aiff` written
    (byte-identical to the verified render); planted `snap-v1.aiff` / `tock-v1.aiff` deleted.
  - A copy on the private pasteboard logs `copy sound played sound=paper`; `do copy` on a
    card logs `paste sound played sound=paper` with no copy sound after.
  - Picking each of the seven in the popup saves `soundChoice` and renders that pair once
    (14 files, no duplicate writes after the queue fix).
  - Old `copySound=Snap` only → Sound = Classic, sounds `classic`; the domain is not
    written. Both switches off + `copySound=Pop` → both off, picker hidden, a copy is
    recorded silently; turning pasting on shows the picker at Paper.
  - `drive tree`: no `[unlabeled]` controls. Screenshots looked at, light and dark (§10:
    system controls, grouped form, separator before Classic, no hardcoded colours).
- **Not verified**: actually hearing the sounds (no audio check is possible here; the
  sample comparison and the play log are the evidence) and the panel's real Return/⌘2
  keystrokes this round (owner active; same code path as `do copy`, verified last round).

Screenshots (`/tmp/clips-test/sounds/shots/`, not committed): `settings-light.png`,
`settings-dark.png`, `sound-menu-dark-1.png`, `settings-sounds-off-dark.png`,
`settings-paste-on-dark.png`.

### Install (2026-11-07)

Backed up `defaults export app.slopapp.clips` first. Quit the installed copy, ran perf,
moved the old bundle aside (rollback copy kept in the coordinator's scratchpad), `ditto
build/Clips.app /Applications/Slopapp/Clips.app`, `lsregister -f` on it, `lsregister -u`
on `build/Clips.app`, relaunched from /Applications: **downtime 22 s**. After: only the
/Applications path is registered; Clips' defaults identical to the backup (no sound keys,
so Paper with both sounds on); history files untouched; `~/Library/Caches/app.slopapp.clips/Sounds`
holds `paper-{copy,paste}-v2.aiff`. The test defaults domain was deleted afterwards.



## Organize-and-reuse round (2026-11-11)

Owner, after comparing Clips with the app it replaces: one Pinned list can't replace
organized collections; form filling needs a paste stack; saved text needs fixing before
reuse; the strip needs multi-select; search should find text inside images. Built on top of
the uncommitted "Trim whitespace" setting, image-card file drags and the SlopKit menu bar
change, all kept.

### What was built

| Feature | How it fits |
|---|---|
| **Named boards** | `ClipsCore/Board.swift`. A board has a name and a system colour (9: red … gray, stored by name). A clip is on at most one board (`Clip.boardID`); being on one *is* being pinned (`isPinned` is now derived), so retention, Clear History and the second-⌘⌫ rule apply unchanged. Tabs: All · boards (colour dot) · + · Text · Links · Images · Files; ⌘← ⌘→ walk them. + / ⇧⌘N make a board and open its name field in the tab (Return keeps, Esc on a just-made board removes it, clicking away keeps the name). Board tab right-click: Rename, Color ▸ (swatches), Move Left/Right, Delete Board…. Double-click renames. History sidebar: a Boards section (drag to reorder, same context menu) and New Board. |
| Pin to a board | ⌘P toggles the first board (Pinned by default, so old muscle memory works); ⌥⌘1–⌥⌘9 the nth board (again: off it); card and ⋯ menus "Pin to ▸" with swatches, checkmark and the ⌥⌘ keys; drag cards onto a board tab (the tab rings in the accent colour while hovered), or onto + for a new board holding them. |
| Board delete | An empty board goes at once. One with clips asks in the strip's notice area ("Delete “Work”? Its 5 clips stay in your history, no longer pinned. Esc keeps it." [Delete Board]); History uses a confirmation dialog. Clips are never deleted with a board. |
| **Migration** | Schema v4: `boards` table, `board_id`, `label`, `ocr_text` columns. Every v3 pinned clip goes onto a "Pinned" board with a fixed id; a fresh history also starts with Pinned. Each open also reconciles with older builds, which still read/write only `pinned` (this build keeps it in step): an older build's pin lands on the first board (recreating Pinned if every board was deleted), its unpin takes the clip off. Tested against a hand-built v3 file (`BoardDatabaseTests`). |
| **Titles** | ⌘R (any kind) / Add Title… / Rename…: the title replaces the kind word in the card header, is the History row title, and is searched. Kept when the same content is copied again. |
| **Editing** | ⌘E turns the preview into an editor: title field, Cancel / Save, the text in an NSTextView. RTF/RTFD clips edit as formatted text and save as RTF (RTFD with pictures); HTML-only formatting can't be rendered safely (remote content), so those clips are edited and saved as plain text, and the editor says so before you save. The edit replaces the clip in place (same id, board, title, dates), with a new fingerprint, so the edited text is what pastes and copying it again finds it. Empty text is refused. Esc cancels; ⌘S / ⌘Return / Return in the title saves; clicking away keeps the edit. History's detail pane hosts the same editor (⌘E, Edit button). `ClipsCore/ClipEdit.swift`. |
| **Multi-select in the strip** | `ClipsCore/StripSelection.swift`, Mac list rules (same as the History table): click, ⌘-click, ⇧-click range from the anchor, ⇧-arrows, ⇧Home/End, ⌘A. Every selected card gets the ring. Pressing one of several selected cards keeps them for a drag; releasing selects just it. Return/⌘C paste/copy them joined (`ClipJoin`), ⌘P/⌥⌘n pin them, ⌘⌫ deletes them (pinned among them: second ⌘⌫; ⌘Z restores all), a drag carries all. Esc collapses the selection before clearing the search. A notice says "3 clips selected. Return pastes them together, ⇧⌘C one by one." |
| **Paste stack** | ⇧⌘C in the strip, Start Paste Stack in the ⋯ and menu bar menus, or an optional global shortcut (Settings › Shortcuts, no default). Empty: every recorded copy joins it. With several cards selected: those, oldest first, and the first is pasted right away. A non-key floating list (top-right) shows what's next and how many are left; click a row to make it next; ✕ stops. The menu bar icon becomes a stack, and the strip shows a "Paste stack" notice with Stop. Ends by itself after the last paste (HUD "Paste stack done"). `ClipsCore/PasteStack.swift`, `Clips/PasteStackController.swift`, `Clips/PasteStackPill.swift`. |
| **Text in images** | Vision `VNRecognizeTextRequest` (accurate, language correction) on device. `TextRecognitionQueue` (core, tested with a fake) works one image at a time, new copies first (1 s after capture), older images 5 s after launch, 0.4 s apart, waiting out Low Power Mode. Results (capped 5,000 chars, "" = none) go in `ocr_text` and the search key; an image card hit by a search shows the matched words in its chip; Copy Text in Image in the card and History menus. |

### Decisions

| Question | Decision | Why |
|---|---|---|
| One board per clip, or tags? | **One** | Matches how people file things and keeps "pinned" one clear idea; multi-board would need a join table and murkier ⌘P. |
| Where do board tabs go? | **Right after All**, where Pinned was | ⌘→ once still reaches Pinned; the kinds read as filters after the collections. + sits between the two groups and doubles as a drop target. |
| Default board, fresh install | **Pinned** (orange) | Same tab and ⌘P as before for everyone; renamable and deletable. If no boards are left, ⌘P makes Pinned again. |
| Deleting a board with clips | **Clips stay, unpinned**; confirm in place | Less destructive than deleting them; the confirmation lives in the strip's notice area so the strip stays open (an alert would steal key and close it). |
| Reordering boards | Move Left/Right in the panel, **drag in History's sidebar** | Drag-reorder inside a 28 pt glass tab row is fiddly; the sidebar has native `.onMove`. |
| Edit in place or as a copy? | **In place** | "Fix saved text before reuse": the fixed version should be the one in its board. |
| Click-away while editing | **Keeps the edit**; Esc discards | Like Finder rename; losing typing is worse than saving it. |
| Order for several clips | **Oldest first** (the order you copied them), for joined paste, joined copy (History too, which used to be newest first) and stacks | One rule everywhere: things copied in reading order paste in reading order. |
| Detecting a paste for the stack | **A promised pasteboard item**: Clips gives the data when an app asks, and that ask is the paste | No event tap, no Accessibility or Input Monitoring, works for ⌘V, Edit › Paste and right-click Paste. Only the first read per item counts (one paste may read RTF then text), with 0.3 s to settle. The item is marked `TransientType`, so other clipboard managers skip it instead of reading it (a read would look like a paste). |
| Global stack shortcut | **Recorder, no default** | ⇧⌘C (the original's) is Inspect Element and more in many apps; the strip's ⇧⌘C is always there. |
| Where Vision runs | **A helper process** (Clips' binary with `--recognize-text`, stdin/stdout, quits after 10 s idle) | In-process, Vision peaked at 202 MB and left Clips at 59 MB (budget 50). With the helper Clips stayed at 35 MB through recognition. |
| Recognition level | Accurate + language correction, image ≤ 2,400 px | Screenshots are the main case; fast mode misses small UI text. It runs once per image, in the background. |
| Smoke test safety | `SLOPAPP_SMOKE_TEST=1` gets a temp history, private pasteboard, no hotkey | `scripts/smoke.sh` runs the bare binary for 3 s; with this round's migration and image reading it would otherwise have migrated and read the owner's real history. |

### Gates

- **Unit tests: 167 pass** (was 110). New: `BoardTests` (board names/colours/moves/tabs,
  pins and pruning, release on delete, labels, **v3 → v4 migration test**, fresh history,
  boards and labels round trip, older-build pin/unpin reconciliation, Pinned coming back,
  recognized text stored and searched), `EditTests` (edit replaces in place and dedupes,
  RTF kept and HTML dropped, kind changes, empty/image refusal, long text in full, strip
  selection rules, joins), `StackTests` (stack order, adding, skip/back, deletes, read
  tracker, recognition queue order/dedupe/failure/cancel, image snippets, new panel keys).
- **`scripts/check.sh Clips`: pass** (lint, icon, SlopKit + Clips tests, release bundle,
  smoke, catalog). The catalog regeneration also carried another builder's Snapper change;
  only my date bump was reverted.
- **Perf**: `check.sh --perf` was **not run as is**: perf.sh launches `build/Clips.app`
  through LaunchServices, which hands the launch to the owner's running /Applications copy
  (same bundle id; last round it opened that copy's Settings). The same measurements on a
  `--direct` test copy of the release build (`scratchpad/tools/perf-direct.sh`, 3 launches,
  3 × 5 s idle, empty test history, load 11): launch 93/98/106 ms, first status item
  260–278 ms, idle CPU lowest 0.025 % (0.039 median), footprint 30.9 MB. After image
  recognition: 35.2–35.9 MB (helper separate, gone when idle).
- **Walkthrough** (release build, `--direct`, `CLIPS_DATA_DIR=/tmp/clips-test/data`,
  private pasteboard `clips-test`, 30 seeded clips + fixtures written with a scratch tool;
  hooks only, strip shown passively; verified through the log, the test database and reads
  of the private pasteboard):
  - Image text: a PNG with "Invoice 4471…" found ~1 s after the copy; searches "4471" and
    "gate b22" each return just their image.
  - Boards: new board, colour, move, three cards ⌘-selected and pinned to it; card dropped
    on a board tab pinned there; empty board deleted at once; a board with clips asked first,
    then deleted with all 37 clips kept unpinned; ⌘P then pinned to the first board left.
  - Editing: RTF clip "tilte" → "title" saved with fresh RTF (no HTML), title "Pancakes"
    saved and searchable; ⌘R title on a plain clip; emptied text refused, then cancelled
    with the original intact.
  - Paste stack: from three selected cards: three pastes delivered them oldest first and
    the stack ended itself. Collect mode: three copies, three pastes in copy order; Clips'
    own re-arming writes were never recorded as copies.
  - Several cards: ⌘C of three link cards copied them oldest first, one per line; ⌘⌫
    deleted all three.

### Not verified, and why

- **Screenshots, light/dark, `drive tree` labels, §10 visual checks**: the Mac's screen was
  locked/asleep for the whole session (owner away), and macOS hides windows from
  Accessibility then; `drive windows` refused. Every new control has an accessibility label
  in code (tabs with board name and count, New Board, Board name, Clip title, Clip text,
  Stop Paste Stack, stack rows, card labels with "pinned to …" and image text). Shoot:
  board tabs (+ hover ring), name field, notices, editor (plain, rich, HTML note), multi-ring,
  stack list, History sidebar Boards and detail, both modes.
- **Real mouse**: drag a card onto a tab (the tab-frame → screen mapping was exercised only
  by the hook, which uses the same mapping), ⌘/⇧-click, the stack list's buttons. Not done
  with the screen locked. The synthetic mouse-down issue from last session couldn't be
  investigated either; SlopDrive posts clicks at the HID level, so the likely cause is the
  `activate` step its mouse guard asks for (activating Clips moves key away from the
  non-activating strip, which then closes itself). Worth checking without `activate`, since
  the floating strip already passes the guard's "own window on top" check.
- Real direct paste of the first stacked clip (needs ⌘V into another app).
