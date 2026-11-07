# Switchboard research (inspired by OpenIn)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: OpenIn
> 4.3.5 (221381, Setapp build; installed copy at /Applications/Setapp/OpenIn.app, read-only)
> + its website, App Store / Setapp listings and release notes, on 2026-11-02. The App Store
> build is ahead (4.5.2, Sep 2026); later features are noted from its release notes. We
> study how it works so we don't reinvent the wheel. We never copy its name, icons,
> artwork, wording, sounds or signature visuals.
>
> OpenIn is the owner's current default browser and was running throughout. It was not
> quit, no setting was toggled, no link was opened through it and the default browser was
> not touched. Its rules list, app lists and history are personal configuration: only their
> structure is described here.

## The job

Switchboard stands in as the Mac's "default browser" so that every link clicked anywhere
(Mail, Slack, Messages, a terminal, a PDF) goes to the right browser, browser profile or
app, instead of always landing in one browser. People with a work profile and a personal
profile, or a "real" browser plus a dev browser, reach for it dozens of times a day without
thinking about it; "done" is the link appearing in the right window as fast as if there
were no middleman. The one interaction that matters: **click a link → if a rule knows
where it goes, it just opens there; otherwise a short list of browsers appears at the
cursor, press 1–9 (or ↑/↓ + Return, or click), and it opens.** Any added latency is felt on every click.

## Who and when

- Clicking a meeting/doc link in Slack or Mail that must open in the work Chrome profile.
- Clicking a personal link (shopping, banking) that should go to Safari, not the work profile.
- A developer opening localhost / staging links in a dev browser, everything else in the main one.
- Holding a modifier while clicking to force the picker (or a specific browser) for one link.
- Links from apps that have a native app equivalent (Zoom, Apple Music) going to that app.

Frequency: many times a day, each use under a second. Settings are touched rarely (setup,
then adding a rule now and then). The owner launches OpenIn hundreds of times (664 launches),
i.e. it is effectively always-on infrastructure.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason).

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Act as default browser | Registers `http`/`https` URL types (role Viewer) in Info.plist; user makes it default in System Settings or via an in-app button | must | Same Info.plist entries. In-app "Make Default Browser…" calls `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)`; macOS shows its own confirm dialog. |
| 2 | Receive links instantly | Menu bar agent (`LSUIElement`), "Start at login" on by default (onboarding says it's so the first link shows the picker instantly) | must | Handle `kAEGetURL` via `NSAppleEventManager` registered in `applicationWillFinishLaunching`. Launch at login on by default once the user makes us default. |
| 3 | App picker | Window of target-app icons, shown only when more than one target is left after rules; keyboard picking (1, 2, 3… default, rebindable since 4.3); icon size Small → XX-Large; reduce-animation option; option to show it even with one app | must | Non-activating `FloatingPanel` at the cursor; 1–9, arrows + Return, Esc, click outside. One icon size. System Reduce Motion instead of an own toggle. |
| 4 | Ordered rules, first match wins | Per handler (Browsers / Mail / Call / each file type) an ordered rules list with a "Default" rule last; rules can target one app or leave several (→ picker) | must | One rules list for web links in v1. Last row = "Otherwise" fallback that can't be deleted. |
| 5 | Domain/path condition | Host and path patterns with wildcards (`*.zoom.us/j/*`), case-insensitive, query/fragment/port aware, glob `**` | must | v1: host match with `*.` wildcard, plus optional path prefix. Show a "test URL" field in the editor. |
| 6 | Source-app condition | "Received from app", including helper processes inside an app bundle; 4.5 improved attribution | must | Sender PID from the Apple Event (`keySenderPIDAttr`) → `NSRunningApplication` → walk to outermost `.app` bundle for helpers. |
| 7 | Modifier-key condition | ⌘ ⇧ ⌥ ⌃ fn as rule conditions | must | Read `NSEvent.modifierFlags` (current keyboard state, no permission) when the event arrives. Built-in default: holding ⌥ (configurable) forces the picker. |
| 8 | Browser discovery | "Discovered apps" = everything that can open `http(s)` (includes non-browsers) | must | `urlsForApplications(toOpen:)`, filtered by a known-browser bundle-ID list; everything else hidden but addable. Verified: on this Mac the raw list includes a terminal and two developer/AI tools. |
| 9 | Order and visibility of targets | Drag to reorder; Add menu; Remove; the same app may be added several times with different settings | must | Order = picker order = number keys. Hide/show per entry. |
| 10 | Chromium browser profiles | Per-browser submenu lists profiles with a "Refresh Profiles" item; each profile becomes its own target | must | Read `~/Library/Application Support/<vendor>/Local State` → `profile.info_cache`; launch with `--profile-directory=<dir>`. Owner uses Chrome. |
| 11 | Firefox profiles | Discovered from `profiles.ini`, `-P <name>` | should | Cheap once #10 exists. |
| 12 | Safari profiles | Per-profile Safari targets; needs AppleScript/Apple Events, a bundled "Browser Launcher" helper, macOS 27 permission prompts; repeated bug fixes across 4.1–4.5 | later | No public API; needs GUI scripting (Accessibility). Fragile and locale-dependent. |
| 13 | Private / incognito targets | Safari Private (Apple Events), Edge InPrivate, Chromium incognito, Firefox private | should | Chromium `--incognito`, Firefox `-private-window` are just arguments. Safari private = later (same problem as #12). |
| 14 | Activate the browser | Brings the chosen browser forward (4.3.5/4.4.0 fixed cases where it didn't) | must | Under macOS 14+ cooperative activation, yield activation to the target before opening. Test cold and warm browsers. |
| 15 | Open in background | Per-target option (tip mentions adding an app twice, one "in the background") | should | `OpenConfiguration.activates = false`; default modifier ⇧ in the picker. |
| 16 | "Always open here" from the picker | Right-click an app in the picker (reviewers didn't find it) | should | Visible affordance: ⌘-click or ⌘+number = "Always open <host> here", creates a rule, shows a HUD. |
| 17 | Copy link from the picker | Not documented | should | ⌘C copies the URL and dismisses. Gives Esc a safe alternative. |
| 18 | Show the link in the picker | Unknown in this version (couldn't open the picker without opening a link) | must | One line with the host (and truncated path) so you know what you're routing. |
| 19 | Default-browser watchdog | "Check if OpenIn is a default app in background", posts a notification when another app takes over | should | Check on wake/app activation (not polling). Show state in the menu; no notification by default. |
| 20 | Handle `.html` files (and other file types) | Files tab: groups and per-extension handlers (html by default), each with its own app list and rules; `public.content` catch-all; "Set as default" for extensions | later | Roadmap says "optional file handler". v1.1: `public.html`/`public.xhtml` only, same picker. |
| 21 | Mail links (`mailto:`, `message:`) | Separate "Mail apps" handler, off by default, own app list + rules; can route to webmail | later | Same engine, different scheme. Keep v1 about web links. |
| 22 | Phone links (`tel:`) | "Call apps" handler, off by default | skip | Rare on Mac; FaceTime already handles it. |
| 23 | Rewrite URLs per target | Regex substitute per target (e.g. https → music://) | later | Covered for common cases by "open in app" targets. |
| 24 | Pre-rule scripts | JavaScript (own JS engine helper) can hide/show targets and rewrite URLs; zsh scripts as targets | skip | Power-user surface, big to test. Shortcuts actions cover automation. |
| 25 | Strip tracking parameters | Sample script removes `utm_*`, `fbclid`, `gclid`… | later | Off by default, offline list. Small, popular in reviews of competitors. |
| 26 | Resolve redirects / short links | "Resolve" toggle, domain list, 1 s timeout | skip | Needs network on the hot path; adds latency by design. Conflicts with our privacy rule. |
| 27 | Link history | "Store history of opened links and files" (retention pop-up), searchable History window, widget | later | Off by default; local only; menu shows "Recent" when on. Privacy first. |
| 28 | Browser extensions | Bundled Safari web extension; Chrome/Firefox store extensions to send a tab/link to the router; rules can match "from extension" | skip | Separate products to ship and review. |
| 29 | Share extension, Services menu | "Open in OpenIn" in Share menu and Services (text containing a URL) | later | Services entry is a few lines of Info.plist; Share extension is a separate target. |
| 30 | Shortcuts / App Intents | Open Browser, Open URL in Browser/Mail/Tel app, Set Focus Hint (Focus filter) | later | "Open URL in <target>" intent is cheap with AppIntents. |
| 31 | Focus integration | Focus filter sets a "hint" rules can match (macOS doesn't expose Focus names) | later | Neat, but niche. |
| 32 | Handoff | Declares `NSUserActivityTypeBrowsingWeb` so Handoff'd pages route through it | later | `application(_:continue:)`, same engine. |
| 33 | Own URL scheme | `openin://open?url=…` and a second "force" scheme that appears to always show the picker | should | `switchboard://open?url=…` (+ `&pick=1`) for scripts and testing. Cheap. |
| 34 | Menu bar icon | Can be hidden; relaunching the app shows it for 5 s to reach Settings | must | Design-system standard: hideable; relaunch brings Settings/icon back (SlopAppDelegate). |
| 35 | Backups | Create/Import backups of config + history, iCloud list | later | v1.1: Export/Import rules as JSON. No iCloud. |
| 36 | Custom app icons, Image Playground icons | Per-target custom icon | skip | Cosmetic. |
| 37 | Tips | Popover tips in Settings ("add the same app multiple times"), "Disable tips" toggle | skip | Quiet by default; the UI should explain itself. |
| 38 | Logs / JS logs | "Export logs…" in About, "Enable JavaScript logs" | skip | Use `os_log`; no export UI. |
| 39 | Release notes window, onboarding tutorial | "New in" window per update; Setup window | skip | Design system: no what's-new sheets, no tours. |
| 40 | Other schemes, magnet links, terminal for executables, phishing check | Added in 4.4.x (Schemes tab, Apple Intelligence phishing detection) | skip | Out of scope for "open every link in the right browser". |

## Key flows

### Flow 1: a link is clicked (the main job)
1. User clicks a link in any app. LaunchServices sends a GetURL Apple Event to the default
   browser (OpenIn), which is already running in the background.
2. OpenIn evaluates rules top to bottom: conditions on URL pattern, source app, modifier
   keys held, Focus hint, request origin (share menu / Handoff / extension).
3. If the matched rule leaves exactly one target, it opens there immediately (browser
   activated, profile/private applied). No UI at all.
4. If several targets remain (or the handler is set to always ask), the app selection
   window appears with the targets as icons in the configured order. Keys 1, 2, 3… pick
   (rebindable); clicking picks; right-clicking an app offers to make a rule.
5. The browser opens the link. Reviews show the gap between pick and page is often blamed
   on the browser itself; one reviewer reported the picker itself was slow to appear.

### Flow 2: first run / onboarding
1. First launch shows a "Setup" window: app icon and name, "Start at login" (on) and
   "Enable notifications" (on) switches, a line saying the app lives in the status bar
   (with a picture of the menu bar icon), and Continue.
2. Further pages were not walked (they lead to the "make default" step, which could show the
   system default-browser prompt; the hard rules forbid triggering it).
3. Default-browser setup per the docs: the app asks to become default ("Fix It"-style
   buttons); mail default is set from Mail.app's settings; file types via Finder's Get
   Info → Change All (App Store version needs a separate Helper app for this).
4. The Setup window can be reopened later from Window → Setup.

### Flow 3: add a browser profile as a target
1. Settings → Browsers → Applications list → Add (menu button).
2. Menu shows "Discovered apps"; browsers with profiles are submenus: the browser itself,
   a "Profiles" section, "Private" (Safari), "Refresh Profiles".
3. Pick a profile → new row in the list. Rows can be reordered; the same app can appear
   several times with different settings (background, profile, rewrite).
4. "Custom" section: "Add zsh script…", "Browse…" (any app).

### Flow 4: create a rule
1. Settings → Browsers → Rules → "+". (Editor not opened in this study: rows couldn't be
   selected without the mouse, and opening the owner's rules would expose them.)
2. Per docs: choose conditions (URL pattern, source app, modifiers, Focus hint, origin,
   printing) and which targets remain visible; drag to order; "Default" stays last.
3. Shortcut path: right-click an app in the picker (per the developer's review reply).

## Settings inventory

Observed in the Setapp 4.3.5 build. "Owner value" is not reported where it would reveal
personal configuration.

| Setting | Default | Options | Keep? |
|---|---|---|---|
| General → Start at login | on (onboarding) | switch | yes: "Launch at login", on after becoming default |
| General → Show menu bar icon | on (onboarding implies) | switch | yes (design-system standard) |
| General → Check if default app in background | on | switch | as menu status + optional notification, off |
| General → Store history of opened links and files | unknown | pop-up of retention periods | later, default off |
| General → Disable tips | off | switch | no |
| App selection window → Always show (even with one app) | off | switch | no: rules decide; modifier forces picker |
| App selection window → Icon size | Small | Small, Medium, Large, X-Large, XX-Large | no: one size |
| App selection window → Reduce animation | off | switch | no: follow system Reduce Motion |
| Developer → Enable JavaScript logs, View logs… | off | switch, button | no |
| Browsers → Enabled | on | switch (per handler) | implicit |
| Browsers → Applications | discovered | ordered list, Add menu (discovered apps, profiles, private, custom script, Browse…), Remove | yes |
| Browsers → Rules | "Default" only | ordered list, + / − | yes |
| Browsers → Developer → Execute script | none | Edit… (JS) | no |
| Browsers → Redirects → Resolve / Domains / Timeout | on / list / 1 s | switch, Edit…, seconds | no |
| Mail apps (Enabled, Applications, Rules, script, `message:` support) | off | as Browsers | later |
| Call apps (Enabled, Applications, Rules, script) | off | as Browsers | no |
| Files → Groups / File types (html default) → per-type Enabled, Applications, Rules, script | html enabled | sidebar + same panes | later (html only) |
| Backups → Create, Import…, list (iCloud) | — | buttons | later (JSON export) |
| About → author note, links, Export logs… | — | — | our AboutView |

## Menus and shortcuts

- **Status item**: hidden on this Mac (owner's setting), so its menu couldn't be opened
  without changing settings. Docs: hidden icon → relaunch app to show it for 5 s.
- **Main menu** (visible when Settings is open): app menu (About, Settings… ⌘,, Services,
  Hide/Hide Others/Show All, Quit ⌘Q); Edit (standard); View (Enter Full Screen); Window
  (standard window items, then History, Release notes, Setup); Help (Help ⌘?).
- **Picker**: number keys 1–9 by default, custom key bindings (e.g. letter keys) since 4.3,
  keyboard navigation added in 4.5. No global hotkey.
- **Comparable app (Velja)** for reference: fn-click forces the picker, letter keys pick,
  ⌃Tab/arrows cycle, Return/Space confirm, ⌘-click "always open this domain here", ⇧ or ⌘C
  copy the link, ⌃ opens in background, ⌥1–9 in its menu.

Our proposal: status item menu = status line ("Default browser" or "Not the default
browser" + "Make Default Browser…") → "Open Link from Clipboard" (should) → Settings… ⌘, →
About → Quit ⌘Q. Picker: 1–9, ←/→, Return, Esc, ⌘C copy, ⇧ = background, ⌘-pick = always
open this host here.

## Permissions and system integration

What OpenIn declares (from its Info.plist, entitlements and bundle):

- **URL types**: `http`/`https` (Viewer), `mailto`/`message`, `tel`, `openin`, `openinx`.
- **Document types**: `public.html`, `public.xhtml` (Viewer, rank Alternate); a
  `public.content` catch-all and a `****` type (role None) so any file type can be assigned
  to it; its own backup type.
- **Services**: one "Open in …" service for text/URLs (`http`, `https`, `mailto` links).
- **Handoff**: `NSUserActivityTypeBrowsingWeb`.
- **Apple Events**: `NSAppleEventsUsageDescription` ("to open some browsers in Private
  mode"), automation entitlement + Safari exception. Folder-access usage strings for
  "reopen last files".
- **Extensions**: Safari web extension, Share extension, two WidgetKit widgets
  (browser launcher, history). Helpers: a "Browser Launcher" app, a native-messaging host
  for the Chrome/Firefox extensions, a JS executor.
- **App Intents**: Open Browser, Open URL in Browser / Mail app / Tel app, Set focus hint.
- iCloud container (backups), app group, notifications. Min macOS 15.1.

### macOS mechanics for our build

| Mechanic | How | Verified? |
|---|---|---|
| Be listed as a browser | `CFBundleURLTypes` with `http` + `https` (role Viewer) and `CFBundleDocumentTypes` for `public.html`/`public.xhtml` (Viewer). | Partly: confirmed these are exactly what Safari, Chrome and OpenIn declare. Which apps System Settings' "Default web browser" pop-up lists was not checked. |
| Discover candidate browsers | `NSWorkspace.urlsForApplications(toOpen: URL("https://…"))`. | **Verified** (read-only script): returned OpenIn, Safari, Chrome **and** a terminal and two developer/AI apps that register `https` for login callbacks. Their Info.plists look like real browsers' (http+https, some also `public.html` Viewer), so there's no clean "is a browser" flag: use a bundled known-browser list, show others as addable. Exclude our own bundle ID. |
| Receive URLs | `NSAppleEventManager.shared().setEventHandler(_:andSelector:forEventClass: kInternetEventClass, andEventID: kAEGetURL)` in `applicationWillFinishLaunching` (so cold-launch events aren't missed). URL = `paramDescriptor(forKeyword: keyDirectObject).stringValue`. Files (`.html`) arrive via `application(_:open:)`; `NSAppleEventManager.shared().currentAppleEvent` there gives the event. | From Finicky's source (MIT), not run by us. |
| Source app | `event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value` → `NSRunningApplication(processIdentifier:)`. Map helper processes (Electron/Chromium helpers, XPC) to their outermost `.app`. If the sender is a CLI tool (`open` from a terminal) it has often exited already: fall back to "unknown" (or walk parent PIDs while it's alive). Velja documents that terminals and `open` without `--wait-apps` can't be attributed reliably. | Unverified by experiment (sending ourselves Apple Events could trigger an Automation prompt). Finicky ships exactly this code. |
| Modifier keys | `NSEvent.modifierFlags` (class property, current hardware state) read when the event arrives. No Accessibility needed. fn is `.function`. | Documented API; not run. Risk: user releases the key before the event lands; read immediately on receipt. |
| Open in a browser | `NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration:)`; `.activates` for foreground/background. | Not run (no URL opening allowed in this study). |
| Chromium profile | Profiles in `~/Library/Application Support/<vendor dir>/Local State` → `profile.info_cache` (dir name → display name). Launch with `--profile-directory=<dir> <url>` and a **new instance** (`open -n -a <app> --args …`, or `OpenConfiguration.createsNewApplicationInstance = true` + `.arguments`); Chrome's singleton hands the URL to the running instance. Plain `.arguments` are ignored when the app is already running. Incognito: `--incognito`. | Mechanism from Finicky source. **Note**: on this Mac (macOS 27.2) listing Chrome's support folder from a terminal-spawned process failed with "Operation not permitted" while neighbouring folders were readable, which matches OpenIn 4.4.4's "macOS 27 profile-permission prompts". Expect a system consent prompt the first time we read another browser's data; profile discovery must degrade to manual entry. Unverified whether the prompt is per-app or per-folder. |
| Firefox profile | `profiles.ini` names, launch `-P <name>` (new instance); private: `-private-window`. | From Finicky source; unverified. |
| Safari profile / private | No API. Only GUI scripting of Safari's File menu (needs Accessibility, locale-sensitive) or AppleScript + System Events. | From public write-ups; unverified. Later. |
| Become default browser | `NSWorkspace.shared.setDefaultApplication(at: ourURL, toOpenURLsWithScheme: "http")` (macOS 12+). The system shows a consent dialog (from CoreServicesUIAgent) asking to keep the old browser or switch; completion runs after the answer. Chromium calls it for `http` and `https`. | Not run (it would change the default / show the prompt). Whether one call covers both schemes is unverified: call both, re-read with `urlForApplication(toOpen:)`. |
| Detect we lost default | `NSWorkspace.shared.urlForApplication(toOpen: URL("https://…"))` == our bundle. | **Verified** read-only: returns OpenIn.app on this Mac. Check on launch, wake and when Settings/menu opens. |
| Activation | macOS 14+ cooperative activation: a background app can't push another app frontmost. Call `NSApp.yieldActivation(toApplicationWithBundleIdentifier:)` (or yield to the app URL) before opening, then open with `activates = true`. OpenIn shipped fixes for browsers not coming forward (4.3.5, 4.4.0). | Unverified; must be in the test plan. |
| Login item | `SMAppService.mainApp.register()` (macOS shows a "login item added" notification). | Standard. |

### Permissions we'd ask for
- **None for the core flow.** Rules by host, source app (PID) and modifiers need no TCC
  permission. The picker is our own panel.
- **Reading other browsers' profile lists** may trigger a macOS 27 "access data from other
  apps" prompt (see above): ask only when the user opens the profile section, with one
  sentence why; on "no", allow typing a profile folder name.
- **Not in v1**: Accessibility / Automation (only needed for Safari profiles/private).
- Becoming default browser: the system dialog, triggered by our button only.

## UX patterns worth adopting

- **Silence when the answer is known.** No picker if a rule leaves one target; the picker is
  the exception, not the default experience.
- **Profiles are first-class targets.** "Chrome – Work" is just another entry in the list,
  with its own number key, not a nested choice.
- **Order is the keyboard map.** The list order in Settings is the 1–9 order in the picker,
  so muscle memory survives.
- **The same app can appear more than once** with different settings (profile, background,
  private), which keeps the rule model simple: rules pick targets, targets carry options.
- **A modifier as an escape hatch.** Holding a key while clicking overrides rules and asks.
- **Learning from the picker.** Turning a one-off choice into a rule from the picker itself
  is the fastest way to build rules; it just needs to be discoverable.
- **Stay resident.** The whole latency story rests on being already running when the link
  arrives (it's why "start at login" is on by default).
- **Watch for hijacks.** Browsers like to reclaim default status on update; noticing that is
  a real feature for a default-browser app.

## What we won't copy, and what we'll do better

- Not copying: name, icon, artwork, wording, the tutorial/release-notes windows, tips,
  icon-size options, paid/trial behaviour (the trial forces the picker every time).
- **Latency we can measure.** Our own budget: picker visible within one frame of the event;
  rule-matched links handed to the browser within ~20 ms of the event (no disk, no network,
  no script engine on the hot path; rules compiled in memory; icons cached at launch). Log
  timings in debug builds. A reviewer's 3–5 s delay complaint was answered with "it's the
  browser"; we want to be able to prove which side is slow.
- **No network, ever, on the hot path** (no redirect resolution).
- **Discoverable "always open here"** (⌘-pick, also shown as a hint line in the picker)
  instead of a hidden right-click; reviewers asked for it.
- **Show the link** (host) in the picker so you know what you're routing.
- **Fewer moving parts**: no JS engine, no helpers, no extensions in v1; one handler (web
  links) done really well. OpenIn's release notes are full of fixes for double-opening,
  focus and profile routing: we keep the surface small and test those exact cases.
- **Sensible default list**: only real browsers shown; dev tools that happen to register
  `https` are hidden until added.
- **Easy way back**: "Stop Being Default…" that hands default status back to a chosen browser.
- **Quiet**: default-status loss shows in the menu (and optionally a notification), not
  nagging alerts.

## Edge cases

- **Cold start**: link clicked while Switchboard isn't running → LaunchServices launches us
  with the event; handler must be registered before `didFinishLaunching`; measure cold path.
- **Several links at once** (e.g. "open all" from a list, or a second click while the picker
  is up): queue them; picker shows one at a time or offers "apply to all"; never drop or
  double-open (OpenIn had double-open bugs from Return + click races, duplicate tabs).
- **Picker dismissed** (Esc / click outside): link is dropped, deliberately; ⌘C before Esc
  keeps it. Consider "reopen last link" in the menu.
- **Picker placement**: cursor on secondary display, near screen edges (clamp to
  `visibleFrame`), over full-screen apps and other Spaces (`.canJoinAllSpaces`,
  `.fullScreenAuxiliary`), cursor hidden while typing (link opened by keyboard: use the
  centre of the active screen).
- **Keyboard focus**: non-activating panel must still receive 1–9/Esc without stealing the
  source app's focus permanently; Secure Input (password field focused) must not break it.
- **Activation**: target browser not running (cold), running with no windows, running on
  another Space, minimized, full screen.
- **Profiles**: profile renamed or deleted; browser with one profile; browser not running +
  profile argument; consent prompt denied; Local State unreadable or JSON changed.
- **Targets disappear**: browser uninstalled or moved → fall back to the picker, mark rule
  as broken in Settings.
- **Ourselves as a target / loops**: never list Switchboard; never hand a URL to an app
  whose default is us.
- **Source app unknown**: links from `open` in a terminal, from helpers, from the system
  (Spotlight, Notification Center); rules with a source condition simply don't match.
- **Modifiers**: released before the event arrives; Caps Lock must not count; fn on
  external keyboards (Velja notes some don't send it).
- **URLs**: IDN/punycode hosts, uppercase hosts, ports, `www.` vs bare domain, `user@host`,
  very long URLs (truncate in the middle for display), `localhost` and IPs, `file://` HTML.
- **Default status**: user declines the system dialog; another browser reclaims default
  after an update; we're quit/deleted while default (macOS falls back to Safari).
- **Sleep/wake, logout**: picker open across sleep; login item disabled by the user in
  System Settings.
- **Accessibility**: VoiceOver names each picker item ("1, Google Chrome, Work profile");
  Reduce Motion; dark/light; increased contrast.

## Our v1 scope

- [x] Registers `http`/`https` (and declares `public.html`/`public.xhtml` as Viewer so
      macOS treats it as a browser); "Make Default Browser…" button + live default status in
      menu and Settings; "Stop Being Default…" hands it back to a chosen browser.
- [x] Menu bar agent, launch at login (on once it's the default browser), receives GetURL
      events warm and cold without losing a link.
- [x] Browser list: discovered real browsers (known bundle IDs) + Chromium profiles as
      separate entries; reorder, hide, add any app; order = picker number keys.
- [x] Picker: non-activating panel at the cursor (clamped to screen), shows the link's host,
      1–9 / arrows + Return / click to open, Esc or click outside cancels, ⌘C copies;
      visible within one frame.
- [x] Rules, ordered, first match wins: conditions host (with `*.` wildcard, optional path
      prefix), source app, modifier keys held; action = open in a target or show picker.
      Final "Otherwise" row: show picker or open in a chosen target.
- [x] Holding the "ask" modifier (default ⌥, configurable) always shows the picker.
- [x] Opening brings the right browser and profile forward (cold and warm browser).
- [x] Settings: General (launch at login, show in menu bar, default browser status),
      Browsers, Rules (editor with "test a URL" field), About.
- [x] Latency check: rule-matched link handed off < 20 ms after the event, picker < 16 ms;
      measured in the test step.

## Open questions

1. **Fallback when no rule matches**: show the picker (roadmap spec, OpenIn's default) or
   open in a primary browser and use the picker only on modifier / no-match? This decides
   how often the picker appears and is the biggest UX call.
2. **Safari profiles / Safari private**: worth Accessibility permission + GUI scripting in a
   later version, or never? (The owner's installed browsers are Safari and Chrome, so this
   matters more than for most users.)
3. **Chrome profiles in v1** are listed as must because the owner uses Chrome; confirm, given
   the possible macOS 27 consent prompt to read Chrome's profile list.
4. **`.html` files and `mailto:`**: v1.1 or v1? Roadmap says "optional file handler"; I kept
   v1 to web links.
5. **History** (local, off by default) in v1.1? It's the one way to recover a link after Esc.
6. **Migration**: offer importing rules from OpenIn's backup or config? (Its config format
   wasn't inspected; it lives in OpenIn's group container and is personal data.)

## Decisions (owner defaults, 2026-11-02)

1. **No rule matches → show the picker.** Configurable in Rules: "When no rule matches" can
   open a chosen browser instead.
2. **Safari profiles / private windows → later.** Needs GUI scripting + Accessibility.
3. **Chromium profiles → v1.** Read from the browser's `Local State`. If macOS blocks the read
   (it does on this Mac, macOS 27.2: a silent EPERM, no prompt), the sheet says so, offers a
   Full Disk Access link, and lets the user add a profile by folder name. Never hangs: the read
   runs off the main thread.
4. **HTML files → v1** (declared as Viewer; picker shows the file name). `mailto:` → v1.1.
5. **Link history → v1.1.** v1 keeps only the last dismissed link in memory ("Reopen <host>" in
   the menu).
6. **Import from OpenIn → later.**

## Build notes (step 3–4, 2026-11-02)

### Gap review: v1 scope

| v1 item | Status | Evidence |
|---|---|---|
| Registers http/https + public.html/xhtml; Make Default Browser…; live status; Stop Being Default… | Done, partly unverified | Info.plist checked. Status reads correctly ("isn't your default browser"; OpenIn is). The make-default and hand-back buttons were **not pressed** (owner's machine: never change the default browser); code calls `setDefaultApplication` for http, https and .html. |
| Menu bar agent, launch at login once default, warm + cold delivery | Done | Warm: picker 7–15 ms after the event. Cold (link launches the app): handled, picker in 69 ms. Found and fixed a bug where the picker pre-warm dropped the launching link. Launch-at-login auto-enable is tied to becoming default (not exercised, see above). |
| Browser list: known browsers, Chromium profiles as entries, reorder/hide/add any app, order = number keys | Done | Discovery hides non-browsers (terminal, AI tools) and other link routers (OpenIn). Hide, move, add profile (manual folder), "Choose App…" all walked through. Picker numbering follows list order. |
| Picker: non-activating at cursor, host shown, 1–9 / arrows+Return / click, Esc / click-away cancels, ⌘C copies | Done | All keys walked through with posted and real (system-wide Esc) keyboard events. Unicode hosts shown decoded, long paths middle-truncated, 11 targets wrap at 6 per row, numbers stop at 9. ⇧ = background, ⌘ = "always open here" (creates/updates a host rule, HUD confirms). |
| Rules: ordered, first match, host (`*.` wildcard) + path prefix, source app, modifiers; Otherwise row | Done | 57 unit tests. Rule created in the editor from a pasted URL (split into host + path), verified routing. Source app attribution verified with a test app (`source=app.slopapp.test.linksender`); links from `open` in a terminal are unattributed (expected). |
| Holding ⌥ (configurable) always shows the picker | Done | Verified with a synthetic ⌥ hold: rule overridden, `reason=askModifier`. |
| Right browser/profile comes forward, cold and warm | Done (warm), partly cold | Chrome came forward from a rule and from the picker; Chrome profile launch hands off to the running Chrome (one process remains). Cold browser not tested (both browsers were running and in use). |
| Settings: General, Browsers, Rules (with tester), About | Done | Light and dark screenshots reviewed. |
| Latency: rule match < 20 ms, picker < 16 ms | Done | Rule → Chrome: decide 0.1 ms, event → handoff 10.1 ms (real open). Picker visible 6.8–15.9 ms warm (one 19 ms outlier). Profile targets: ~150 ms (a short-lived browser process does the handoff). |

Also fixed during testing: queued links stalled after a rule-matched one; focus stayed on the
(windowless) Switchboard after Esc/⌘C/background opens (macOS activates the default browser on
every link), now handed back; duplicate "Add Rule" accessibility names; Delete key could remove
a rule while typing (now ⌘⌫); deletions now undoable (⌘Z).

### Design-system checklist (§10)

| # | Item | Result |
|---|---|---|
| 1 | Main job in one shortcut/click | Pass: links route with no UI, or one keypress in the picker |
| 2 | Native look, light + dark | Pass: system materials, accent selection, no hex colors |
| 3 | Keyboard + menus | Pass: picker fully keyboard; menu items carry shortcuts; lists: ⌘⌥↑/↓ move, ⌘⌫ remove, Return edits a rule |
| 4 | Esc / ⌘, / ⌘Q | Pass |
| 5 | Settings General + About | Pass |
| 6 | Copy (HIG case, verbs, no !) | Pass |
| 7 | Empty states | Pass: Browsers and Rules use ContentUnavailableView with one action |
| 8 | Permissions only when needed | Pass: none required; profile access failure explains itself with a Settings link |
| 9 | Destructive actions undoable | Pass: remove browser / delete rule register ⌘Z |
| 10 | No network | Pass: no networking code |
| 11 | Performance budgets | Pass: launch 172 ms, first icon 323 ms, idle CPU 0.03 %, footprint 24.8 MB |
| 12 | VoiceOver names | Pass with a tooling note: `drive tree` flags Settings switches/pop-ups as `[unlabeled]`, but each has `AXTitleUIElement` pointing at its label (VoiceOver reads it). SlopDrive should follow `AXTitleUIElement`. |
| 13 | Reduce Motion | Pass: picker selection animation off under Reduce Motion |
| 14 | Window state persists | Pass: SwiftUI Settings window |

### Known risks

- Making Switchboard the default browser, handing it back, and the auto login item were never
  exercised on this machine (deliberately). First real test: on a spare account or by the owner.
- The picker's focus behaviour depends on macOS activating the default browser for each link;
  verified with a test app's `NSWorkspace.open`, which is the same path real apps use.
- Chrome profile list unreadable under macOS 27 privacy rules without Full Disk Access; the
  manual folder entry is the fallback.
- Safari-in-front activation from the picker was inconclusive (Safari was already in front during tests).

## Sources

- OpenIn product page and FAQ: https://loshadki.app/openin4/
- OpenIn on Setapp: https://setapp.com/apps/openin and reviews https://setapp.com/apps/openin/customer-reviews
- OpenIn on the Mac App Store (version history to 4.5.2): https://apps.apple.com/us/app/openin-4-advanced-link-handler/id1643649331?mt=12
- OpenIn 4.3 release post: https://www.producthunt.com/p/openin-app/openin-4-3
- The Sweet Setup review: https://thesweetsetup.com/taming-links-on-macos-with-open-in/
- Velja (comparable app, features and FAQ on attribution/profile limits): https://sindresorhus.com/velja
- Finicky source, MIT (GetURL handler, sender PID, profile launch): https://github.com/johnste/finicky
- Apple: `setDefaultApplication(at:toOpenURLsWithScheme:completion:)` https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:)
- Chromium `shell_integration_mac.mm` (default-browser consent dialog): https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/shell_integration_mac.mm
- Safari private/profile scripting limits: https://mjtsai.com/blog/2023/12/11/opening-urls-in-private-safari-windows , https://forum.popclip.app/t/support-for-safari-profiles/2186
- Installed OpenIn 4.3.5: Info.plist, entitlements, App Intents metadata, Settings panes via
  `scripts/drive` (read-only).

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-02)

Blind tester, first round. Triage by the coordinator, confirmed in the fix round. All fixes
verified on an isolated copy of the build (own bundle id and settings), because the owner made
the real build their default browser during the round.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 A full URL pasted into Website (`https://www.example.com/blog/post?x=1`) saved a rule that never matched | major | Accept | `Rule.parseWebsite` drops scheme, user info, `www.`, query and fragment, and splits off the path. The editor shows what will be saved ("Matches: example.com/blog/post") or why it can't be ("“my site” isn't a website…"), and Save is disabled until the rule can match. 10 new unit tests. |
| F2 Removing a browser silently repointed its rules to the picker; re-adding didn't restore them | major | Accept | Rules keep their target. Removed targets that rules (or "When no rule matches") still use are kept in `removedTargets`. Removing asks first ("1 rule uses Safari. Remove it?"). Rules show "Safari (missing)" in orange and fall back to the picker at runtime. Adding the same browser/profile back reuses its identity, so rules reconnect, with a toast. The VoiceOver label now says "shows the picker" / "opens in X, which is missing, so it shows the picker". |
| F3 ⌘-pick inserted its rule at the top, hiding more specific rules | minor | Accept | A learned rule goes just below the last rule it would hide, else at the top (`Router.learnedRuleIndex`). The confirmation toast has an Undo button (clickable, never takes focus), plus "Undo “Always Open host”" in the menu bar menu. Rules that can never match get a warning icon and a caption ("Rule 3 is never used: rule 2 above it catches the same links first…") via `RuleAnalysis.shadowing`. |
| F4 Picker cut long hosts from the end, hiding the registrable domain | minor | Accept | The host truncates from the front, and the path moved to its own line. The header is at least 320 pt wide. |
| F5a ⇧ (background) with Chrome still brought Chrome forward | minor | Investigated: not ours | We open with `activates = false`. Reproduced without Switchboard: a plain `NSWorkspace.open(…, activates: false)` to Chrome brings Chrome forward. Chromium activates itself. Documented in the target's options when "Open in the background" is on for a Chromium browser. |
| F5b With Settings open, focus stayed on Switchboard instead of returning to the previous app | minor | Accept (partly ours) | A normal pick with Settings open does bring the browser forward (verified). But Esc, ⌘C, refused links and background opens kept focus on Switchboard when its Settings window was open. Switchboard now tracks the last other active app (event-driven) and returns focus there. |
| F6 Becoming the default browser silently turned on Launch at login | — | Reject as a bug, made visible | Intended (links shouldn't wait for a launch). There's now a toast when it happens and a line under Default browser in General explaining it, with the toggle right above. |
| F7 Delete key didn't remove a selected browser/rule | nit | Accept | `onDeleteCommand` on both lists: Delete works when the list has focus and appears as Edit › Delete. The ⌘⌫ button shortcut was removed: it fired even while typing in the link tester. Verified: Delete/⌘⌫ in the tester field don't touch rules. Removal is still undoable with ⌘Z. |
| F8 Profile sheet fields were labelled by their placeholders | nit | Accept | Fields are labelled "Name" and "Folder". |
| F9 Settings window height jumped on selection and while typing in the tester | nit | Accept | The Browsers options area has a fixed height and the tester result line is always present, so selecting a row or typing no longer resizes the window. Different tabs keep their own height (standard macOS). |

Not reachable by the tester's tools, covered by our own tests this round: holding ⌥ forces the
picker over a matching rule; a ⌘-only rule matches with ⌘ held and not without; a source-app
rule matches links from that app (`source=app.slopapp.test.linksender`); activating another
app dismisses the picker.

Gates after fixes: 68 unit tests (16 suites) pass; `scripts/check.sh Switchboard --perf` green
(first menu bar icon 244 ms, idle CPU 0.025 %, footprint 24.9 MB).

### Round 2 (2026-11-03)

New blind tester. No blockers or majors, so the exit criterion is met once the minors are fixed
or deferred. All verified on the isolated test copy; the owner's live build was only rebuilt
and relaunched.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 Settings… from the status menu opened the window inactive, behind the front app (⌘W disabled) | minor | Accept | Cause: SlopKit's `MenuFooter` uses macOS 14's cooperative `NSApp.activate()`, which a background menu bar app can be refused. Switchboard now has its own footer that activates (`activate(ignoringOtherApps:)`) and makes the Settings window key on the next run-loop turn. Verified the app is active after Settings…. **SlopKit should adopt this**; Awake has the same footer. |
| F2 Open Link from Clipboard ignored a matching rule (first browser highlighted) | minor | Accept | When the picker shows anyway (clipboard, Reopen, `pick=1`, ⌥ held), it preselects what the rules would choose (`Router.preferredTarget`), including a "When no rule matches" browser. Verified: forced iana.org link → Return opened the rule's Safari. |
| F3 Website "*." or "*" silently made a match-everything rule | minor | Accept | Refused inline: "“*” would catch every link. To choose where links no rule matches go, use “When no rule matches”…". With other conditions: "Leave Website empty instead." |
| F4 After deleting a rule, Edit ▸ Undo stayed disabled | minor | Accept | Root cause was F1: the Settings window wasn't key, so the Edit menu didn't see its undo history. Verified Edit ▸ Undo restores a deleted rule once the window is key. And because a menu bar app's menu bar is never visible, an "Undo Delete"/"Undo Remove" button now appears next to the list for 10 s after a deletion. |
| F5 A rule requiring ⌥ collides with "Always show the picker while holding ⌥" | minor | Accept | Decision: the "always show the picker" key wins (it's the escape hatch). The rule sheet warns while editing (saving is still allowed, the setting may change), and the list flags such rules as never used with the reason. `Rule.isBlocked(byAskModifiers:)`, `RuleAnalysis.unused`. |
| F6 Manual Chrome profile folder wasn't validated | minor | Accept | The sheet checks the folder exists (an existence check works even when macOS protects the profile list): "Found this profile folder." or a warning that a wrong name makes Chrome create a new, empty profile. Adding is still allowed. |
| F7a "1 rule … Those rules" grammar | nit | Accept | Singular/plural message, plus a variant when only "When no rule matches" uses it. |
| F7b + menu listed browsers already added | nit | Accept | Listed ones show "(Added)" and are disabled; hidden ones stay enabled (adding shows them again). |
| F7c Row separator only under the first row | nit | Accept | Separators hidden in both lists. |
| F7d Browsers tab had excess empty height | nit | Accept | The list is as tall as its rows need (110–240 pt). The options area shrank to 132 pt: the profile folder moved into the title line and the Chrome note became one line. |
| F7e Smart punctuation in the Test-a-link and Website fields | nit | Accept | Autocorrection off; curly quotes and dashes are converted back as you type (`LinkParser.plainText`). |
| F7f Odd accessibility frames on −/↑/↓ | nit | Accept | Icon-only Labels with a 20×20 hit area; frames now report 20×20. |
| Missing: link inside surrounding clipboard text | — | Accept | `LinkParser.webLink(in:)` falls back to the first http(s) or www. link inside the text (NSDataDetector), ignoring bare words like "file.txt". |
| Missing: Safari private window | — | Defer | Needs Accessibility scripting of Safari's menus (see feature #12/#13). Noted in the README. |

Gates after fixes: 74 unit tests (17 suites), bundle and smoke pass. Perf: launch 146–152 ms,
first menu bar icon 309–342 ms, footprint 25–26 MB all pass. Idle CPU passed once (0.020 %) and
then measured 0.29–0.40 % while other agents were driving apps in parallel. A back-to-back
control showed unchanged Awake at 0.33 % and Switchboard at 0.29 %: the extra work is AppKit
redrawing the menu bar icon (`NSStatusItem _updateReplicants`) on every app switch, not
Switchboard code. Re-measure on a quiet machine. `perf.sh` also intermittently fails with
"no running app matches" (on Awake too): a tooling race in its quit/relaunch loop.
Status → beta, version 0.2.0 (build 2).


## Parity pass (2026-11-03)

Owner request: "Switchboard should show the browser options in a vertical list rather than a
horizontal one." Plus a parity check against OpenIn (see `docs/parity-pass.md`).

### How OpenIn presents choices (studied read-only)

From its official website screenshots (downloaded to `/tmp/switchboard-parity/`, not
committed): a tall rounded panel with **one row per target**: large app icon, app name with a
smaller profile/"Private" line under it, the **number key at the right**, a **"…" button per
row**, a rounded grey highlight on the selected row, and the **URL along the bottom** with a
share button. ↑/↓ move, Return opens, or press the number. The installed copy wasn't triggered
(it would need a link routed through it) and its settings weren't touched.

### What we built

- **Vertical list picker.** Each row: app icon, app name, a second line for profile / Private /
  Background, the number key (1–9) as a small key cap on the right. The selected row uses the
  system selection colour (follows the accent colour, like a menu item). The host and the path
  line sit at the top (the owner asked for it there; OpenIn has the URL at the bottom), with a
  copy button (⌘C). Hint line at the bottom.
- **Keyboard:** ↑/↓, Tab/⇧Tab (wrap around), Home/End, Return/Space/Enter, 1–9, Esc, ⌘C; ⌘ =
  always open here, ⇧ = background, as before. ←/→ no longer move (vertical list).
- **Row actions** (OpenIn's "…" and right-click): the highlighted row shows a "…" menu; every
  row has the same context menu: Open, Open in Background, Always Open <host> Here. Also exposed
  to VoiceOver as named actions.
- **Matched row highlighted:** when the picker shows anyway (⌥ held, clipboard, `pick=1`), the
  row the rules would choose is preselected (unchanged logic, verified in the new list).
- **Fits any screen:** the list is sized for the pointer's screen; with many browsers it
  scrolls (half a row peeks out at the bottom) and the keyboard selection stays scrolled into
  view. The panel is placed under the pointer and clamped to the visible frame (SlopKit
  `PanelPlacement`). Geometry is pure and unit-tested (`PickerLayout`).
- **Hover only selects after the pointer moves,** so a panel that opens under a resting pointer
  keeps the rules' preselection.
- **Picker size** (General → Picker size: Small / Medium / Large): parity with OpenIn's icon
  size setting (it has five steps; three cover it).
- **Remove tracking from links** (General, off by default): drops `utm_*`, `fbclid`, `gclid`,
  `msclkid`, `mc_eid` and similar before matching/opening; other parameters keep their order
  and encoding. OpenIn ships this as a sample script; ours is an offline list.

### Gap table vs OpenIn

| OpenIn feature | Status | Notes |
|---|---|---|
| Vertical app-selection list, number keys, ↑/↓ + Return | Done | This pass |
| Per-row "…" / right-click actions | Done | This pass. Open / Background / Always Open Here |
| URL shown in the picker + share/copy | Done | Top of the panel (owner's choice); copy button + ⌘C |
| Icon size setting | Done | Small / Medium / Large |
| Reduce animation setting | Done differently | The list has no animation at all (menu-like) |
| "Always show even with one app" | Rejected | Rules decide; holding ⌥ forces the picker |
| Rebindable picker keys (letters) | Deferred (S–M) | Needs a key editor per target and collision checks; 1–9 cover nine targets |
| Default browser, warm/cold links, rules, source app, modifiers, profiles, private (Chromium/Firefox), background, ⌘-learn, copy, `.html`, own URL scheme, watchdog, menu bar icon | Done | Earlier rounds |
| Tracking-parameter removal | Done | This pass, off by default |
| Firefox profiles | Deferred (S) | `profiles.ini` + `-P`; Firefox isn't installed here, so it couldn't be verified |
| Safari profiles / Safari private | Deferred (L) | Needs Accessibility scripting of Safari's menus |
| Mail links (`mailto:`) handler | Deferred (M) | Second handler, app list and rules UI; becoming the default mail app can't be tested on the owner's Mac |
| Link history window | Deferred (M) | "Reopen <host>" covers the last dismissed link; a history needs a retention setting and search UI |
| Services menu / Share extension | Deferred (S / L) | Services entry is small but needs `pbs` refresh and another app's Services menu to test (real mouse); Share extension is a separate target SwiftPM can't build |
| Shortcuts / App Intents | Deferred (M) | SwiftPM doesn't run the App Intents metadata processor, so intents wouldn't register without Xcode build steps |
| Handoff | Deferred (S) | Can't be verified without a second device |
| URL rewrite per target | Deferred (M) | Regex editor per target |
| Backups (export/import) | Deferred (S) | Not everyday; config is one JSON file |
| Focus hint, JS scripts, zsh targets, redirect resolving, browser extensions, phishing check, tel: | Skip | As decided in the inventory (network, power-user, or separate products) |

### Design-system deviations

- Picker rows use the **system selection colour** (`selectedContentBackgroundColor` +
  `selectedMenuItemTextColor`) rather than a tinted accent wash, to read like a menu item.
  System colours only, no hex.
- None otherwise: SF Symbols in UI, system type, glass/material panel from SlopKit.

### Gates (2026-11-03)

- Unit tests: 91 tests in 21 suites pass (17 new: list layout, keyboard selection, row
  subtitles, tracking parameters, config compatibility).
- `scripts/check.sh Switchboard --perf`: all PASS. Launch 150 ms, first menu bar icon 333 ms,
  idle CPU 0.008 % (lowest) / 0.027 % (median), footprint 29.0 MB (busy machine, load 4.6).
- Picker latency (event → visible, release build, warm): 6 browsers 7–13 ms; 30 browsers
  (Large, scrolling) 14–20 ms. Prewarm now also measures the header/footer and builds the
  scrolling layout, which took the first long-list show from 42 ms to 20 ms. One 60 ms show
  happened right after changing the size with Settings open (one-time re-layout).
- Scripted walkthrough on an isolated copy (bundle id `app.slopapp.switchboard.paritytest`, no
  URL/document type claims, `SWITCHBOARD_CONFIG` + `SWITCHBOARD_DRY_RUN`), links sent with
  `open -a`: ↓↓ Tab ⇧Tab ↑ moved the selection as expected; Return opened the selection; 3
  opened Chrome Work with `--profile-directory`; ⇧4 opened with `activates=false`; Esc
  dismissed; ⌘2 created a learned rule; a forced picker preselected the rule's Chrome Work row;
  the "…" menu opened over the panel without dismissing it and "Open in Background" worked;
  30 targets scrolled with the selection kept in view; Small size and tracking removal were
  set in Settings and took effect (`?id=5&utm_source=…&fbclid=…` → `?id=5`). Real-mouse click
  on a row opened that row's profile.
- **Not tested: owner active.** Right-click context menu with the real mouse (the owner was
  using the Mac in every window over ~15 minutes; the same actions were verified through the
  "…" menu, which shares the code). Hover selection wasn't exercised separately (SlopDrive has
  no pointer-move without a click). ⌘C wasn't pressed (it writes the real clipboard; the code
  path is unchanged from earlier rounds).
- `drive tree`: no `[unlabeled]` controls in the picker (rows "1, Safari", "More for Safari",
  "Copy Link"); each row is its own accessibility group so the "…" menu follows its row.
- Live build: the test copy was quit, unregistered (`lsregister -u`) and deleted. Then
  `build/Switchboard.app` was rebuilt by `check.sh`, relaunched, and confirmed running and
  still the default for http, https and `.html`. Every existing setting is unchanged; the
  settings file gained the two new keys at their defaults (`pickerSize: medium`,
  `stripsTrackingParameters: false`).

Screenshots (`/tmp/switchboard-test/`, not committed): `picker-light.png`,
`picker-dark.png`, `picker-preselect-2.png`, `picker-30-scrolled.png`,
`picker-small-dark-1.png`, `picker-row-menu-1.png`, `settings-general-dark.png`.

## Polish pass (2026-11-05)

Brief: `docs/polish-pass.md`. All work on an isolated test copy (bundle id
`app.slopapp.switchboard.polishtest`, no http/https/html claims, `SWITCHBOARD_CONFIG` +
`SWITCHBOARD_DRY_RUN` fixtures under `/tmp/switchboard-test/`), built with the same SDK stamp as
`bundle.sh`. The test copy was quit, unregistered and deleted at the end. The live build was
only rebuilt once, by `check.sh`, then reopened right away.

### Defects (before → after, measured with `scripts/measure` on @2x shots)

| Surface | Defect | Before | After |
|---|---|---|---|
| Picker | Panel radius literal | `FloatingPanel(cornerRadius: 16)` | default `Radius.xl`, read back as `floatingPanelCornerRadius` |
| Picker | Selection not concentric with the panel | radius 8 at 6 pt inset in a 16 pt panel | inset `Spacing.s` (8), radius `Radius.nested(in: 16, padding: 8)` = 8; pill 8 pt from both sides |
| Picker | Separators heavy | `Divider` 1.0 pt | `Hairline` 0.5 pt (one device pixel), `separatorColor` |
| Picker | Header text column off the name column | host at x 36, names at x 57 | both at x 56 (AX: 72 = panel 16 + 56) |
| Picker | Header symbol not on the icon column | link glyph at x 15, icons at 14–16.5 | glyph centred in the icon column (centre 32 = 16 + 32/2) |
| Picker | Icon inset uneven inside the highlight | 6 pt above/below, 8 pt beside | 8 pt on every side (row = icon + 2 × 8; Small 40, Medium 48, Large 60; unit test) |
| Picker | Off-grid padding | list 6, header 10, row gap 10 | 8, 12, 8 |
| Picker | Copy button and key caps not on one column | copy centre 277, key centre 276; key cap radius 5 literal | both in a 20 pt slot 16 pt from the edge (AX 280–300); key cap `Radius.xs` |
| Picker | Rows past 9 put "…" in the wrong place (no key cap to offset from) | "…" 38 pt from the row edge, empty slot at 8 | key and menu slots always reserved; "…" 8 pt before the key column on every row |
| Picker | Long name re-truncated when its row was highlighted, and cut mid-word | "Safari Technol…tended Edition" | tail truncation, constant width: "Safari Technology Preview…" |
| Picker | File names cut from the front (rule for hosts) | "…for the picker test page.html" | middle: "A very long fil…test page.html" |
| Picker | Footer text inset | 12 pt | 16 pt, same edge as the icons |
| Toast (⌘-pick) | Radius literal 14, `.hudWindow` material, different from the HUD | 14 pt rounded rect | SlopKit `FloatingPanel` glass capsule (48 pt tall, radius 24); Undo is a capsule 12 pt from the top, bottom and trailing end, so concentric; fades out like the HUD |
| General | Explanations were their own form rows (orphan rows with separators) | 7 rows, 422 pt window | subtitles of Default browser and Remove tracking: 5 rows, 397 pt |
| General | Default state "Switchboard" in plain green text | `.green` text | secondary text, green check symbol |
| General | Recovery notice in `.orange` | ~2.2:1 | `.textOrange` + warning symbol |
| Rules | Warning caption and missing browser in `.orange` | 2.25:1 | `.textOrange` 4.57:1 |
| Rules | Tester hint in `.tertiary` | 1.64:1 | `.secondary` 3.11:1 (antialiased sample; the system floor) |
| Rules | Arrows ragged, right-aligned destinations | arrows at x 290–440 | fixed 180 pt destination column, arrows in one column at x 274 |
| Rules | Warning icon pushed the condition text right | conditions at x 51 and 75 | icon after the text, conditions all at x 51 |
| Rules | Yellow multicolour triangles next to orange text | mixed | all `.textOrange` |
| Rules | Grouped form doubled the margins | caption → section 35 pt, bottom margin 41 pt | 12 pt and 21 pt (form margins taken back; its background hidden so it can't cover the caption) |
| Rules | "(missing)" pushed long names out | "Firefox Developer Edition (missing)" | orange name + warning symbol, with the full name in the tooltip and VoiceOver label |
| Rule editor | Modifier keys different widths, uneven gaps | 35/37/37/36 pt, gaps 16–17 | 44 pt each, gaps 8 |
| Rules, empty | Symbol pushed out of a 180 pt frame; description wrapped to 3 lines with an orphan word | no symbol | symbol back, two-line description, `minHeight` 240 |
| Browsers, empty | Bare "+" as the only action, plus the irrelevant reorder caption; removing the last browser hid its Undo | "+" | "Add Browser" menu button, Undo Remove next to it, no caption |
| Browsers | "Not installed" and missing-folder note in `.orange` | ~2.2:1 | `.textOrange` |
| Browsers | Removal message named the app, not the profile | "until you add Google Chrome back" | "until you add Google Chrome (Work) back" |

Checked and fine as is: About (SlopKit), menu bar menu (system menu, follows the system
appearance), profile sheet layout, 30-target scrolling (selection stays in view; rows past 9
keep their columns), the waiting-links footer, light and dark everywhere.

### Test hooks added

- `SWITCHBOARD_ASSUME_DEFAULT=1`: shows the "is the default browser" state (General, menu)
  without being it.
- `SWITCHBOARD_SETTINGS_TAB=general|browsers|rules|about`: opens Settings on that tab at launch,
  through the app menu's Settings… item. Added because the screen was locked for about 25 minutes
  mid-pass, and window captures still work then but Accessibility doesn't.
- `SWITCHBOARD_DRY_RUN=1` now also logs default-browser changes instead of making them, so a
  test copy can never change the real default.

### Gates

- `scripts/lint.sh Switchboard`: pass (5 radius literals before, 0 after).
- 92 unit tests in 21 suites pass (new: the icon inset is even in every size).
- `scripts/check.sh Switchboard --perf`: all PASS. Launch 163 ms, first status item 379 ms,
  idle CPU 0.004 % (lowest) / 0.010 % (median), footprint 29.2 MB (busy machine, load 4.8).
  Picker event → visible 13–20 ms warm (6 targets), 30 ms for 30 targets (Large, scrolling).
- `drive tree`: 0 `[unlabeled]` in Settings, the rule sheet and the picker. Close button 16×16.
- Live build: running, and the default for http, https and `.html`
  (`NSWorkspace.urlForApplication(toOpen:)` → `build/Switchboard.app`).

### Not done

- **Hover and right-click with the real mouse: not tested (owner active / screen locked).**
  Hover selection is the same code as before; selection and keyboard focus were checked.
- Profile sheet in its loaded state: not shot. It would show the owner's real Chrome profile
  names. Only colours changed there.
- Curly apostrophes: Switchboard's UI uses straight `'` like the rest of the suite and SlopKit.
  Changing one app alone would make it inconsistent, so that's a suite-wide decision.
- Browsers list: the height estimate (34 pt per row) can end the list exactly on a row edge,
  so it's not obvious that it scrolls. Cosmetic; left for a later pass.

Screenshots (`/tmp/slopapp-polish/switchboard/`): `before/` (picker-light, picker-rich-light,
picker-rich-dark, general-light, browsers-light, browsers-selected-dark, rules-light,
about-light, rule-editor-new-light-1, menu-light) and `after/` (picker-rich-light/-dark,
picker-small-light, picker-large-light, picker-30-end-dark, picker-waiting-dark,
picker-file-light/-dark, toast-light, general-light/-dark, general-default-light/-dark,
browsers-light/-dark, rules-light/-dark, about-light/-dark, empty-browsers-light/-dark,
empty-rules-light/-dark, rule-editor-new-light-1, remove-confirm-light-1, menu-default).

### Golden Gate + light/dark (2026-11-06)

Follow-up for the owner's "optimized for dark/light mode and fit in with macOS Golden Gate"
(design system §4 "Fitting in on macOS 27 Golden Gate", §10 items 25–26). Same isolated test
copy as above, deleted again at the end.

| Check | Finding | Change |
|---|---|---|
| Menus text-only | Status menu, picker row "…" pull-down and right-click menu, Add menu, rule context menu: all plain text already. The browser icons in the picker are information, so they stay. | None needed |
| Sidebars | Switchboard has none (Settings uses the standard tab toolbar) | n/a |
| Toolbar | Standard SwiftUI Settings toolbar, system glass | None |
| Inactive windows | Settings lists, checkboxes and the selected tab grey out when another of our windows (About) is key, light and dark (`gg/browsers-inactive-*.png`). The picker's highlight was always `selectedContentBackgroundColor`. | The picker highlight now follows `appearsActive`: unemphasized grey and primary text when not key. It's normally key whenever it's visible; seen once while it was being dismissed (`gg/picker-dark-resigning-key.png`). |
| "…" button colour | On the blue highlight, light mode drew the dots dark (#0C2852, 3.47:1). A borderless menu takes the tint, not the foreground style. | `.tint(selectedText)`: white in both modes (#FFFEFF) |
| Glass | Picker and Undo toast use SlopKit `FloatingPanel` (regular glass, follows the clear/tinted setting); no hand-made translucency | None |
| Hairline | Now SlopKit's (1 pt layout, pixel on its top edge); my in-app copy is gone. Panel 398 → 399 pt. Gaps: row → drawn line 8.5 pt above the list, 8.0 pt below (only at 2×). | Left as is: fixing it means reading the display scale during layout, which SlopKit avoids on purpose |
| Menu footer | Switchboard's own footer (activation workaround) is now in SlopKit | Uses SlopKit `MenuFooter` |
| Reopen opens Settings | Checked on the test copy: a rule-matched link, a picker link, a forced `switchboard://` link and an `.html` file never opened Settings, and a link that cold-launches the app shows only the picker. Opening the app again (`open -a` with no link) opened Settings. | Kept `opensSettingsOnReopen` on: links arrive as GetURL/open-document events, never as reopen. Reopening the app is the way back in when the menu bar icon is hidden. |
| Live appearance change | New hook `SWITCHBOARD_FLIP_APPEARANCE_AFTER`: started light, flipped to dark while running. The pre-drawn picker, Settings (incl. `.textOrange`) and the toast all follow (`gg/flip-*`). | Hook added (README) |
| Drawn black/white, shadows, layers | None in the code (grep: no `.black`/`.white`, `cgColor`, layer colours or custom shadows) | None |

Contrast, light | dark (window captures): warning/missing text 4.57 | 6.85:1, tester hint 3.11
(antialiased `.secondary`) | 5.68:1, white on the picker highlight 4.19 | 4.84:1.

**Open (SlopKit): the regular glass lightens opaque fills inside it.** The system
selection colour is #0064E1 (5.37:1 with white), but inside the picker it draws as #347AE0
(4.19:1 in light). Last pass it drew #406EDD (4.67:1) under the earlier glass style.
`compositingGroup()` doesn't change it. A window capture shows the glass over flat grey rather
than the real backdrop, and an on-screen capture would include the owner's content blurred
behind the panel, so on-screen contrast and the clearest glass setting (would need changing
System Settings) weren't measured.

Gates: lint pass; 92 tests pass; `scripts/check.sh Switchboard --perf` all PASS (launch
148 ms, first status item 338 ms, idle CPU 0.006 % lowest, footprint 32.3 MB, load 7.6).
Live build running and default for http/https/`.html`; its config file and defaults are
identical to the pre-gate backup.

Light | dark side by side: `/tmp/slopapp-polish/switchboard/gg/sbs/` (picker, general,
browsers, browsers-inactive, rules, about, empty-browsers, empty-rules, toast). Singles,
flip shots, menus: `/tmp/slopapp-polish/switchboard/gg/`.
