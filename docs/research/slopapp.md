# Slopapp research (inspired by Setapp's Mac app)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: Setapp
> desktop 3.58.0 (163) (installed copy at /Applications/Setapp.app and its agent at
> ~/Library/Application Support/Setapp/LaunchAgents/Setapp.app, read-only) + Setapp's help
> center, developer docs and public reviews, on 2026-11-02. We study how it works so we
> don't reinvent the wheel. We never copy its name, icons, artwork, wording, sounds or
> signature visuals.
>
> The agent (SetappAgent) was already running and was left running. The main app was
> launched for the walkthrough and quit afterwards. Nothing was installed, updated,
> uninstalled, opened, toggled or signed in/out. The owner's account, membership,
> installed apps, update list and notifications are personal: only their layout is
> described here. The owner has Setapp's menu bar icon turned off, so the status menu
> couldn't be opened without changing a setting; it's described from the Settings pane
> and its strings.

## The job

Slopapp is the hub for the suite. People use it to find out which small utilities exist,
install one in a click, keep them all current without visiting websites, and remove them
cleanly. They open it in bursts: when setting up a Mac, when they need a tool for
something ("is there one that converts video?"), or when the menu bar says updates are
waiting. Success means the app is in Applications, opened, verified as ours, and the
user never handled a zip, a Gatekeeper warning or a download folder. **The interaction
that matters most: find an app (search or browse), press Install, see progress inline,
and the button turns into Open.** Second: one glance at the menu bar shows "2 updates",
one click on Update All, done.

## Who and when

- New Mac or first visit: browse Discover, install three or four apps in a row.
- Looking for a tool for a task: type a task word or the name of a paid app they know
  ("Paste", "CleanShot") and find our alternative.
- Updates are waiting: the count in the menu bar or the Updates sidebar item gets a click,
  then Update All.
- Tidying up: uninstall an app they stopped using, sometimes with its settings too.
- Launching: open an installed app from the menu bar list instead of Finder or Spotlight
  (less common; Spotlight/Raycast users rarely do this).

Frequency: the library window a few times a month, a couple of minutes each time. The
menu bar item and background check run all the time and must cost nothing.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason).

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Library window with sidebar | ~1100×640 window. Sidebar: personal dashboard, Favorites, My Apps, Collections, How-tos, App Guides, All Apps (with five task categories indented under it), AI category, Updates (with a count badge). Back/forward arrows sit above the sidebar. | must | `NavigationSplitView`: Discover, Installed, Updates (count badge), Favorites, then All Apps with the categories indented under it (parity pass). |
| 2 | Discover / home | A long scrolling dashboard: banner carousel (promos), ranked "best of" chart, how-tos, personal recommendations, collections, guides, new arrivals, recently updated. | must | One grid of all our apps grouped by category headers. ~30 apps fit on one page; no carousel, no promos. |
| 3 | "New" / "Recently updated" rows | Dedicated rows on home; cards carry NEW / HOT badges. | should | A small "Recently updated" row at the top of Discover, from feed dates. No HOT badges. |
| 4 | Categories | Five task categories in the sidebar, each a grid page with a title and one-line description. | should | Section headers inside Discover (and a category filter menu in the toolbar if cheap). Not sidebar items. |
| 5 | App card | Icon, name, short pitch, rating %, platforms, NEW badge. Install/Open/Update button appears on the card (hover/selection). | must | Icon, name, tagline, state button always visible (not hover-only: discoverable and VoiceOver-friendly). |
| 6 | Search | Toolbar search field, ⌘F ("Search All Apps"). Searches by name and by task. Remembers search history (setting). Has a funny empty state for no results. | must | `.searchable` across name, tagline, category, **and the paid app it replaces** ("Paste" finds Clips). Plain empty state. No history. |
| 7 | App detail page | Big icon, name, tagline, rating, primary button with disclosure menu, Favorite and Share buttons; info strip: version (ⓘ shows last update date; clicking shows release notes), size, platforms, language count, developer link; four feature bullets; description with "Show more"; screenshots and videos; ratings and reviews; developer, support and policy links; related apps. | must | Icon, name, tagline, "Alternative to …", primary button + "…" menu, version, size, minimum macOS, category, **permissions it needs**, **network: none**, What's new (release notes), short description/bullets, links (source, README). Screenshots later. |
| 8 | Primary button states | Install → Installing… (with Stop Installation) → Open. Update when a newer version exists. Uninstalling… while removing. | must | Install → Downloading 42% (Cancel) → Verifying… → Installing… → Open. Update, Updating…, and error state with Retry. Same states on card, detail and menu. |
| 9 | Button disclosure menu | Triangle on the Open button: Uninstall, Version History, Reveal in Finder. | must | "…" menu: Open, Reveal in Finder, Release Notes, Move to Trash…. |
| 10 | Install | One click. Downloads a zip (developers upload a zip), installs into /Applications/Setapp, opens the app afterwards by default. Running apps are tied to the account. | must | Download zip from the feed URL → verify sha256 → unzip to a temp folder → verify code signature and team ID → move into Applications → strip quarantine only after verifying. |
| 11 | Open after install | Setting "Open automatically after installation", on. | should | Same, as a setting, default on. |
| 12 | Installed list ("My Apps") | Grid page with segmented filter: All, Installed, Purchased, Inactive (not opened in a while). Cards show Open. | must | Installed: list or grid of our apps found on this Mac, with version and location. No "Inactive" (needs usage tracking). |
| 13 | Updates page | Title, one-line description, "Update all" button top-right, grid of cards with Update buttons. Empty state: all apps up to date. | must | Same idea as a list: icon, name, installed → new version, size, release notes disclosure, Update; Update All in the toolbar and header. |
| 14 | Update all | Button on Updates page; also "Update Apps" from notifications. | must | Toolbar + menu bar + menu item. Runs sequentially, one progress per row. |
| 15 | Automatic updates | On by default: checks about every 30 min, installs silently when the app isn't running, shows release notes after. | later | v1: background check at most every 6 h, install on user's click. Auto-install as an opt-in later. |
| 16 | Updating a running app | Asks "Quit X to update it?" with Quit and Update; reopens the apps right after. Can defer: "Reopen your apps to install updates." | must | Sheet: "Clips is open. Quit it to update?" Quit and Update / Cancel. Relaunch it after if it was running. |
| 17 | Release notes | Shown automatically after an app updates (setting, on); on demand from the version link; "What's New" in app menu; per-app Version History. Notes follow New / Updated / Fixed. | should | Show notes inline in Updates rows and the detail page. No pop-up after updating (design system: no what's-new sheets). |
| 18 | Uninstall | Disclosure menu → Uninstall → alert with Remove Application (keeps data), Uninstall Completely (app + data, cache, user files), Cancel. | must | Sheet: "Move Clips to the Trash?" with a checkbox "Also remove its settings and data" (off). Everything goes to the Trash, so it's recoverable. Quit the app first if running. |
| 19 | Apps installed outside it | Keeps its own copies in /Applications/Setapp; an App Store or website copy is a separate app with separate data, not adopted. Users must delete one by hand. | must | Detect our bundle IDs anywhere (LaunchServices), show "Installed elsewhere" with the path. Update in place if writable, else offer Reveal in Finder. Never install a second copy. |
| 20 | Menu bar item | Optional (owner has it off). Click either opens the app or shows a context menu with installed apps, the AI assistant and settings. Badge in menu bar (setting). | must | `MenuBarExtra` (.menu): status line ("2 updates" / "All apps up to date"), Update All, installed apps (click to open), Open Library…, Check for Updates, footer. Hideable in Settings. |
| 21 | Update count | Badge on the Updates sidebar item, on the Dock icon (a Dock tile plug-in shows it even when not running), and in the menu bar. | must | Sidebar badge + menu bar status line/icon variant. No Dock badge (design system: quiet). |
| 22 | Check for updates now | App menu "Check for Updates…"; Settings > Updates has a button and "Last check: …". | must | Menu item ⌘R plus Settings row with last-checked time. |
| 23 | Background check | Agent process at login, checks every ~30 min, also handles notifications. | must | At most every 6 h, on wake and on launch if overdue; one small JSON fetch with ETag/If-Modified-Since. No separate agent. |
| 24 | Update notifications | "You've got updates!", "X updated!", "One app updated!"; plus marketing ones (new apps, unused apps, tips and offers, recently updated apps), each toggleable; an in-app bell with an unread count. | should | One optional notification "Updates available" (off by default). No marketing notifications, no in-app inbox. |
| 25 | Favorites + Install all | Heart on any app; Favorites page has Install all ("batch install on new devices"). | later | A "Install all" on Discover or a set of starred apps is handy for new Macs; v1.1. |
| 26 | Back/forward navigation | ⌘[ / ⌘], arrows above the sidebar. | should | Only if detail is pushed; a three-column split view may not need it. |
| 27 | Sidebar shortcuts | Go menu: ⌘1 dashboard, ⌘2 Favorites, ⌘3 My Apps, ⌘4 All Apps; Refresh ⌘R. | must | ⌘1–⌘5: Discover, Installed, Updates, Favorites, All Apps; categories in View ▸ Categories. |
| 29 | Settings window | Toolbar tabs: General, Notifications, Menu bar, Updates, Privacy (560 pt wide). | must | General (Launch at login, Show in menu bar, Open after installing), Updates (Check automatically, Last checked + Check Now, Notify), About. |
| 30 | Self-update | App menu Check for Updates…, "Install automatically" covers Setapp itself, separate updater helper allowed by an `NSUpdateSecurityPolicy` entry. | should | Slopapp is an entry in its own feed and updates itself with the same verified path, then relaunches. |
| 31 | Beta channel | "Get beta versions of Setapp and installed apps", off. | later | Needs a beta field in the feed. |
| 32 | Ratings and reviews | Thumbs-up %, rating count, Rate the app, Edit your rating; rating prompts setting. | skip | Needs a server and accounts. |
| 33 | Account, membership, sign-in, billing | Required sign-in before anything; membership chip in toolbar, avatar menu, View My Account…, Sign Out. | skip | No accounts; everything is free. |
| 34 | AI assistant and AI credits | Toolbar button, credits counter, AI category, an Eney extension. | skip | Out of scope; not a hub's job. |
| 35 | Collections, How-tos, App Guides | Editorial content pages. | skip | ~30 apps don't need editorial; READMEs cover how-tos. |
| 36 | Personal recommendations, "Inactive" filter, unused-app nudges | Based on usage tracking. | skip | Needs usage tracking; we have no telemetry. |
| 37 | Usage analytics | Privacy pane explains usage data is collected (to pay developers and personalize). | skip | No telemetry, by principle. |
| 38 | Notification center (in-app inbox) | Bell with unread count in the toolbar. | skip | Noise. |
| 39 | Setapp folder in Dock / Finder sidebar | General settings toggles; Finder Sync extension. | skip | Apps live in Applications like any other app. |
| 40 | Suggestions outside the app | Finds apps for tasks you search elsewhere; needs Accessibility. | skip | Invasive; no permissions for a hub. |
| 41 | Sound effects | "Play sound effects", on. | skip | Design system: system sounds only. |
| 42 | Share an app | Share button on detail. | later | A "Copy Link" in the "…" menu is enough when the website has per-app pages. |
| 43 | iOS apps / QR code install | Install iOS app, QR code popover. | skip | Mac only. |
| 44 | Discovery Mode | Toggle between task-first cards and name-first "classic" cards. | skip | One clear card design: name and tagline both visible. |
| 45 | Uninstall the hub itself | Help > Uninstall… removes Setapp and warns that all its apps stop working. | should | Our apps keep working without the hub. Just a Help menu note; dragging to Trash is enough. |
| 46 | Help, feedback, legal | Help Center, Share Feedback…, Terms, Privacy Notice. | should | Help menu: Slopapp Website, Report an Issue (GitHub). |

## Key flows

### Flow 1: install an app (the main job)
Setapp:
1. Open Setapp (Dock/Launchpad, or the menu bar icon if shown). The window opens on the
   personal dashboard.
2. Browse a category in the sidebar or press ⌘F and type a name or task.
3. Click a card → the detail page (icon, name, tagline, primary button, info strip,
   bullets, description, screenshots, reviews).
4. Click Install. The button turns into a progress state ("Installing…") with a way to
   stop it. No confirmation, no password prompt, no Gatekeeper dialog.
5. When done, the app opens automatically (setting on by default) and the button reads
   Open. The app lands in /Applications/Setapp.

Ours: same shape, shorter. Card or detail → Install → inline progress (download %,
Verifying…, Installing…) → Open (and it opens, by default). A failure turns the button
into Retry with a one-line reason under it.

### Flow 2: first run
Setapp:
1. Installer puts Setapp.app into Applications. On first launch it asks you to sign in or
   create an account before you can install anything.
2. A setup wizard suggests apps to install.
3. It installs a login agent (SetappAgent, a menu bar-capable helper with a Finder Sync
   extension), a launcher and an updater helper in ~/Library/Application Support/Setapp,
   plus a Dock tile plug-in for the update badge. It checks the macOS version and shows an
   alert if too old.

Ours:
1. Open Slopapp. The library window opens on Discover. No sign-in, no wizard, no tour.
2. On first launch it scans for our apps already on the Mac, so Installed is correct from
   the start (Flow 6).
3. The menu bar item appears. Launch at login is offered as a plain toggle in Settings
   (see Open questions for the default).

### Flow 3: updates
Setapp:
1. The agent checks every ~30 minutes. Updates for apps not running install silently. A
   notification says what updated; release notes appear the next time the app opens.
2. If an app is running, it's left alone and a prompt explains it must quit ("Quit X to
   update it?" → Quit and Update); apps reopen after updating.
3. Manually: sidebar Updates (count badge) → Update all at the top right, or Update on a
   card. Empty state when everything is current.

Ours:
1. Background check (≤ every 6 h, on wake if overdue) updates the count in the menu bar
   and the sidebar badge. Nothing installs on its own in v1.
2. Updates section: one row per app with installed → available version, size, release
   notes, Update. Update All runs them one after another.
3. Running app: sheet asking to quit it, Quit and Update / Cancel, relaunch after.
4. From the menu bar: "2 updates" status line, Update All item.

### Flow 4: uninstall
Setapp:
1. My Apps → click the app → disclosure triangle on Open → Uninstall.
2. Alert with Remove Application (keeps data), Uninstall Completely (app + data, caches,
   user files), Cancel.
3. Button shows Uninstalling…, then Install.

Ours:
1. "…" menu on the card or detail → Move to Trash… (also in the app's context menu and
   ⌘⌫ on a selected row).
2. Sheet: "Move Clips to the Trash?" + checkbox "Also remove its settings and data"
   (off). Buttons: Move to Trash, Cancel. If the app is running, the sheet says it will be
   quit.
3. App bundle (and, if checked, its Application Support folder, preferences plist,
   caches, saved state) go to the Trash. The button returns to Install.

### Flow 5: launch from the menu bar
Setapp: if "Show context menu" is chosen, clicking the icon shows installed apps, the AI
assistant and settings; otherwise a click opens the main window.
Ours: the menu lists installed apps alphabetically with their icons; picking one opens it.

### Flow 6: an app installed outside the hub
Setapp: keeps its own copies separate; a website or App Store copy is a different app and
isn't adopted (users delete one by hand, back up license keys, data doesn't migrate).
Ours: on launch and on each check, look up every catalog bundle ID with LaunchServices.
Found → Installed (with path, e.g. "In Downloads"), compared against the feed for
updates. If its folder is writable, Update replaces it in place; if not, offer Reveal in
Finder and explain. Never install a second copy next to it.

## Settings inventory

Values seen in Setapp are the owner's current settings; documented defaults noted where
known.

| Setting (Setapp) | Seen / default | Options | Keep? |
|---|---|---|---|
| General › Show Setapp folder in Dock | off | toggle | skip |
| General › Show in Finder sidebar | off | toggle | skip |
| General › Open automatically after installation | on | toggle | **keep**, default on |
| General › Rate-app suggestions | on | toggle | skip (no ratings) |
| General › Feedback suggestions | on | toggle | skip |
| General › Discovery Mode | on | toggle (task-first vs classic cards) | skip |
| General › Play sound effects | on | toggle | skip |
| General › Remember search history | on | toggle | skip (no history at all) |
| Notifications › New apps / Unused apps / Tips and offers / Recently updated apps | all on | toggles; essential alerts always delivered | skip (one opt-in "Notify me when updates are available", off) |
| Notifications › Badge in menu bar / on Dock icon | on / on | toggles | keep count in menu bar only |
| Menu bar › Show icon | off (owner) | toggle | **keep** as "Show in menu bar", default on |
| Menu bar › Click icon to | Open app | Open app / Show context menu | skip: always a menu, which has Open Library… |
| Updates › Install automatically | on (documented default) | toggle | later (opt-in) |
| Updates › Check for Updates + Last check | — | button + timestamp | **keep** |
| Updates › Show release notes after updating | on | toggle | skip (notes shown inline instead) |
| Updates › Beta versions | off | toggle | later |
| Privacy › notice explaining usage data collection | — | text + links | replace with an About line: "No accounts, no tracking. Slopapp only downloads the catalog and the apps you install." |

Ours, in design-system order:
- **General:** Launch at login · Show in menu bar · Open apps after installing.
- **Updates:** Check for updates automatically (on; at most every 6 hours) · Notify me when
  updates are available (off) · "Last checked: today at 10:31" + Check Now.
- **About:** `AboutView`.

## Menus and shortcuts

Setapp main menu (relevant items):
- **Setapp:** About, Settings… ⌘,, Check for Updates…, What's New, Terms, Privacy Notice,
  View My Account…, Sign Out, Hide/Quit ⌘Q.
- **File:** Close ⌘W, Close All ⌥⌘W.
- **Edit:** standard + Search All Apps ⌘F, Refresh ⌘R.
- **Go:** Back ⌘[, Forward ⌘], dashboard ⌘1, Favorites ⌘2, My Apps ⌘3, All Apps ⌘4,
  plus unshortcut items for the other sidebar entries and Updates.
- **Window**, **Help:** Help Center, Share Feedback…, Uninstall….
- No global shortcuts.

Ours:
- **Slopapp:** About Slopapp, Check for Updates… ⌘R (catalog + apps), Settings… ⌘,, Quit ⌘Q.
- **Edit:** standard + Find ⌘F.
- **View:** Discover ⌘1, Installed ⌘2, Updates ⌘3, Favorites ⌘4, All Apps ⌘5, Categories ▸, Back ⌘[, Forward ⌘].
- **App** (acts on the selection): Install / Open ⌘O, Update, Update All ⇧⌘U, Reveal in
  Finder ⇧⌘R, Move to Trash… ⌘⌫.
- **Help:** Slopapp Website, Report an Issue.
- In the list/grid: arrows move, Return opens detail (or Open if installed), Space for
  nothing (no Quick Look).
- **Menu bar extra:** status line → Update All (if any) → installed apps → Open Library… →
  Check for Updates → `MenuFooter`. No global hotkey.

## Permissions and system integration

Setapp: login agent in ~/Library/Application Support/Setapp/LaunchAgents (LSUIElement,
`setapp://` URL scheme, Finder Sync extension), main app with a `setappDiscovery://`
scheme, a Dock tile plug-in (badge when not running), an updater helper whitelisted with
`NSUpdateSecurityPolicy` (macOS 13+ App Management), Sentry crash reporting, an optional
Accessibility-based "suggestions" feature. Apps install to /Applications/Setapp; the
first-run sign-in is mandatory. Third-party guides note leftovers after removal (dead
Launchpad entries, a reappearing empty folder).

Ours:
- **No permissions in the normal case.** Writing into /Applications works for admin
  users without a prompt. Standard users: fall back to ~/Applications and say so.
- **App Management (macOS 13+):** replacing another app's bundle is allowed without a
  prompt only if both are signed by the same team (or the target opts in via
  `NSUpdateSecurityPolicy`). Every Slopapp app must be signed with the same Developer ID
  team as the hub; until then (ad-hoc builds) macOS may show the App Management prompt on
  update. The build step must test this.
- **Login item:** `SMAppService.mainApp` via SlopKit `LaunchAtLogin`.
- **Notifications:** only requested when the user turns on "Notify me…".
- **Quarantine/Gatekeeper:** files downloaded with URLSession aren't quarantined; we do the
  checks ourselves (sha256 + `SecStaticCodeCheckValidity` + team ID pin) and refuse on
  any mismatch.
- Optional `slopapp://app/<slug>` URL scheme so the website can open an app's page:
  should.

## UX patterns worth adopting

- **The button is the state.** One control that reads Install / progress / Open / Update,
  used identically on cards, the detail page and lists, so people learn it once.
- **Secondary actions hide behind the primary button.** Uninstall, release notes and
  Reveal in Finder live in a small menu attached to Open, so the destructive action is
  never one stray click away.
- **The update count lives in exactly two places** (sidebar badge, menu bar), and the
  Updates page has one big "update everything" button in its header.
- **Ask before quitting a running app to update it**, and reopen it afterwards so the
  user's flow isn't broken.
- **Two-level uninstall**: removing the app keeps its data by default; wiping data is an
  explicit extra choice.
- **The info strip** on the detail page (version, size, platforms, developer) answers
  "what am I getting" at a glance before any prose.
- **Sidebar sections get ⌘-number shortcuts** in a Go/View menu.
- **Search by task, not just by name.** We go one step further: search by the paid app
  you're replacing.

## What we won't copy, and what we'll do better

- Not copying: name, icon, artwork, wording, sounds, signature visuals, the promo
  carousel, account/membership UI, ratings, AI credits, editorial pages, upsells.
- **No account wall.** Setapp won't install anything until you sign in; we open straight
  to the catalog.
- **No promotional noise.** Reviews and forum posts complain about promo notifications
  from a paid product; Setapp has four marketing notification categories on by default
  and an in-app inbox. We have one optional update notification.
- **No usage tracking.** Setapp collects usage to pay developers and to drive
  "recommended"/"inactive" features. We collect nothing; the only network traffic is the
  feed and the zips the user asked for.
- **Light.** Setapp is ~370 MB plus ~230 MB of helpers and an always-on agent. We're one
  small app within the window-app budget, with the menu bar item in the same process.
- **Clean exit.** Users report dead Launchpad entries for apps they never installed and
  folders that reappear after removing Setapp. We install real apps into Applications,
  create no placeholders or proxies, and our apps keep working if the hub is deleted.
- **Not a single point of failure.** Forum threads describe all Setapp apps refusing to
  launch when its licensing broke. Our apps don't check in with the hub.
- **Adopt existing copies** instead of keeping a second, separate copy (Flow 6).
- **Show what an app needs before installing**: permissions and "network: none" on the
  detail page, which Setapp doesn't show.
- **Update state is always visible**: progress inline, errors with Retry and a reason,
  not a silent background process.

## Edge cases

- **Download:** offline, DNS failure, slow link (progress keeps moving, Cancel works),
  partial download, HTTP 404 (feed points at a missing release), redirect to GitHub's CDN,
  very large zips.
- **Verification:** sha256 mismatch, unsigned or ad-hoc signed bundle, wrong team ID,
  bundle ID inside the zip differs from the feed, version inside differs from the feed,
  zip with extra files or a symlink escaping the folder, zip containing no .app. All
  refuse, delete the temp files, show one clear error.
- **Disk:** not enough space (check before unzip), /Applications not writable (standard
  user), app on a read-only or external volume.
- **Existing copies:** app already in /Applications from the website, in ~/Applications,
  in Downloads, or translocated (running from a randomized read-only path); two copies of
  the same bundle ID (pick the newest, show both paths); local version newer than the feed
  (dev build: never "update" backwards); app renamed by the user.
- **Running apps:** updating or uninstalling an app that's running (quit, wait, relaunch);
  app refuses to quit (unsaved changes) → stop and tell the user; updating Slopapp itself
  (relaunch into the new version); updating a menu bar app with `LSUIElement`.
- **Update All:** one app fails while others succeed (finish the rest, report the failure
  on its row); user quits the hub mid-update (atomic replace: never leave a half-copied
  bundle; use a temp folder and `replaceItemAt`).
- **Feed:** malformed JSON, unknown schema version, an app removed from the feed (keep it
  in Installed, mark "No longer in the catalog"), feed newer than this hub understands,
  cached feed when offline (show "Last checked …"), clock skew.
- **Background check:** sleep/wake (check on wake if overdue, not on every wake), no
  network at the scheduled time, laptop on battery (fine: one tiny request), no polling.
- **Uninstall:** settings folder doesn't exist, sandboxed app with a container, app was
  set to launch at login (its login item stays registered: tell the user or have the app
  unregister on next launch), Trash on another volume.
- **UI:** empty states (no apps installed, no updates, no search results, offline first
  run with no cached feed), long app names, dark/light, Reduce Motion for progress,
  VoiceOver labels on every state of the primary button, window size restored, menu bar
  item hidden then app relaunched (brings it back).

## Our v1 scope

- [x] Library window: sidebar Discover, Installed, Updates (count badge); ⌘1–⌘3. *(Parity pass: + Favorites ⌘4, All Apps ⌘5 with categories.)*
- [x] Discover: all catalog apps as cards (icon, name, tagline, state button), grouped by category. *(Built as Available Now / Coming Soon; see Decisions 11.)*
- [x] Toolbar search (⌘F) across name, tagline, category and the apps it replaces; empty state.
- [x] App detail: icon, name, tagline, "Alternative to …", version, size, minimum macOS, release notes, primary button + "…" menu.
- [x] Install: download the zip from the JSON feed with progress and Cancel.
- [x] Install: verify sha256, bundle ID, code signature and team ID; refuse with a clear error on mismatch.
- [x] Install: atomic move into /Applications (fallback ~/Applications), then Open (opens automatically, setting on).
- [x] Open from card, detail, Installed list and menu bar.
- [x] Detection of our apps installed anywhere (LaunchServices), shown as installed with path; no duplicate installs. *(Copies outside Applications are read-only; a managed copy only on explicit "Install a Copy in Applications". Decisions 1.)*
- [x] Updates list: installed → available version, release notes, per-app Update.
- [x] Update All (toolbar, menu, menu bar); continues past a failed app and reports it.
- [x] Running app on update/uninstall: ask to quit, then relaunch after update.
- [x] Uninstall: Move to Trash… with "Also remove its settings and data" (off), all to the Trash.
- [x] Menu bar extra: status line with pending update count, Update All, installed apps, Open Library…, Check for Updates, footer; hideable.
- [x] Background update check at most every 6 h (on launch/wake if overdue), conditional request, no polling; "Last checked" + Check Now. *(No ETag/If-Modified-Since yet: the feed is ~10 KB.)*
- [x] Settings: General (Launch at login, Show in menu bar, Open apps after installing), Updates, About. *(Update rows live in General; SlopSettings has no Updates tab.)*
- [x] Offline and error states: cached catalog, one-line errors with Retry.
- [x] No telemetry, no account; README states the only network calls (feed + downloads).
- [x] Every action in a menu with its shortcut; no unlabeled controls; light/dark; Reduce Motion.

## Open questions

1. **Who updates apps installed outside the hub?** The plan says those update through
   Sparkle. If both Sparkle and the hub can update the same copy, they can race. Proposal:
   the hub updates any copy it can write to; apps skip their own Sparkle check when the
   hub is installed (or Sparkle is only in website builds). Owner's call.
2. **Install location:** plain /Applications (proposed; matches how people expect apps to
   live) or a /Applications/Slopapp subfolder like Setapp's?
3. **Ad-hoc builds before the Developer ID exists:** allow installs verified by sha256
   only in a clearly labeled "unsigned builds" mode, or block installs until signing is in
   place? App Management prompts on update are likely with ad-hoc signing.
4. **Launch at login default:** the background check and menu bar count only work while
   Slopapp runs. Default on (offered as a visible toggle) or off (design-system default)?
5. **Dock presence:** a regular window app, or a menu bar app (`LSUIElement`) that shows a
   Dock icon only while the library window is open?
6. **Self-update:** the hub updates itself from its own feed entry (proposed), or via
   Sparkle?
7. **Auto-install updates** as an opt-in setting in v1.1, or never?
8. **Feed fields:** the catalog needs bundleId, version, build, url, sha256, size,
   minimumMacOS, teamID, releaseNotes, date, replaces, permissions, network flag. Is the
   website's `catalog.json` the feed (one file), or a separate signed `feed.json`?

## Sources

- Installed Setapp 3.58.0 (163): main menu, main window, category grid, app detail page,
  My Apps and Updates layout, Settings panes (General, Notifications, Menu bar, Updates,
  Privacy), bundle Info.plists and string tables, read via `scripts/drive` and plutil.
- [Setapp support: Uninstall macOS app](https://support.setapp.com/hc/en-us/articles/213812525-Uninstall-macOS-app)
- [Setapp support: Updates and release notes](https://support.setapp.com/hc/articles/213588289-Updates-and-release-notes)
- [Setapp developer docs: Updating your apps](https://docs.setapp.com/docs/updating-applications)
- [Setapp developer docs: requirements](https://docs.setapp.com/docs/preparing-your-application-for-setapp)
- [Setapp: How to remove Setapp from Mac](https://setapp.com/how-to/remove-setapp-from-mac)
- [MacPaw: Setapp gets UI revamp](https://macpaw.com/news/setapp-gets-ui-revamp)
- [Product Hunt: Setapp reviews](https://www.producthunt.com/products/setapp/reviews)
- [MacPowerUsers: Anyone else having issues with Setapp](https://talk.macpowerusers.com/t/anyone-else-having-issues-with-setapp/30814)
- [MacRumors: Setapp has insidious and scary behavior](https://forums.macrumors.com/threads/setapp-has-insidious-and-scary-behavior.2214967) (via search summary; page blocked fetching)
- [Capterra: Setapp reviews](https://www.capterra.com/p/240554/Setapp/reviews/)
- [Trustpilot: Setapp](https://ca.trustpilot.com/review/setapp.com)
- [NotePlan: switching from the App Store to Setapp](https://help.noteplan.co/article/90-how-to-switch-to-from-appstore-to-setapp)
- [Brett Terpstra: So you got Setapp](https://brettterpstra.com/2019/04/22/so-you-got-setapp-dot-dot-dot-make-the-most-of-it)

## Decisions (build step, 2026-11-02)

Open questions above, decided by the builder (owner asleep); each can be revisited.

1. **Who updates copies outside the hub:** the hub updates copies in its own folder and in
   `/Applications` / `~/Applications` in place. Copies anywhere else (a dev build in
   `build/`, Downloads) are shown with their path and can be opened, but are never changed
   (they're often development builds, and Switchboard runs from `build/` as the owner's
   default browser). "Install a Copy in Applications" is offered in the ⋯ menu. They don't
   count as pending updates. Sparkle isn't in v1; when it arrives, apps should skip their own
   check when the hub manages them.
2. **Install location:** `/Applications/Slopapp/` when writable, else `~/Applications/Slopapp/`
   (the brief's call; keeps our apps together and makes "managed" unambiguous).
3. **Before a Developer ID:** installs are allowed with ad-hoc signatures when `brand.json`
   has no `teamId`, checked by sha256 from the HTTPS feed plus a valid signature, and
   labelled "Unsigned development build". With a `teamId`, only Apple-issued certificates
   from that team pass. App Management prompts weren't seen in testing (installs were under
   /tmp); they may appear for ad-hoc apps in /Applications on macOS 13+.
4. **Launch at login:** off by default (design system). The menu bar item and background
   check run whenever Slopapp runs.
5. **Dock presence:** a normal window app whose Dock icon disappears when the window closes
   (it stays in the menu bar). With the menu bar icon hidden, closing the window quits.
6. **Self-update:** deferred. The launcher is in its own feed (`hub: true`), hidden from the
   lists; a newer version shows as a menu bar item that opens the releases page.
7. **Auto-install:** later, opt-in only.
8. **Feed:** a separate `feed.json` (`scripts/feed.mjs`), not the website's catalog.json:
   it needs checksums and zip-derived versions the website doesn't. Published to gh-pages.
9. **Bundle id:** `app.slopapp.slopapp`. The doubled word is ugly but invisible to users,
   and `<prefix>.<slug>` keeps every tool (new-app.sh, feed.mjs, Application Support paths)
   on one rule.
10. **Feed refresh:** on every launch (a person opened it) and on ⌘R; in the background at
    most every 6 h (`NSBackgroundActivityScheduler`), and after wake if overdue. Also after
    an install fails with a checksum/version/missing-file error, so Retry uses a fresh entry.
11. **Discover layout:** two sections (Available Now, Coming Soon) instead of category
    headers: with 5 released apps, categories would mostly be headers over one card. Search
    covers categories and replaced apps.
12. **No update notifications in v1:** the menu bar count is the signal (design system:
    quiet by default).
13. **"Open apps after installing" stays on** (round 2): menu-bar apps get a HUD saying
    they're in the menu bar, so the launch is never silent.

## Build notes (2026-11-02)

- Core (`SlopappCore`): feed parser (lossy per entry, relative URLs, schema guard), version
  compare, `URLPolicy` (HTTPS only; file/loopback only with `SLOPAPP_FEED_URL`),
  `SignaturePolicy`, inventory/locations, catalog join + search, `Installer` (download →
  sha256 → ditto → one .app with the right bundle id and version → signature/team →
  quit hook → atomic swap with rollback), `Uninstaller` (Trash + Put Back), schedule.
- **Tests:** 42 Swift Testing tests in 8 suites, including integration tests that build real
  tiny app bundles (ad-hoc signed, zipped with ditto) and run the real installer: install,
  update in place, sha256 mismatch, unsigned, modified-after-signing, required team vs
  ad-hoc, corrupt zip, wrong bundle id, wrong version, offline, 404, non-HTTPS in
  production, too-new macOS, refusing to quit, cancel mid-download, uninstall with data +
  put back.
- **Gates:** `scripts/check.sh Awake Slopapp --perf` all PASS. Slopapp perf: launch 131 ms,
  first window 344 ms, idle CPU 0.033 %, footprint 36.7 MB (window-app budget 120 MB).
- **Scripted walkthrough** (release build, `apps/Slopapp/test-feed.sh`, everything under
  /tmp/slopapp-test, light and dark): Discover (installable + Coming Soon), detail page,
  Install (download over http://localhost, verify, opens after install), build/Awake.app
  detected as "installed elsewhere" (read-only, Open works), "Install a Copy in
  Applications", Check for Updates (⌘R), Updates list with badge and What's New, per-app
  Update with the app running (quit prompt → quit → update → relaunched with a new pid),
  Update All (2 apps, one running), bad sha256 / bad signature / corrupt zip (each refused,
  old copy untouched, one-line error + Retry), offline (banner over the cached catalog,
  download error), Move to Trash with and without settings/data (app quit first), Undo
  (banner and ⌘Z) put everything back, search (⌘F; "cleanshot" finds Snapper), Settings,
  About, menu bar menu (status line, Update All, installed apps, Open Slopapp), status icon
  with count, closing the window drops the Dock icon, Open Slopapp / reopening brings it
  back. Screenshots in /tmp/slopapp-shots (not in the repo).
- **Accessibility:** `scripts/drive tree` shows no `[unlabeled]` controls in Discover,
  Installed, Updates, detail, uninstall sheet, Settings, About, menu bar menu.
- **Found while testing and fixed:** sidebar selection not drawn (NavigationLink rows →
  tagged labels); ⌘F didn't focus search (added Find… command); stale cached feed made a
  fresh test feed fail (refresh on launch + after checksum errors); Undo banner missing on
  pushed detail pages; double separators in the menu bar menu; installed-but-unavailable
  apps listed under Coming Soon; Trash name clash naming for folders with dots;
  `MenuBarExtra` label now a single drawn image (icon + count).
- **Environment lesson:** a test copy with a real app's bundle id and a higher version makes
  LaunchServices open the test copy (Awake's perf gate failed until it was unregistered).
  The test feed therefore uses Testbed/Sandbox (own bundle ids) for every scenario, lists
  Awake without a download, and `test-feed.sh clean` unregisters all test copies.
- **Menu bar overflow:** on this Mac the menu bar is full; with Testbed/Sandbox icons showing,
  macOS hides Slopapp's status item (it's not in the Accessibility tree at all). The test
  feed turns their icons off; reopening them brings their icons back.

### Design checklist (design-system §10)

| # | Item | Grade |
|---|---|---|
| 1 | Main job in one click, no setup | PASS (Install on the card) |
| 2 | Native look, accent color, light/dark | PASS (system controls; brand only in icon/About) |
| 3 | Every action in a menu with shortcut | PASS (View ⌘1–5 ⌘[ ⌘], Apps menu ⌘O ⇧⌘R ⌘⌫ ⇧⌘U ⌘D, ⌘R, ⌘F) |
| 4 | Esc / ⌘, / ⌘Q / standard shortcuts | PASS (Esc clears search and cancels sheets) |
| 5 | Settings: General + About | PASS |
| 6 | HIG copy, verb buttons, errors say what to do | PASS |
| 7 | Empty states with symbol, line, action | PASS (no installs, no updates, no results, catalog unavailable) |
| 8 | Permissions only when needed | PASS (none needed) |
| 9 | Destructive actions to Trash with undo | PASS |
| 10 | No network unless the feature needs it | PASS (feed + chosen downloads only; documented) |
| 11 | Performance budgets | PASS |
| 12 | VoiceOver names every control | PASS |
| 13 | Reduce Motion | PASS (no custom animation) |
| 14 | Window size/position persist | PASS (SwiftUI window frame autosave) |

### Deferred (with reasons)

- Self-update of Slopapp (needs replace-and-relaunch of the running bundle; v1.1).
- Update notifications (opt-in), automatic installs (opt-in), beta channel: later.
- Screenshots/long descriptions/permissions on app pages: the feed has no fields yet.
- Category filter and "Install all" for a new Mac: v1.1.
- `slopapp://` URL scheme for the website: later.
- Real-world App Management prompt behavior for ad-hoc apps in /Applications: can't be
  tested without touching the real Applications folder; verify on the first real release.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-03)

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 Apps deleted outside Slopapp still show as installed (Open → "Couldn't open… Try reinstalling" dead end) until a catalog refresh succeeds; the leftover "Retry" reads like "retry opening" | major | Accept | The install folders (managed + Applications) are watched with kernel vnode events (`FolderWatcher`, debounced, no polling), so a deleted app flips to Install within ~0.3 s. Also re-scans on launch, activation, ⌘R/Check Now (before the network, so it works offline) and right before Open; Open on a missing copy says where it was and to install it again. Errors now know their kind: only failed installs/updates turn the button into Retry. Reinstall (repair) added to the ⋯ menu, the context menu and Apps menu. Notes like "no longer at…" clear when the app is back. |
| F2 Selecting a row in Installed doesn't enable Apps ▸ Reveal in Finder / Move to Trash | minor | Accept | Selection is shared (`Navigation.selection`); Apps-menu commands act on the open page, else the selected row/card. Context menu is built from the selection (the empty selection menu was hiding the row menus). Added Apps ▸ Show Details (⌘↓) and Reinstall. |
| F3 Discover/search results not keyboard navigable; Return in search should open the result | minor | Accept | Discover and search results take arrow keys (column-aware across sections, `GridNavigation` in Core with tests), Return shows details, Esc clears the selection; the selected card is highlighted and scrolled into view. Discover and Installed take focus when shown; search results don't (typing stays in the field). Return in the search field opens the selected or first result. |
| F4 Add Back (⌘[) and Show/Hide Sidebar (⌃⌘S) | minor | Accept | View ▸ Back ⌘[ and SwiftUI's standard sidebar commands (⌃⌘S). |
| F5 ⌘O means Install/Open in the Apps menu but "Open Slopapp" in the menu bar menu | nit | Accept | "Open Slopapp" has no shortcut; ⌘O is always the app action. |
| F6 "More" button's accessible name changes | nit | Accept | The ⋯ menu's label is now a `Label("More actions for <App>")` (icon only), stable in every state. |
| F7 9×9 pt dismiss ✕ on the undo bar | nit | Accept | 22×22 pt hit target, with a tooltip. |
| F8 Settings first opened on About | nit | Accept (verified) | Cause: SwiftUI restores the last Settings tab, and an earlier session left About selected. The saved tab index is cleared at launch, so Settings opens on General each launch (still remembered within a session). |
| F9 No confirmation of what an update changed | nit | Accept | HUD after Update / Update All / Reinstall ("Updated Testbed to 1.1.0", "Updated 2 apps"), and a "Recently Updated" list (last 7 days, from → to, when) on the Updates page, also shown when everything is up to date. |

Gates after the fixes: 47 tests in 9 suites pass; `scripts/check.sh Slopapp` passes (test, bundle, smoke, catalog);
no `[unlabeled]` controls on any page. Walkthrough on the release build with the test feed:
deleting an installed app in the file system flips it to Install; Open on a just-deleted app
shows the "no longer at" note with Install (not Retry); arrow keys + Return in Discover
(down from the last "Available" row lands in "Coming Soon", same column); ⌘[ back; ⌘F, type,
Return opens the result; Installed row selection enables Apps-menu Open/Reveal/Reinstall/
Move to Trash; Reinstall and Update show the HUD and the Recently Updated list; ⋯ keeps its
name after an uninstall; Dismiss is 22×22.

Perf: launch 138–215 ms, first window 345–489 ms, memory 36–39 MB (all PASS). Idle CPU was
inconsistent this session: 0.039 % and 0.054 % in two clean runs, 0.32–0.46 % in others, while the
unchanged reference app Awake measured 0.17–0.23 % (over budget too) at the same time. Sampling
Slopapp at idle shows only AppKit redrawing status-item replicants (`NSStatusItem
_updateReplicants`, `CALayer renderInContext`), driven by other activity on screen; none of
Slopapp's code is on the stack. The menu bar count image is now rasterized once per count
instead of drawn on demand. Also: `perf.sh`'s 3-launch mode often aborts because `drive launch`
still sees the just-quit app as running (LaunchServices lags ~50 ms behind the process exit);
`--runs 1` avoids it. ⌃⌘S couldn't be exercised: a system dialog held activation, so menu
validation saw no key window (it's SwiftUI's standard command).

### Round 2 (2026-11-03)

No blockers or majors: the exit rule is met once these minors are fixed (they are).

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 "Open apps after installing" (on) silently launches menu-bar apps with no visible sign | minor | Accept | **Decision: keep it on** (a fresh install should be one click to use, as in the original), but menu-bar apps now get a 3-second HUD: "Opened Testbed. It's in your menu bar." Every install also leaves a note under the button ("Installed version 1.0.0."). |
| F2 A row's "Couldn't download…" stays after the catalog comes back | minor | Accept | Errors caused by the network (offline, server error, missing file) are marked as such and cleared when a refresh succeeds. Checksum/signature failures stay (they need the user to see them). |
| F3 The Trash banner stays after the app is reinstalled; Undo then does nothing | minor | Accept | Each re-scan drops the banner (and its ⌘Z action) once a copy is back at the trashed path; Undo on a stale banner explains "Testbed is already installed again." |
| F4 Offline, Updates still says "All apps are up to date" | nit | Accept | Header and empty state say "Couldn't check for updates." with the last successful check time when the last refresh failed. |
| F5 Red/orange status text unreadable on a selected row | nit | Accept | Error, signature and notice lines switch to the primary (white) style on an emphasized selection (`backgroundProminence`). |
| F6 Reinstall gives no feedback | nit | Accept | Progress shows in the button (as for installs); afterwards a note under the button ("Reinstalled version 1.1.0.") for 6 s plus the "Reinstalled …" HUD and a Recently Updated entry. |
| F7 Trash banner should say whether settings/data were removed | nit | Accept | "Sandbox and its settings and data were moved to the Trash." / "… was moved to the Trash. Its settings were kept." |
| F8 The hub's About says "Part of Slopapp" | nit | Accept | `HubAboutView` (in-app, named to move to SlopKit as a hub option) replaces it in the app menu, the menu bar menu (`HubMenuFooter`, same items as SlopKit's `MenuFooter`) and the Settings About tab (Settings rebuilt from SlopKit's public `GeneralSettingsTab` + this About). Two About surfaces remain (window + Settings tab), as the design system asks; they now show the same text. |
| Tool: `bump` only went to one version | — | Accept | `test-feed.sh bump`/`bad-*` now publish the next minor version each run (1.1.0, 1.2.0…). |

Note: the round-2 tester had turned "Open apps after installing" off in the real Slopapp
preferences; that key was deleted so the default (on) applies again.

Gates: 47 tests pass; `scripts/check.sh Slopapp --perf` all PASS (launch 153 ms, first window
387 ms, quietest idle window 0.043–0.094 %, footprint 47 MB, machine load ~11); no `[unlabeled]`
controls. Walkthrough on the release build: install a menu-bar app (HUD shown, note under the
button, app running), Reinstall (note + HUD), uninstall with data (new banner text), reinstall
(banner gone), offline Update All (network errors) → reconnect + Check (errors cleared),
offline Check with nothing pending (header says the check failed), selected Installed row
(white status text), About from the app menu and Settings (hub text, version 0.2.0).

**Ship:** `app.json` → status `beta`, version `0.2.0` (build 2); README updated.

## Parity pass (2026-11-03)

Owner's request: "Redesign the launcher to look more like the Setapp launcher. Remove the
Also Great section." Governed by [`docs/parity-pass.md`](../parity-pass.md).

**How the original was studied.** Setapp's main window layout comes from the earlier
read-only walk (3.58.0) plus official help-center screenshots (support.setapp.com articles
213587729 "App categories", 213588289 "Updates and release notes", 213812525 "Uninstall"),
downloaded to `/tmp/slopapp-parity/web/` and viewed there (never committed). Setapp itself
wasn't opened this time: the owner was at the Mac (idle < 60 s) and its home, My Apps and
Updates views show their account and apps; the official screenshots cover every view
needed. Menu bar contents come from Setapp's own Settings string ("quick access to
installed apps, AI assistant, and settings").

**What the original looks like (structure only).** Full-height grey sidebar with Back/Forward
chevrons at the top; main pages (My Explorer, Favorites, My Apps, Collections, How-tos, App
Guides), then All Apps with five task categories indented under it (no icons), and Updates
with a count at the bottom when there are updates. Content: search at the top. Home is a
wide banner carousel (app icon, big headline, "New app — Name") followed by rows ("The best
of…" chart, collections) with a title, a line under it and "See all ›". Grid pages: large
title, one-line description, sort control top right (Top Rated / New), capsule filter chips,
a hairline, then a 3-column grid of cards: icon left; task-first headline (what it does,
two lines), app name in grey, a meta line (rating · platforms). App page: big icon; name,
pitch; a blue "Open ▾" split button (Reveal in Finder, Version History, Add to Favorites,
Share, Uninstall) with heart and share buttons beside it; a rounded grey strip (Version ⓘ,
size, platforms, language … Developer: link); feature bullets in two columns; screenshots;
description with "You may also like" in a column on the right. Uninstall: an alert with
three stacked buttons (Remove Application / Uninstall Completely / Cancel). Updates: title,
line, "Update all" top right, cards with "Update".

### Gap table

| Original's structure / feature | Slopapp now | Status |
|---|---|---|
| Sidebar: main pages, then All Apps with indented categories, Updates with count | Discover, Installed, Favorites; All Apps + Utilities / Productivity / Media / Design / Developer indented, no icons (only categories with apps show); Updates last with a count (moved 2026-11-04, see Chrome pass) | done |
| Back / Forward at the top left | Chevrons in the sidebar on the window buttons' row (2026-11-04); ⌘[ / ⌘]; Forward history (`PageHistory`, tested) | done |
| Home banner carousel | Featured banners (apps you can install now, ones not on this Mac first), paged sideways with the next one peeking in (2026-11-04, replaced arrows + dots), click opens the page | done (own visuals: brand greens / mint / cream) |
| Home rows with title, line, "See all ›" | One row per category: title, our one-line blurb, "See All N ›" to the category page, first two rows of cards | done |
| "Best of" chart, How-tos, Collections, App Guides, personal recommendations | — | skip (needs ratings/editorial/usage data; see feature rows 32, 35, 36) |
| Grid page: title, line, sort top right, filter chips, hairline, 3-col cards | All Apps and category pages: same layout; sort Featured / Name; chips All / Available / Coming Soon | done |
| Card: icon left, task-first headline, name, meta line | Same; meta line is version / from → to / category where useful; the state button (Install, progress, Open, Update, Coming Soon) is always visible under it (not hover-only, as decided in v1) | done |
| My Apps page as a card grid | Installed as cards (version, "not managed", unsigned badge); ⌘⌫ on the selected card | done |
| Updates: title, line, "Update all" top right, cards with Update | Same, plus from → to · size and a "What's New" popover per card; Recently Updated kept below | done |
| App page header: icon, name, pitch, split button, heart, share | Same: prominent split button (main action + arrow menu: Open, Reveal in Finder, Install a Copy, Reinstall, Favorites, Move to Trash…), heart, Share (GitHub folder; hidden for planned apps) | done |
| Rounded info strip with developer link | Version, size, macOS N+, Menu bar / Window app, category … "Source: GitHub" | done |
| Feature bullets (two columns) | Highlights built from the feed: what it replaces, where it lives, free and open source, no account | done |
| Screenshots & videos, long description | — | deferred: the feed has no fields for them (M: feed.mjs + per-app assets) |
| "You may also like" column | "More in <Category>" column (up to 4, available first) | done |
| Favorites + Install all | Heart / ⌘D / context menu; Favorites page with Install All (installs the missing ones in a row) | done |
| Uninstall alert with three stacked choices | Alert: Move to Trash / Move to Trash with Its Data / Cancel (replaces the checkbox sheet); Undo banner + ⌘Z unchanged | done |
| Menu bar: open the app; installed apps; settings | Status line, Update All, Open Slopapp, installed apps (icons), Check for Updates, footer | done (order tuned; no AI item) |
| Menu bar "click to open app" vs "show menu" option | — | deferred: `MenuBarExtra` can't open a window on click (S: AppKit status item) |
| Version History in the button menu | — | deferred: the feed carries only the latest notes (S, needs feed history) |
| Ratings, AI assistant, account chip, notification bell, credits | — | skip (no accounts, no telemetry; see feature rows 32–38) |
| Search at the top of the content | Borderless search field at the top left of the content panel (2026-11-04); typing always shows results, even from an app page | done |
| Also Great | Removed entirely (sidebar item, view, `RecommendedApp`, its test, README, this doc, roadmap spec) | done |

### Decisions

1. **Shortcuts:** ⌘1 Discover, ⌘2 Installed, ⌘3 Updates (as asked: the three remaining
   sections stay on ⌘1–⌘3), ⌘4 Favorites, ⌘5 All Apps, categories under View ▸ Categories,
   ⌘[ / ⌘] Back / Forward, ⌘D Favorites. (2026-11-04: the sidebar now puts Updates last, as the
   original does; the shortcuts and the View menu order stay as they were.) Sidebar order followed the numbers, so Updates sat
   third rather than at the bottom as in the original (it's a core page here, always shown).
2. **Favorites added** (feature row 25, was "later"): cheap, and "Install All" is the
   new-Mac flow. Stored per feed (`favorites` / `favorites:dev`), slugs only.
3. **Discover has no "Available Now / Coming Soon" split any more:** each category row lists
   available apps first, then planned ones; the chips on All Apps / category pages filter.
4. **Uninstall is an alert with two Trash choices** instead of a sheet with a checkbox, as in
   the original; both still go to the Trash with Undo.
5. **Split button is our own** (`SplitButton.swift`, in-app, named to move to SlopKit):
   SwiftUI's `Menu` + `primaryAction` can't take the prominent style, and the original's
   main action is clearly filled. Main part = prominent `Button`; arrow = `Button` that pops
   a native `NSMenu` built at press time.
6. **Hero shows apps you can install now** (not installed ones first); it resets to the
   first one when the set changes. No auto-advance (quiet, no timers).
7. **Default window 1120×720** (3 columns of cards, like the original); minimum 820×520.

### Deviations from the design system (and why)

- **Brand colors in UI**: the Discover banner uses the brand's forest/ink/leaf/mint
  gradient with white text. The launcher is the hub, the brief allows our brand there, and
  the original's signature banner needs a colored surface. App icons (forest green) sit on
  the bright leaf end so they stay visible.
- **Custom-drawn controls**: filter chips (capsules, accent fill when selected), the
  banner's arrow buttons and page dots, and the split button's clipped pair. All use the
  user's accent color and system fonts; they exist to match the original's layout.
- *(Superseded by the Chrome pass below.)* **Toolbar title hidden** on macOS 15+ (`toolbar(removing: .title)`): pages carry large
  in-content titles like the original; the window keeps its title for the Window menu and
  VoiceOver.
- *(Superseded by the Chrome pass below.)* Search stays the native toolbar field (trailing) rather than a custom field at the top
  left: native ⌘F, Esc and VoiceOver behavior matter more than the exact spot.

### Gates

- **Tests:** 57 Swift Testing tests in 12 suites pass (new: `BrowseTests`,
  `FavoriteListTests`, `PageHistoryTests` — categories order, filter/sort, featured, related,
  highlights, favorites, Back/Forward incl. syncing with the stack's own back). Also Great's
  test removed.
- **`scripts/check.sh Slopapp`:** PASS (SlopKit test, Slopapp test, bundle, smoke, catalog).
- **Perf:** `scripts/perf.sh` starts by quitting any running `build/Slopapp.app`, and one
  was running that this session didn't start (pid 9629, real feed, launched via
  LaunchServices before the session), so the gate script wasn't run. The same measurement
  (3 launches → median, 3 × 5 s idle windows → lowest, peak footprint) was run on a copy of
  the release build under /tmp, launched directly: launch 120 ms (< 300), first window
  335 ms (< 600), idle CPU 0.035 % (< 0.2; windows 0.101 / 0.035 / 0.148), footprint
  62.8 MB (< 120), load 3.7. Footprint is up from ~47 MB (more cards and the banner on
  screen at once).
- **Walkthrough** (release build copy, `test-feed.sh` overrides, everything under
  /tmp/slopapp-test, light and dark): Discover banner + category rows + See All; All Apps
  chips (Available → 3, Coming Soon → 13) and Name sort; category page; app page (split
  button prominent when key; arrow menu lists Open / Reveal / Favorites / Move to Trash…;
  picking Add to Favorites works); install from a card (progress → Open, note, app opened);
  Favorites via the heart → Favorites page → Install All; `bump` → ⌘R → Updates (badge 2,
  from → to · size, What's New popover) → Update All with both apps running → quit prompt →
  updated to 1.1.0 and relaunched (new pids) → Recently Updated; Move to Trash via Apps
  menu → three-choice alert (says the app is open) → "with Its Data" → app + prefs in the
  test Trash, banner → Undo put both back; offline → banner over the cached catalog → serve
  → Try Again clears it; ⌘F + typing "lungo" → Results (finds Awake) → Return opens it;
  typing again on an app page jumps back to results; ⌘1 then arrows (down, right, down) →
  selection highlight → Return opens Dual; ⌘[ / ⌘] / Back / Forward buttons; ⌘3–⌘5; menu bar
  menu (status, Update All, Open Slopapp, installed apps); 820-pt minimum width.
- **`[unlabeled]`:** 0 on Discover, Installed, Updates, Favorites, All Apps, a category, an
  available and a planned app page, the uninstall alert, Settings, the main menu and the
  menu bar menu.
- **Found and fixed while testing:** icons vanished on the first (all-forest) banner →
  leaf-green end behind the icon; the version caption truncated in two columns → own line
  under the name; native split button ignored the prominent style → `SplitButton`; its
  menu didn't open while the app wasn't key → anchors on the library window; info strip
  said "Coming soon" for an installed app without a download → shows the version; Source /
  Share pointed at a missing folder for planned apps → hidden; search typed on an app page
  kept the page on top → typing pops to results.
- **Environment notes:** a LaunchServices launch of a second copy latched onto the running
  pid 9629 and reopened its window; it was closed again via its close button (back to no
  windows, menu-bar only). The test copy shares the `app.slopapp.slopapp` defaults domain,
  so its window frame was restored afterwards and `favorites:dev` deleted.

### Screenshots (not in the repo)

`/tmp/slopapp-parity/shots/`: `discover-light.png`, `discover-key-light.png`,
`keyboard-selection-light.png`, `allapps-light.png`, `category-light.png`,
`detail-awake-light.png`, `detail-update-light.png`, `split-menu-2.png`,
`detail-comingsoon-light.png`, `installed-light.png`, `favorites-light.png`,
`updates-light.png`, `whatsnew-popover-1.png`, `quit-confirm-1.png`, `updates-done-2.png`,
`uninstall-alert-1.png`, `trash-banner.png`, `offline-light-1.png`, `narrow-820.png`,
`final-discover-dark.png`, `final-installed-dark.png`, `final-updates-dark.png`,
`final-favorites-dark.png`, `final-detail-dark.png`, `allapps-dark.png`, `detail-dark.png`.
Reference images from Setapp's help center: `/tmp/slopapp-parity/web/`.

### Deferred

- Screenshots and long descriptions on app pages (M): need feed fields and assets.
- Version History in the button menu (S): the feed has only the latest notes.
- Menu bar "click opens Slopapp" option (S): needs an AppKit status item instead of
  `MenuBarExtra`.
- Moving `SplitButton`/`PopUpMenu`, `FilterChips` and the card grid into SlopKit (S) once
  another app needs them.

## Chrome pass (2026-11-04)

Owner, after trying the parity build: "We want it to look more like setapp, remember." The
pages were close; the frame around them still read as a stock `NavigationSplitView` with a
compact toolbar, and "why are the window's close buttons so tiny". Reference: the owner's own
side-by-side screenshot (never transcribed: it shows their account) and Setapp's window
measured read-only with `scripts/drive tree Setapp` (frames only, no screenshots, no clicks).

### What changed

- **Window chrome** (`Views/WindowChrome.swift`, generic, named to move to SlopKit): hidden
  title bar (`.windowStyle(.hiddenTitleBar)`), a transparent title bar with an **empty unified
  `NSToolbar`** installed by a window accessor (`storeWindowChrome()`), the toolbar backdrop
  hidden (`toolbarBackgroundVisibility(.hidden)`, macOS 15+; `toolbarBackground(.hidden)` on 14)
  and its title removed (`toolbar(removing: .title)`, 15+; a KVO guard keeps `titleVisibility`
  hidden on 14). The window title is still set per page (Window menu, VoiceOver).
  `WindowDragArea` lets the empty top strips move the window (double-click follows the
  system's zoom / minimize setting).
- **Layout** (`Views/LibraryChrome.swift`, `MainWindow.swift`): full-height sidebar
  (196 pt, `.sidebar` material behind the window) with Back / Forward on the window buttons'
  row; content in an inset rounded panel (6 pt from the top, right and bottom; corners
  concentric with the window's: `ConcentricRectangle` on macOS 26+, 10 − 6 = 4 pt before;
  measured on macOS 27: a 6 pt gap along the edges and around the curves; `textBackgroundColor`, a hairline in light mode) with its own header row: a
  borderless magnifier + "Search" field on the left; on the right the update status
  ("✓ Up to Date" / "1 Update" / "Checking…" / "Can't Check", accent colour, opens Updates),
  a thin divider and Check for Updates. No toolbar band, no divider across the top.
- **Sidebar**: custom rows instead of `List`: filled glyphs in the secondary colour
  (star / checkmark.circle / heart / square.grid.2x2 / arrow.down.circle, `.fill`), 28 pt
  rows, 40 pt pitch for the main pages and 28 pt for All Apps, its categories and Updates.
  Selection is a grey rounded rectangle (accent-tinted while the sidebar has keyboard focus).
  Categories keep the icon's space, so they line up with the labels. **Updates is the last
  row**, with a grey capsule count. Up / Down move between rows once it has focus (Tab from search).
- **Pages**: `NavigationStack` replaced by a small `PageStack`: the section's page stays
  alive under an open app page (opacity 0, disabled, hidden from VoiceOver), so scroll
  position survives Back; the grid takes the arrow keys again when you come back. This also
  stops SwiftUI from installing its own toolbar. One status banner along the bottom of the
  panel for every page (the app page's duplicate is gone).
- **Discover**: banners are a horizontal, view-aligned scroll the width of the panel; the
  next banner peeks in at the right edge (and the previous one at the left once you've
  moved). Click a peeking banner to bring it in, click the one in view to open its page;
  trackpad swipe / Shift-scroll work. Arrows and dots removed. Banner: small uppercase line,
  semibold large title, name · category, big tilted icon on the right; 220 pt tall, 16 pt
  corners. Backgrounds alternate through brand palettes (forest/leaf with mint, mint with
  leaf, cream with an ember glow; text ink on the light ones). Section titles are
  regular-weight `.largeTitle` with a `.title3` secondary line; See All stays (our rows
  don't scroll sideways, so there are no paging chevrons).
- **Headings everywhere** are regular weight now (page titles, app page name, What's New,
  On This Mac, More in…, Recently Updated), as in the original.
- **Core** (`SlopappCore/Chrome.swift`, tested): `SidebarItem` (order with Updates last,
  arrow-key moves clamped at the ends, glyphs) and `HeaderStatus` (what the status item says).
  `Navigation.Section` is now a typealias for it.

### Why the window buttons were small (and the fix)

Measured: in plain AppKit test windows on this Mac (macOS 27.2) every configuration (plain,
hidden title bar, unified, compact, expanded toolbar) gives 16×16 buttons 23 pt apart; our
app gave 12×14, 20 pt apart, in every configuration. The cause is the binary, not the
window: SwiftPM (Swift Build) links by calling the toolchain's `swiftc` directly without
`SDKROOT`, so clang can't read the SDK version from `--sysroot` and passes
`-platform_version macos 14.0 14.0` to the linker. `otool -l` shows `sdk 14.0` in
`LC_BUILD_VERSION`, so macOS treats the app as built against the macOS 14 SDK and runs it in
the pre-26 compatibility look (legacy small window buttons, older controls). Every app built
by `scripts/bundle.sh` has the same stamp (Awake checked: `sdk 14.0`).

Fix (Slopapp only): `Package.swift` adds `-Xlinker -platform_version -Xlinker macos
-Xlinker 14.0 -Xlinker 26.0` to the executable's link flags. The binary now says
`minos 14.0, sdk 26.0` (both slices), and macOS uses the current window design, with 16×16 buttons.
26.0 is the first SDK with that design; the deployment target is unchanged. Side effect:
the whole app (buttons, Settings, alerts) now draws in the current macOS style, which is
what the design system intends ("Liquid Glass on macOS 26+"). A repo-wide fix belongs in
`scripts/bundle.sh` (e.g. run `swift build` with `SDKROOT="$(xcrun --show-sdk-path)"`); not
done here because other apps' looks would change and `scripts/` is out of this brief's scope.

### Measurements (release build, AX frames)

| | Setapp | Slopapp now |
|---|---|---|
| Window buttons | 16×16, 23 pt apart, 25 pt below the top, 19 from the left | 16×16, 23 pt apart, 18 pt below the top, 18 from the left (centre line 26 pt) |
| Back / Forward | 14×16 at +138 / +166 | 24×24 hit areas centred at +145 / +173, on the buttons' centre line |
| Sidebar | ~186 pt, list from +84, rows 40 / 28 | 196 pt, list from +76, rows 40 / 28 pitch |
| Content header | ~66 pt | 40 pt row inside the panel (46 pt from the window top), centred on the buttons' line; banner starts ~70 pt down |
| Panel inset | 5 pt | 6 pt |

The buttons sit 7 pt higher than Setapp's: a unified toolbar centres them 26 pt down
whatever its items' height (tested), and Setapp evidently moves them by hand. Moving the
system's buttons ourselves is fragile (AppKit re-lays them out on resize and full screen),
so we keep AppKit's position and line Back/Forward, search and status up with it.

### Decisions

1. **Updates last in the sidebar** (as the original); ⌘1–⌘5 unchanged (⌘3 Updates), so the
   View menu keeps the shortcut order (`SidebarItem.menuOrder`).
2. **Choosing a sidebar row clears the search** and returns to that page's root (clicking
   the current page pops an open app page).
3. **Status item** says "Up to Date" / "N Updates" / "Checking…" / "Can't Check"; it always
   opens Updates. No account, credits, AI or notification items.
4. **No sidebar toggle**, and `SidebarCommands` is gone (there's no split view to collapse).
5. **Banners**: no auto-advance (quiet, no timers); the palettes alternate by position.

### Deviations from the design system (and why)

- **Custom window chrome**: hidden title bar, empty toolbar for full-size buttons, custom
  sidebar rows, an inset content panel and a custom search field instead of `.searchable`.
  The original's layout puts Back/Forward beside the window buttons and search inside the
  content, which a stock split view + toolbar can't do. Kept native: system window buttons,
  `.sidebar` material, system fonts, accent colour for status and focus, ⌘F, Esc clears,
  Return opens the first result, VoiceOver labels, window title.
- **Panel colour**: `textBackgroundColor` (white / near-black) on the sidebar material, so
  the content reads as a separate surface like the original's. Hairline border in light mode only.
- **Brand colours** on the banners (forest, leaf, mint, cream, ember, ink from
  `brand/brand.json`): the hub is the brand's place; no pastel palette from the original.
- **Linker SDK stamp** (above): an app-local build setting, until the pipeline sets it for everyone.

### Gates

- **Tests:** 63 Swift Testing tests in 14 suites pass (new: `SidebarOrderTests`, `HeaderStatusTests`).
- **`scripts/check.sh Slopapp --perf`:** PASS (busy machine, load 12.4): launch 143 ms
  (< 300), first window 340 ms (< 600), idle CPU 0.016 % (< 0.2), footprint 57.5 MB (< 120).
- **`scripts/drive tree Slopapp`:** `closeButton` / `minimizeButton` / `fullScreenButton` are
  16×16; 0 `[unlabeled]` on Discover, Installed, Favorites, All Apps, Utilities, Updates
  (empty and with an update), search results, an app page, Settings.
- **Walkthrough** (debug build and release `build/Slopapp.app`, `test-feed.sh`, everything
  under /tmp/slopapp-test, light and dark, AX only: owner at the Mac, no mouse or global keys):
  Discover; click the peeking banner → it scrolls in (not opened) → click again opens it →
  ⌘[ back to Discover with the banners where they were; app page (Back enabled, no title
  drawn in the bar); Installed, Favorites (empty state), Updates (empty state centred in the
  panel), Developer category, All Apps; ⌘F + "awake" → Results; "dual" + Return → Dual's
  page; Clear button; install Testbed from a card → `bump` → ⌘R → header "1 Update", sidebar
  badge 1, Updates page with Update All; header status → Updates; `offline` + ⌘R → "Can't
  Check" and the banner along the bottom of the panel with Try Again; Tab from search → sidebar
  → Up moves Updates → Developer, Down on the last row stays; View menu has no toolbar or
  sidebar toggles; Settings in the current macOS style.
- **Not run:** real mouse clicks and drags (owner at the Mac: the window-drag strips and
  clicks in the top band were verified by hit-testing in AppKit test windows, where controls under an
  empty unified toolbar receive the click, not with the cursor); the uninstall alert after
  the SDK change (the screen locked mid-walkthrough; see below if re-run).

### Screenshots (not in the repo)

`/tmp/slopapp-chrome/shots/`: `final-discover-light.png`, `final-discover-dark.png`,
`final-detail-light.png`, `final-detail-dark.png`, `p-banner2.png` (second banner in view,
mint palette), `p-updates-2.png`, `p-offline.png`, `p-search.png`, `p-category.png`,
`p-installed.png`, `p-favorites.png`, `final-settings.png`, `try4-detail-light.png`.


## Polish pass (2026-11-05)

Brief: `docs/polish-pass.md` ("I want each app to have a very close attention to detail").
The chrome pass's design (full-size window buttons, Back/Forward in the sidebar, the inset
panel concentric with the window) is kept; this pass finishes everything inside it. Every
number below is measured on release-build screenshots (`scripts/drive shot`, 2x) with
`scripts/measure line` / `corners` and ImageMagick pixel reads, before → after. Test data:
`apps/Slopapp/test-feed.sh` (everything under `/tmp/slopapp-test`), plus a throwaway
1,001-app feed for edge content. Page content edges are x = 232 and 873 pt in the 915 pt
window (panel 196…909, 36 pt margins).

### Defects fixed

| # | Where | Before | After |
|---|---|---|---|
| 1 | Lint | 5 corner literals (split button 8, banner 16, info strip 12, card 12, sidebar row 7), 24 spacing warnings | 0 / 0: `Radius.xl`, `Radius.l`, `Radius.m`, capsule split button, card highlight concentric with the icon tile; spacing from `Spacing` or named `PageLayout` / `WindowChrome` constants |
| 2 | Card icons | art 15 pt right of the page edge (8 pt card padding + 7 pt icon margin): icons didn't line up with titles, banners or the search magnifier | art at 232 (layout by the 824/1024 icon tile, `AppIconView(alignsArt:)`); same for app page (was 248.5), More in… (+4.7) and Recently Updated (+3) |
| 3 | App page margin | 44 pt (strip and highlights at 240, everything else at 232); top padding 28 | 36 pt like every page; art top at 70 = banner / page-title top |
| 4 | Featured banner | 569 pt in a 641 pt column: right edge at 801, See All and the grid end at 873; peek 107 pt of an edge that aligned with nothing | 641 pt, edges 232 / 873; next banner peeks 24 pt in the margin, 12 pt gap (the code's stated intent: it measured the width outside the negative padding) |
| 5 | Banner text / icon | text 40 pt from the left, icon art 58 pt from the right | both 40 pt (`FeaturedBanner.inset`) |
| 6 | Banner edge, dark mode | forest banner's ink end merged into the #1E1E1E panel (no visible left edge) | 0.5 pt separator hairline inside the shape (both modes; also helps cream on white) |
| 7 | Header right side | refresh glyph ends at 882 (trailing padding 20 vs leading 36); status → divider → glyph 14 / 19 pt | glyph ends at 872 (See All ends at 872, banner at 873); 13.5 / 12.5 pt |
| 8 | Sidebar | rows 9 pt from the edges, icon centre 27 vs close button 26; first row top 76 vs page top 70; Forward chevron ends at 177 vs the rows' content edge 180 | 8 pt; icon centre 26; first row 70 (`WindowChrome.pageTop`); chevron ends 181 / count capsule ends 180 |
| 9 | Disabled Back/Forward | quaternary: #DBDCDD on #E4E5E6, practically invisible | tertiary (visible, clearly dimmer, as Finder) |
| 10 | App page buttons | Install 28 pt, its arrow 19 pt (shorter, separate shape), heart and share 30 pt | all 28 pt (top 148.5 / bottom 176.5 measured): one capsule split by a 1 pt gap; symbol buttons carry a hidden text line so they size like text buttons (`SymbolButton`) |
| 11 | Split button menu | dropped 60 pt left of the arrow | from the control's left edge, 4 pt below |
| 12 | Page header controls | top-aligned: control centre 82 vs title centre ~86 | centred on the title line (85 / 86) |
| 13 | Cards in a row | a one-line pitch next to a two-line one put the buttons 20 pt apart vertically | every card reserves two lines; buttons line up in every row (checked on All Apps and with 1,001 apps) |
| 14 | Coming Soon pill | 19 pt next to 20 pt buttons (row baselines off by 1 pt); large one 6 pt padding | exactly the button's height (`ButtonHeightSlot`: a hidden bordered button of the same control size), 20 / 28 |
| 15 | Progress in place of a button | ring 16 pt in a 20 pt slot: row height changed; What's New / shield slid sideways (progress is wider) | same slot height; the accessory steps aside while it runs |
| 16 | "Installed version 1.0.0." | pushed the rest of the grid down 20 pt, then back up 6 s later | drawn below the button outside the layout (fits in the row gap), fades in and out |
| 17 | Install → Open | after a successful install the card flashed the prominent Install again until the async rescan landed; Move to Trash flashed Open | `Store.scanInventory()` is awaited before the progress goes away: progress goes straight to the new state |
| 18 | Scrolling | on every page scroll content drew over the search field and status (macOS 26 scroll views run under the toolbar) | pages clip at the header; a hairline appears under the header only while the page is scrolled (macOS 15+) |
| 19 | Hairlines | SwiftUI `Divider` is 1 pt here (2 device pixels of #E6E6E6) | `Hairline`: 1 device pixel of separatorColor (page headers, Discover, app page, status bar, header divider, About) |
| 20 | Discover rhythm | 28 pt above each category's divider, 40 below; a divider dangling after the last row | hairlines between rows only, 32 / 32 (`PageLayout.sectionGap`) |
| 21 | Grid | row gap 26 (off the 4 pt grid) | 24 |
| 22 | Placeholder tiles | 82 % of the frame, radius 0.27 × side: rounder and 1 pt bigger than real icon art | the icon grid's 80.5 %, `Radius.iconTile(side:)` |
| 23 | Card hover / selection | radius 12 around a 13 pt icon tile 8 pt inside (not concentric); scrolling a selected card into view clipped its highlight | tile radius + 8 = 21.1; grid cells include the highlight (spacing compensated), so it scrolls fully into view |
| 24 | Status text contrast | error / notice / signature lines in plain .red / .green / .orange (green ≈ 2.2:1 on white) | SlopKit `.textRed` / `.textGreen` / `.textOrange`; primary on a selected row as before |
| 25 | Sidebar count contrast | secondary on the grey capsule: 3.4:1 (selected row) / 3.6:1, light mode | primary |
| 26 | Coming Soon contrast | secondary on button grey: 3.8:1, light mode | quinary fill (lighter than a button: it isn't one); dark 5.0:1 |
| 27 | Filter chips | no hover or pressed state; `.white` text; stayed accent-filled in an inactive window (white on grey there) | `ChipStyle`: hover, pressed, inactive (grey fill, primary text), `alternateSelectedControlTextColor` |
| 28 | Status bar (offline, Trash undo) | icon and text 16 pt in (page edge is 36); dismiss cross ended at 868 | 36 pt; cross ends at 873 |
| 29 | Quit and Update dialog | no default button; "Slopapp reopens it" when two apps quit | Return confirms; "reopens them when the updates are done" for several |
| 30 | Category with a filter that matches nothing | a grey line, no symbol, no way back | `ContentUnavailableView` with a line per filter and Show All |
| 31 | More in… and Recently Updated rows | no hover state; Recently Updated opened only on double-click; a hairline after the last row | card hover highlight (concentric with their icons); single click opens; hairlines between rows only |
| 32 | Banner paging | 350 ms slide, also with Reduce Motion | 250 ms; no slide with Reduce Motion |
| 33 | Menu bar menu | installed apps had no icons (a drawing-handler image, and menu labels default to title only) | 16 pt bitmap icons (cached), `.labelStyle(.titleAndIcon)` |
| 34 | About window | visible title and a separator under the title bar | drawn like the system's About panels: transparent title bar, no title, no separator (title still set for the Window menu and VoiceOver) |

### Checked and fine

Window corners concentric with the panel (`measure corners`: 6.0 pt along the edges, 5.7 at
the curve, window radius 17.1); Back/Forward and header on the window buttons' 26 pt
centre line; search magnifier at 233.5; empty states centred in the panel (Updates
centre 308 vs panel 306); 1,001-app feed: lazy grid, footprint 58 MB, long names and
pitches truncate at the end of the line, `See All 201` in monospaced digits; offline banner;
Move to Trash alert (default "Move to Trash", Escape cancels); Undo; settled idle CPU
0.001–0.058 %.

### Decisions

1. **Icon art, not the icon canvas, sits on alignment lines.** macOS icons carry a 100/1024
   transparent margin; at 72 pt that read as a 7 pt indent (15 with the card padding).
   Hover and selection highlights reach 8 pt past the content instead.
2. **Banner = content width**, peeking 24 pt into the margin: both its edges line up with the
   grid, See All and the header controls. The original peeks more; alignment won.
3. **Scroll hairline** under the header (only while scrolled), like Finder and System
   Settings; the chrome pass's "no divider across the top" still holds at rest.
4. **Coming Soon** is lighter than a button (quinary) rather than darker text: it's a
   status, not a disabled button, and it keeps secondary text at its contrast floor.
5. **Hairline instead of `Divider`** everywhere outside menus (menus keep native separators).

### Components built in-app (named to move to SlopKit)

`Hairline` (`Views/Hairline.swift`, one device pixel of separatorColor),
`ButtonHeightSlot` (a slot exactly as tall as a bordered button of a control size),
`SymbolButton` / `SymbolButtonLabel` (symbol-only bordered buttons as tall as text ones),
`CardHighlight` (hover/selection shape concentric with an icon tile), `ChipStyle`.

### Gates

- **`scripts/check.sh Slopapp --perf`:** PASS (lint, 63 tests in 14 suites, bundle, smoke,
  perf). Perf (load 4.9): launch 168 ms (< 300), first window 356 ms (< 600), idle CPU
  0.027 % (< 0.2), footprint 59.0 MB (< 120). An earlier run at load 9.6 missed idle CPU
  (0.266 %, launch-time feed and icon work landing in the windows); `sample` showed the main
  thread blocked throughout and settled idle measured 0.001–0.058 %.
- **`scripts/lint.sh Slopapp`:** passes with no warnings (was 5 failures, 24 warnings).
- **`scripts/drive tree`:** 0 `[unlabeled]` on Discover, Installed, Updates, Favorites, All
  Apps, Utilities, an app page, Settings; close / minimize / zoom 16×16 (main window,
  Settings, About).
- **Walkthrough** (release build, `test-feed.sh`, light and dark): every page; search and
  Return; app page with the split-button menu; ⌘D favorite; install from a card (no
  Install flash); Update All → Quit and Update (Return confirms) → progress → Recently
  Updated; What's New popover; Move to Trash (⌘⌫, Return) → status bar → Undo; offline
  (`test-feed.sh offline`) → status bar and Try Again; Settings General and About; About
  window; menu bar menu; 1,001-app feed. The screen was locked for part of the session:
  those steps ran by keyboard (keys posted to the app, window captures), the rest by AX
  once it unlocked.

### Not done (and why)

- **Hover states not seen on screen.** Card, row, chip and sidebar hover are designed in code
  (and pressed / inactive for chips), but showing them needs the real pointer: SlopDrive
  has no pointer-move, and while I post keys my own events reset `HIDIdleTime`, so I couldn't
  confirm the owner was away long enough for real-mouse checks. A blind tester should hover
  a card, a More in… row, a Recently Updated row and the filter chips.
- **Focus ring** on the custom buttons: only shows with Full Keyboard Access (a system
  setting this pass mustn't change).
- **Discover's header status during offline** still says "2 Updates" when updates are known
  (a `HeaderStatus` rule from the chrome pass, tested; Updates and the status bar both say
  the catalog couldn't be reached).

### SlopKit notes (not changed here)

- SwiftUI `Divider` draws 1 pt on macOS; there's no SlopKit hairline, so every app that uses
  `Divider` misses the 0.5 pt rule. `Views/Hairline.swift` is ready to move.
- `ButtonHeightSlot` / `SymbolButton` solve a general macOS 26 issue (image-only bordered
  buttons are taller than text ones; anything replacing a button changes the row height).

### Screenshots (not in the repo)

`/tmp/slopapp-polish/slopapp/`: `before-*-{light,dark}.png` (start of the pass),
`final-{discover,installed,updates,favorites,allapps,detail}-dark.png`,
`final-{discover,favorites,detail}-light.png`, `final-allapps-scrolled-dark.png`
(header hairline, highlight in view), `final-splitmenu-light-1.png`,
`final-releasenotes-light-1.png`, `final-menubar-1.png`, `final-settings-light.png`,
`final-settings-about-light.png`, `final-about-window.png`, `r2-trash-alert-light-1.png`,
`r5-quitupdate-light-1.png`, `r2-trashed-light.png` (Undo bar, shot before fix 28), `r4-offline-light.png`,
`r4-search-light.png`, `r5-updating-light.png`, `r6-recent-light.png`,
`r5-edge-allapps-light.png` and `r5-edge-discover-light.png` (1,001 apps, long names).

## Candy-glass pass (2026-11-06)

Owner: "I want the launcher and website aesthetic to be more of this glass + sugar candy
colour, reminiscent of the iMac G3 era. App collection should still be very modern though
for easier daily use on the eyes." Reference: `brand/reference-candy-era.png` (five
translucent coloured cases with white inner panels). New icon: `AppIcon.icon` (strawberry →
tangerine, frosted white layers). Palette: `brand.json` `candy` / `Brand.Candy`; no new
colour literals in the app (`Views/Candy.swift` derives everything from them).

### What changed

The candy is the **frame and the accents**. Pages, cards, app pages and text are unchanged:
system colours, the user's accent on buttons, quiet white / near-black panel.

| Where | Before | After |
|---|---|---|
| Window shell (sidebar + the 6 pt rim round the panel) | system sidebar material, grey | the same material washed with the icon's strawberry → tangerine (28 %), a soft plastic highlight along the top; dark mode strawberry → grape (24 %), a berry jewel, because tangerine over graphite turned brown. Half strength in an inactive window |
| Content panel | white / near-black, concentric | unchanged: the frosted "inner panel" of the case (measured concentric: 6.0 pt along the edges, 5.7 at the curve) |
| Sidebar symbols | secondary grey | strawberry (Golden Gate's coloured sidebar icons), shade computed for ≥ 3.3:1 on the shell: 3.7–4.8:1 light, 3.7–4.4:1 dark (plain strawberry measured 1.8–3.2:1 on its own tint) |
| Categories in the sidebar | blank icon slot | a flavour dot per category (website mapping: Utilities blueberry, Productivity tangerine, Design grape, Developer lime, Media lagoon, Hub strawberry) |
| Selection pill | grey (accent while the sidebar had focus) | candy glass: strawberry → coral tint, top highlight, 0.5 pt light rim; stronger while the sidebar has keyboard focus; grey in an inactive window. Label 10.4:1 light, 6.3:1 dark |
| Updates count | grey capsule | tangerine candy, graphite digits (6.6:1 light, 5.3:1 dark; a shade deeper in dark mode) |
| Header status | accent text | "Up to Date" in strawberry (4.5:1 computed on the panel); waiting updates as a glossy tangerine capsule with graphite text |
| Category titles (Discover rows, category pages) | plain | the flavour dot hangs in the margin 12 pt before the title (the title stays on the 232 pt edge); See All in the flavour's readable shade |
| Featured banners | forest / mint / cream | candy flavours in turn (strawberry hero, lagoon, tangerine, grape, lime, blueberry): saturated gradient (the lead colour holds under the text, the gradient happens behind the icon), a sheen ellipse across the top, a frosted ice disc behind the icon, a little shade along the bottom edge, a 0.5 pt light rim, and a shadow in the banner's own colour (black and tighter in dark mode). The hero is deepened strawberry → tangerine with white text, like the website's primary button |
| Banner text | ≥ 4.5:1 by palette choice | computed: graphite on tangerine / lime / lagoon in light mode; white elsewhere, the lead darkened until white clears 5.2:1 (headroom for the sheen). Dark mode: every banner a deep jewel with white text. Measured (sRGB, worst point beside the text, eyebrow to subtitle): light 4.95 (lagoon subtitle) … 7.7:1, dark 5.4 … 9.3:1. First version measured 3.1–4.4:1 in six spots (trailing colour under the text, sheen over the eyebrow, 90 % text) |
| Inactive window | n/a | symbols, dots, count, status capsule and selection go grey; the shell wash halves; banners keep their colour (they're imagery) |

Measurement note: screenshots are Display P3; all colour numbers above are after converting
to sRGB (`magick -profile "sRGB Profile.icc"`). Read raw, the candy colours look ~25 % paler
(sRGB `#0A9DBF` is `#449CBC` in P3).

### Decisions

1. **Primary: strawberry + the icon gradient.** The other flavours only tell categories
   apart (and take turns on the banners), with the website's category mapping.
2. **Gloss only on candy surfaces we draw** (selection pill, count, status capsule, banners).
   Native buttons stay native: no gel buttons, no textures, no pinstripes.
3. **The shell tints the system material**; it doesn't replace it. The desktop still blurs
   through and the clear / tinted setting still changes the material; sidebar text is the
   system label colour (10:1 or more on the shell).
4. **Dark mode is its own palette**, not dimmed light mode: berry → plum shell, jewel banners,
   deeper solid candy, black shadows.
5. **Banners are computed for contrast**, not tuned by eye; carousel is lazy and the banner
   shadow is cast by a plain shape behind it (79 MB footprint on the real feed; 85 MB with
   the whole banner rendered offscreen for its shadow).

### Golden Gate + light/dark

- Sidebar: still the chrome pass's own full-height sidebar (edge to edge, no inset card), now
  with coloured symbols. Not the system `NavigationSplitView` sidebar (deviation recorded in
  the chrome pass: the Setapp-like layout needs Back/Forward on the window buttons' row).
- Menus: text only. The menu bar menu shows installed apps' icons (information, allowed);
  context menus and the split-button menu are plain text.
- Toolbar: unchanged from the chrome pass (empty unified toolbar for full-size buttons; the
  search row lives in the panel).
- Inactive window: checked on every page (`inactive-*.png`): accents grey out.
- Glass: system material only; no readable text sits on clear glass without the label colour.
- Light and dark: every page, the banners (all five flavours) and the chrome measured in both.
  Dark shadows are black and tighter; nothing pure white or black drawn as a surface (the
  panel is `textBackgroundColor`).

### Gates

- `scripts/check.sh Slopapp --perf`: PASS. Perf (load 7–12): launch 133–152 ms, first window
  368–382 ms, idle CPU 0.021–0.091 %, footprint 78–85 MB (< 120; 59 MB before this pass,
  the rest is the candy layers; the new layered icon was measured and isn't it). One perf run
  at idle 0 (someone using the Mac) read 9.6 % / 300 MB and didn't reproduce in three more
  runs or a 50 s soak (0.004–0.27 %, steady 80 MB).
- `scripts/lint.sh Slopapp`: passes. The only new numeric colours are two measured sidebar
  samples used as contrast references (`// lint:allow`), not drawn.
- Key-window shots were taken only after 60 s without input; the owner was at the Mac for
  part of the session, so some runs waited or skipped (About window with the new icon not
  shot for that reason).

### Owner choices

- **Content buttons**: they keep the system accent (blue for most people), as the design
  system says, so the candy stays in the frame. Alternative: give the launcher its own
  accent (strawberry, deepened for white text) so Install / Update match the frame. That's
  one `AccentColor` asset plus `NSAccentColorName`; macOS uses it only when the user's
  accent is set to Multicolor.
- **Hero banner**: deepened strawberry → tangerine with white text (matches the website's
  button). Alternative: bright strawberry with graphite text (4.6:1), more "candy", less
  matching.

### Screenshots (not in the repo)

`/tmp/slopapp-polish/slopapp/candy/`: `before-*-{light,dark}.png`;
`key-{discover,installed,updates,allapps,category}-{light,dark}.png` (key window);
`inactive-*-{light,dark}.png`; `banner-{0-strawberry,1-lagoon,2-tangerine,3-grape,4-lime}-{light,dark}.png`.
