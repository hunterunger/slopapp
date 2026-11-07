# Triggers research (inspired by BetterTouchTool)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied:
> BetterTouchTool 6.1110 (folivora.AI; **not installed on this Mac**, by instruction not
> installed for this study) from its website, documentation, community forum, release notes,
> Setapp reviews and user "my setup" threads, on 2026-11-07. Platform notes come from Apple
> documentation, Apple developer forums and open-source projects that read the trackpad.
> We never copy names, icons, artwork, wording, sounds or signature visuals.

## The job

People hire this kind of app to make their own hands faster: a gesture, an extra mouse button
or a key combination does the thing they do fifty times a day (open a link in a new tab,
close a tab, go back, put this window on the left half, run that Shortcut), and it does the
right thing for the app in front. They set it up once, forget it exists, and notice only when
it's missing on a new Mac. "Done" is: perform the input, the action happens instantly, and
nothing else about the Mac feels different (no lag, no misfires, no system gesture broken).

The one interaction that matters most: **tap three fingers on a link and it opens in a new
tab** (more generally: perform an input, the bound action runs in the front app, in under a
frame of perceived delay).

BetterTouchTool (BTT) has grown into a platform: 18 trigger families (trackpad, Magic Mouse,
mice, keyboards, Touch Bar, Stream Deck, MIDI, gamepads, Siri Remote, drawings, AI assistants,
...), hundreds of actions, a launcher, clipboard manager, screenshot tool, menu bar manager,
window snapping, floating widgets, scripting servers and a phone remote. The research job here
is mostly **the cut**: what do people actually use, and what is the smallest Triggers that
covers it well.

## Who and when

- Browsing: three-finger tap on a link opens it in a background tab; three-finger tap on a tab
  closes it; swipes or tip-taps switch tabs; extra mouse buttons go back and forward in
  Safari and Finder (which ignore buttons 4 and 5 on their own).
- Window placement without the keyboard: four-finger swipe left/right puts the window on that
  half, up maximizes, down minimizes; a gesture moves the window to the other display.
- Per-app power moves: a gesture or mouse button sends Esc in one app, a middle click in
  another, a menu command with no shortcut in a third (DEVONthink, OmniFocus, Excel, CAD).
- Keyboard: F-keys or ⌃⌥ combos open apps, run Shortcuts, or trigger menu items that have no
  shortcut.
- Mice without vendor software: replace Logitech Options / Razer Synapse for button mapping.

Frequency: dozens to hundreds of fires a day for the gestures and mouse buttons (each fire
is instantaneous). Configuration happens a few times in the first week, then rarely.

## What people actually use (ranked by real use)

Evidence: the "how do you use BTT" threads on Automators and Mac Power Users (two threads), the
MacRumors gestures thread, MacStories' tutorials, the 20 most recent Setapp reviews (Jan to Oct
2026, app versions 5.800 to 6.954), and the many single-purpose apps that exist only because
people buy BTT for one thing (MiddleClick, MiddleDrag, Trident: three-finger tap as middle
click; Swish: window gestures; Multitouch: gestures only). Counts are approximate mentions.

| Rank | Use | Evidence | Triggers v1? |
|---|---|---|---|
| 1 | **Trackpad multi-finger gestures** mapped to keys, clicks and app actions (3/4-finger swipes and taps, tip-taps, corner clicks) | ~30 mentions in MPU thread; ~10 Automators; 5 of 20 Setapp reviews; every MacRumors poster | Yes: 3/4-finger taps and swipes |
| 2 | **Three-finger tap/click = middle click** (open link in new tab, close tab, paste in Terminal) | MacRumors, MPU, MacStories; at least four standalone open-source apps exist for this alone | Yes, as an action |
| 3 | **Tab and navigation gestures** (next/prev tab, new/close tab, back/forward), usually per app | 4 posters in MacRumors, MPU (tim, SteveMac), MacStories | Yes: per-app bindings + "press shortcut" |
| 4 | **Window placement** by gesture or shortcut (halves, maximize, minimize, next display, thirds on ultrawides) | ~25 mentions MPU; 3 of 10 in "BTT without a Touch Bar" | Yes: a small set of window actions |
| 5 | **Touch Bar** customization | ~15 MPU, ~5 Automators (2018-2020 era) | No: hardware discontinued |
| 6 | **Mouse buttons** (back/forward, Mission Control, replacing vendor drivers) | 4 of 20 Setapp reviews, 2-3 per forum thread | Yes: extra buttons with modifiers |
| 7 | **Keyboard shortcuts** per app, to apps / menu items / other shortcuts | 3 of 10 "without Touch Bar"; samkale's window keys | Yes: key combos (no remapping engine) |
| 8 | Hyper key, modifier-only taps, key remaps, tap-hold keys | 3-4 mentions | Later at most (needs a keyboard event tap) |
| 9 | Text snippets / key sequences | 2-3 mentions | No: Shorthand's job |
| 10 | Clipboard history, launcher, screenshots, menu bar hiding | 1-2 mentions each | No: Clips, Snapper, Tuck, Spotlight |
| 11 | Drawn gestures (draw "M" for Mail) | 2 mentions | Later |
| 12 | Scripting (AppleScript/JS, URL scheme, webserver), Stream Deck, MIDI, gamepads, AI | Power-user tail | "Run Shortcut" covers most; rest skip |

Takeaways: people use **a handful of gestures and buttons, heavily, mostly per app**. Recent
reviewers praise depth but nearly all criticism is about complexity and the learning curve.
Several people say they use BTT "only" for one or two things. That is the opening: the
everyday 80% with a fraction of the surface.

## macOS built-ins and other Slopapp apps (overlap)

**macOS already does** (as of macOS 26/27; we don't duplicate, we coexist):

- Trackpad (System Settings › Trackpad): tap to click, secondary click, Look Up (force click
  or three-finger tap), pinch zoom, smart zoom, rotate, swipe between pages (2 or 3 fingers),
  swipe between full-screen apps (3 or 4 fingers), Notification Center (two-finger swipe from
  the right edge), Mission Control (3/4 up), App Exposé (3/4 down), show Desktop (spread thumb
  and three fingers), the thumb-and-three-finger pinch (Launchpad before macOS 26; reportedly
  opens Apps in 26 and its toggle was removed from Settings). Three-finger drag lives in
  Accessibility › Pointer Control and moves the 3-finger system swipes to 4 fingers.
- Magic Mouse: secondary click, smart zoom, swipe between pages/full-screen apps, two-finger
  double-tap for Mission Control.
- Keyboard › Keyboard Shortcuts › App Shortcuts: assign a key combo to any menu item title, for
  all apps or one app. Shortcuts app: keyboard shortcuts for shortcuts.
- Window tiling (macOS 15+): Window › Move & Resize menu, Fn-⌃-arrow keys, drag to edges.
- Hot Corners, Mission Control keys, media keys.

**macOS does not**: let you add gestures (any custom 3/4-finger tap or swipe), map extra mouse
buttons (Safari and Finder ignore buttons 4/5), bind a gesture or button to a menu item or
shortcut per app, or open apps/URLs/Shortcuts from a gesture or button.

**Other Slopapp apps:**

- **Tiles** (on hold): keyboard window snapping with a pure layout core. Triggers needs only a
  small set of window actions. Recommendation: build the layout math once as a SlopKit module
  (`WindowLayout`: halves, maximize, center, next display, coordinate flips, min-size readback)
  that Triggers uses now and Tiles reuses if it's ever built. Triggers does not do drag-to-edge
  snapping or snap areas (macOS does).
- **Shorthand** (planned): typed abbreviations → text. Triggers has no key-sequence or typed-word
  triggers and no "insert text" action in v1, so the two never fight over a keyboard event tap.
- **Clips** (clipboard), **Snapper** (screenshots), **Tuck** (menu bar items), **Switchboard**
  (links to browsers): BTT bundles all of these; Triggers bundles none.
- **Dictate** already watches the Fn key and uses Carbon hotkeys; its `Hotkeys.swift` and
  test-mode hooks (`Diagnostics.swift`: throwaway defaults, act-only-into a test target,
  distributed-notification hooks) are the pattern to follow.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else v1.1),
**later**, **skip** (with why).

### Inputs: trackpad and Magic Mouse

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | 3- and 4-finger tap | Dedicated trigger per finger count, all trackpads or built-in only / Magic Trackpad model | **must** | Recognized from raw touch frames (see Platform). Tap = all fingers down within ~120 ms, up within ~300 ms, total movement < 5% of pad. |
| 2 | 3- and 4-finger swipe, 4 directions | Per finger count and direction | **must** | Fires once per swipe at a distance threshold; direction by dominant axis. Warns when macOS uses the same swipe. |
| 3 | 5-finger tap/swipe, whole-hand tap | Yes | later | Rare in real setups. |
| 4 | 1- and 2-finger taps in zones (corners, edges, top/bottom) | Corner taps, side taps, "tap top/bottom" for 3 fingers | later | Some love corner clicks; conflicts with tap to click. |
| 5 | Double taps (2/3/4 fingers) | Yes | later | Adds a wait to every single tap (to rule out a double): a latency cost on the common case. |
| 6 | TipTap (one finger rests, another taps left/right) and TipSwipe | Yes, 1-3 fingers | later | Popular for tab switching in MacRumors thread. Needs good palm rejection. v1.1 candidate. |
| 7 | Clicks with N fingers (physical click), force click, "click with left/right finger harder" | Yes | should (3-finger click) / later (rest) | Physical click arrives as a left mouse-down; to repurpose it the app must swallow left clicks, putting an event tap in the path of every click. Ship only if the latency budget holds (see Platform). |
| 8 | Corner clicks / corner force clicks | Yes | later | |
| 9 | Pinch / spread with thumb, rotate, pinch in/out | Yes | later | Overlaps system pinch/rotate. |
| 10 | Edge swipes and continuous edge slides | Yes (newer) | later | |
| 11 | Circles, triangle swipes, long touch, touch start/release | Yes | later / skip | Niche. |
| 12 | Continuous (fluid) gestures driving a value (volume, brightness) | Yes (6.884) | later | |
| 13 | Drawn gestures (draw a letter) | Separate recorder, 3/4/5-finger drawing | later | Two mentions in surveys. |
| 14 | Modifier keys required during a gesture | Optional per gesture | should | Cheap: read `CGEventSource.flagsState` at recognition time. Doubles the gesture vocabulary. |
| 15 | Cursor-position condition (over title bar, Dock, menu bar, notch) | Per gesture | later | "Over title bar" is Swish's signature; nice later. |
| 16 | Repeat while touching | For clicks/tip-taps/swipes | later | |
| 17 | Trackpad type filter (built-in vs external) | Per gesture | later | v1 treats all trackpads alike, per device state kept separate. |
| 18 | Magic Mouse gestures (taps, swipes, middle tap) | Full family | later | Same touch source; owner's hardware decides. Open question. |
| 19 | Haptic feedback on recognize | Optional | later | |
| 20 | Actions on touch release (down/up pairs, e.g. middle-drag for CAD) | Yes | later | |

### Inputs: mouse, keyboard, other devices

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 21 | Extra mouse buttons (middle, 4, 5, up to 31) with optional modifiers | Single/double/triple/quadruple click per button; long click; per app | **must** (single press) / later (multi-click, long press) | Active event tap on other-mouse down/up only; the original press is swallowed when a binding matches, passed through otherwise. |
| 22 | Left/right click + modifier combos, button chords | Yes | later | Puts the tap on every click. |
| 23 | Scroll with modifier, smooth scrolling, scroll-to-gesture | Yes | skip | Tap on every scroll event is the riskiest latency path; Mos/SteerMouse territory. |
| 24 | Mouse drawings / mouse gestures (hold button and drag) | Yes | later | |
| 25 | Logitech / Razer device integration | Vendor-specific | skip | Generic HID buttons cover most; vendor protocols are a maintenance sink. |
| 26 | Keyboard shortcut trigger (combo + key) | Recorder, key down or key up, per app | **must** | Carbon hotkeys via `KeyboardShortcuts` (already vetted): no keyboard event tap, no Input Monitoring, typing latency untouched by construction. Per-app = register only while that app is frontmost. |
| 27 | Tap vs hold vs long hold on a key, key repeat | Separate action categories | later | |
| 28 | Modifier-only shortcuts, key sequences, typed words | Key Sequence triggers | skip (key sequences, typed words: Shorthand) / later (modifier taps) | Needs a keyboard event tap (Input Monitoring, secure input blind spots). |
| 29 | Hyper key, Caps Lock remap, home-row tap-hold, low-level remaps | Yes | later / maybe never | Karabiner-Elements territory; a keyboard tap in the typing path. Open question. |
| 30 | Left vs right modifier distinction | Option | skip (v1) | Carbon hotkeys can't; comes with a keyboard tap later. |
| 31 | Auto-adapt shortcuts to keyboard layout | Option | should | `KeyboardShortcuts` stores key codes; display uses the current layout. Note on non-US layouts. |
| 32 | Touch Bar widgets and buttons | Large editor, presets | skip | No Mac with a Touch Bar has shipped since 2023. |
| 33 | Stream Deck, macro pads, MIDI, gamepads, Siri/Apple Remote, Leap Motion, generic HID | Yes | skip | Tail of the tail. |
| 34 | Phone remote app, window streaming | BTT Mobile | skip | Network. |
| 35 | Named triggers, timers, time windows, Wi-Fi/app-launch/wake automations | "Other triggers" | later | An automation engine is a different app. |
| 36 | Text-selection popup actions | Floating menu on selection | skip | Needs reading selected text everywhere. |

### Scope and conditions

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 37 | All-apps bindings | "For All Apps" list | **must** | |
| 38 | Per-app bindings; app binding beats all-apps for the same input | App list in the sidebar; drag an app in; app wins | **must** | Frontmost app decides (cached from `NSWorkspace` activation notifications, never queried in the input path). |
| 39 | Turn all-apps bindings off in an app (games, remote desktops, VMs) | Per-app setting with three modes | **must** | One toggle per app: "Use all-apps triggers here". Also a status-menu item for the front app. |
| 40 | Per-binding "do nothing here" (pass the input through in one app) | "Use Apple default or do nothing" action | should | An app binding with action "Pass through" overrides the global one. |
| 41 | App groups (e.g. all browsers) | Conditional activation groups | should | A built-in "Browsers" group is very cheap and covers the tab/back/forward use. Custom groups later. |
| 42 | Advanced conditions (variables, finger count, window title, Wi-Fi, mouse position, colour under cursor) | Rule editor per trigger | later / skip | Conditions are where BTT's complexity lives. |
| 43 | App under the pointer instead of frontmost | Not documented | later | Matters for mouse; frontmost is predictable. |

### Actions

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 44 | Press a keyboard shortcut (in the front app) | Records a combo, posts it like a real keyboard; option to adapt to layout | **must** | Posted as HID-level key events with explicit flags; released modifiers the user is still holding are accounted for. Recursion guard (don't re-trigger our own hotkey). |
| 45 | Send a shortcut to a specific app (not frontmost) | Tries direct, else briefly activates the app | later | |
| 46 | Mouse clicks: middle click at pointer (and right click, ⌘-click) | "More mouse buttons" actions | **must** (middle) / should (right, ⌘-click) | Middle click is the single most-wanted action. |
| 47 | Choose a menu item in the front app | Action that triggers a menu bar item by path | **must** | Accessibility walk of the front app's menu bar, press by title path. Picker shows the chosen app's menus when it's running. |
| 48 | Open an app, URL or file | Launch/URL actions | **must** | `NSWorkspace`. |
| 49 | Run a Shortcut | Shortcuts integration | **must** | `shortcuts run` (or the Shortcuts URL scheme). Covers most scripting needs safely. |
| 50 | Window actions: left/right half, maximize, center, minimize, next display | Big built-in set plus snap areas | **must** (this small set) / later (thirds, quarters, custom) | Shared `WindowLayout` core in SlopKit (Tiles-ready). Top/bottom halves are cheap: include. |
| 51 | System actions: Mission Control, App Exposé, show Desktop, Spaces left/right, Notification Center | Predefined actions | should | Mission Control/App Exposé via `com.apple.exposelauncher`; Spaces via posting the user's ⌃←/→. Verify each on macOS 27. |
| 52 | Media and volume/brightness keys, mute | Predefined actions | should | System-defined media key events. |
| 53 | Lock screen, sleep display, sleep | Predefined | later | |
| 54 | Close/new tab, back/forward, reopen tab | Usually via shortcuts | should (as presets of #44) | Shown as named suggestions ("Close tab = ⌘W"), not separate engines. |
| 55 | Action sequences, delays, control flow | Multiple actions per trigger, if/else, wait | later | v1: one action per binding. Real setups are overwhelmingly one action. |
| 56 | Shell / AppleScript / JavaScript actions | Yes | later (open question) | Arbitrary code; Shortcuts already offers "Run Shell Script". |
| 57 | Insert/type/paste text | Yes | skip | Shorthand. |
| 58 | Clipboard manager, screenshot tool, launcher, menu bar item hiding, floating menus, desktop widgets, HUD widgets, presenter mode, AI assistants, clean URLs, context menus | Built-in tools | skip | Other Slopapp apps or out of scope; AI needs network. |
| 59 | Move mouse, drag mouse, mouse position memory | Yes | skip | Rare; risky. |

### App, configuration and feedback

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 60 | Editor window: sidebar of apps, list of bindings, inspector | Four-pane window: apps, triggers, actions, config sidebar (undockable) | **must** | Library archetype, two panes plus a sheet: sidebar (All Apps, Browsers, apps), table of bindings (input → action, on/off). Edit in a sheet, not a permanent inspector. |
| 61 | Record a trigger by performing it | Mostly picked from a popover list; shortcuts recorded | **must** | Our signature improvement: "Do it now" area listens for the next gesture, button or combo and names it, with a picker as the fallback. |
| 62 | Conflict warnings | Some warnings for 3-finger tap/swipe; forum full of "my gesture also triggers Mission Control" | **must** | Read (never write) the macOS trackpad prefs and show "macOS also uses this for Mission Control" with a button to the Trackpad pane. Also warn on duplicate bindings and on shortcuts already used by macOS/menu items. |
| 63 | Enable/disable a binding; pause everything | Per-trigger toggle; "temporarily disable" | **must** | Status menu: Pause Triggers. |
| 64 | "Recently used" log of what fired | Section in the editor | should | In-memory list of the last ~20 fires (input, app, action, time). No content. Clicking one opens the binding: the fix for "what just happened". |
| 65 | HUD when a trigger fires | Optional per trigger | should (global option, off) | SlopKit `HUD`. Helps while learning. |
| 66 | Starter suggestions | Presets, community presets, preset marketplace | should | Empty state offers a few one-click starters (3-finger tap → middle click; buttons 4/5 → back/forward in Browsers and Finder; 4-finger swipe left/right → halves). Nothing is on until clicked. |
| 67 | Import / export | Presets as files; iCloud sync | should (export/import JSON) / skip (sync) | Plain JSON, versioned schema. No sync (network). |
| 68 | Trash for deleted bindings, undo | "Trash" entry in app list | should (undo) | `UndoManager` for delete/edit; no separate trash list. |
| 69 | Search triggers and settings | Search field | should | `.searchable` over binding names/actions. |
| 70 | Scripting API: AppleScript, URL scheme, webserver, CLI, JS, OSC | All of them | later (App Intents: pause/resume, run a binding) / skip (webserver, OSC) | Webserver = network. |
| 71 | Diagnostics export | Help › export debug info | should | Local file with versions, permission state, event tap stats, binding count. No content. |
| 72 | Licence, trial, Setapp, Mobile unlock | Paid | skip | Free and open source. |

### Must-haves, counted

Inputs: 1 taps, 2 swipes, 21 mouse buttons, 26 keyboard combos. Scope: 37/38 all-apps and
per-app, 39 turn off in an app. Actions: 44 press shortcut, 46 middle click, 47 menu item,
48 open, 49 run Shortcut, 50 basic window moves. App: 60 editor, 61 record by doing, 62
conflict warnings, 63 enable/pause. Plus the Accessibility gate and the "trackpad gestures
unavailable" degraded state. **Twelve feature must-haves plus four app-shell must-haves.**
Everything else waits.

## Key flows

### Flow 1: bind a gesture (the main job)

1. Status menu › Edit Triggers… opens the editor (the only window besides Settings). Sidebar:
   All Apps, Browsers, then each app with its own bindings; `+` at the bottom adds an app
   (running apps first, then Choose…).
2. With All Apps selected, ⌘N (or the toolbar `+`) opens the New Trigger sheet.
3. Top of the sheet: a large "Do it now" area, listening. The person taps three fingers; the
   area names it ("Three-finger tap") within a frame. Pressing a mouse button or a key combo
   works the same way. A popup next to it lists every supported input for people who'd rather
   pick (and for VoiceOver). Esc while listening cancels listening, not the sheet.
4. If macOS uses the same input (e.g. three-finger swipe up = Mission Control), an inline note
   says so with "Open Trackpad Settings"; if another binding in the same scope uses it, the
   note names it and offers to edit that one instead.
5. Below: Action, a grouped list (Keyboard shortcut, Click, Menu item, Open, Shortcut,
   Window, System). Picking one shows its one or two fields (record a combo; choose a menu path;
   choose an app/URL; choose a Shortcut; choose a window move).
6. Add (Return). The binding is live immediately and appears in the table as
   "input → action" with an on/off switch. No save step.
7. Using it: the gesture runs the action. Optional HUD (off by default) names what fired.

### Flow 2: first run and permissions

1. Launch: status item appears; the editor opens once (first launch only) with an empty state:
   a symbol, one line about what Triggers does, "Add Trigger", and three starter suggestions
   (each a one-click add, nothing enabled by default).
2. No permission is asked at launch. Gesture *detection* needs none (to verify on macOS 27,
   see Platform); most *actions* (posting keys and clicks, menu items, window moves, swallowing
   mouse buttons) need Accessibility.
3. The first time an enabled binding needs Accessibility, a slim info bar appears at the top
   of the editor: one sentence ("Triggers needs Accessibility access to press keys, click and
   move windows for you"), Open System Settings (exact pane), live re-check. The status menu
   shows the same as a fix-it item. Bindings that need it show a small warning badge.
4. If the trackpad source can't load (private framework missing or changed), gesture inputs
   show as unavailable with one line of explanation; mouse and keyboard bindings keep working.
5. If the person declines Accessibility: bindings that only open apps/URLs/Shortcuts still
   work; others stay badged. No nagging, no repeated prompts.

### Flow 3: per-app binding (Safari back with a mouse button)

1. Sidebar `+` › Safari (or use the built-in Browsers group).
2. ⌘N, press the mouse's back button in the "Do it now" area (it's swallowed while recording).
3. Action: Keyboard shortcut ⌘[. Add.
4. In Safari, the back button goes back. In every other app the button behaves as before
   (passed through untouched).

### Flow 4: get out of the way

1. Status menu › Pause Triggers: everything stops (event tap removed, hotkeys unregistered,
   touch source stopped). The status icon shows the paused state. Same item resumes.
2. Status menu › "Turn Off in <front app>" (e.g. a game or a remote desktop): all-apps bindings
   stop in that app; its own bindings (if any) still work.

### Flow 5: "what just happened?"

1. Something fired unexpectedly. Status menu › Recent shows the last few fires
   ("Three-finger tap → Middle Click · Safari · 2 s ago").
2. Clicking one opens the editor at that binding.

## Settings inventory

BTT's own settings are split into standard and advanced with a search field; the docs don't
enumerate them. What it exposes that matters to us: gesture recognition sensitivity, long-press
durations (1.5 s default for very long hold), key repeat rate/delay, HUD overlay, window
snapping on/off, menu bar icon, launch at login, sync.

Ours:

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Launch at login | off | toggle | must |
| Show in menu bar | on | toggle (relaunch brings it back) | must |
| Show a confirmation when a trigger fires | off | toggle (SlopKit `HUD`) | should |
| Tap sensitivity | Standard | Relaxed / Standard / Strict (maps to time and movement limits) | should |
| Swipe distance | Standard | Short / Standard / Long | should |
| Ignore gestures while typing | on | toggle (suppress taps for ~0.3 s after a key press; only if it can be done without a keyboard tap: see open question) | later |
| Use all-apps triggers in <app> | on | per app, in the editor sidebar's context menu | must |
| Pause Triggers | off | status menu only | must |
| Shortcuts tab: Pause/Resume Triggers, Open Editor | unset | recorders | should |
| Advanced: export diagnostics | — | button | should |

Settings tabs: General, Shortcuts (only if the two global shortcuts ship), Advanced, About.
Bindings themselves live in the editor, not Settings.

## Menus and shortcuts

**BTT** (from docs): menu bar icon opens a menu with Configuration, presets, a way to disable
it, and Quit; Settings is ⌘, in the configuration window. Not verified first-hand (not installed).

**Ours, status menu** (`.menu` style):

- Status line: "14 triggers on" / "Paused" / "Needs Accessibility access" (fix-it).
- Edit Triggers… (opens the editor)
- Pause Triggers (toggle; shortcut shown if the person set one)
- Turn Off in <Front App> (toggle, title follows the app that was active)
- Recent › (last ~10 fires; click opens the binding)
- `MenuFooter` (Settings…, About, Quit ⌘Q)

**Editor window main menu** (app becomes `.regular` while the editor is open, as Snapper's
`AppPresence` does): File › New Trigger ⌘N, Add App… ⇧⌘N, Duplicate ⌘D, Import…, Export…,
Close ⌘W. Edit › Undo/Redo, Delete ⌫, Select All, Find ⌘F. Trigger › Turn On/Off ⌘T, Edit
Trigger… ↩, Run Action Now ⌘R (runs the action once, as a test). Window, Help.

No global shortcuts by default (any default could collide with someone's own bindings).

## Permissions and system integration

| Need | API | Permission | When asked | If refused |
|---|---|---|---|---|
| Read trackpad touches | MultitouchSupport (private), see Platform | Reportedly none (verify on macOS 27) | Never | — |
| Swallow/see extra mouse buttons | `CGEvent.tapCreate`, `.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`, mask = other-mouse down/up only | Accessibility | First enabled mouse binding | Mouse bindings badged; buttons pass through |
| Keyboard combo triggers | Carbon `RegisterEventHotKey` via `KeyboardShortcuts` | None | — | — |
| Press keys, click | `CGEvent.post` | Accessibility | First binding using it | Badged |
| Menu items, window moves | `AXUIElement` | Accessibility | First binding using it | Badged |
| Open apps/URLs/files | `NSWorkspace` | None | — | — |
| Run a Shortcut | `/usr/bin/shortcuts run` or URL scheme | None (Shortcuts may ask per shortcut) | — | Error HUD |
| Mission Control etc. | `open -b com.apple.exposelauncher`, posted keys | Accessibility for posted keys | — | — |
| Read macOS gesture settings | `CFPreferencesCopyAppValue` on the trackpad domains, read-only | None | — | Conflict notes omitted |
| Launch at login | `SMAppService` (SlopKit) | None | — | — |
| Input Monitoring | Not needed in v1 (no keyboard event tap) | — | — | — |

No App Sandbox (event taps and AX need it off; Slopapp ships direct). No network.
App Intents (later): Pause Triggers, Resume Triggers, Run Binding.

## Platform notes (the hard part)

### Event taps: what we tap and how

- **Tap as little as possible.** The event mask is the main performance and risk lever. v1's
  only active tap watches `otherMouseDown`/`otherMouseUp` (buttons 2 and up). No mouse-moved,
  scroll, left/right click or keyboard events. The tap is installed only while at least one
  enabled mouse binding exists and Triggers isn't paused, and removed otherwise.
- **Never on the main thread.** The tap runs on a dedicated thread with its own run loop, so a
  busy SwiftUI frame can never stall the person's input. The callback reads an immutable
  snapshot of the bindings (a dictionary keyed by app + button + modifiers, swapped atomically
  when bindings or the front app change), decides swallow or pass in constant time, and hands
  the action to the main actor asynchronously. No allocation, no locks the main thread holds,
  no Accessibility or workspace calls inside the callback.
- **Swallow both halves.** If a button-down is swallowed, its matching up (and any drag) is
  swallowed too, even if the front app changed in between; otherwise apps see stray ups.
- **Timeouts.** On `tapDisabledByTimeout` re-enable once and log; repeated timeouts within a
  minute mean something is wrong: remove the tap and show a fix-it in the status menu rather
  than fight the system. `tapDisabledByUserInput` (secure event input, see below) is
  respected.
- **Revoking Accessibility can freeze input.** An Apple developer forums report (2026,
  FB24619068) shows system-wide input hanging when Accessibility is revoked from an app with
  an active `.defaultTap`; BTT's 6.588 release notes fixed the same class of freeze. Mitigation:
  watch for trust changes (`com.apple.accessibility.api` distributed notification, plus a
  slow `AXIsProcessTrusted()` check only while a tap is installed) and invalidate the tap the
  moment trust is gone; keep the tap absent when there are no mouse bindings. Test this
  deliberately (edge cases).

### Trackpad gestures: detection

- **There is no public API for global multi-finger taps or swipes.** Public options: `NSEvent`
  gesture events (`swipe`, `magnify`, `rotate`, `gesture`) only exist when macOS itself
  recognized a gesture and only go to the app under the pointer; global monitors can see them
  but not change them; taps never produce events at all; and the Dock consumes its own gestures
  (Mission Control, Spaces) before any app sees them. Reading `allTouches()` from a tapped
  gesture event is undocumented and reportedly returns nothing in many cases.
- **What everyone uses**: `MultitouchSupport.framework` (private): enumerate devices
  (`MTDeviceCreateList`), register a contact-frame callback, start each device. Each frame
  carries per-finger id, normalized position, velocity, size, pressure, angle and state. BTT,
  Jitouch, MiddleClick (GPL), Multitouch, Hammerspoon modules and the MIT-licensed
  OpenMultitouchSupport Swift wrapper all go this way. Reportedly needs no TCC permission and
  the App Sandbox off. Symbols have been stable since 10.5.
- **Risk and containment**:
  - Private: could break on any macOS release (BTT's notes show gesture fixes on most macOS
    majors). Load it with `dlopen`/`dlsym` at runtime, never link it, so a missing or changed
    framework degrades to "gestures unavailable" instead of a crash at launch. Validate frames
    (positions in 0…1, sane finger counts) and switch off on garbage.
  - Behind a `TouchFrameSource` protocol; the recognizer only ever sees our own `TouchFrame`
    struct, so a future replacement (a public API, or a different private path) touches one file.
  - Write our own thin binding (~150 lines) rather than depend on a package; OpenMultitouchSupport
    (MIT) is a good reference. If adopted instead, it goes through the dependency rules.
  - Not App Store-safe; irrelevant (we ship direct).
- **Multiple devices**: built-in and Magic Trackpad deliver frames separately; keep recognizer
  state per device (mixing them "sees six fingers where there are three"). Re-enumerate on
  device add/remove and **after wake** (a known failure mode of these tools is "stops working
  after sleep"; BTT 6.635 fixed gestures interrupted by wake notifications).
- **Recognizer**: a pure state machine over frames, in `TriggersCore`, tested with synthetic
  and recorded frame sequences. Taps: finger count reached quickly, short duration, small
  movement, all fingers lifted (MiddleClick's defaults are 300 ms and 5% movement). Swipes:
  N fingers moving together past a distance threshold, dominant axis. Palm rejection: ignore
  very large contacts and contacts resting at the pad's edges; ignore a "3-finger tap" that is
  really one tap-to-click with two resting fingers.
- **New 2026 MacBook Pros with touch displays**: BTT 6.1110 separates screen touches from
  trackpad touches. Triggers must only ever read trackpad devices.

### Conflicts with macOS's own gestures

- We **observe** touches; we can't stop macOS from also acting on them. A 3-finger swipe up
  bound in Triggers will also open Mission Control if macOS has it on. BTT's forum is full of
  exactly this; its answer is "turn the system gesture off". We do better by telling people
  *before* it happens: read the trackpad preference domains (built-in and Bluetooth trackpad)
  for three-finger drag, three-finger tap (Look Up), 3/4-finger horizontal and vertical swipes,
  pinch and spread, and show "macOS also uses this" in the editor with a button to the right
  System Settings pane. Read-only: never write Apple's preferences.
- Three-finger drag on: 3-finger swipes and taps are effectively unusable; say so and suggest
  4 fingers.
- Two-finger anything collides with scrolling and secondary click: not offered in v1.
- Swallowing system gestures with an event tap (dropping Dock-control events) is possible in
  principle but fragile and surprising: skip.

### Secure input

- When any app enables secure event input (password fields, some terminals; often leaked by
  buggy apps), macOS stops delivering keyboard events to every event tap. v1 has **no keyboard
  event tap**, so this doesn't break typing-related features. Carbon hotkeys are a separate
  path and are reported to keep firing (verify in the spike with a focused password field; if
  not, show "Paused while a password field is active" rather than failing silently).
- Mouse and trackpad paths are unaffected by secure input.
- If a keyboard tap is ever added (hyper key, modifier taps), detect `IsSecureEventInputEnabled()`
  and name the holder app in the status menu (the BTT and Cursor forum threads show how
  confusing silent failure is).

### Performance budgets and how to measure

House budgets (design system §8) apply: launch < 300 ms, idle CPU < 0.2%, footprint < 50 MB.
Input-path budgets on top, because an input tool that adds lag is broken (BTT's forum has
recent "scrolling stutters / drag-and-drop choppy while BTT runs" threads):

| Path | Budget | How we measure |
|---|---|---|
| Event tap callback (other-mouse only) | p99 ≤ 50 µs, max ≤ 1 ms, never a timeout | `CGGetEventTapList` reports each tap's `minUsecLatency`/`avgUsecLatency`/`maxUsecLatency` and its event mask: a `scripts/perf.sh Triggers` extension reads ours and fails over budget or if the mask contains more than other-mouse events. Plus `os_signpost` intervals around the callback. |
| Events we don't handle | zero work: they never reach us (mask) | Same tap list: mask check. |
| Touch frame → recognizer | p99 ≤ 20 µs per frame on Apple silicon, no allocation | Unit benchmark replaying 100k synthetic frames through the recognizer (loose ×10 assertion in tests, tight number logged). |
| CPU while touching (two-finger scrolling for 10 s) | ≤ 1% of one core above baseline | `perf.sh` style sampling of our process during a recorded-frame replay (`TRIGGERS_REPLAY`), and by hand on real scrolling. |
| CPU when not touching, no buttons pressed | 0 wakeups from the input path | Frames only arrive while fingers touch; tap only wakes on extra buttons. `perf.sh` idle CPU. |
| Input recognized → action dispatched | ≤ 10 ms | Signpost from recognition to dispatch. |
| Key shortcut posted / click posted | ≤ 15 ms after recognition | Signpost; test target window records arrival time. |
| Window move | ≤ 50 ms (Tiles' budget) | Signpost around the AX calls. |
| Typing latency | unchanged by construction (no keyboard tap) | Mask check above. |

A local perf log (`TRIGGERS_PERF_LOG=path`) writes only numbers (histograms), never what was
pressed or where.

## Testing design: never inject into the owner's apps

Hard constraint: tests and walkthroughs must never post events into the system's input stream
where they could reach the owner's real apps. Design for it from day one:

1. **Everything behind protocols** (`TriggersCore`, like Awake's `PowerAssertion`/`Scheduler`):
   - Input: `TouchFrameSource`, `MouseButtonSource` (the tap), `HotkeySource`,
     `FrontmostAppSource`, `SystemGestureSettings` (macOS prefs reader),
     `AccessibilityTrust`.
   - Output: `ActionPerformer` with `KeyPoster`, `Clicker`, `MenuInvoker`, `WindowMover`,
     `Opener`, `ShortcutRunner`.
   - Pure pieces: `GestureRecognizer` (frames → gestures), `Router` (input + front app +
     bindings snapshot → swallow/pass + action), `ConflictChecker`, binding store (JSON codec,
     schema migration).
   - Fakes: scripted sources replaying timelines; a recording performer that captures actions.
     Unit tests never create a real tap, never post, never touch AX.
2. **The real tap callback is testable without posting.** The callback is a plain function
   `decide(_ event: CGEvent) -> Decision` around the router. Tests *construct* `CGEvent`s
   (`CGEvent(mouseEventSource:mouseType:...)`, set button number and flags) and call it
   directly. Nothing is posted.
3. **Test mode** (Dictate's pattern, env vars read by `Diagnostics`):
   - `TRIGGERS_DATA_DIR`: throwaway bindings file and defaults suite.
   - `TRIGGERS_NO_INPUT=1`: no MultitouchSupport, no tap, no hotkeys; only replay sources.
   - `TRIGGERS_REPLAY=/path/timeline.json`: feeds touch frames, button presses and hotkeys
     (our own structs) into the real recognizer and router in the running app. In-process
     only; nothing reaches the system event stream.
   - `TRIGGERS_ACT_ONLY_IN=<bundle id>`: performers act only when that app is frontmost and
     is the test target; anything else is skipped and logged. Key and click posts in test mode
     use `CGEvent.postToPid(testTargetPID)` instead of the global stream; menu and window
     actions resolve only the test target's AX element.
   - `TRIGGERS_FAKE_APPS=1`: the app picker and sidebar list fake apps, and the Shortcut
     picker lists fake shortcuts, so screenshots never show the owner's installed apps or
     Shortcut names (personal content).
   - Open-URL/app and Run-Shortcut performers are fakes in test mode (they'd otherwise open the
     owner's browser or run the owner's shortcuts); they log what they would have done.
   - `TRIGGERS_TEST_HOOKS=1`: distributed notifications to replay a timeline, open the editor
     or a Settings tab, quiet windows (Dictate's `TEST_QUIET`).
4. **The throwaway test window**: a tiny target app (built from a scratch Swift file into
   `/tmp`, as Dictate's walkthrough did) with a menu `Test › Ping` (counter), a text area that
   logs key combos and mouse buttons it receives with arrival times, and a window that reports
   its frame. Walkthroughs bind inputs to actions scoped to this app only, replay inputs, and
   read results from its log and `scripts/drive tree`.
5. **Owner idle check**: as Dictate's walkthrough did, anything that needs the test target in
   front waits until the owner has been idle ≥ 60 s and aborts if another app comes forward.
6. **What only a human can verify**: real fingers on a real trackpad and real mouse buttons.
   The editor's "Do it now" area doubles as a recognize-only test pad (nothing is performed
   while recording), so the owner can check recognition on their hardware without anything
   happening in their apps. These items go in the v1 checklist as "owner hand test".
7. **Guard rail in code review**: `CGEvent.post(tap:)` appears in exactly one production
   type, which test mode replaces; `scripts/drive key --global` and `--allow-mouse` are never
   used for Triggers.

## UX patterns worth adopting

- **Per-app scope as the primary organizer** (BTT's app sidebar): people think "in Safari, this
  gesture means back", so the sidebar is apps, not trigger types.
- **App beats all-apps for the same input**, with an explicit "use all-apps triggers here" off
  switch for games and remote desktops.
- **Bindings are live the moment they're added**: no Save, no restart.
- **A "last fired" history** to debug surprises.
- **A pass-through action** ("do nothing here, let macOS have it") instead of complex
  condition rules.
- **Optional HUD while learning**, off once you know your gestures.
- **Fire on gesture completion, not a guessed timeout**: taps fire on lift; avoiding double-tap
  variants in v1 keeps single taps instant.

## What we won't copy, and what we'll do better

- Not copying: name, icon, the four-pane editor and its visuals, Touch Bar/Notch Bar styling,
  preset marketplace, licence/trial/mobile upsell, wording, any of the 18 trigger families
  beyond the four we need.
- **Doing better:**
  - **Record by doing.** Perform the gesture or press the button to create a binding,
    instead of hunting through a list of 100+ gesture names.
  - **Conflicts explained up front**, from the actual macOS settings, instead of forum threads
    after the fact.
  - **A small, legible surface**: four input kinds, a dozen actions, one sheet. The complexity
    complaint is the main criticism in recent reviews.
  - **Zero cost on paths we don't use**: minimal event mask, no keyboard tap, nothing on
    scroll or pointer moves. Recent BTT threads report scroll stutter and choppy drags while it
    runs; Triggers should be measurably invisible (budgets above, checked by tooling).
  - **Fails safe**: tap torn down on permission loss; gestures degrade cleanly if the private
    framework changes; pause from the status menu at any time.
  - **Private and offline**: no account, no sync, no webserver, no AI, no network.
  - **Doesn't swallow other apps' jobs** (clipboard, snippets, screenshots, menu bar).

## Edge cases

- **Multiple trackpads**: built-in + Magic Trackpad at once; one unplugged mid-gesture;
  Bluetooth reconnect; external trackpad on a desktop Mac with no built-in.
- **Sleep/wake, lid close, fast user switching, screen lock**: re-enumerate touch devices and
  check the tap is enabled after wake; nothing fires while locked; no stuck "button down" state.
- **Accessibility revoked while running**: tap invalidated immediately, no input freeze
  (test by hand with the test target, owner present); re-granted: everything comes back without
  restart.
- **Secure event input on** (password field focused): keyboard combos still work or the status
  line says why not; mouse and gestures unaffected.
- **Tap timeouts** under heavy load (compile + video call): tap re-enabled once, then fix-it.
- **System gesture overlap** (Mission Control, Look Up three-finger tap, three-finger drag,
  App Exposé): warned, not fought. Settings changed while Triggers runs: warnings update.
- **Palm and resting thumb**: typing with palms on the pad must not produce taps; a tap-to-click
  with two resting fingers is not a three-finger tap.
- **Swipe vs scroll**: two-finger scroll that gains a third finger mid-way; momentum scrolling.
- **Front app changes mid-gesture or between button down and up**: the down's decision governs
  the up.
- **Recursion**: an action that presses a key combo bound as a trigger must not loop.
- **Held modifiers**: posting ⌘[ while the person still holds ⌥ from a modifier+button trigger.
- **Menu item actions**: app not running, menu titles localized differently, items disabled,
  menus that are built lazily, Electron/Java apps with odd menus. Show a HUD on failure
  ("Couldn't find File › Export in Pages").
- **Window actions**: full-screen windows, fixed-size windows, minimum sizes, multiple displays
  with different scales, Stage Manager, no focused window (do nothing quietly). Shared with
  Tiles' list.
- **Shortcut not found** (renamed/deleted Shortcut): HUD with what to do.
- **Keyboard layouts**: AZERTY/Dvorak display of recorded combos; combos that use keys absent
  on the current layout.
- **Conflicting hotkeys**: registration fails because another app owns the combo: show it in
  the editor, not silently.
- **Many bindings** (hundreds, imported): editor stays fast; router lookup stays O(1).
- **Empty state**, all bindings off, everything paused.
- **Games / remote desktops / VMs**: all-apps off for that app works; full-screen games with
  their own mouse handling.
- **Touch display MacBooks**: never treat screen touches as trackpad touches.
- **Accessibility of the app itself**: every control labeled; the "Do it now" area has a
  picker alternative so VoiceOver and Switch Control users can create every binding; Reduce
  Motion respected in the HUD.
- **Light/dark, accent colour, non-English UI text** in the editor and HUD.

## Our v1 scope

- [ ] Status menu: status line, Edit Triggers…, Pause Triggers, Turn Off in <front app>,
      Recent, `MenuFooter`. Paused state visible on the icon.
- [ ] Editor window (library archetype): sidebar All Apps / Browsers / apps (+ add, remove,
      "Use all-apps triggers here"), bindings table with on/off, search, undo, empty state with
      starter suggestions.
- [ ] New/Edit Trigger sheet with "Do it now" recording for gestures, mouse buttons and key
      combos, and a picker fallback; recording never performs actions.
- [ ] Trackpad: 3- and 4-finger tap; 3- and 4-finger swipe left/right/up/down; optional
      modifier keys. Per-device state; survives sleep/wake and device changes.
- [ ] Mouse: extra buttons (middle, 4, 5, …) with optional modifiers; original press swallowed
      only when a binding matches.
- [ ] Keyboard: key combos as triggers (Carbon hotkeys), per app by registering only while
      that app is in front.
- [ ] Scope: app binding beats all-apps; all-apps off per app. (Should, if cheap: Browsers
      group, pass-through action.)
- [ ] Actions: press keyboard shortcut; middle click (right click and ⌘-click if cheap); choose
      menu item; open app/URL/file; run Shortcut; window left/right/top/bottom half, maximize,
      center, minimize, next display.
- [ ] Conflict notes from the real macOS trackpad settings and from duplicate bindings, with a
      button to the right System Settings pane.
- [ ] Accessibility info bar and fix-it item, live re-check, per-binding badges; tap torn down
      on revocation.
- [ ] Gestures-unavailable state if the trackpad source fails to load; mouse and keys keep
      working.
- [ ] Settings: General (launch at login, show in menu bar, confirmation HUD), About.
- [ ] `TriggersCore` tests: recognizer (taps, swipes, palms, resting fingers, multi-device),
      router (precedence, pass-through, down/up pairing, recursion), conflict checker, JSON
      store; tap `decide` tested with constructed `CGEvent`s.
- [ ] Test mode (env vars above), replay timelines, throwaway test target; walkthrough drives
      the editor and replays inputs, actions land only in the test target.
- [ ] Performance: tap mask and latency checked via `CGGetEventTapList`; recognizer benchmark;
      idle CPU/memory within house budgets.
- [ ] Owner hand test (real hardware): three-finger tap → middle click in a browser; four-finger
      swipes → window halves; mouse back/forward in Safari; a key combo opening an app; pause
      and resume; revoke and re-grant Accessibility.

## Open questions

Each with a recommendation; the owner decides before step 3.

1. **Private MultitouchSupport.** It's the only way to get custom trackpad gestures, every tool
   in this space uses it, and it could break on a future macOS. OK to use it, loaded at runtime
   behind a protocol with a clean "gestures unavailable" fallback? *Recommend yes.*
2. **Window actions in Triggers while Tiles is on hold.** Build a small shared `WindowLayout`
   in SlopKit and offer only halves/maximize/center/minimize/next display in Triggers?
   *Recommend yes; Tiles stays on hold and can reuse it.*
3. **Script actions** (shell, AppleScript). Leave them out of v1 and point people to "Run
   Shortcut" (Shortcuts can run shell scripts)? *Recommend leaving them out.*
4. **Keyboard event tap features** (hyper key, Caps Lock remap, modifier-only taps, "ignore
   taps while typing"). They need Input Monitoring and sit in the typing path. Out of v1, and
   possibly never (Karabiner does it well)? *Recommend out of v1.*
5. **Three-finger physical click** (separate from tap). Needs a tap on every left click. v1.1
   only if measured latency holds? *Recommend v1.1.*
6. **Magic Mouse gestures.** Does the owner use a Magic Mouse? If yes, its taps/swipes are a
   cheap v1.1 on the same touch source.
7. **Defaults.** Ship with nothing enabled and one-click starter suggestions (3-finger tap →
   middle click, mouse back/forward in Browsers and Finder, 4-finger swipes → halves)?
   *Recommend suggestions, nothing on by default.*
8. **Size.** The roadmap says L. With this cut it's closer to M-L (the editor and the
   recognizer are the bulk). Fine to keep it after Gauge and Tuck as planned?

## Sources

- [BetterTouchTool website](https://folivora.ai/) and [pricing](https://folivora.ai/buy)
- [BTT release notes](https://updates.folivora.ai/bettertouchtool_release_notes.html)
- BTT docs: [installation and first run](https://docs.folivora.ai/docs/getting-started/installation),
  [configuration overview](https://docs.folivora.ai/docs/configuration/basic-overview/),
  [creating a trigger](https://docs.folivora.ai/docs/configuration/new-trigger),
  [global vs app-specific](https://docs.folivora.ai/docs/configuration/global-vs-app-specific),
  [trackpad and Magic Mouse](https://docs.folivora.ai/docs/trackpad-mouse/magic-mouse-trackpad),
  [keyboard shortcuts](https://docs.folivora.ai/docs/keyboard-shortcuts/overview),
  [normal mouse](https://docs.folivora.ai/docs/normal-mouse/overview),
  [actions](https://docs.folivora.ai/docs/actions/overview),
  [sending shortcuts](https://docs.folivora.ai/docs/actions/sending-shortcuts),
  [conditions](https://docs.folivora.ai/docs/actions/conditions),
  [window snapping](https://docs.folivora.ai/docs/window-snapping/overview),
  [trigger JSON reference (full gesture list)](https://docs.folivora.ai/docs/json/trigger-definitions/)
- BTT forum: [4-finger swipe triggering macOS 3-finger swipe](https://community.folivora.ai/t/4-finger-swipe-up-triggering-3-finger-swipe-up-of-macos/41928),
  [3-finger swipes also triggering 2-finger scrolling](https://community.folivora.ai/t/btt-3-finger-swipes-simultaniously-trigger-macos-2-finger-swipes/3156),
  [scroll stutter while BTT runs](https://community.folivora.ai/t/noticeable-stutter-when-scrolling/45567),
  [choppy drag and drop while BTT runs](https://community.folivora.ai/t/macos-drag-and-drop-slow-and-choppy-while-btt-runs-normal-when-it-does-not/46326),
  [Launchpad gesture on macOS 26](https://community.folivora.ai/t/launchpad-shortcut-with-trackpad-how-can-i-customise-it-or-disable-it-macos-26/45525)
- Usage surveys: [Automators: how do you use BTT](https://talk.automators.fm/t/how-do-you-use-bettertouchtool/1104),
  [MPU: show us your BTT tricks](https://talk.macpowerusers.com/t/show-us-your-bettertouchtool-tricks/16563),
  [MPU: BTT without a Touch Bar](https://talk.macpowerusers.com/t/better-touch-tool-without-a-touch-bar/24649),
  [MacRumors: BTT gestures](https://forums.macrumors.com/threads/bettertouchtool-gestures.1693622/),
  [MacStories: window management with BTT](https://www.macstories.net/tutorials/three-ways-to-use-bettertouchtool-to-enhance-window-management-with-a-trackpad/),
  [Setapp reviews](https://setapp.com/apps/bettertouchtool/customer-reviews),
  [dev.to: BTT as a window manager](https://dev.to/freekmurze/using-bettertouchtool-as-a-window-manager-1klo)
- Single-purpose alternatives: [MiddleClick](https://github.com/artginzburg/MiddleClick),
  [Multitouch](https://multitouch.app/), [11 trackpad apps (dev.to)](https://dev.to/ris58h/11-macos-apps-to-increase-productivity-with-trackpad-1co0)
- Platform: [OpenMultitouchSupport (MIT)](https://github.com/Kyome22/OpenMultitouchSupport),
  [go-macos/multitouch notes](https://pkg.go.dev/github.com/go-macos/multitouch),
  [Hammerspoon multitouch module](https://github.com/catokolas/HS_ModulesContrib-multitouch),
  [Apple: Handling trackpad events](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html),
  [Apple TN2150: secure event input](https://developer.apple.com/library/mac/technotes/tn2150/_index.html),
  [Apple forums: input freezes when Accessibility is revoked with an active tap](https://developer.apple.com/forums/thread/844416),
  [tapDisabledByTimeout](https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbytimeout),
  [Cocoa-dev: taps disabled when slow](https://lists.apple.com/archives/Cocoa-dev/2010/Sep/msg00890.html),
  [Cursor forum: leaked secure input disables all taps](https://forum.cursor.com/t/cursor-leaks-secure-event-input-breaks-all-system-wide-input-taps-until-quit-or-screen-lock/167585),
  [Hammerspoon eventtap docs](https://commandpost.fcp.cafe/api-references/hammerspoon/hs.eventtap.md),
  [CopyCat PR: moving off CGEventTap to Carbon hotkeys](https://github.com/andyhtran/CopyCat/pull/8)
- macOS: [MacRumors: Safari ignores mouse back/forward](https://forums.macrumors.com/threads/mouse-back-forward-buttons-do-not-work-in-safari.2448011/),
  [Macworld: trackpad gestures](https://www.macworld.com/article/1439575/macos-trackpad-gestures-you-need-to-know.html)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

## Owner decisions (2026-11-07)

- **Private MultitouchSupport: yes**, loaded at runtime behind a protocol; if it breaks, gestures switch
  off and mouse buttons and key combos keep working.
- **Starts empty**, with one-click starter suggestions (three-finger tap = middle click, four-finger
  swipe = back/forward, and so on).
- **No Magic Mouse** support planned (the owner doesn't use one).
- The doc's other recommendations stand: window actions through shared SlopKit layout code, Run
  Shortcut instead of shell/AppleScript actions, no hyper key or keyboard tap in v1, three-finger
  physical click no earlier than v1.1 and only if latency holds.
