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

