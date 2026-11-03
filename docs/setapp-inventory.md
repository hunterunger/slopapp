# Setapp inventory

Snapshot taken **2026-11-02** from [setapp.com/apps](https://setapp.com/apps) (default
sort, which puts the most popular apps first), cross-checked against Setapp's own
"best apps" round-ups. Setapp lists 270+ apps. This covers the ~50 at the top of the
list, which is where most usage sits. Ratings are Setapp's user scores. Setapp
doesn't publish install numbers, so "rank" is list position, not downloads.

## Owner's favourites

These are the 18 Setapp apps installed on this Mac, ranked by real use (macOS launch counts
as of 2026-11-02). They set the build order. Apps that start at login show low launch counts
but run all day, so they rank high.

| Rank | Setapp app | Use | Slopapp app | Priority |
|---|---|---|---|---|
| 1 | OpenIn | 664 launches, used daily | Switchboard | P1 |
| 2 | CleanShot X | 10 launches, runs at login | Snapper | P1 |
| 3 | Paste | 9 launches, runs at login | Clips | P1 |
| 4 | ClearVPN | 6 launches, used recently | — | Skipped: a VPN needs servers and an operator. Use WireGuard or Tailscale. |
| 5 | CleanMyMac | Runs at login | Tidy | P1 |
| 6 | Squash | 3 launches | Squish | P1 |
| 7 | Permute | 3 launches | Convert | P1 |
| 8 | PDF Squeezer | Installed, not launched recently | Squish (shared with Squash) | P1 |
| 9 | Sip | Installed, not launched recently | Dropper | P2 |
| 10 | PixelSnap | Installed, not launched recently | Ruler | P2 |
| 11 | Image2icon | Installed, not launched recently | Iconsmith | P2 |
| 12 | Typeface | Installed, not launched recently | Specimen | P2 |
| 13 | World Clock Pro | Installed, not launched recently | Zones | P2 |
| 14 | Archiver | Installed, not launched recently | Crate | P2 |
| 15 | Nitro PDF Pro | Installed, not launched recently | Paper | P3 |
| 16 | ForkLift | Installed, not launched recently | Dual | P3 |
| 17 | Gitfox | Installed, not launched recently | Commit | P3 |
| 18 | Luminar | Installed, not launched recently | — | Skipped: an AI photo editor is a product company, not a utility. |

## Inspiration, not imitation

For each app we study the original: what it's for, how its main flows go, and every feature
it has. Years of polish went into those flows, and we'd rather learn from them than
reinvent them. We don't copy names, icons, marketing copy, assets, or signature visuals.
Every Slopapp app gets its own name, a Lucide-based icon, our shared design system, and
code written from scratch.

## Top 50 on Setapp

**Size** is a rough build estimate for a solid v1: **S** = a day or two, **M** = about a
week, **L** = weeks or a hard OS problem (private APIs, drivers, privileged helpers).

The last five rows (rank "—") are the owner's favourites that sit outside Setapp's top 50.
**Plan** uses roadmap priorities: **P1** up first, **P2** next, P3 later.

**Open source today** lists existing free alternatives. Several of these are excellent.
Slopapp's angle isn't that nothing free exists; it's one consistent, trusted, signed
collection with a single hub, the way Setapp bundles things.

| # | Setapp app | Rating | What it does | Open source today | APIs we'd need | Size | Plan |
|---|---|---|---|---|---|---|---|
| 1 | CleanMyMac | 97% | Cleanup, uninstaller, malware scan | Pearcleaner (uninstaller) | FileManager, Full Disk Access | L | **P1: Tidy** |
| 2 | Bartender | 96% | Hide/organize menu bar icons | Ice, Hidden Bar | Private-ish menu bar tricks, Accessibility | L | Not planned yet |
| 3 | CleanShot X | 99% | Screenshots, scrolling capture, annotate, record | Shottr (free, not OSS) | ScreenCaptureKit, AVFoundation | L | **P1: Snapper** |
| 4 | Paste | 98% | Clipboard history | Maccy, Clipy | NSPasteboard polling, global hotkey | M | **P1: Clips** |
| 5 | Downie | 98% | Video downloader | yt-dlp (+ GUIs) | yt-dlp | M | Skip (legal grey area) |
| 6 | iStat Menus | 96% | CPU/GPU/RAM/sensor menu bar stats | Stats | host_statistics, IOKit, SMC | M | P3: Gauge |
| 7 | Permute | 98% | Convert audio/video/images | HandBrake, FFmpeg GUIs | AVFoundation, ImageIO | M | **P1: Convert** |
| 8 | TextSniper | 99% | OCR text from anywhere on screen | TRex, Normcap | ScreenCaptureKit, Vision | M | P3: Snip |
| 9 | AlDente Pro | 98% | Battery charge limit | AlDente (free tier is OSS) | SMC via privileged helper | L | Skip, recommend AlDente |
| 10 | BetterTouchTool | 98% | Custom gestures, shortcuts | Hammerspoon, Karabiner | CGEventTap, Accessibility | L | Not planned |
| 11 | ClearVPN | 89% | VPN | WireGuard, Tailscale | NetworkExtension + servers | L | Skip (needs servers) |
| 12 | Nitro PDF Pro | 89% | Edit/annotate PDFs | Skim | PDFKit | L | P3: Paper |
| 13 | Spark Mail | 90% | Email client | Thunderbird | IMAP/SMTP | L | Skip (huge scope) |
| 14 | TablePlus | 99% | Database GUI | Beekeeper Studio, DBeaver | Postgres/MySQL/SQLite drivers | L | Not planned |
| 15 | BetterZip | 96% | Create/extract/encrypt archives | Keka | libarchive | M | See Archiver (Crate) |
| 16 | Numi | 99% | Notepad calculator with units | Soulver-likes, `qalc` | Pure Swift parser | M | P3: Tally |
| 17 | Mosaic | 92% | Window tiling | Rectangle, Loop | Accessibility (AXUIElement) | M | P3: Tiles |
| 18 | Ulysses | 98% | Markdown writing/publishing | MarkText, Zettlr | TextKit 2 | L | Not planned yet |
| 19 | ForkLift | 96% | Dual-pane file manager + SFTP | Marta (free) | FileManager, NIO SSH | L | P3: Dual |
| 20 | Timing | 98% | Automatic time tracking | ActivityWatch | NSWorkspace frontmost app, SQLite | M | P3: Hours |
| 21 | Gemini | 93% | Duplicate file finder | dupeGuru | Hashing, FileManager | M | P3: Twins |
| 22 | Session | 98% | Pomodoro focus timer | Pomatez | Timers, notifications, Focus filter | S | P3: Focus |
| 23 | BusyCal | 96% | Calendar + tasks | Thunderbird | EventKit | L | Not planned |
| 24 | One Switch | 98% | Menu bar toggles (dark mode, hide desktop...) | — | AppleScript/defaults, IOKit | S | P3: Switches |
| 25 | Craft | 96% | Docs and notes | AppFlowy, AFFiNE | — | L | Skip |
| 26 | Yoink | 99% | Drag-and-drop shelf | Dropover (not OSS) | NSPanel, drag sessions | M | P3: Shelf |
| 27 | MindNode | 99% | Mind maps | Freeplane | Custom canvas | L | Not planned |
| 28 | Lungo | 99% | Keep Mac awake | KeepingYouAwake, Amphetamine (free) | IOPMAssertion | S | P3: Awake |
| 29 | QuitAll | 98% | Quit apps in bulk | — | NSWorkspace / NSRunningApplication | S | P3: Quit |
| 30 | DevUtils | 99% | Offline dev toolbox (JSON, JWT, Base64...) | DevToys (Windows), He3 | Pure Swift | M | P3: Devkit |
| 31 | Folx | 95% | Download manager, torrents | Transmission, Motrix | URLSession, libtorrent | L | Skip |
| 32 | PDF Squeezer | 98% | Compress PDFs | Ghostscript CLIs | PDFKit, Quartz filters | S | **P1: Squish** |
| 33 | Pulltube | 97% | Video download/trim | yt-dlp GUIs | yt-dlp | M | Skip |
| 34 | Boom 3D | 91% | System volume booster/EQ | eqMac | Audio driver (HAL plugin) | L | Skip |
| 35 | Archiver | 97% | Archives | Keka | libarchive | M | **P2: Crate** |
| 36 | Sip | 93% | Color picker + palettes | — | NSColorSampler | S | **P2: Dropper** |
| 37 | AirBuddy | 96% | AirPods/Bluetooth battery | — | IOBluetooth, private APIs | L | Not planned |
| 38 | PixelSnap | 99% | On-screen ruler | — | ScreenCaptureKit, edge detection | M | **P2: Ruler** |
| 39 | Path Finder | 92% | Finder replacement | — | FileManager | L | Not planned |
| 40 | SideNotes | 97% | Notes in a side panel | — | NSPanel, SwiftData | M | P3: Margin |
| 41 | Movist Pro | 98% | Media player | IINA | AVPlayer / libmpv | L | Recommend IINA |
| 42 | CloudMounter | 92% | Mount cloud storage in Finder | rclone | File Provider extension | L | Not planned |
| 43 | HoudahSpot | 98% | Advanced file search | — | NSMetadataQuery (Spotlight) | M | P3: Seek |
| 44 | Capto | 86% | Screen recording | OBS | ScreenCaptureKit | L | Folded into Snapper |
| 45 | Dato | 99% | Menu bar calendar + clocks | Itsycal | EventKit | M | P3: Glance |
| 46 | Squash | 92% | Compress/resize images | ImageOptim | ImageIO | S | **P1: Squish** |
| 47 | Supercharge | 100% | Finder/system tweaks | — | defaults, Finder Sync | M | Not planned |
| 48 | Xnapper | 96% | Pretty screenshots for sharing | — | ScreenCaptureKit, Core Image | M | Folded into Snapper |
| 49 | Typeface | 98% | Font browser | — | CoreText | M | **P2: Specimen** |
| 50 | BetterMacWidgets | new | Desktop widgets | — | WidgetKit | M | Not planned |
| — | OpenIn | — | Pick which browser or app opens each link or file | Finicky, Velja (free, not OSS) | Default-browser handler, Apple Events, NSWorkspace | M | **P1: Switchboard** |
| — | Image2icon | — | Turn images into app/folder icons | — | ImageIO, iconutil, NSWorkspace.setIcon | M | **P2: Iconsmith** |
| — | World Clock Pro | — | World clocks and time-zone planner | — | TimeZone, MenuBarExtra | S | **P2: Zones** |
| — | Gitfox | — | Git client | GitHub Desktop, Sourcetree (free) | libgit2 / git CLI | L | P3: Commit |
| — | Luminar | — | AI photo editor | darktable, RawTherapee | Core Image, ML models | L | Skip (a product company, not a utility) |

## What this tells us

1. **The most-loved Setapp apps are small utilities.** Half the top 50 are one-job menu bar
   tools (keep awake, clipboard, OCR, color picker, timer). They're the cheapest to build and
   the ones people use daily. They're also most of the owner's favourites.
2. **The big apps are a different business.** Email, VPN, PDF editors, and database GUIs need
   servers, years of polish, or both. Leave them out until the small apps are solid.
3. **Some open alternatives are already great** (Rectangle, Maccy, Stats, Keka, IINA, AlDente).
   Where they are, Slopapp can link to them from the hub instead of rebuilding. Rebuild only
   where we can match quality and bring something the collection needs (same look, same
   settings, one update channel).
4. **Skip legally risky apps.** Video downloaders and VPNs bring legal and infrastructure
   problems a free project shouldn't take on.

## Build order

Priorities 1 and 2 from [`catalog/roadmap.json`](../catalog/roadmap.json), which holds the
specs. Awake (Lungo) is already built as the reference app for the pipeline.

| Order | Slopapp app | Alternative to | Size | Why here |
|---|---|---|---|---|
| 1 | Switchboard | OpenIn | M | Used hundreds of times. Small surface, big daily payoff. |
| 2 | Clips | Paste | M | Runs all day. Sets up the hotkey and floating-panel patterns. |
| 3 | Snapper | CleanShot X | L | Runs all day. Biggest app in the set; ship v1 (capture + annotate) first. |
| 4 | Squish | Squash, PDF Squeezer | S | Drop in, smaller file out. Easy to test with fixtures. |
| 5 | Convert | Permute | M | Same drop-and-queue window as Squish. |
| 6 | Tidy | CleanMyMac | L | Uninstaller first. Review before delete, always to the Trash. |
| 7 | Dropper | Sip | S | Small, visual, pure AppKit. |
| 8 | Ruler | PixelSnap | M | Screen overlay and edge detection. |
| 9 | Iconsmith | Image2icon | M | We already render icons for our own apps. |
| 10 | Specimen | Typeface | M | CoreText browser, no permissions needed. |
| 11 | Zones | World Clock Pro | S | Menu bar list plus a time scrubber. |
| 12 | Crate | Archiver | M | libarchive does the heavy lifting. |

## Sources

- [Setapp app catalog](https://setapp.com/apps)
- [Setapp: best Setapp apps](https://setapp.com/app-reviews/best-setapp-apps)
- [Setapp: best Setapp apps for Mac](https://setapp.com/app-reviews/best-setapp-apps-for-mac)
- [Setapp: most valuable Mac apps](https://setapp.com/app-reviews/most-valuable-mac-apps)
- [Setapp: pricing explained](https://setapp.com/app-reviews/setapp-pricing-explained)
