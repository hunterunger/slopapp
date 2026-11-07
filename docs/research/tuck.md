# Tuck research (inspired by Bartender)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md) on 2026-11-07.
> Studied: **Bartender** (built by Ben Surtees / Surtees Studios, sold to Applause Group in 2024).
> Versions: 6.6.2 for macOS 26 and 7.x for macOS 27 "Golden Gate" (Setapp reviews cite 7.1.0).
> Bartender is **not installed** on this Mac, so this is based on its website, release notes,
> Golden Gate preview notes, support FAQ and permissions pages, Setapp reviews, forum threads
> (TidBITS, MacRumors, MPU, BetterTouchTool community) and press. To learn which techniques work
> on current macOS we read about the *behaviour* of the open-source **Ice** (GPL; no code read
> or copied), its fork **Thaw**, **Hidden Bar** and **MenuBarHider**, and the reports on them.
> We also ran read-only checks on this Mac (Mac with a notch, built-in 1728 pt display,
> macOS 27.2 26B123, SDK 27.0): `CGWindowList` metadata (no titles), Accessibility reads of
> menu bar items (counts, positions and actions only, no app names), the AppKit SDK headers,
> the System Settings › Menu Bar pane (read only, not changed, quit afterwards), and **one
> throwaway status item of our own**, shown for about 2 seconds at its natural width. We did not
> hide, move, resize, rearrange or quit any of the owner's menu bar items, and we did not use
> a spacer. We never copy Bartender's name, icons, artwork, wording or signature visuals.

## The job

A Mac collects menu bar icons: sync clients, VPNs, chat apps, utilities (about 20 on the
owner's Mac, many of them Slopapp's). Most are glanced at once a week, but they all take space
next to the clock, and on a notched MacBook some end up out of reach. People use a menu bar
manager to **choose** what stays visible (the few icons they use daily) and to put the rest
out of sight but **one click or keystroke away**. "Done" feels like a calm, short menu bar that
looks the same every day, where nothing they need is ever lost.

The one interaction that matters most: **click Tuck's icon (or press a shortcut) → the tucked
icons appear → click the one you need → they tuck themselves away again.** The second-best
interaction, and the one most likely to survive future macOS changes: **press a shortcut,
type a few letters of any menu bar item, press Return, and its menu opens**, whether that item
is shown, tucked or pushed behind the notch.

## Who and when

- Every morning or after login: the bar should already look the way they set it up. No effort.
- Several times a day: open a rarely used item (VPN, sync status, a Slopapp utility) without
  hunting for it. Each use takes about 2 seconds.
- Before a screen share, recording or demo: hide everything except the essentials.
- On a notched MacBook, or moving between the laptop screen and a wide external display: the
  icons that matter must not vanish behind the notch.
- Setup: a few minutes once, then rarely touched (a new app adds an icon, so they tuck it).

## What macOS already does (verified on 27.2 unless noted)

This decides what Tuck has to add. Apple has steadily absorbed the easy half of this job.

| Native feature | Since | What it does | Limits |
|---|---|---|---|
| ⌘-drag to reorder | forever | Hold ⌘ and drag any status icon to a new spot. ⌘-dragging a system item off the bar removes it. | Manual. Third-party icons can't be removed this way. |
| System Settings › Menu Bar › Menu Bar Controls | 26 (Control Centre in 11–15) | Show or hide Apple's items one by one: Clock options, Siri, Spotlight, Wi‑Fi, Bluetooth, Battery, AirDrop, Focus, Screen Mirroring, Display, Sound, Now Playing, Fast User Switching, Text Input, Time Machine, Keyboard Brightness, VPN, Timer, Weather; some have "always" vs "when active" pickers. "Add Controls…" adds controls from apps. | Off means off. No "reveal on demand". |
| System Settings › Menu Bar › **Allow in the Menu Bar** | 26 | A switch per app that has ever shown a status item (about 40 on this Mac). Off hides **all** of that app's icons without quitting it. | Off means gone until you come back to this pane. No on-demand reveal. Per app, not per item. Stale entries for removed apps linger (Apple forum reports). |
| Overflow chevron | 27 | When the icons don't fit (usually because of the notch or a long app menu), macOS folds the leftmost icons behind a chevron at the edge of the icon area. Clicking it shows them; clicking again folds them. | **The width decides, not the user.** No shortcut, no auto-fold timer, no settings, nothing on a wide screen where everything fits. On this Mac it already folds away several Slopapp status items (see `docs/research/awake.md`, "Environment finding"). |
| Keyboard focus on status menus | forever | ⌃F8 ("Move focus to status menus"), then arrows; macOS 27 adds an expanded-interface API so custom popovers join keyboard navigation. | You arrow through every icon; no search. |
| Auto-hide the whole menu bar | forever | Never / Always / Desktop only / Full screen only (popup in the same pane). | All or nothing. |

**What Tuck must add to be worth installing:**

1. **You choose** what is tucked away (a stable set), instead of the width choosing.
2. **Reveal on demand and re-tuck by itself**: a click on Tuck's icon or a global shortcut, and
   it folds back after a few seconds. Works the same on a notched laptop and a 5K display.
3. **Find any item by typing**: a keyboard panel that lists every menu bar item (shown, tucked or
   folded by the system) and opens the chosen one. Nothing native does this.
4. **A clean-bar shortcut** for screen sharing: tuck every third-party icon at once, then restore.
5. **One overview** of all items with their state, and a shortcut to the System Settings pane
   for things that should be off for good (we don't duplicate Apple's switches).

Things we **don't** add because macOS does them now: reordering (⌘-drag), hiding Apple's own
items (Menu Bar Controls), turning an app's icon off permanently (Allow in the Menu Bar), and
the notch overflow on 27.

## Feasibility: how menu bar managers work, and what broke

Apple has **no public API** for managing other apps' status items (checked: the macOS 27
`NSStatusItem.h` adds only `expandedInterfaceDelegate`/`expandedInterfaceSession`, for an
app's *own* popover). Every manager relies on side effects or private behaviour, and every
major macOS release since 14 has broken them.

### What changed, release by release

- **macOS 14–15:** each status item was its own small window. Managers listed those windows,
  captured their pixels (Screen Recording), and moved them by posting synthetic ⌘-drag mouse
  events. macOS 15 started asking again periodically for Screen Recording consent, and showing
  a purple capture indicator, which made people nervous about these apps (Bartender's own page
  explains it only reads the menu bar and keeps the images in memory).
- **macOS 26 Tahoe:** Ice's author doubted Ice could be adapted (Ice went quiet in Sept 2025;
  Thaw forked it). Bartender 6 was rebuilt but shipped months of cursor hijacking, ghost clicks,
  re-indexing and WindowServer CPU creep, because it kept the layout in order by moving the
  real mouse and screenshotting the bar. Its fix (6.4.1) was an "On-Demand" layout mode that
  only rearranges when asked.
- **macOS 27 Golden Gate (released 14 Sept 2026):** the whole menu bar is drawn by one
  system process (`MenuBarAgent`) as **one window**. Per-item windows are gone, so Ice, Hidden
  Bar, Barbee, Sane Bar, Glow and Bartender 6 all stopped hiding on beta 1. Bartender 7 is a
  27-only rewrite; Thaw 3 is a 27-only rewrite that "never moves items"; Hidden Bar 1.11.1 and
  MenuBarHider hide through a private `MenuBarAgent` restriction. Ice issue #954 is unanswered.
  Bartender's Setapp reviews from late Oct–Nov 2026 are dominated by "doesn't work on 27" and
  "Screen Recording granted but not recognised".

### Verified on this Mac (macOS 27.2)

- `CGWindowListCopyWindowInfo`: **no window at the status-item level (25)** for any app.
  The bar consists of full-width (1728×33) windows owned by WindowServer and `MenuBarAgent`.
  Our throwaway status item reported an `NSStatusBarWindow` at level 25 with a placeholder
  window number (2^32) and **no** WindowServer window of its own. Window-list techniques are dead.
- Accessibility still works: each app's `AXExtrasMenuBar` lists its items with real screen
  positions and sizes (16 items across the running apps; 11 of them offer `AXPress`; the 5
  Apple items hosted by `MenuBarAgent` have no label and no actions). Our own item showed up in
  AX with its title and frame.
- `NSScreen.auxiliaryTopLeftArea/RightArea` describe the notch (here: notch from x 771 to 957).
- The private frameworks `MenuBarClient` and `MenuBarClientCore` are present (what the
  private restriction technique uses).
- Each app's defaults hold `NSStatusItem VisibleCC <autosaveName>` (0 or 1). Several Slopapp
  apps have 0 here, matching the overflow folding them away. The old `NSStatusItem Preferred
  Position` keys only remain in Control Center's domain, so ordering is no longer something an
  app can set through its own defaults.

### Techniques, judged

| Technique | How it works | OS range | Public? | Needs | Failure mode | Verdict |
|---|---|---|---|---|---|---|
| **Spacer (divider) item** | Tuck owns a divider item; to tuck, it sets the divider's `length` very large so everything left of it is pushed off the bar. The user ⌘-drags icons left of the divider to tuck them. | 13–26 work (behind the notch, pushed items can land under it) | Public API, undocumented effect | nothing | On 27, reported: items longer than half the screen width are dropped, and pushed items fall into the system chevron. Fails safe (nothing hidden). | **Spike before deciding.** Only path for macOS 14–26; probably useless on 27. |
| **MenuBarAgent restriction** ("assessment mode" allow-list) | Tuck tells the menu bar agent which apps may show icons: every running app except the tucked ones. Releasing it shows everything again instantly. | 27 only | **Private** (`dlopen`, runtime lookup) | No TCC prompt reported; must run from `/Applications`, not sandboxed | Any 27.x update can remove it → detect and show everything. Side effects: blocks Notification Center while active (clock click does nothing; others lift it while the pointer is over the clock); per app, not per item; can't hide items without a bundle id; apps outside `/Applications` are always hidden. | **The only way to hide on 27.** Owner's call (open question 1). |
| Unloading Apple menu extras (`CoreMenuExtra`) | Unload Time Machine, VPN etc. one by one, reload on reveal | 27 | Private | — | A crash or uninstall leaves the extra switched off in System Settings | **Skip.** Native switches cover it. |
| **Accessibility read + press** (`AXExtrasMenuBar`, `AXPress`) | Read every item's owner, label, frame; press one to open its menu | 10.x–27 (verified) | **Public** | Accessibility | Some items have no label or no press action; tucked items may not be pressable (spike) | **Use.** Powers Find and the Items list. |
| Synthetic ⌘-drag to reorder | Post mouse events that drag items | 14–26; Bartender 7 dropped it | Public events, but moves the real cursor | Accessibility | Cursor hijacking, ghost clicks (Bartender 6's biggest complaint) | **Skip.** The user ⌘-drags. |
| Screen capture of item images | Capture the bar, crop each item by its AX frame (or hide/re-capture/diff, as Brow does) | 14–27 | Public (ScreenCaptureKit) | Screen Recording (re-consent prompts, capture indicator) | Stale or wrong crops; privacy worry | **Later** (only for "show when it changes" and real icons in a panel). App icons instead. |
| Desktop/wallpaper screenshot for bar styling | Paint a tinted strip | ≤26 | — | Screen Recording | The call returns nothing on 27 | **Skip** (and styling is Bartender's signature). |
| `NSStatusItemSpacing` / `NSStatusItemSelectionPadding` | Global `-currentHost` defaults that tighten icon spacing | 11–27 (reported) | Undocumented defaults | none | Needs logout; Apple items ignore it on 27 (reported) | **Later**, as an opt-in with a Restore button. |

**Fragility, honestly:** Tuck's hiding will be the most fragile thing in Slopapp. On 27 it
rests on one private mechanism that Apple can change in any point release; on 14–26 on an
undocumented side effect. The design must assume it will break: a health check at launch and
after every wake/OS update, and the failure mode is always **"everything is shown, Tuck says
so"**, never "icons stuck hidden". Find, the Items list and the System Settings shortcut use
public APIs only and keep working when hiding doesn't.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else v1.1),
**later**, **skip** (with the reason).

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Hidden section | Items in a "Hidden" section disappear from the bar; layout page with Shown / Hidden / Always Hidden lists | must | "Tucked" set of apps (per app on 27, matching the system's granularity). Persist bundle ids only. |
| 2 | Reveal by clicking the app's icon | Click the Bartender icon; hidden items appear in the bar (or in Bartender Bar) | must | Left click on Tuck's icon toggles. Icon shows state (outline = tucked, filled = showing). |
| 3 | Reveal by global hotkey | "Show hidden items" hotkey | must | `ShortcutRow`. Toggles. |
| 4 | Auto re-hide | Hides again after you interact or after a delay | must | Re-tuck N seconds after reveal (default 10 s) or when the opened item's menu closes; Never option. |
| 5 | Find an item by typing | Quick Search (5), Command Bar (7): find, show and activate any item | must | `FloatingPanel` at the top centre of the active screen: type, arrows, Return presses the item (untucking briefly if needed), Esc closes. App icon + item label from AX. Public API, survives OS changes. |
| 6 | Health check and safe fallback | Debug logs; "Restart Menu Bar" button in 7 preview | must | At launch, wake, display change and OS update: verify hiding works (tuck a probe item of our own, read it back via AX). If not, release everything and say "Hiding isn't available on this macOS version" in the menu. |
| 7 | New apps' icons | Option to show or hide newly appeared items | must | New apps are shown by default; Tuck recomputes on every app launch so a tucked app launched later stays tucked. |
| 8 | Items overview | Layout page with item images, Disabled Items section (7 beta 4) | must | Settings › Items: every app with menu bar items, app icon, name, Shown/Tucked switch. Footer link "Turn icons off for good in System Settings…" opens the Menu Bar pane. |
| 9 | Clean bar (hide everything) | Focus Mode hotkey hides the whole bar (7) | should | Shortcut and menu item "Tuck everything" (all third-party icons except Tuck). For screen shares. |
| 10 | Always-hidden tier | Second section, shown with ⌥-click or its own hotkey | later | Adds a second set and UI; the single set covers most needs. |
| 11 | Reveal on hover / click empty bar / scroll / swipe | Quick Reveal options | later | Needs reliable "empty space" detection on the single-window bar. Off by default anyway. |
| 12 | Separate bar for hidden items | Bartender Bar below the menu bar, on hover/click/hotkey; themable | later | Needs item images (Screen Recording) or app icons plus click-through activation. Find covers the job. |
| 13 | Show an item when it changes | "Show for updates": image-change, icon-match or script triggers | later | Spec item, but needs Screen Recording and pixel diffing (Thaw 3 has "attention reveal" off by default). Fragile on 27. |
| 14 | Triggers / Automations | Battery, Wi-Fi network, location, time, Focus filter, URL actions | later | Most useful one is "show VPN icon on public Wi-Fi". A Focus filter or Shortcuts actions would be our cheap route. |
| 15 | Profiles / presets | Saved layouts switched by hotkey, trigger, Focus or display setup | later | |
| 16 | Per-item hotkeys | Assign a hotkey to show and open one item | later | Find + Return is nearly as fast. |
| 17 | Shortcuts / AppleScript / URL scheme | App Intents, AppleScript dictionary | later | "Tuck", "Show tucked items", "Tuck everything" as App Intents. |
| 18 | Reorder items for you | Drag in the layout page; Bartender moves them with synthetic mouse drags | skip | macOS ⌘-drag does this; synthesising it hijacks the cursor (top Bartender 6 complaint). |
| 19 | Keyboard-navigate the bar | Arrow through items after a hotkey | skip | Native ⌃F8. Find is better. |
| 20 | Hide Apple's items (clock, Control Center) | 7 can hide system items | skip | Native switches in System Settings › Menu Bar. We link there. |
| 21 | Notch handling: overflow into hidden, swap shown/hidden | "Move items that don't fit into Hidden", "Swap to make room" | skip | macOS 27's chevron does this natively. |
| 22 | Menu bar styling (tint, gradient, pills, borders, shadows, rounded corners, per-Space) | Big part of Bartender's identity | skip | Signature visuals, and the desktop-capture call it needs is gone on 27. |
| 23 | Spacers, labels, emoji, groups | Own items as separators or a group item that holds others | skip | Decoration; groups need moving items. |
| 24 | Icon spacing (Default/Small/Tiny) | Writes the hidden spacing defaults | later | Opt-in, reversible, needs logout. |
| 25 | Widgets (custom items from scripts/data sources) | No-code item builder | skip | A different app. |
| 26 | Clipboard history in the Command Bar, Top Shelf notch shelf (Pro) | Upsell features | skip | Clips and Shelf cover these; not this job. |
| 27 | Item images from Screen Recording | Images in layout page, Bartender Bar, search | later | App icons (no permission) in v1, like Bartender 7 and Thaw without the permission. |
| 28 | Launch at login | Setting | must | SlopKit `LaunchAtLogin`, on by default (a menu bar manager that doesn't start at login is broken). |
| 29 | Hide its own icon | Setting | should | SlopKit "Show in menu bar"; the hotkey keeps working; relaunching opens Settings. |
| 30 | Diagnostics | "Send debug logs" | should | Advanced: "Copy diagnostics": macOS build, mechanism, health result. No app names unless the user ticks a box, no item titles ever. |
| 31 | Battery-saving mode | "Lower power usage on battery" | skip | We're event-driven with no polling; nothing to save. |
| 32 | Onboarding demo, Pro upsell, license flows | Onboarding with demo, licence email | skip | Quiet by default; one inline explanation in Settings. |
| 33 | Multi-display setups | Profiles per monitor setup | must (behaviour) | Tucking applies to the bar on every display. Per-display profiles later. |

## Key flows

### Bartender's main flow (from its docs and reviews)
1. Click the Bartender icon, press the hotkey, or (if enabled) hover/scroll on the bar.
2. Hidden items appear in the menu bar beside the shown ones (or in the Bartender Bar under it).
3. Click an item; its menu opens. After you interact or a delay, they hide again.
4. On 27, Bartender 7 shows hidden items in its Bartender Bar and "clicks" the real item when
   you choose one (the only time it touches the mouse).

### Tuck flow 1: reveal and use a tucked item
1. The bar shows the user's daily icons, then Tuck's icon (a small "tucked" glyph).
2. Click Tuck's icon or press the reveal shortcut → tucked icons appear in their usual places
   (instant; Reduce Motion: no animation). Tuck's icon switches to its filled state.
3. Click the icon you need; its menu opens. Tuck doesn't re-tuck while a menu is open.
4. 10 s after the last menu closes (setting), or on a second click/shortcut, they tuck away.
   Right-click (or ⌥-click) on Tuck's icon opens Tuck's menu instead.

### Tuck flow 2: find an item by typing
1. Press the Find shortcut (or choose "Find a Menu Bar Item…" in Tuck's menu).
2. A small search panel appears at the top centre of the active screen, without taking focus
   from the front app's documents. It lists every item: app icon, app name, item label when the
   app provides one, and a tag for "tucked" or "folded by macOS".
3. Type to filter (fuzzy, by app name and label). Arrows move; 1–9 pick directly.
4. Return → the panel closes, Tuck untucks if needed, presses the item, and its menu opens
   where it lives. Esc or a click outside closes the panel.
5. If the item can't be pressed (no `AXPress`), Tuck reveals the tucked icons and briefly
   highlights where the item is, and says so in one line.

### Tuck flow 3: first run and choosing what to tuck
1. Launch → Tuck's icon appears. Nothing is tucked yet, so nothing changes. No window, no tour.
2. First click on the icon opens Settings › Items (there's nothing to reveal yet). The list
   shows every app that currently has menu bar icons, with a Tucked switch. One sentence at
   the top: "Tucked icons stay out of sight until you click Tuck's icon or press its shortcut."
3. The list's labels and the Find panel need Accessibility. The Items tab shows a
   `PermissionGate` inline the first time (one sentence why, button to the exact pane, live
   re-check). Hiding itself needs no permission on 27; without Accessibility the list falls
   back to app names from running apps, and Find is unavailable.
4. The user flips switches; the effect is immediate (the icon disappears). "Tuck everything"
   and "Show everything" buttons sit under the list.
5. Shortcuts tab: reveal, find and clean-bar recorders, unset by default (open question 6).

### Tuck flow 4: hiding stops working (OS update)
1. Health check fails at launch or after an update → Tuck releases everything (all icons back).
2. Tuck's menu's status line says "Hiding isn't available on macOS 27.x yet. Everything is
   shown." Find and the Items overview keep working. No alert, no notification.
3. Each launch re-checks; when an update to Tuck restores it, hiding resumes with the saved set.

### Tuck flow 5: clean bar for a screen share
1. Press the clean-bar shortcut (or menu: "Tuck Everything").
2. Every third-party icon except Tuck's is tucked; Apple's items stay (they're the user's to
   switch in System Settings). Tuck's icon shows a distinct state.
3. Same shortcut again restores the previous set exactly.

## Settings inventory

Bartender's settings (from docs and release notes; defaults mostly unpublished):

| Setting (Bartender) | Default | Options | Keep? |
|---|---|---|---|
| Start at login | off at first launch (6.2.1 fixed its toggle) | on/off | yes (on) |
| Show Bartender's menu bar icon, icon choice | shown | several glyphs | show/hide yes; icon choice no |
| Auto-hide (re-hide delay) | on | delay | yes |
| Quick Reveal: hover, click empty bar, scroll, swipe | off | each | later |
| Show hidden items in Bartender Bar instead of the bar | off | | later |
| Hide shown items when revealing hidden ones | off | (7) | skip |
| Move items that don't fit into Hidden / swap to make room | on (7 recommends it) | when short / every click / never | skip (native) |
| ⌥-click shows always-hidden / all items | on | | later |
| Show or hide new items | show | | yes (show) |
| Layout mode | On-Demand recommended (6) | On-Demand / Live | n/a (we never move items) |
| Item indexing (keep order across restarts) | off | Advanced | n/a |
| Lower power usage on battery | off | | skip |
| Menu bar style, spacing | default | many | skip / later (spacing) |
| Hotkeys: show hidden, always hidden, search/Command Bar, keyboard navigate, Bartender Bar at mouse, Focus Mode, per item | unset | | reveal, find, clean bar |
| Debug logs | off | send | copy diagnostics |

Tuck v1 (SlopKit `SlopSettings`, tabs in order):

| Tab | Setting | Default | Notes |
|---|---|---|---|
| General | Launch at login | on | |
| General | Show in menu bar | on | Hidden → hotkeys still work; relaunch opens Settings. |
| General | Tuck again automatically | after 10 seconds | 5 s / 10 s / 30 s / 1 min / Never. |
| General | Show icons from newly opened apps | on | Off = new apps start tucked. |
| Items | Per-app Tucked switch | off | Plus Tuck Everything / Show Everything, and the System Settings link. |
| Shortcuts | Show or tuck icons | unset | `ShortcutRow`, subtitle explains. |
| Shortcuts | Find a menu bar item | unset | |
| Shortcuts | Tuck everything | unset | |
| Advanced | Status: "Hiding works on this Mac" / "isn't available" + which method | — | Read-only line, Check Again button. |
| Advanced | Copy diagnostics | — | No item titles. |
| About | `AboutView` | — | |

## Menus and shortcuts

**Bartender:** left-click the icon reveals; right-click (7: also right-click on empty bar space)
opens its menu (preferences, layout, quit). Hotkeys are user-set; no published defaults.

**Tuck's status item:** left-click toggles tucked/showing. Right-click or ⌥-click opens the
menu (`.menu` style):

1. Status line: "4 apps tucked" / "Everything is shown" / "Hiding isn't available on this macOS"
2. Show Tucked Icons / Tuck Icons (mirrors the reveal shortcut)
3. Find a Menu Bar Item… (shows its shortcut)
4. Tuck Everything (checkmark while active)
5. Pause Tucking (shows everything until turned back on or Tuck quits)
6. Menu Bar Settings… (opens System Settings › Menu Bar)
7. `MenuFooter` (Settings… ⌘,, About, Quit ⌘Q)

Global shortcuts (all unset by default, see open question 6): reveal/tuck, find, tuck
everything. Find panel: type, ↑/↓, 1–9, Return, Esc.

## Permissions and system integration

- **Accessibility (Privacy & Security › Accessibility; "Device Control and Data Access" on 27
  per `docs/research/clips.md`)**: to read item labels and positions (Items list, Find) and to
  press items (Find). Asked inline on the Items tab or the first time Find opens, never at
  launch. Without it: hiding still works on 27 (if the private method is approved), the Items
  list shows app names only, Find says it needs access with one button.
  Ad-hoc signed builds lose this grant when the binary changes (every Slopapp update until a
  Developer ID exists). Tuck must re-check on launch and show the inline row again rather than
  silently failing.
- **Screen Recording: not used in v1.** If a later version draws real item images or watches
  for icon changes, the rules are: capture only the menu bar strip, keep crops in memory only,
  never write them to disk, never send them anywhere, drop them when the panel closes, make it
  optional (app icons otherwise), and say all that in the Settings explanation and README.
- **Private MenuBarAgent restriction (27, if approved)**: no TCC prompt reported. Tuck must run
  from `/Applications` (the agent ignores apps elsewhere, including `~/Applications`) and not be
  sandboxed. Behind a protocol (`MenuBarHiding`) with a fake for tests, `dlopen` with a version
  check, and the health check above.
- **Launch at login**: `SMAppService` via SlopKit.
- **Global shortcuts**: `KeyboardShortcuts` (no permission).
- **No network, no analytics, no accounts.** Persisted state: the tucked set (bundle ids) and
  settings. Item labels read through Accessibility can contain personal text (a song title, a
  timer, a VPN location); they're shown live in Find and never stored or logged.
- **Not used**: Automation, Full Disk Access, mouse event synthesis, URL scheme, App Intents (later).

## UX patterns worth adopting

- **The divider idea, without the dragging**: one clear boundary between "daily" and "tucked".
  We express it as a switch per app instead of making people ⌘-drag icons past a divider.
- **Re-tuck on its own**: the bar always returns to calm without a second click.
- **Typing beats hunting**: Bartender's search was the feature power users praised most;
  it's also the part that doesn't depend on fragile tricks.
- **Never touch the cursor**: Bartender 7 and Thaw 3 both concluded that moving the user's mouse
  is unacceptable. We never synthesise mouse events.
- **Arrange once, let the user own the order**: Thaw 3's "you arrange with ⌘-drag, we only hide
  and reveal" is the honest model on 27.
- **App icons when there are no item images**: both Bartender 7 and Thaw fall back to the owning
  app's icon without Screen Recording. Good enough, and no permission.
- **Fail open**: Hidden Bar 1.11.1 and MenuBarHider leave the bar expanded if the private
  method disappears. Hidden icons that can't come back are the worst possible outcome.

## What we won't copy, and what we'll do better

- **Not copying**: the name, icons, the separate themed bar under the menu bar, menu bar
  styling (tints, pills, borders), notch shelf, Pro/subscription and licence flows, wording.
- **Doing better**:
  - **Honest about fragility.** A visible health status, fail-open behaviour, and no promises
    in the README that an OS update can break silently. Bartender's Setapp page kept selling
    6.6.2 to macOS 27 users for weeks while reviews said it didn't work.
  - **Light.** No polling, no indexing, no screenshots, no WindowServer load. Bartender 6's
    CPU creep, choppy scrolling and battery drain are its most common complaints.
  - **No cursor hijacking, no ghost clicks.** We never move items or the mouse.
  - **No Screen Recording in v1**, so no capture indicator, no monthly re-consent, no "granted
    but not recognised" loop (the top macOS 27 complaint), and nothing to distrust.
  - **Transparent ownership and code.** Bartender's 2024 silent sale (users found out from a
    changed signing certificate) shook trust in an app that reads the screen. Tuck is open source.
  - **Small scope, works with the system**: we link to Apple's switches instead of re-creating
    them, and let macOS 27's chevron handle the notch.
  - **Find works for everything**, including items macOS folded behind its own chevron.

## Edge cases

- **macOS version**: 27.x with the private method missing or changed (fail open); 26 and
  earlier (spacer path or "not supported", open question 2); a point update while Tuck runs.
- **Crash or force-quit while tucked**: the restriction must end with the process (spike:
  verify icons come back after `kill -9`). Login after a crash: icons visible until Tuck starts.
- **Tuck launched outside `/Applications`** (dev builds in `build/`): the agent may ignore it;
  say so instead of hiding nothing silently. `scripts/run.sh` testing needs a plan (spike).
- **Notification Center blocked** while the restriction is active (clock click). Must keep the
  clock usable (lift while the pointer is over the clock, or untuck on clock hover).
- **Apps with several icons** (on 27 they tuck together); apps with **no bundle id** or run
  from outside `/Applications` (always hidden by the agent while tucking: never include them in
  the "allowed" calculation wrongly; list them as "can't be tucked").
- **App launched after tucking**: a tucked app that starts later must stay tucked; a new app
  must appear (default). App quits and relaunches. Login items starting before Tuck.
- **Tuck's own icon folded away** by the overflow on a full bar: hotkeys still work; relaunch
  opens Settings; Settings suggests ⌘-dragging Tuck's icon to the right.
- **Multiple displays**: menu bar on every display, with and without "Displays have separate
  Spaces"; display connect/disconnect; a notched laptop plus an external screen; mirrored.
- **Full-screen apps and auto-hidden menu bar**: reveal shortcut while the bar is hidden.
- **Sleep/wake, fast user switching, screen lock**: re-check health, keep state.
- **Screen sharing / recording**: Tuck Everything restores exactly the previous set.
- **Right-to-left languages**: status items sit on the left; "left of" logic must not be assumed.
- **Accessibility revoked mid-use**: Find shows the inline permission row; hiding unaffected.
- **Items without labels or without `AXPress`** (Apple items on 27 have neither): show app
  icon + app name; Find falls back to reveal and highlight.
- **Item labels with personal content**: never logged, never in diagnostics.
- **Huge menu bars** (60+ icons) and very wide displays; empty bar (nothing to tuck).
- **Dark/light, Reduce Motion, Increase Contrast, VoiceOver**: Tuck's status item and the
  Find panel rows fully labelled (no `[unlabeled]` in `scripts/drive tree`).
- **The owner's real menu bar during testing**: tests must use the fake `MenuBarHiding`; any
  live hiding test runs against a throwaway test app's status item, in a VM or a separate
  user account (open question 8).

## Our v1 scope

Assumes the owner approves the private 27 method (open question 1). If not, v1 is items 5–8
and 11–15 only, and the app should be reconsidered.

- [ ] 1. Settings › Items lists every app with menu bar icons (app icon + name), each with a Tucked switch; flipping it hides or shows that app's icons immediately.
- [ ] 2. Clicking Tuck's icon shows the tucked icons; clicking again tucks them; the icon shows the state.
- [ ] 3. The reveal shortcut does the same from any app, including full screen.
- [ ] 4. Tucked icons tuck themselves away again after the chosen delay (default 10 s), never while one of their menus is open.
- [ ] 5. Find: the shortcut opens a search panel listing every menu bar item; typing filters; Return opens the chosen item's menu (untucking it if needed); Esc closes; 1–9 pick.
- [ ] 6. Find works for items macOS folded behind its own overflow chevron, or says clearly what it can't do.
- [ ] 7. Without Accessibility: an inline permission row with a button to the exact pane; live re-check; hiding still works.
- [ ] 8. Health check at launch, wake, display change: if hiding doesn't work, every icon is shown and the menu says so; nothing ever stays stuck hidden (including after a force quit).
- [ ] 9. A tucked app launched after tucking stays tucked; a new app's icon is shown (default).
- [ ] 10. Tuck Everything (menu + optional shortcut) hides all third-party icons and restores the exact previous set.
- [ ] 11. "Menu Bar Settings…" opens System Settings › Menu Bar.
- [ ] 12. The clock still opens Notification Center while icons are tucked.
- [ ] 13. Settings tabs: General (launch at login on, show in menu bar, re-tuck delay, new apps), Items, Shortcuts, Advanced (status + copy diagnostics), About. Menu ends with `MenuFooter`.
- [ ] 14. Hiding Tuck's own icon keeps the shortcuts working; relaunching opens Settings.
- [ ] 15. No Screen Recording request, no network, no mouse movement, idle CPU ~0%; persisted data is bundle ids and settings only.
- [ ] 16. Works with two displays and on the notched built-in display.

## Open questions

1. **Private API on macOS 27.** Hiding on 27 is only possible through the private
   `MenuBarAgent` restriction (what Hidden Bar 1.11.1 and MenuBarHider use, and likely
   Bartender 7 and BetterTouchTool). Switches set a "no private APIs" precedent. Accept it for
   Tuck, behind a protocol with a health check and fail-open, and a README note that a macOS
   update can turn hiding off? If not, Tuck can only offer Find + the overview on 27, which
   is probably not worth a separate app (Find could live in the Slopapp hub instead).
2. **OS range.** Slopapp targets macOS 14+. Ship Tuck as 27+ only (like Bartender 7 and
   Thaw 3), or also build the spacer method for 14–26? The owner runs 27.2; the spacer path
   doubles test work for users we may not have. Recommendation: 27+ for v1.
3. **Is it worth it now?** macOS 27's chevron already solves the "lost behind the notch" part.
   Keep Tuck at priority 3 and build it last, or ship Find first (public API, low risk) and add
   hiding after the private method survives 27.1–27.3?
4. **"Show items when they update"** (in the roadmap spec) needs Screen Recording and pixel
   diffing, which are fragile on 27 and a privacy cost. Defer to later? (Recommendation: yes.)
5. **"Reorder" (in the roadmap spec)**: rely on macOS ⌘-drag and never move items ourselves?
   (Recommendation: yes; moving items means moving the user's cursor.)
6. **Default shortcuts**: leave all three unset (recorder shown on first use), or ship defaults
   such as ⌃⌥ + a letter for reveal and Find? Needs a collision check on the owner's setup.
7. **Per-app granularity**: on 27 all icons of one app tuck together. Fine for v1?
8. **Live testing**: hiding experiments can't touch the owner's real bar. OK to run them in a
   macOS 27 VM or a separate user account with a throwaway test app? Also: dev builds run from
   `build/`, but the agent may ignore apps outside `/Applications`.
9. **Slopapp's own icons**: several Slopapp apps already get folded away on the owner's Mac.
   Should Tuck treat Slopapp apps specially (e.g. a "Slopapp" group), or should the hub offer a
   single combined menu instead? Product direction call.
10. **Notification Center workaround**: lifting the restriction while the pointer is over the
    clock briefly shows tucked icons. Acceptable, or untuck fully when the clock is clicked?

## Sources

- Bartender: [home page (Bartender 7)](https://www.macbartender.com/),
  [Bartender 6 release notes](https://macbartender.com/Bartender6/release_notes),
  [Golden Gate (macOS 27) preview and beta notes](https://www.macbartender.com/goldengate/releases/),
  [support FAQ](https://www.macbartender.com/Bartender6/support/),
  [Bartender 5 feature page](https://www.macbartender.com/Bartender5/),
  [Screen Recording permission explanation](https://macbartender.com/Screen-Recording-Permission),
  [permissions info](https://macbartender.com/Bartender5/PermissionInfo),
  [Bartender Pro announcement](https://www.macbartender.com/B5blog/Bartender-Pro/),
  [Bartender 3 preferences guide](https://macbartender.com/b3gettingstarted/bartender-preferences)
- Reviews and opinion: [Setapp customer reviews](https://setapp.com/apps/bartender/customer-reviews),
  [TidBITS: Bartender 6 on Tahoe](https://talk.tidbits.com/t/bartender-6-on-tahoe-being-problematic/32061),
  [9to5Mac: Bartender is good again (Mar 2026)](https://9to5mac.com/2026/03/11/bartender-for-mac-is-good-again-and-my-menu-bar-is-very-thankful/),
  [heise: Bartender 6 lag on macOS 26](https://heise.de/-11167978),
  [MacRumors: new ownership (2024)](https://www.macrumors.com/2024/06/04/bartender-mac-app-new-owner/),
  [Setapp: Quick Reveal article](https://setapp.com/app-articles/bartender-quick-reveal)
- macOS 27 changes: [publicspace.net: macOS 27 menu bar](https://www.publicspace.net/blog/macos-27-menu-bar/),
  [Badgeify: macOS 27 menu bar changes](https://badgeify.app/macos-27-golden-gate-menu-bar-changes/),
  [Brow: macOS 27 menu bar](https://brow-app.com/blog/macos-27-menu-bar),
  [macos-tahoe.com: what works on 27](https://macos-tahoe.com/blog/macos-27-menu-bar-apps-broken-bartender-ice-icons-hidden-behind-notch-fix-2026/),
  [BetterTouchTool community thread](https://community.folivora.ai/t/macos-27-golden-gate-menu-bar-management-broken-solutions-ice-thaw-bartender-barbee-etc/47232),
  [Apple Developer Forums: NSStatusItem issues on macOS 27](https://developer.apple.com/forums/thread/836113)
  (vendor blogs, treated as reports and cross-checked where possible)
- Open-source projects (behaviour only, no code): [Ice](https://github.com/jordanbaird/Ice),
  [Ice issue #954 (macOS 27)](https://github.com/jordanbaird/Ice/issues/954),
  [Thaw 3.0.0-alpha.1 notes](https://github.com/thaw-app/Thaw/releases/tag/3.0.0-alpha.1),
  [Hidden Bar](https://github.com/dwarvesf/hidden) and [its releases](https://github.com/dwarvesf/hidden/releases),
  [MenuBarHider README](https://github.com/happy666End/MenuBarHider) and [wiki](https://github.com/happy666End/MenuBarHider/wiki)
- macOS 26 native controls: [9to5Mac: Tahoe menu bar feature](https://9to5mac.com/2025/06/28/new-macos-tahoe-feature-solves-common-complaint/),
  [Apple Community: removing third-party apps in Menu Bar settings](https://discussions.apple.com/thread/256145886)
- Local, read-only (2026-11-07, macOS 27.2): System Settings › Menu Bar pane;
  `AppKit.framework/Headers/NSStatusItem.h` (SDK 27.0); `CGWindowList` and Accessibility probes.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (<date>)
| Finding | Severity | Decision | Why / fix |
|---|---|---|---|

## Owner decision (2026-11-07)

**Skipped.** The owner chose not to build Tuck: the only working hiding method on macOS 27 is private
and fragile, and a search-only version wasn't worth a separate app. Kept as research in case macOS
gains a public API.
