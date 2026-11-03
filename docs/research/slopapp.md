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
| 1 | Library window with sidebar | ~1100×640 window. Sidebar: personal dashboard, Favorites, My Apps, Collections, How-tos, App Guides, All Apps (with five task categories indented under it), AI category, Updates (with a count badge). Back/forward arrows sit above the sidebar. | must | `NavigationSplitView`: Discover, Installed, Updates (count badge), Also great. Keep it to four items. |
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
| 27 | Sidebar shortcuts | Go menu: ⌘1 dashboard, ⌘2 Favorites, ⌘3 My Apps, ⌘4 All Apps; Refresh ⌘R. | must | ⌘1–⌘4 for our four sections. |
| 28 | Also great (third-party) | n/a (Setapp only lists its own catalog). | must | Static list from the feed: Rectangle, Maccy, IINA, Keka, AlDente, Stats. Each: what it does, what it replaces, "Installed" if detected, button opens its website. We don't download or update them. |
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
- **View:** Discover ⌘1, Installed ⌘2, Updates ⌘3, Also Great ⌘4.
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

- [x] Library window: sidebar Discover, Installed, Updates (count badge), Also great; ⌘1–⌘4.
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
- [x] Also great: Rectangle, Maccy, IINA, Keka, AlDente, Stats with description, what they replace, Installed badge, website link. *(No "what they replace" line.)*
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
  Installed, Updates, Also Great, detail, uninstall sheet, Settings, About, menu bar menu.
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
| 3 | Every action in a menu with shortcut | PASS (View ⌘1–4, Apps menu ⌘O ⇧⌘R ⌘⌫ ⇧⌘U, ⌘R, ⌘F) |
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
