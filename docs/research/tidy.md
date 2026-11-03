# Tidy research (inspired by CleanMyMac)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-02: **CleanMyMac 5.7.3 (50703)**, Setapp build, `/Applications/Setapp/CleanMyMac.app`,
> read-only. Also MacPaw's help center, Setapp reviews, press reviews (Macworld, MacStories,
> TidBITS Talk), and two open-source and freeware references for leftover finding:
> **Pearcleaner 5.4.3** (source read at commit `7724df7`) and **AppCleaner** (FreeMacSoft,
> closed source, studied through reviews). We study how they work so we don't reinvent the
> wheel. We never copy their names, icons, artwork, wording, sounds or signature visuals.
>
> **How the installed copy was studied.** Only CleanMyMac's Finder Sync extension was
> running. The main app and its menu bar agent were not. Launching the main app opens its
> main window, which shows the owner's disk and scan data. That is off limits, and the brief
> also says never to relaunch it, so **I did not launch it**. No window was opened or
> screenshotted, no scan ran, and no setting was touched. Instead I read the bundle
> statically: `Info.plist`, the framework list, and the English `Localizable.strings` of
> the Applications, Cleanup, My Clutter, Space Lens, Settings and main-menu modules. That
> gave the menu structure, the Settings panes and their controls, the uninstaller's resource
> groups, the junk categories and the Large & Old filters, with no personal data.
> Keyboard shortcuts and Settings defaults can't be read this way; they are marked "not
> observed".
>
> Pearcleaner is licensed Apache 2.0 + Commons Clause. We learn from its approach only;
> **no code is copied**.

## The job

Someone wants their disk space back and their Mac free of things they no longer use, without
breaking anything. There are two triggers. The first is "I'm done with this app": dragging
it to the Trash leaves preferences, caches, containers, launch agents and helpers behind,
sometimes still running at login. The second is "my disk is full": where did 40 GB go? Often
it's caches, logs, Xcode DerivedData and simulators, old device support files, or a few huge
forgotten files. "Done" is a reviewed list where everything was understood before it left,
it all sits in the Trash where it can be restored, and the space shows up once the Trash is
emptied. **The one interaction that matters: pick an app (from a list or by dropping it) →
see every file that belongs to it, grouped by kind, with sizes and paths → uncheck anything
doubtful → Move to Trash.** Junk and Large & Old work the same way: a reviewed, checkable list,
then Move to Trash.

## Who and when

- An app trial ended, or a Setapp app is no longer wanted: remove it and its leftovers.
- An app misbehaves: wipe its preferences and support files and start fresh ("reset"),
  keeping the app.
- "Your disk is almost full": find the big things fast (caches, DerivedData, simulators,
  device support, old ISO/DMG/video files).
- A developer's monthly sweep: DerivedData for deleted projects, unavailable simulators,
  device support for iOS versions they no longer test on.
- Housekeeping after years of installs: leftovers from apps deleted long ago.

Frequency: a few times a month for uninstalls (seconds each), a monthly or "disk full" sweep
for junk (1–5 min). Nobody keeps this app open; it must be fast to open and quiet when closed.

## CleanMyMac at a glance (5.7.3)

- **Shape.** One big window with a left sidebar of modules: Smart Care, Cleanup,
  Protection, Performance, Applications, My Clutter, Space Lens, Cloud Cleanup, Assistant
  (View menu order). Every module has the same rhythm. It opens on an intro screen with a big
  Scan button, then shows a scanning screen with the current path, then summary **tiles**
  ("X GB found", each with Review / Clean / Remove). A "Review All…" button leads to a
  **manager**: categories on the left; a checkable list in the middle with groups,
  search and sort; a bottom bar with the selected total and the action button. After the
  action comes a completion screen (View Log, Review More Items, Done).
- **Applications module.** Uninstaller (sidebar filters: All Applications, Unused (not
  opened for 6 months), Suspicious, Selected, Stores (App Store, Setapp, Steam, Battle.net,
  Other), Vendors (Apple, Adobe, Google, JetBrains, MacPaw, Microsoft, Other), Plugins
  (Audio)). The other parts are Updater, Leftovers (files of already-removed apps) and
  Installers (unused DMGs). Each app row shows the icon, name, last opened, total size, and
  a disclosure with its resources grouped as: Applications, Binaries, Preferences,
  Supporting Files, Container, Logs, Crashes, Login Items, Plugins, Dock Icon, Help,
  User Data, Installers, Other. Sort by name, size, last opened or last updated. Right-click:
  Open, Select (with all resources), Reveal in Finder, Get Info, Ignore, Quick Look. "Reset"
  means selecting every resource except the binaries. System apps sit on the ignore list
  by default ("Ignore system applications" setting); they can be reset but not removed.
- **Running apps.** A quit sheet lists the apps that must quit to clean all their files:
  Quit / Quit All / Force Quit / Ignore and Continue, plus a "Can't be quit" state.
- **Cleanup module.** System Junk (groups: User Cache Files, System Cache Files, User Log
  Files, System Log Files, Language Files, Universal Binaries, Document Versions, iOS
  Device Backups, Broken Preferences, Broken Login Items, Deleted Users, Xcode Junk), plus
  AI Clutter (AI tool caches, logs, temp files, stale versions; Ollama / LM Studio models),
  Mail Attachments and Trash Bins.
- **Smart Selection defaults (from the help center).** Preselected: all broken login
  items and broken preferences, user and system logs, system caches, language files, and
  all user caches except Gradle. iOS backups are preselected except the newest. Document
  versions saved under 4 h apart are preselected, keeping the latest in each range. Xcode
  Junk is preselected except module caches and archives. The Xcode group only appears if
  Xcode is installed and has built something.
- **Xcode Junk contents.** Derived data, module caches, device support files, iOS device
  logs, archives, simulators, Xcode caches.
- **My Clutter module.** Large & Old Files, Duplicates, Similar Images, Downloads (Safari,
  Chrome, Slack). Pick a location (internal, external or connected drive). Large & Old shows
  only files ≥ 50 MB and **preselects nothing**. Filters: **By Kind** (Archives,
  Documents, Pictures, Videos, Other), **By Size** (Small = tens of MB, Average = hundreds
  of MB to 1 GB, Huge = several GB), **By Access Date** (one week, one month, six months, one
  year ago, plus "last week"), and Selected. Search, sort by size, name or date. Right-click:
  Select, Reveal, Get Info, Quick Look. **Removal is permanent and bypasses the Trash**
  (help center).
- **Everything else.** Malware scanning (Moonlock engine), Performance (RAM, maintenance
  scripts, login items), Space Lens (bubble map of disk usage), Cloud and Email Cleanup,
  the Assistant, a Health Monitor menu bar app, an App Updater, Finder integration
  ("uninstall from Finder"), a trash watcher that offers to uninstall correctly when an app
  is dragged to the Trash, and an "Agent" privileged helper with Authenticate… /
  Deauthenticate in the app menu.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason).

### Uninstall

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | App list | Scan first, then "Manage My Applications" opens the list: icon, name, last opened, size (incl. resources) | must | Lists apps immediately from `/Applications`, `/Applications/Setapp`, `~/Applications` and Spotlight (`kMDItemContentType == com.apple.application-bundle`, local volumes). Sizes computed lazily off the main actor and cached by bundle path + modification date. |
| 2 | Pick by drop / Open | Drop on window | must | Drop a `.app` on the window or the Dock icon, or `⌘O` "Choose App…". Selects that app and runs its leftover search. |
| 3 | Leftover search for one app | Disclosure under the app row lists resources by group | must | Detail pane: groups by kind with per-group and per-item sizes; each item shows its path (abbreviated with `~`). Rules in "Recommended leftover-matching rules" below. |
| 4 | Groups by kind | 14 resource groups (Binaries, Preferences, Supporting Files, Container, Logs, Crashes, Login Items, …) | must | Our groups: App, Application Support, Caches, Preferences, Containers, Group Containers, Saved State, Web Data (HTTPStorages, WebKit, Cookies), Launch Items (agents, daemons, helpers), Logs & Crash Reports, Other. |
| 5 | Uncheck items | Checkbox per resource; select app "with all resources" | must | Checkbox per item and per group (tri-state). Everything with an ID match is checked; name-only and shared items are labelled, and shared items start unchecked. |
| 6 | Move to Trash | Removes (permanently for most modules); progress screen; log | must | `FileManager.trashItem` per item, recording (original → trashed URL) pairs. Result line: "Moved 14 items (1.2 GB) to the Trash", with Undo, Open Trash and Show Details. |
| 7 | Put Back / undo | None in-app; Trash only where it uses the Trash | must | Finder's Put Back doesn't work for files trashed through `FileManager` (rdar 41878624). Instead `⌘Z` / "Put Back" in Tidy moves the recorded items back. A History list keeps past removals while the items are still in the Trash. |
| 8 | Refuse Apple system apps | System apps hidden via the ignore list; resettable but not removable | must | Refuse if the path is under `/System`, or the code satisfies the `anchor apple` requirement (OS-signed: Safari, Notes…). Verified on this Mac: Safari and Notes pass; Xcode, Pages, Keynote and GarageBand (App Store, "Apple Mac OS Application Signing") don't, so they **can** be uninstalled. |
| 9 | Running apps must quit first | Quit sheet: Quit / Quit All / Force Quit / Ignore and Continue | must | Sheet listing the app and any running helpers whose bundle IDs are in its ID family. Buttons: Quit (polite terminate), Force Quit (after 5 s without response), Cancel. **No "ignore and continue".** |
| 10 | Leftovers of already-deleted apps | Applications › Leftovers, found by a background scan | must | Sidebar item "Leftovers" under Uninstall (or a filter on the app list). Conservative orphan rules (below); **nothing preselected**; grouped by inferred bundle ID with path, size and last modified. |
| 11 | Reset an app | Select every resource except binaries | should | "Reset…" action: same list with the app bundle unchecked and locked. Cheap once #3 exists. |
| 12 | Batch uninstall | "Selected" filter accumulates several apps | later | One app at a time in v1 keeps the review honest. Multi-select of apps later. |
| 13 | Sort and search apps | Sort by name, size, last opened, last updated; search | must | Sort by Name / Size / Last Opened (`kMDItemLastUsedDate`); `.searchable`, `⌘F`. |
| 14 | Filters: unused, store, vendor | Unused (6 months), Stores, Vendors, Plugins | should | "Not opened in 6 months" filter is cheap (Spotlight last-used). Store/vendor filters later. |
| 15 | Suspicious apps | Flags apps from vendors in certain countries | skip | Security/political judgement, not our job; no malware claims. |
| 16 | 32-bit / unsupported badge | Crossed-out icon | later | Rare on Apple silicon Macs now. |
| 17 | Audio and other plugins | Plugins filter (audio) | later | Separate inventory of `~/Library/Audio/Plug-Ins/*`, QuickLook, PreferencePanes, Screen Savers. |
| 18 | Root-owned items (App Store apps, `/Library` daemons and helpers) | Privileged "Agent" helper; Authenticate… | must | App Store apps and pkg-installed files are `root:wheel` (verified: Xcode, Pages). Moving them needs an administrator. v1: one standard admin password prompt at removal time for just those items, or "Reveal in Finder" if the user cancels. See open question 1. |
| 19 | Finder integration | Finder Sync extension: uninstall from Finder | should | A **Services** entry "Uninstall with Tidy" for `.app` files (no extension process, nothing running). |
| 20 | Offer to uninstall when an app hits the Trash | Notification ("offer to uninstall correctly"), via the menu agent | later | Needs a background watcher on `~/.Trash`; conflicts with "quiet by default" and idle budgets. Leftovers (#10) catches the same files after the fact. |
| 21 | Remove Dock icon | "Dock Icon" resource group | skip | Editing the Dock's prefs is fragile; macOS drops missing apps from the Dock itself. |
| 22 | App Updater | Checks versions online | skip | Needs a network and a catalog; out of scope. |
| 23 | Installers (unused DMGs/PKGs) | Applications › Installers | should | `.dmg`/`.pkg` in `~/Downloads` (and Desktop) with sizes, unchecked. Lives under Junk in Tidy. Needs FDA or a folder grant for Downloads. |
| 24 | Pkg receipts | Not surfaced | later | `pkgutil --files` lists can include shared paths; risky. |
| 25 | Ignore list | Right-click › Ignore; Settings › Ignore List per module; "Reset All" | should | Right-click "Ignore" on an app, item or junk group; Settings › Ignored lists them with a Remove button. |

### Junk

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 26 | User caches | User Cache Files, grouped by app, all preselected except Gradle | must | `~/Library/Caches/*` and the per-user `DARWIN_USER_CACHE_DIR` entries, grouped by owner app (resolved from bundle ID to name and icon). Preselect third-party caches; `com.apple.*` caches listed but unchecked; caches of **running apps unchecked** with "Quit X to clean". |
| 27 | User logs | User Log Files, preselected | must | `~/Library/Logs/*` (per app) + `~/Library/Logs/DiagnosticReports` (crash reports). Preselected. |
| 28 | Xcode junk | DerivedData, module caches, device support, device logs, archives, simulators | must | See the "Developer junk" list below. DerivedData per project with the project name read from its `info.plist` (`WorkspacePath`), flagged "project no longer exists" when it's gone. Archives unchecked, with a note that they hold the dSYMs needed to symbolicate crash reports. |
| 29 | Unavailable simulators | Part of Xcode Junk | must | Simulator devices whose runtime is no longer installed (`device.plist` runtime vs installed runtimes). See open question 3 for how they're removed. |
| 30 | Package-manager caches | Not covered (AI Clutter covers some AI tools) | should | Pure caches only: SwiftPM, CocoaPods, Carthage, Homebrew downloads, npm `_cacache`, Yarn, pip, uv, Go build cache, Gradle caches (unchecked). Never `~/.cargo` wholesale, `~/.m2`, `~/.nvm`, `~/.conda` or other things that hold installed toolchains. |
| 31 | System caches and logs (`/Library`, `/private/var`) | System Cache / Log Files, preselected | later | Needs admin and can fight running daemons. v1 is user-level only. |
| 32 | AI tool clutter | AI Clutter (Claude, Codex, Gemini, Cursor caches/logs; Ollama / LM Studio models) | later | Relevant to the owner, but folders like `~/.claude` mix caches with config, history and projects. Needs a careful per-tool list; models are huge and re-downloadable but user-chosen. |
| 33 | Language files | Removes unused `.lproj` from app bundles | skip | Modifies signed app bundles, breaks signatures and updates. |
| 34 | Universal binaries | Strips the other architecture | skip | Same: modifies signed bundles; comes back on update. |
| 35 | Document versions | Removes versions < 4 h apart | skip | System-managed store, little benefit, risk to user data. |
| 36 | iOS device backups | Preselects all but the newest | later | Big wins but irreplaceable data; needs its own careful UI. |
| 37 | Broken preferences / login items | Detects corrupt plists and dead login items | later | Small wins; login items overlap with Background Items in System Settings. |
| 38 | Mail attachments, Trash bins, deleted users | Separate categories | skip | Mail data and Trash emptying are permanent deletes; deleted-user folders need admin and are rare. |
| 39 | "Empty the Trash to free X" | Not applicable (deletes permanently) | must | After any move, the result says how much space is freed **once the Trash is emptied**, with an Open Trash button. We never empty it ourselves. |

### Large & Old

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 40 | Large & Old list | Files ≥ 50 MB in a chosen location; nothing preselected | must | Home folder by default (excluding `~/Library` and `~/.Trash`). Spotlight query for speed (`kMDItemFSSize ≥ threshold`), with a `FileManager` walk as a fallback when Spotlight is off for a volume. Bundles/packages count as one item. Nothing preselected. |
| 41 | Threshold | Fixed 50 MB | must | Default 50 MB; a toolbar menu offers 50 MB / 100 MB / 500 MB / 1 GB. |
| 42 | Filters / grouping | By Kind, By Size, By Access Date, Selected | must | Toolbar: Kind (Videos, Pictures, Audio, Archives & Disk Images, Documents, Other), Last opened (any, > 1 month, > 6 months, > 1 year), sort by size, name, last opened. "Last opened" = `kMDItemLastUsedDate`, falling back to the modification date. |
| 43 | Choose location | Drop-down of drives and connected devices | should | "Choose Folder…" to scan another folder or an external volume. Without FDA this is also the graceful fallback (see Permissions). |
| 44 | Quick Look / Reveal / Get Info | Right-click menu | must | Space = Quick Look; Reveal in Finder; Copy Path. |
| 45 | Move to Folder / secure erase | CMM X offered Move to Folder and Remove Securely | skip | Secure erase is meaningless on APFS/SSD; "Move to folder" is Finder's job. |
| 46 | Duplicates, Similar Images | My Clutter | skip | Separate Slopapp app (Twins). |
| 47 | Downloads review | Per browser and Slack | later | Overlaps with Large & Old and Installers. |
| 48 | Disk map (Space Lens) | Bubble visualisation of folders | later | Nice, but a separate interaction model; not part of the owner's v1. |

### App-wide

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 49 | Full Disk Access | Assistant recommendation "Allow Full Disk Access"; Settings › General shows status + Enable; Help › About Full Disk Access | must | SlopKit `PermissionGate(.fullDiskAccess)` shown **inside each section only when it matters**, with partial results still visible below a banner. Live re-check. |
| 50 | Review before delete | Smart Care can clean without review ("Clean" on a tile) | must | **Every** removal goes through the checked list and a visible total. No one-click "clean everything". |
| 51 | Log of what was removed | View Log after each cleanup | should | History sheet: date, count, size, paths; Put Back while the items are still in the Trash. |
| 52 | Smart Care (one-click scan of everything) | Big button scanning all modules | skip | Encourages deleting without understanding; our sections each load fast enough on their own. |
| 53 | Malware scanning, real-time protection | Moonlock engine, background monitor | skip | Owner rule: no malware claims. XProtect already does this. |
| 54 | "Speed up", RAM release, maintenance scripts | Performance module | skip | Owner rule: no speed/RAM/optimisation claims. They're mostly placebo on modern macOS. |
| 55 | Menu bar health monitor | Separate login-item app with CPU/RAM/disk/battery tiles | skip | Gauge (roadmap) covers system stats; Tidy has no background presence. |
| 56 | Notifications (low space, Trash size, reminders) | Settings › Notifications | skip | No background process; "quiet by default". |
| 57 | Smart Insights (AI explains an item) | Apple Intelligence, macOS 26+ | later | On-device Foundation Models could explain an unknown folder. Nice, not v1. |
| 58 | Sounds, themes, intro animations | Sound on main actions, custom themes, motion | skip | Design system: system sounds only, honour Reduce Motion. Setapp reviewers ask to skip the animations. |
| 59 | Cloud, Email cleanup, Updater, Assistant | Separate modules | skip | Out of scope, network, accounts. |

## Recommended leftover-matching rules

These are what the build implements and unit-tests with fake file trees. Principle:
**identifier matches first, exact names second, never substrings.** AppCleaner's and
Pearcleaner's strict modes are close to this. Pearcleaner's Enhanced and Deep modes (substring,
team-ID prefix, company name, Spotlight metadata/content) are exactly where its reported
false positives come from. A competitor's review cites "Opera" matching `operations.pdf`,
and its orphan search flagged files of still-installed apps
([discussion #528](https://github.com/alienator88/Pearcleaner/discussions/528)).

**Identity, read from the app bundle before anything moves**

1. **B**: `CFBundleIdentifier`. If it's missing, only name rules (6) apply and every result
   is unchecked.
2. **Names N**: `CFBundleName`, `CFBundleDisplayName`, `CFBundleExecutable`, and the `.app`
   file name without its extension. Deduplicated. Names under 4 characters are dropped, and
   so is anything on a **generic-word stoplist** (e.g. Notes, Mail, Music, Photos, Code,
   Data, Cache, Default, Helper, Update, Updater, Setup, Agent, Google, Microsoft, Adobe,
   Apple, Java, Python, Node, Electron, Steam, CrashReporter).
3. **ID family F**: B, plus the bundle IDs of every bundle embedded in the app (login
   items, launch services helpers, XPC services, app extensions, helper apps). Frameworks are
   excluded: their IDs (Sparkle, Sentry…) are shared by many apps.
4. **App groups G**: the `com.apple.security.application-groups` entitlement of the app
   and its embedded bundles, read with `SecCodeCopySigningInformation`.
5. **Team ID T**: used only to *protect* items (rule 14), never to select them.

**Matching for an installed app**

6. **Normalise item names** before comparing. Strip a known suffix: `.plist`,
   `.savedState`, `.binarycookies`, `.sfl2`/`.sfl3`, or the ByHost
   `.<hardware-UUID>.plist`. Compare case-insensitively.
7. **ID rule**: an item matches if its normalised name **equals x or starts with x + "."**
   for some x in F. Prefixes stop at a dot boundary (`com.foo.app` never matches
   `com.foo.app2` or `com.foo.application`). Plain "contains" is never used.
8. **Containers**: `~/Library/Containers/<x>` for x in F, plus UUID-named containers whose
   `.com.apple.containermanagerd.metadata.plist` `MCMMetadataIdentifier` is in F.
9. **Group containers and Application Scripts**: names exactly in G. If another installed
   app also declares that group, the item is shown **unchecked** with "Also used by <app>".
10. **Launch items**: a plist in `~/Library/LaunchAgents`, `/Library/LaunchAgents` or
    `/Library/LaunchDaemons` matches if rule 7 holds for its file name or `Label`, if its
    `Program` / `ProgramArguments[0]` points inside the app bundle, or if its
    `AssociatedBundleIdentifiers` intersect F. The `/Library/PrivilegedHelperTools` binary
    named by a matched plist's `Program` also matches. Loaded user agents are booted out
    (`launchctl bootout gui/<uid>/<label>`) before their plist is trashed.
11. **Exact names**: in Application Support, Caches and Logs (user and `/Library`), a
    direct child whose name equals a name in N is a match. The comparison is
    case-insensitive and also tries the name with spaces removed. It is skipped if another
    installed app claims that name or ID. Shown with the caption "Matched by name"; checked.
12. **Vendor folders (should)**: inside Application Support, Caches and Logs, a direct
    child named like B's organisation component (`com.<org>.app`) may hold a rule 7 or 11
    match one level down. Only the inner item is proposed, never the vendor folder.
13. **Fixed per-ID locations**, all using rule 7:
    - `~/Library/Preferences/<x>.plist` and `ByHost/<x>.<UUID>.plist`
    - `~/Library/Saved Application State/<x>.savedState`
    - `~/Library/HTTPStorages/<x>` (folder and `.binarycookies`)
    - `~/Library/WebKit/<x>`
    - `~/Library/Cookies/<x>.binarycookies`
    - `~/Library/Caches/<x>`
    - `~/Library/Application Support/<x>`
    - `~/Library/Logs/<x>`
    - `DARWIN_USER_CACHE_DIR/<x>` and `DARWIN_USER_TEMP_DIR/<x>`
    - `…/com.apple.LSSharedFileList.ApplicationRecentDocuments/<lowercased B>.sfl*`
    - Crash reports in `~/Library/Logs/DiagnosticReports` (and `/Library/…`) whose name
      starts with the executable name followed by `-` or `_`
14. **Never**:
    - substring, fuzzy or Spotlight-metadata matching
    - Team-ID-prefix or company-name selection
    - anything in `~/Documents`, `~/Desktop` or home-root dotfiles (v1)
    - `/System`, `~/.Trash`
    - a standard Library folder itself, or the home folder
    - `com.apple.*` items, unless B itself is `com.apple.*` (App Store Apple apps like
      Xcode), and even then never `~/Library/Developer`, which belongs to Junk
    - symlinks are trashed as links and never followed
    - nested results collapse into their parent
15. **Setapp variants**: `<id>-setapp` and `<id>` are the same family for *protection*. An
    uninstall of one shows the other variant's files **unchecked** under "Other version".
16. **Re-validate right before trashing**: the path still exists, it isn't a symlink
    swapped in since the scan, and it still matches.

**Leftovers of already-deleted apps (orphans)**

17. Scan only the **direct children** of: Application Support, Caches, Preferences (+
    ByHost), Containers, Group Containers, Application Scripts, Saved Application State,
    HTTPStorages, WebKit, Cookies, LaunchAgents, Logs.
18. A candidate must have a **reverse-DNS name** after normalisation: at least 3
    dot-separated components, no spaces, first component a TLD-like token (com, org, net, io,
    app, dev, co, me, de, …). Group containers: `<TEAMID>.<rest>` or `group.<rest>`.
    **Names that aren't IDs are never orphan candidates in v1.**
19. Installed set:
    - the ID families and app groups of every app found by Spotlight on local volumes
    - direct enumeration of `/Applications` (+ `Setapp`), `~/Applications` and
      `/System/Applications`
    - bundle IDs of running processes
20. **Not an orphan** if any of these hold:
    - it equals an installed ID, or starts with an installed ID + "."
    - an installed ID starts with it + "."
    - it differs from an installed ID only by `-setapp`
    - it's `com.apple.*`
    - any installed app shares its organisation (`com.<org>.`)
    - for group containers: an installed app declares the group or has the same team-ID
      prefix
21. **Not an orphan if modified in the last 7 days**: something still writes to it.
22. Results are grouped by inferred ID with total size and last modified; **nothing
    preselected**.

## Developer junk (v1 list)

All under `~/Library/Developer` unless noted. Shown only when present:

| Item | Default | Note |
|---|---|---|
| Xcode DerivedData (per project) | checked | Project name from `info.plist` `WorkspacePath`. "Project not found" badge when the workspace is gone. Rebuilds on next build. |
| Module cache (`DerivedData/ModuleCache.noindex`) | unchecked | Slow to rebuild (CMM also leaves it unchecked). |
| Xcode caches (`~/Library/Caches/com.apple.dt.Xcode`, `…/com.apple.dt.xcodebuild`) | checked | |
| iOS / watchOS / tvOS / visionOS / macOS DeviceSupport (per OS version) | checked | Re-copied from the device on next connect (slow). Show the version and build. |
| iOS Device Logs | checked | |
| Documentation cache (`Xcode/DocumentationCache`) | checked | |
| SwiftUI Previews devices (`Xcode/UserData/Previews`) | checked | Recreated by Xcode. |
| Simulator caches (`CoreSimulator/Caches`) | checked | |
| Unavailable simulators (runtime no longer installed) | checked | See open question 3. |
| Archives (`Xcode/Archives`, per archive) | unchecked | Contains the dSYMs needed to read crash reports for shipped builds. |
| Package-manager caches (should, #30) | checked, Gradle unchecked | Pure caches only. |

Simulator runtimes (multi-GB disk images managed by `simctl runtime`) are **later**: they
can't go to the Trash.

## Key flows

### CleanMyMac flow 1: uninstall an app (from help center and bundle strings)
1. Sidebar › Applications. An intro screen explains Uninstaller / Updater / Leftovers. Click Scan.
2. Scanning screen ("Looking in <path>"), then summary tiles (unused apps, leftovers found,
   installers found, updates).
3. "Manage My Applications" → manager window section Uninstaller, filter All Applications.
4. Tick an app (or expand it and tick individual resources). Right-click for Reveal, Quick
   Look, Ignore.
5. Uninstall (bottom bar). If the app or its helpers are running, a sheet lists them: Quit /
   Quit All / Force Quit / Ignore and Continue.
6. Progress screen ("Uninstalling applications…"), then a completion screen with the result
   and View Log / Review More Items / Done. Failures say to quit related apps and retry.

### CleanMyMac flow 2: first run (from help center and bundle strings)
1. Activation (Setapp build: licensed by Setapp; direct build: MacPaw account sign-in or trial).
2. Intro flow, then the Smart Care home with one big Scan button.
3. Running a scan registers its helper components with macOS so they show up in
   Privacy & Security › Full Disk Access. The Assistant then shows "Allow Full Disk Access"
   with a button that opens System Settings. Without FDA it still runs but "can't scan all
   areas".
4. A privileged Agent asks for an admin password (Authenticate…) for system-level work.
5. Background items (menu agent, health monitor, updater) need "Allow in the Background" in
   System Settings for monitoring features.

### Tidy flow 1: uninstall an app (the main job)
1. Open Tidy. The window opens on **Uninstall**: the app list (icon, name, size,
   last opened) appears immediately, and sizes fill in as they're computed.
2. Pick an app: click it, type to filter (`⌘F`), drop a `.app` on the window or Dock icon,
   or `⌘O`.
3. The detail pane shows the app header (icon, name, version, total) and then the groups.
   Each group is a disclosure with a tri-state checkbox and its size. Each item has a
   checkbox, name, abbreviated path, size and a caption when it matters ("Matched by name",
   "Also used by Word", "Needs administrator").
4. Uncheck anything doubtful. Space = Quick Look, Reveal in Finder from the context menu.
5. Press **Move to Trash** (`⌘⌫`); its label carries the total ("Move 14 Items to Trash
   (1.2 GB)").
6. If the app or a helper is running, a sheet asks to quit it first: Quit / Cancel, with
   Force Quit offered after 5 s. Nothing moves until it has quit.
7. Items that need an administrator are grouped into one standard admin prompt (see open
   question 1).
8. Result banner: "Moved 14 items to the Trash. Empty the Trash to free 1.2 GB." Buttons: Put
   Back (`⌘Z`), Open Trash. The app disappears from the list.
9. Refused cases explain themselves inline. "Safari is part of macOS and can't be
   uninstalled." "Tidy can't uninstall itself. Drag it to the Trash."

### Tidy flow 2: first run / Full Disk Access
1. No onboarding. The window opens on Uninstall with the app list (needs no permission).
2. Selecting an app runs the search right away. Without FDA, a slim `PermissionGate` banner
   sits above the results: one sentence ("Tidy needs Full Disk Access to see app containers
   and other protected folders, so some leftovers may be missing."), plus "Open System
   Settings". Results from readable places are still listed. **Protected folders are not
   touched without FDA**, so no "access data from other apps" prompts appear.
3. Junk works without FDA for most of `~/Library/Caches`, `~/Library/Logs` and
   `~/Library/Developer`, with the same banner.
4. Large & Old without FDA: scanning the home folder would trigger separate Desktop /
   Documents / Downloads prompts. So the section shows the gate with two options: Open
   System Settings, or "Choose Folder…" (an open panel grants access to that folder only).
5. Granting FDA is picked up live (1 s re-check while the gate is visible) and the
   current section rescans.

### Tidy flow 3: clear junk
1. Sidebar › **Junk**. The scan starts on first open (only known folders, a few seconds) and
   shows progress per group.
2. The list is grouped: Caches (by app), Logs (by app), Crash Reports, Developer (Xcode
   DerivedData by project, Device Support by version, Simulators…), Installers (should).
   Each group shows a size and defaults per the tables above.
3. Running apps' caches are unchecked with "Quit <app> to clean".
4. Move to Trash → result with "Empty the Trash to free X" and Put Back.
5. `⌘R` rescans.

### Tidy flow 4: large and old files
1. Sidebar › **Large & Old**. With FDA it scans the home folder (Spotlight) on first open;
   without FDA it offers Choose Folder….
2. A table with name, kind icon, size, last opened and folder. Toolbar: minimum size,
   Kind, Last opened, sort. Nothing checked.
3. Check files (Space for Quick Look), then Move to Trash → result + Put Back.

### Tidy flow 5: leftovers of deleted apps
1. Uninstall › **Leftovers** (sidebar child). Scan runs on open.
2. Grouped by inferred ID ("com.example.oldapp", with a nicer name when a plist reveals
   one), with total size, item count, last modified. Nothing checked.
3. Check, then Move to Trash, then the result.

## Settings inventory

CleanMyMac's panes and controls, from the Settings bundle strings. Defaults were not
observed (the window wasn't opened; see header) unless the help center states them.

| Setting (CMM) | Default | Options | Keep? |
|---|---|---|---|
| General › Full Disk Access status + Enable / Learn More | — | button | **Yes**: in Tidy's General tab, status + Open System Settings |
| General › Enable Finder integration (+ Open Extension Settings) | not observed | toggle | Partly: a Services entry needs no toggle |
| General › Keep icon in Dock when not open | not observed | toggle | No (we have no agent) |
| General › Play sounds for main actions | not observed | toggle | No: moves are silent; the result banner is the feedback |
| General › Reduce Motion | System | System / Enabled / Disabled | No: follow the system setting |
| General › Custom themes on special occasions | not observed | toggle | No |
| General › Smart Insights, Assistant recommendations | not observed | toggles | No |
| General › Updates: keep up to date automatically | not observed | toggle | No (Slopapp handles updates) |
| General › Analytics: share usage statistics | not observed | toggle | No (no telemetry, ever) |
| Scanning › Modules to scan with Smart Care; categories per module | all on (implied) | checklists | No: each section has its own defaults |
| Protection › Malware monitor, background scan, scan DMGs/archives/mail/USB, iCloud exclusion, scan modes | not observed | toggles, Quick / Balanced / Deep | No (no malware features) |
| Ignore List › sections per module (System Junk, Uninstaller, Large & Old…), "Ignore system applications", Reset Selected / Reset All | System apps ignored | list + buttons | **Should**: Settings › Ignored (one list, Remove button). System apps are always refused, not a setting |
| Notifications › Offer to uninstall correctly, hung apps, Chrome memory, low RAM, free space below X, Trash over X, drive connected, overfilled drives, Smart Care reminder (3 days / weekly / 2 weeks / monthly), low device battery | not observed | toggles, thresholds | No |
| Menu › Enable Menu, Open at Login, Recommendations, External drives (clean on eject, disks larger than X) | not observed | toggles | No |
| Email Cleanup › connected accounts | — | — | No |

Tidy Settings (480 pt, grouped form):
- **General**: Full Disk Access status (Open System Settings); "Show Apple caches in Junk"
  (off); Large & Old default minimum size (50 MB).
- **Ignored** (should): list of ignored apps, paths and junk groups, with a Remove button.
- **About**.

No Launch at login (Tidy is a window app with no background job).

## Menus and shortcuts

**CleanMyMac main menu** (from the bundle's menu strings; shortcuts not observed):

- **App menu**: About, What's New, My Account, Activate… / Activation Info… / Update
  License / Subscribe…, Preferences…, Privacy Policy, Terms of Service, Authenticate… /
  Deauthenticate (privileged agent), Services, Hide / Hide Others / Show All, Quit.
- **File**: Close.
- **Edit**: Undo, Redo, Cut, Copy, Paste, Delete, Select All.
- **View**: Smart Care, Cleanup, Protection, Performance, Applications, My Clutter, Space Lens,
  Cloud Cleanup, Assistant.
- **Window**: Minimize, Zoom.
- **Help**: CleanMyMac Help, About Full Disk Access, Contact Support…, Provide Feedback…,
  Submit Malware…, Enable / Disable Extended Logs, Acknowledgments, More MacPaw Products,
  Rate Us.
- `⌘,` opens Settings on the General tab (help center).

**Tidy (proposed)**

| Menu | Item | Shortcut |
|---|---|---|
| File | Choose App… | `⌘O` |
| File | Choose Folder… (Large & Old) | `⇧⌘O` |
| File | Rescan | `⌘R` |
| File | Move to Trash | `⌘⌫` |
| File | Reveal in Finder | `⇧⌘R` |
| File | Quick Look | Space / `⌘Y` |
| File | Copy Path | `⌥⌘C` |
| Edit | Put Back (undo last move) | `⌘Z` |
| Edit | Select All / Deselect All | `⌘A` / `⇧⌘A` |
| Edit | Find | `⌘F` |
| View | Uninstall / Leftovers / Junk / Large & Old | `⌘1` / `⌘2` / `⌘3` / `⌘4` |
| View | Sort By › Name / Size / Last Opened | — |
| Window | History | `⇧⌘H` |
| Tidy | Settings… | `⌘,` |

Context menu on any row: Quick Look, Reveal in Finder, Copy Path, Ignore (should), Check /
Uncheck.

## Permissions and system integration

**CleanMyMac.** It declares usage strings for Desktop, Documents, Downloads, Photos,
Calendars, Contacts, Reminders, Apple Music and Bluetooth, each saying it wants to clean or
look for threats. It relies on Full Disk Access for the main app plus its Menu and Health
Monitor helpers, and on a privileged helper ("Agent", `SMPrivilegedExecutables`) for
root-owned files. Login items: a menu bar app and a health monitor. A Finder Sync extension
was running at the time of study even with the app closed. Other integrations: an App
Intents extension, a URL scheme (activation), Sparkle-style updater XPC (MAS updater),
Dropbox, Google Drive, Gmail and Microsoft SDKs for cloud and email cleanup, and an
analytics framework. Without FDA it still runs but finds less; it pushes FDA through the
Assistant.

**Tidy:**

- **Full Disk Access** via SlopKit `PermissionGate(.fullDiskAccess)`. It is asked only
  inside the section that needs it, never at launch, with one sentence and a button that
  opens Privacy & Security › Full Disk Access. Live re-check. Without it, Tidy:
  - skips `~/Library/Containers`, `~/Library/Group Containers` and other TCC-protected
    folders entirely, so macOS 14+ never shows "Tidy would like to access data from other
    apps"
  - says that some results may be missing
  - offers Choose Folder… for Large & Old instead of touching Desktop / Documents /
    Downloads
- **Administrator rights**, only at removal time and only for root-owned items: App Store
  apps, `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools`, root-owned
  `/Library/Application Support/<x>`. One prompt per removal. See open question 1.
- **App Management** (macOS 13+) may apply when moving another app's bundle. Verify in the
  build. If macOS blocks it, fall back to Reveal in Finder with an explanation.
- **No** login item, background agent, Finder Sync extension, notifications, network or
  analytics.
- **Services**: "Uninstall with Tidy" for `.app` files (should).
- Opening `.app` documents: the Dock-icon drop and `application(_:open:)` route to the
  uninstaller.

## UX patterns worth adopting

- **One rhythm for every section.** In CMM every module is scan → summary → review list →
  action → result with log. Our sections share one list component: grouped rows,
  tri-state group checkboxes, size per row and group, and a bottom bar with the checked
  total and one verb button.
- **Smart preselection with visible reasons.** CMM preselects the safe majority and leaves
  risky items (archives, module caches, newest iOS backup, Gradle) unchecked. We do the
  same, and say *why* in a caption on the unchecked items.
- **Group by kind, show the path.** Resource groups make a 40-item list scannable; the
  path makes every item verifiable.
- **Quit sheet before touching a running app.** CMM and AppCleaner both protect running
  apps. We go further: no "continue anyway".
- **Reset = uninstall minus the app.** A cheap, useful second verb on the same list.
- **Leftovers as a standing list.** Files of apps already gone, found without the user
  remembering the app's name.
- **Nothing selected in Large & Old.** These are the user's own files; CMM never preselects
  them. We keep that.
- **DerivedData named by project** (our addition): the folder hash is meaningless, but the
  workspace path in its `info.plist` isn't.

## What we won't copy, and what we'll do better

- **Not copying**: name, icon, artwork, wording, sounds, signature visuals (the tile
  dashboard, animated intros, themes), the assistant, activation and upsell flows
  ("Unlock Full Version", "Unlock New Features"), the Suspicious-vendor filter, and the
  scare framing (junk described as slowing the Mac down, warnings about being unprotected).
- **Doing better:**
  - **Always to the Trash, with Put Back.** CMM's Large & Old deletes permanently; the
    help center says so. Every Tidy removal is recoverable from the Trash and undoable in-app
    (`⌘Z`).
  - **Honest space numbers.** We say space is freed when the Trash is emptied. Sizes are
    allocated sizes, and the result says "up to" where APFS clones or hard links can make
    real savings smaller.
  - **No "Clean" without review.** No one-click clean on a summary; the action always sits
    under the list it acts on.
  - **No background presence.** CMM runs a Finder Sync extension, a menu app, a health
    monitor and an agent. Its own Setapp reviewers report UI freezes and actions that silently
    do nothing in 5.7.x. Tidy runs only while its window is open.
  - **No performance or malware claims.** Caches are described as "files apps can
    recreate", not as slowing the Mac down.
  - **Conservative, explainable matching.** Every item says *why* it matched (ID, container
    metadata, app group, launch item pointing into the app, exact name). The rules forbid
    the substring, team-ID and company-name matching that caused Pearcleaner's false
    positives. Shared items (group containers used by sibling apps) are flagged and
    unchecked.
  - **Fast first screen.** No mandatory scan before seeing your apps; the list is there on
    open.
  - **No intro screens or animations to sit through** (a Setapp reviewer asked to skip
    them).
  - **No accounts, no network, no analytics.**

## Edge cases

- **App identity**: no bundle ID; bundle ID with 1–2 components; duplicate copies of the same
  app (two Xcodes, `/Applications` and `~/Applications`); apps on external volumes; App
  Translocation paths (run from a DMG or quarantine); wrapped iOS apps on Apple silicon
  (`Wrapper/` inside a container bundle); Steam game launchers; Setapp `-setapp` variants;
  Homebrew casks (brew still thinks they're installed, so mention it in the result);
  Electron apps whose support folder is named after the product, not the ID (rule 11);
  vendor suites sharing group containers (Office) and shared vendor folders (JetBrains,
  Adobe).
- **Refusals**: macOS apps (`anchor apple`, `/System`), Tidy itself, an app that is inside
  another app's bundle.
- **Running**: the app is running; a helper or login item from its family is running; the
  app relaunches itself after quit (re-check right before moving); the app refuses to quit
  (Force Quit after 5 s); the app is quit by the user mid-sheet.
- **Ownership**: root-owned app bundles (App Store apps, verified), root-owned `/Library`
  items, locked files (`uchg`), items on read-only volumes, SIP-protected paths (never
  offered). The user cancels the admin prompt (items stay, and the result says which).
- **Moves**: an item vanished or changed between scan and move (re-validate); a name
  collision in the Trash (`trashItem` renames, so record the returned URL); an external
  volume's own `.Trashes`; moving a folder with hundreds of thousands of files (DerivedData)
  must not block the UI; Put Back after the user emptied the Trash or moved the item (Put
  Back disabled, with an explanation); Put Back when the original parent folder no longer
  exists (recreate it).
- **Sizes**: allocated vs logical size; APFS clones and hard links (pnpm store, Time
  Machine local snapshots) make freed space smaller than listed; iCloud "dataless"
  (evicted) files report sizes they don't occupy (skip them in Large & Old, or show "in
  iCloud"); sparse files, disk images; huge folders (DerivedData > 50 GB, 200k files):
  sizing is cancellable and streams progress.
- **Permissions**: FDA missing, granted mid-session (rescan), revoked mid-session (moves
  fail gracefully with "Full Disk Access was turned off"); macOS 14+ "access data from other
  apps" prompts must never appear (no reads inside other apps' containers without FDA);
  Desktop / Documents / Downloads prompts must never appear unprompted.
- **Junk**: caches recreated instantly by a running app (show the post-move size honestly
  on rescan); a cache folder that is a symlink; `com.apple.*` caches held by daemons;
  DerivedData for a project currently building in Xcode (Xcode running = uncheck with a
  note); unavailable simulators while Simulator.app is running; no Xcode installed (the
  Developer group is hidden).
- **Large & Old**: Spotlight disabled or still indexing (fall back to a walk); packages
  (`.photoslibrary`, `.musiclibrary`, `.fcpbundle`, VM bundles): shown as one item with a
  "Library" warning and never preselected; files inside `~/Library` are excluded; files on
  the scanned external drive that gets ejected mid-scan.
- **UI**: empty states (no leftovers found, no junk, no large files: `ContentUnavailableView`
  with one action); 500+ apps; very long paths (middle truncation, full path in the tooltip
  and Copy Path); non-English app names and right-to-left paths; dark and light mode;
  VoiceOver labels on every checkbox ("Include Caches, 230 MB"); keyboard-only operation;
  Reduce Motion; window size and sidebar selection restored on relaunch.

## Our v1 scope

Uninstall
- [x] The app list appears on open (name, icon, size filling in, last opened); sort by
      name / size / last opened; `⌘F` filters.
- [x] Pick an app by click, drop on the window or Dock icon, or `⌘O`.
- [x] Leftovers found per the matching rules (1–16), grouped by kind with sizes and
      abbreviated paths; group and item checkboxes; captions for name matches and shared
      items.
- [x] Refuses macOS apps (`/System` or `anchor apple`) and Tidy itself, with a clear
      sentence. App Store Apple apps (Xcode, Pages) are allowed.
- [x] Running app or helper → quit sheet (Quit, Force Quit after 5 s, Cancel); nothing
      moves until it has quit.
- [x] Move to Trash moves exactly the checked items, including root-owned ones through one
      admin prompt (or Reveal in Finder on cancel); the result shows count and
      "Empty the Trash to free X"; Put Back (`⌘Z`) restores them.
- [x] Leftovers section: orphans per rules 17–22, nothing preselected, Move to Trash + Put
      Back.

Junk
- [x] User caches grouped by app (third-party preselected, Apple unchecked, running apps
      unchecked with a note), user logs, crash reports, all with sizes.
- [x] Developer junk per the table: DerivedData by project name, device support by version,
      device logs, documentation cache, previews, simulator caches, unavailable simulators,
      archives (unchecked); hidden when absent.
- [x] Move to Trash + result + Put Back; `⌘R` rescans.

Large & Old
- [x] Home folder scan (≥ 50 MB, threshold menu), Kind and Last-opened filters, sorting,
      nothing preselected, Quick Look, Reveal, Move to Trash + Put Back.
- [x] Choose Folder… for another folder or volume.

App-wide
- [x] `PermissionGate(.fullDiskAccess)` per section with partial results and live re-check;
      no TCC prompts for other apps' data, Desktop, Documents or Downloads without FDA.
- [x] Every removal goes through a reviewed list and the Trash; no permanent deletes
      anywhere.
- [x] Library window (`NavigationSplitView`): sidebar Uninstall (with Leftovers), Junk,
      Large & Old; keyboard navigation, Space = Quick Look, every action in a menu with its
      shortcut.
- [x] Settings: General (FDA status, Apple caches toggle, default threshold), About.
- [x] No malware, "speed up", RAM or optimisation wording anywhere.

Build status: all checked; partial ones are noted in "Build notes → Builder decisions"
(admin prompt → Show in Finder; App Store Apple apps refused; unavailable simulators and the
Apple-caches toggle later; Choose Folder limited to the home folder; Dock-icon drop works via
Open With / `open -a` only). Should items built: Reset (uncheck the app), package-manager caches.

Should (v1 if cheap): Reset an app (#11); unused-apps filter (#14); Services "Uninstall with
Tidy" (#19); Installers in Junk (#23); Ignore list (#25); package-manager caches (#30);
History sheet (#51); vendor-folder rule 12.

## Open questions

1. **Root-owned items** (App Store apps, `/Library` daemons and helpers). Options: (a) a
   standard admin password prompt that moves just those items to the user's Trash; (b) ask
   Finder over Apple Events (Finder handles auth and gives real Put Back, but adds an
   Automation permission prompt); (c) a privileged helper (heavy, a system extension-like
   install); (d) only Reveal in Finder.
2. **Finder Put Back vs our own Put Back.** Finder's Put Back only works for items trashed
   by Finder. Is Tidy's in-app Put Back (`⌘Z`, History) enough?
3. **Unavailable simulators.** `xcrun simctl delete unavailable` deletes permanently.
   Moving device folders to the Trash keeps the "always to Trash" rule, but CoreSimulator's
   device set must cope.
4. **Apple (`com.apple.*`) user caches in Junk**: list them unchecked, or hide them unless
   a setting is on?
5. **AI tool clutter** (Claude, Codex, Cursor caches; Ollama / LM Studio models). It's
   relevant to the owner but needs a careful per-tool allowlist.
6. **Orphan candidates with non-ID names** (e.g. `Application Support/SomeApp`). v1 ignores
   them entirely. Is that too conservative?
7. **Large & Old scope**: home folder only by default, or the whole startup volume like CMM?

## Decisions (research defaults, 2026-11-02; owner may override)

1. **Root-owned items → (a)** one admin prompt at removal time listing what needs it,
   moving the items into the user's Trash. On cancel or failure: leave them and offer Reveal
   in Finder. No helper, no Apple Events in v1. Verify App Management behaviour during the
   build.
2. **Put Back → Tidy's own** (undo + History, works while items are still in the Trash).
   Finder-backed trashing is *later*, if the owner wants Finder's Put Back.
3. **Unavailable simulators → move their device folders to the Trash, with Simulator /
   Xcode quit first.** Then confirm `simctl list` is clean (unit + manual test in the build).
   If CoreSimulator can't cope, fall back to listing them with a "Delete Permanently…"
   button behind a confirmation. That would be the only non-Trash action and needs the
   owner's OK first.
4. **Apple caches → listed, unchecked**, with a Settings toggle "Show Apple caches in Junk"
   (off hides them).
5. **AI clutter → later**, as its own group with a per-tool allowlist; never the whole
   `~/.claude` / `~/.codex` folders.
6. **Non-ID orphans → ignored in v1.** Rule 18 stands; revisit with real data.
7. **Large & Old → home folder** (excluding `~/Library`), plus Choose Folder… for anything
   else, including external volumes.

## Sources

- CleanMyMac knowledge base (index): https://macpaw.com/support/cleanmymac/knowledgebase
- Uninstall apps: https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller
- Remove system junk (Smart Selection defaults): https://macpaw.com/support/cleanmymac/knowledgebase/system-junk
- System junk cleanup list (groups, Xcode junk contents): https://macpaw.com/support/cleanmymac/knowledgebase/system-junk-cleanup-list
- Large and old files (50 MB, permanent removal): https://macpaw.com/support/cleanmymac/knowledgebase/large-and-old
- CleanMyMac X Large & Old (older options: Remove Securely, Move to Trash, Move to Folder): https://macpaw.com/support/cleanmymac-x/knowledgebase/large-and-old
- AI clutter: https://macpaw.com/support/cleanmymac/knowledgebase/ai-clutter
- Full Disk Access: https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access
- Safety considerations: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety
- Concepts and usage index: https://macpaw.com/support/cleanmymac/knowledgebase/concepts-and-usage
- General index (background items, agent): https://macpaw.com/support/cleanmymac/knowledgebase/general
- Reset apps how-to: https://macpaw.com/how-to/reset-mac-applications
- Setapp listing and reviews: https://setapp.com/apps/cleanmymac , https://setapp.com/apps/cleanmymac-x/customer-reviews
- Macworld review (5.x): https://www.macworld.com/article/3396118/cleanmymac-x-441-review.html
- MacStories on the 5.0 redesign: https://www.macstories.net/reviews/macpaw-updates-cleanmymac-with-a-fresh-design-and-new-tools/
- MacRumors news (redesign): https://www.macrumors.com/2024/10/16/macpaw-releases-redesigned-cleanmymac/
- TidBITS Talk on uninstallers: https://talk.tidbits.com/t/do-you-recommend-using-an-app-to-remove-other-apps/20095?page=2
- Pearcleaner source (Locations.swift, AppPathsFetch.swift, ReversePathsFetch.swift,
  Conditions.swift, DevelopmentView.swift, UndoManager.swift): https://github.com/alienator88/Pearcleaner
- Pearcleaner orphan reliability discussion: https://github.com/alienator88/Pearcleaner/discussions/528
- Pearcleaner vs App Cleaner (competitor; partial-name false positive example): https://nektony.com/reviews/pearcleaner-vs-app-cleaner-uninstaller
- AppCleaner: https://freemacsoft.net/appcleaner/ ; reviews: https://www.drbuho.com/review/appcleaner-review , https://www.macworld.com/article/2995495/remove-extra-application-files-with-appcleaner.html
- Finder Put Back doesn't work for programmatic trashing: https://openradar.appspot.com/41878624
- "Access data from other apps" prompt (macOS 14+): https://discussions.apple.com/thread/255172264
- Installed CleanMyMac 5.7.3: `Info.plist`, framework list, English `Localizable.strings`
  of ApplicationsModule, ApplicationsTerminator, JunkCleanupModule, OrganizeModule,
  SpaceLensModule, Features_Settings and the main app (read-only, app not launched).
- Local verification: `codesign -R="anchor apple"` and owner/group of Safari, Notes, Xcode,
  Pages, Keynote, GarageBand.

## Build notes

Built 2026-11-02 (`apps/Tidy`). Archetype: library window, sidebar Uninstall / Leftovers
(Apps) and Junk / Large & Old (Files).

### Builder decisions (where the build differs from the research defaults)

- **Root-owned items: (d) Show in Finder, not an admin prompt.** `/Library` items and
  root-owned bundles are listed, locked ("Needs an administrator") with Show in Finder. An
  in-app admin prompt means running a privileged `mv`; that's a lot of risk surface for v1.
  Later.
- **All `com.apple.*` apps are refused**, including Apple's App Store apps (Xcode, Pages):
  they're root-owned, so without the admin prompt Tidy couldn't remove them anyway.
- **Apple caches are hidden in Junk**, not listed unchecked, and the trash policy refuses any
  `com.apple.*` path except `com.apple.dt.*` (Xcode caches). Settings toggle: later.
- **Unavailable simulators: deferred.** Only `CoreSimulator/Caches` and simulator logs.
- **Loaded launch agents aren't booted out**; their plist goes to the Trash and they stop
  at the next login. Later.
- **App groups from entitlements, UUID containers, recent-documents lists, Dock-icon drop,
  Services menu, History sheet, ignore list, vendor-folder rule 12: later.** Group
  containers match by stripping `TEAMID.` / `group.` and applying the bundle id rule.
- **Names**: ≥ 4 characters, stoplist, also tried without spaces; executable names count
  (stoplisted "Electron" etc. don't). Embedded helper ids count only from the app's own
  vendor (so Sparkle's XPC ids never claim anything).
- **Orphans** also skip anything an installed app claims by any rule, and launch agents
  whose program still exists; groups are keyed by the first 3 id parts. Two real false
  positives (`org.swift.swiftpm`, a launch agent named after another vendor) were caught by
  the fixture and fixed.
- **Large & Old** without Full Disk Access first asks (PermissionPrompt + "Scan Without
  Those Folders") instead of letting macOS prompt per folder. Choose Folder is limited to
  the home folder in v1 (the trash policy only allows home and app folders).
- **Device support**: all versions but the newest per platform start checked.
- **Space checks/unchecks** the selected rows (the review is the main job); Quick Look is
  `⌘Y` and in the context menu.
- **App sizes** are measured as rows appear (all at once when sorting by size), so launch
  doesn't walk every app.

### Safety

Every move goes through `TrashPolicy.check` (inside home / app folders / `/Library` stand-in
only; never the standard Library folders themselves, top-level home folders, `ByHost`,
`DerivedData` etc.; never `com.apple.*`; parent symlinks resolved). Setting any `TIDY_*`
variable switches to test mode: home, app folders, `/Library` and the Trash all come from
the variables, test mode never falls back to the real home, LaunchServices isn't asked, and
only pretend-running apps (`TIDY_RUNNING_IDS`) can be "quit". All testing ran on
`/tmp/tidy-test`; nothing outside it was moved.

### Gates (2026-11-02)

- `scripts/check.sh Tidy --perf`: PASS. 55 Swift Testing tests (9 suites) against a fixture
  with 13 apps, ~90 leftovers incl. decoys, 2 deleted apps + 6 non-orphan look-alikes, junk
  and large files. Perf: launch 135–139 ms, first window 366–390 ms, idle CPU 0.05–0.08 %,
  footprint 55–58 MB.
- One read-only real-home benchmark (`tidy-tool bench`, no Full Disk Access, counts only):
  114 apps listed in 228 ms; Library index 4,087 entries in 436 ms; leftover matching for
  all apps 1.0 s (≈9 ms per app); 377 leftover items measured (133k files, 23.7 GB) in
  1.2 s; all app bundles (469k files, 52 GB) in 2.8 s; 104 deleted-app groups in 1.2 s
  (before the LaunchServices check the app adds); junk 1,441 items listed in 274 ms and
  measured (871k files) in 8.9 s; large-file walk of the home folder minus
  Desktop/Documents/Downloads: 2.9 M entries in 39 s (progress + Stop shown).
- Walkthrough (release build, fixture, light and dark): list → select → 21 leftovers
  grouped → Move to Trash → result + Put Back → restored; Space toggles a row; `⌘⌫`, `⌘Z`;
  running app → quit sheet → quit → moved; Safari refused; `/Library` items locked;
  containers locked without FDA and included with `TIDY_ASSUME_FULL_DISK_ACCESS=1`;
  `open -a Tidy Notely.app` selects it; Leftovers (2 groups, nothing checked); Junk (sizes,
  running app's cache unchecked, move + Put Back); Large & Old (filters, check, move);
  real-Mac normal launch shows the FDA prompt for Large & Old. `scripts/drive tree`: no
  `[unlabeled]` controls. Note: `scripts/drive set` doesn't change SwiftUI pop-up buttons;
  click the pop-up, then the menu item.
- Not verifiable here: the FDA-granted path on a real Mac (this terminal has no FDA; the
  fixture override covers the UI path), Finder's Put Back (not supported for app-trashed
  items; Tidy's own Put Back is used).


## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-03)

Triage by the coordinator; all accepted. Fixed the same day; gates re-run (62 tests,
`check.sh Tidy --perf` green: launch 163 ms, first window 402 ms, idle CPU 0.05 %, 53 MB).

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 ⌘⌫ in the search field ran File ▸ Move to Trash and trashed Tasker.app, which search had hidden, with no confirmation | major | accept | Menu commands that share text-editing keys (⌘⌫, ⌘Z, ⇧⌘Z) now go to the text field being edited (`TextEditing.forward`). Selections follow the visible results (`ReviewRules.reconcile`; the detail clears when the selected app is filtered out). Every Move to Trash acts only on checked items that are visible (`ReviewRules.actionable`). Uninstalls started from a menu or shortcut ask first ("Move Tasker to the Trash? Tasker and 1 item, 614 KB…"); the review pane's own button doesn't. Regression tests: `ReviewRuleTests`. Walked: select Tasker, type "Note", ⌘⌫ → text deleted, detail cleared, nothing moved; ⌘⌫ in the list → confirmation. |
| F2 Admin-only leftovers vanished after uninstall; Leftovers never listed them | major | accept | The result screen lists every item left in place (name, folder, "Needs an administrator" / "Needs Full Disk Access") with Show in Finder and a one-line explanation. Leftovers now matches apps sitting in the Trash with the full rules (ids, distinctive names, `/Library` items), grouped under the app's name ("app is in the Trash"), locked admin items included with a Show in Finder notice; `/Library` launch items and helper tools join the id-based scan. Tests: `appsInTheTrashKeepTheirLeftoversVisible`, `trashedCopyOfAnInstalledAppIsIgnored`. |
| F3 Generic-name folders (Code, Ox, shared Tasker) silently skipped | minor | accept | New "Possible Matches" group: exact-name folders whose name is common, short or shared by another installed app, never checked, captioned "Common name" / "Also Tasker in Setapp". Test: `commonAndSharedNamesArePossibleMatchesOnly`. |
| F4 Group checkbox wrong (checked over locked items; mixed reported as on) | minor | accept | AppKit tri-state checkbox (`TriStateCheckbox`): off / mixed / on from the actionable items only, disabled when none; accessibility value 0/1/2. |
| F5 Put Back only for the latest action; Undo disabled | minor | accept | Session history: Edit ▸ Undo/Redo Move to Trash (⌘Z / ⇧⌘Z) walk it, File ▸ Recently Moved to Trash… (and History… in the action bar) puts back any earlier move. |
| F6 Choices not remembered or synced | minor | accept | Size threshold is one setting (Settings and Large & Old share it); sort order, age and kind filters and "Scan Without Those Folders" persist. Test mode stores its choices in a separate defaults domain. |
| F7 Size sort used only the bundle; Last Opened had no dates | minor | accept | Labelled "App Size" (row tooltip says so; the detail header shows the total with files). Last Opened is offered only when Spotlight has dates; dates show in rows. |
| F8 Same-named apps indistinguishable | nit | accept | Rows show the folder when another app has the same name. |
| F9 Junk row names didn't match folders | nit | accept | Title is the real folder name; the friendly name (app, project) follows the path. |
| F10 Pinned group header overlapped rows in Junk | nit | accept | Headers get an opaque background and more padding. |
| F11 Application icon looked like a checkbox; "Zero KB" vs "—"; "locked" wording; no Help; non-app files ignored silently | nit | accept | New Application symbol; sizes read "0 KB", unknown totals "—"; wording names the reason; Help ▸ Tidy Help opens the README on GitHub; dropping or opening a non-app says Tidy only uninstalls apps and why it was ignored. |

Also found while fixing: under heavy machine load the perf gate's idle window caught the
first sizes walk. App sizes are now remembered between launches (keyed by bundle and
Info.plist dates) and Spotlight dates are fetched for visible rows only.

### Round 2 (2026-11-03)

Safety held: every restore exact, nothing wrong moved. Triage by the coordinator; all
accepted except one AX nit that SwiftUI can't do (below). Gates re-run: 64 tests,
`check.sh Tidy --perf` green (launch 145 ms, first window 385 ms, idle CPU 0.04 %, 62 MB).

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 Large & Old layout broke when the list emptied after Move to Trash (pane centred, filter bar and footer floating) | major | accept | Every empty state (`ContentUnavailableView`) in every section now fills the space between its bars; the Large & Old content area is pinned between filter bar and footer. Walked: filter to 1 GB, move the only file → filter bar top, "No Files Match" centred, result + Put Back at the bottom. |
| F2 Undo history lost on quit despite "Put Back works while items are still in the Trash" | minor | accept | The move log (original ↔ trashed path, sizes, app name) is saved as JSON (`TrashLog`; test mode: `/tmp/tidy-test/tidy-history.json`, else Application Support) and reloaded keeping only what's still in the Trash and not yet put back. Recently Moved to Trash… and ⌘Z work after relaunch. Test: `TrashLogTests`. |
| F3 Esc/⌘. didn't close History; ⌘3 switched sections behind a sheet | minor | accept | History and Full Disk Access sheets close on Esc and ⌘. (`onExitCommand`); section shortcuts, Move to Trash, Undo/Redo and Recently Moved are disabled while any sheet or alert is up. |
| F4 Partial Put Back failure alert appeared only after the sheet closed | minor | accept | Shown inline at the top of the History sheet immediately. |
| F5 Button doesn't confirm, menu command does | minor | accept (decision) | Kept, and made the rule explicit: the review pane's Move to Trash button never asks, because it acts on the list right above it and everything can be put back (its tooltip says so); a menu item or ⌘⌫ asks before an uninstall, because it can fire without looking at the pane (round 1 F1). Other sections never ask: what they move is junk or files the user checked one by one. |
| F6 Search field: Select All/Copy/Paste disabled, no ⌘F, Undo said "Undo Move to Trash" while typing | minor | accept | Tidy tracks text editing (`NSControl` begin/end editing): while typing, Edit ▸ Undo/Redo are plain "Undo"/"Redo" and go to the field. Edit ▸ Find (⌘F) focuses the search field. Cut/Copy/Paste/Select All were disabled only because the tester's keys reached an inactive app; with the window active they're enabled and work (verified). |
| F7 Group "check all" ✓ with locked items unchecked; header counts inconsistent | minor | accept | Group headers read "3 of 7 checked, 2 locked" (or "N items, locked"); the box state counts checkable items only. The app header counts every listed item except possible matches, so it equals the sum of the groups. |
| F8 Same-named apps' location truncated | nit | accept | Rows show the folder name only ("in Setapp"). |
| F9 "Not an app" alert's default button | nit | accept | OK is the default; Show in Finder only appears for permission problems. |
| F10 AX: empty "Sort By" item, unlabeled checkbox column sort button, empty subtitle text, duplicated row help, truncated "Allow Full Disk Acce…" | nit | accept | View ▸ Sort Apps By is a plain list of checkable items; the checkbox moved into the Name column (no unlabeled header); empty subtitles aren't drawn; one combined tooltip per row; sidebar item reads "Full Disk Access…". |
| F10b AX: UUID column identifiers in Large & Old | nit | reject | SwiftUI's `Table` assigns them and ignores `customizationID` for the AX identifier; VoiceOver announces the column titles, which are set. Revisit if the table moves to AppKit. |
| F11 "Large files start at" sat in the Full Disk Access group | nit | accept | Moved to its own "Large & Old" section in Settings ▸ Advanced (SlopSettings puts all General rows in one group). |

Also: the empty state now says "your home folder" instead of "~". While verifying F6, a
⌘C in the search field put the three characters "abc" on the system clipboard.

### Round 3 (2026-11-03)

No blockers or majors; the tester checked every move and restore against the file system.
Exit criterion met with these fixed or deferred. Gates: 64 tests, `check.sh Tidy --perf`
green on a busy machine (load 17: launch 168 ms, first window 457 ms, idle CPU 0.03 %
lowest / 0.04 % median, 65 MB). Shipped as **beta 0.2.0**.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 Partial Put Back (name conflict) left the user stuck: row said "Put back", one item stayed in the Trash with no way to find it | minor | accept | The entry becomes "Partly put back" and keeps only what's still in the Trash (also across relaunches). Each item shows why, with Show in Trash and, when its place is taken, Keep Both (goes back as "Name (restored).ext"; `TrashService.putBack(keepBoth:)`, tested). The put-back result says "1 item is still in the Trash", and the alert offers Show What's Left…. Walked: uninstall Ox, recreate its plist, Put Back → partial; relaunch; Keep Both → `com.fixture.ox (restored).plist`, Trash empty. |
| F2 Header item counts meant different things | nit | accept | One rule everywhere: "N items · M checked", N counts every row (locked and possible matches included), M the checked movable ones; the app header uses the same rule over all its rows. |
| F3 Leftovers badge only after opening Leftovers | nit | accept | The badge shows the last count (remembered) at launch; a fresh count runs in the background 30 s after launch or as soon as the section opens. Not at launch itself: on a real Mac it asks LaunchServices about ~100 candidates, which showed up in the idle budget. Item sizes are measured only once the section is open. |
| F4 Bundle without Info.plist showed a blank subtitle and the "prohibited" icon | nit | accept | Generic app icon and "Unknown version" (row and header). |
| F5 Window menu didn't list the main window | nit | accept | Window ▸ Tidy (⌘0). Decision: closing the window quits, as a single-window utility with nothing running in the background (SlopAppDelegate's standard); documented in the README. |
| No confirmation before trashing personal files in Large & Old | — | defer | Every move is undoable (⌘Z, Put Back, Recently Moved to Trash… across relaunches) and files are checked one by one; documented in the README. Revisit if a later round shows people trashing files by accident. |

Also: the running-apps list only updates the UI when it actually changes (other apps
starting and quitting on a busy Mac were redrawing the app list). Coordinator note
acknowledged: tests and walkthroughs don't write the real clipboard (none of the unit tests
touch a pasteboard; manual copy checks will use a private pasteboard).

