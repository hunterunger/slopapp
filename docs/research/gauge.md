# Gauge research (inspired by iStat Menus)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: iStat
> Menus 7 (7.5 is current, September 2026; the last published notes are for 7.3, May 2026).
> It is **not installed** on this Mac, so this is based on Bjango's product page, help center,
> version history, App Store listing, launch coverage and forum threads, plus the MIT-licensed
> open-source **Stats** (exelban/stats v3.0.25, its source and issue tracker) to see which
> macOS APIs work for each sensor today. Public and private APIs were probed read-only on this
> Mac (Mac16,5, M4 Max, macOS 27.2 26B123, SDK 27.0) on 2026-11-07. Updated from a first draft
> of 2026-11-03. We never copy its name, icons, artwork, wording, sounds or signature visuals,
> and we don't copy Stats' code or design either; it was read only to see which APIs it uses.

## The job

Gauge answers "why is my Mac slow, hot, loud or draining?" and "is that download still
going?" at a glance, without opening Activity Monitor. People keep one or two small live
numbers in the menu bar all day (CPU and network most often, then memory and temperature) and
click when something feels off, to see the last few minutes and which app is responsible.
"Done" is naming the culprit within two seconds, and a monitor that never becomes the culprit.

The one interaction that matters most: **glance at a live number in the menu bar; click it;
see a short history and the top processes; act on the culprit (quit it or open Activity
Monitor).**

## Who and when

- Fans spin up or the laptop gets warm: click, see which process is at 300% CPU.
- The Mac feels sluggish: check memory pressure and swap, see which app has the most memory.
- A big download, upload or backup: watch the network rate in the menu bar.
- Unplugged in a meeting: battery %, time remaining, whether it's charging.
- "Disk almost full" warnings: free space per volume.
- Developers: watching a build, a runaway test or a local server eat CPU.

Frequency: passive glances all day; a click a few times a day, 5 to 20 seconds each. Gauge
runs 24/7, so its own cost adds up over every hour the Mac is on.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with the reason). "API" notes refer to the sensor table below.

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| **CPU** | | | | |
| 1 | CPU readout in the menu bar | Many modes: percentage, history graph, bars, per-core bars, pie, stacked label + value, dual-line | must | Text "23%" (`.monospacedDigit()`), total normalised to 0–100% of all cores. Mini bar is a later mode. |
| 2 | CPU history | Graph in the dropdown; ranges from 10 min to 28 days, stored in a database across restarts | must (in memory: 10 min and 1 h) / later (persisted days) | Ring buffers only, no disk writes in v1. |
| 3 | User / system / idle split | Yes | must | Same tick counters as #1. |
| 4 | Per-core usage | Per-core bars; efficiency and performance cores styled separately; "super cores" grouping in 7.3; hyper-threading merge on Intel | should | Group by `hw.perflevelN` (N levels, not assumed 2) and device-tree `cluster-type`. Must stay compact at 32 cores. |
| 5 | Load average, uptime | Yes | must | `getloadavg`, `kern.boottime`. Microseconds. |
| 6 | CPU frequency | Apple silicon frequency (7.0) | skip | Private `IOReport` only; Stats' IOReport energy reads return zeros on macOS 27 unless `powermetrics` (root) runs. |
| 7 | Top CPU processes | Top apps list; child processes combined into their app | must | Top 5, sampled only while the dropdown is open. See "Sampling design". |
| 8 | GPU utilisation | GPU usage, memory, temperature, frequency, FPS on supported Macs | should (utilisation % only) | Public IOKit, undocumented key. Hide when the key is missing. |
| 9 | GPU memory, temperature, frequency, FPS | Yes | skip | Private (IOReport / HID / SMC). |
| **Memory** | | | | |
| 10 | Memory pressure | Pressure graph, the glossary explains it | must | Headline of the section (used memory is always high on macOS). |
| 11 | App / wired / compressed / cached / free | Yes | must | `host_statistics64(HOST_VM_INFO64)`; Activity Monitor's breakdown (App = internal − purgeable). |
| 12 | Swap used | Yes | must | `vm.swapusage`. |
| 13 | Page-ins/outs, swap-ins/outs rate | Yes | should | Deltas of `vm_statistics64`; free with #11. |
| 14 | Top memory processes | Top apps, combined with children | must | `ri_phys_footprint` (Activity Monitor's "Memory" column). |
| 15 | Memory readout in the menu bar | % used, pressure graph, pie | must (option) | Show pressure as a % or "Normal / Warning / Critical". |
| **Disks** | | | | |
| 16 | Free space per volume | Used / free in menu bar and dropdown | must | `volumeAvailableCapacityForImportantUsage` (matches Finder, includes purgeable). Refresh every 30 s and on mount/unmount, not every tick. |
| 17 | Disk read/write activity | Menu bar and dropdown | should | `IOBlockStorageDriver` "Statistics" byte counters (constants are in public IOKit headers). |
| 18 | S.M.A.R.T. status | Yes (direct version) | skip | IOKit SMART plug-in / NVMe user client; niche. |
| 19 | Per-app disk activity | Yes | later | `ri_diskio_bytesread/written` deltas come free with the process sweep; UI space is the cost. |
| 20 | Disk readout in the menu bar | Yes | must (option) | Free space of the boot volume. |
| **Network** | | | | |
| 21 | Up/down rates in the menu bar | Several modes; interface icon mode (7.3) | must | "↓ 1.2 MB/s ↑ 40 KB/s", fixed width. |
| 22 | Rate history | Yes | must | Both directions on one sparkline, fixed labelled span. |
| 23 | Interface, local IP, link speed | Connection details, link speed in submenus | must (primary interface + local IP) / later (link speed) | Primary interface from SystemConfiguration; event-driven via `NWPathMonitor`. |
| 24 | Public IP | Fetched from Bjango's servers | skip | Network call. |
| 25 | Connectivity indicator / ping | Pings google.com and 1.1.1.1 | skip | Network traffic. |
| 26 | Wi-Fi network name | Needs Location Services | later | A permission prompt for a label isn't worth it in v1. |
| 27 | Per-app bandwidth | Top apps by bandwidth | skip | Needs spawning `nettop` (Stats users report its network module costs most energy) or private `NetworkStatistics`. |
| 28 | VPN awareness / location flag | Yes | later | |
| 29 | Data transferred since boot | Stats shows totals | later | Counters are already read. |
| **Battery and power** | | | | |
| 30 | Battery readout in the menu bar | % with different display per state (draining, charging, full) | must (option; hidden on desktops) | Event-driven, never polled. |
| 31 | Time remaining / time to full | Yes | must | `IOPSCopyPowerSourcesInfo`. "Calculating…" while macOS estimates. |
| 32 | Power source, adapter watts | Yes | must (source) / should (watts) | `IOPSCopyExternalPowerAdapterDetails`. |
| 33 | Cycle count, battery health | Yes | should | `AppleSmartBattery` registry properties (public IOKit, undocumented keys). |
| 34 | Battery / power history graph | Added in 7.02 | later | |
| 35 | System power draw (W) | Sensors | later | `AppleSmartBattery` "PowerTelemetryData", undocumented, laptops only. |
| 36 | Energy mode switching | Low Power Mode toggle on supported Macs | skip | Changing it needs admin (`pmset`). We read `isLowPowerModeEnabled` only. |
| 37 | Bluetooth device batteries | AirPods, mice, keyboards, trackpads | later | Not the core job. |
| **Sensors** | | | | |
| 38 | Temperatures | Helper or HID/SMC reads; simple and detailed lists | open question (later, opt-in) | No public API on Apple silicon. See the sensor table and Open questions #1. |
| 39 | Fan speeds | SMC | later (with #38) | SMC reads work without root here; keys differ per model. |
| 40 | Fan control | Privileged helper; not in the App Store version | skip | Needs root writes (helper). Stats' own helper is "legacy" and breaks on macOS 27 updates. |
| 41 | Voltages, currents, component power | Sensors list | skip | Private, per-chip, zeros on 27. |
| 42 | Thermal state | Not shown | must (one line) | Public `ProcessInfo.thermalState` + change notification: our honest stand-in for #38. |
| **Global** | | | | |
| 43 | One combined menu bar item | Combined mode: choose what's in the bar and what's in the dropdown | must (the only shape in v1) | One status item with 1–3 chosen readouts; the dropdown shows every section. |
| 44 | One status item per metric | The default | later | Re-evaluate after v1; macOS 27's overflow arrow makes it less risky. |
| 45 | Readout order | ⌘-drag in the menu bar; order in settings | should | Order in the Settings list. |
| 46 | Hide/reorder dropdown sections | Hover switches and handles on a menu preview | later | Fixed order in v1; empty sections (no battery) are hidden. |
| 47 | Update frequency | "Quicker / slower" slider | must | 1 s / 2 s (default) / 5 s. |
| 48 | Slow down on Low Power Mode | Not in the original | should (ours) | Drop to 5 s while Low Power Mode is on. |
| 49 | Pause while the display sleeps | Gaps shown in history for sleep | must | Stop the timer on screen sleep and system sleep; history shows a gap, not a spike. |
| 50 | Themes, colours, menu backgrounds, compact spacing | Carousel of themes; compact spacing (not with multiple displays) | skip | System materials, accent colour, system spacing. |
| 51 | Rules and notifications | High CPU, low disk, IP change, connectivity loss, weather, DST | later | The useful two: "CPU above X% for Y min" and "low disk space". |
| 52 | Global shortcut to open the dropdown | Set per menu in the Rules tab | should | `KeyboardShortcuts`, unset by default. Also the escape hatch when the item is hidden. |
| 53 | App launcher in menus | Yes | skip | Not the job. |
| 54 | Clocks, world clocks, calendar | Yes | skip | Zones covers it. |
| 55 | Weather, astronomy | Paid weather subscription | skip | Network, not the job. |
| 56 | Import/export settings | Yes (reviews say it broke) | skip | A handful of settings. |
| 57 | Process icons in lists | Yes (7.3 improved iPad app icons) | should | `NSRunningApplication.icon` or the bundle's icon; generic icon for daemons. |
| 58 | Combine child processes into their app | On by default, toggle in the Statistics menu | should | Group by the outermost `.app` in the executable path (public); fall back to the process name. |
| 59 | Click a process | Not documented | should | Opens Activity Monitor. |
| 60 | Quit an app from the list | Not in the original | should (ours) | Context menu: Quit (polite, via `NSRunningApplication.terminate()`); Force Quit asks first. GUI apps owned by the user only. |
| 61 | Launch at login | Login item (reviews/known issues: breaks after macOS upgrades) | must | SlopKit General tab, off by default. |
| 62 | Recovering a hidden item | Help page explains the notch and full menu bar | must | `SlopAppDelegate`: relaunch opens Settings; on macOS 27 the system overflow arrow reaches it. |
| 63 | Desktop widgets | Stats only | later | Needs a widget extension target. |
| 64 | Control Center control | Not offered | skip | See "macOS 26/27 menu bar specifics". |
| 65 | Localisation | 30+ languages | later | |

### Must-haves, counted

Grouped as the test step walks them: (1) one combined status item with 1–3 readouts from
CPU, memory, network, disk free and battery; (2) CPU section (total, user/system, history,
load, uptime, top 5); (3) memory section (pressure, breakdown, swap, top 5); (4) network
section (rates, history, primary interface, local IP); (5) disk free per volume; (6) battery
basics when present (%, state, time left, source); (7) thermal state line; (8) update
interval with pause on sleep; (9) Settings with General (launch at login, show in menu bar,
readouts, interval) and About; (10) the CPU and energy budgets below, measured.
**Ten, all on public or long-stable APIs, no permissions, no helper.**

## Sensor API map (what works today, without root)

Measured on this Mac (M4 Max, macOS 27.2) from an unsandboxed, unprivileged process. Slopapp
apps are ad-hoc signed and not sandboxed, so IOKit user clients and spawning system tools work.

| Sensor | API | Public? | Root / helper? | Cost per read (here) | Risk | Gauge |
|---|---|---|---|---|---|---|
| CPU total, per core, user/system | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` tick deltas | Public Mach | No | ~4 µs (with VM stats) | Low | v1 |
| P/E core grouping | `sysctl hw.nperflevels`, `hw.perflevelN.name/.logicalcpu`; device tree `cpus/*` "cluster-type" | Public sysctl; registry property undocumented | No | µs | Low; new levels appear (7.3 "super cores") | should |
| Load average, uptime | `getloadavg`, `sysctl kern.boottime` | Public | No | µs | None | v1 |
| CPU/GPU frequency, CPU/GPU/ANE power | `libIOReport` (`IOReportCreateSubscription`…) | **Private** dylib, no header | No, but… | — | **High**: on macOS 27 energy channels read 0 for unprivileged readers unless `powermetrics` runs (Stats #3621) | skip |
| Memory breakdown | `host_statistics64(HOST_VM_INFO64)` | Public | No | (in the 4 µs) | Low | v1 |
| Memory pressure level | `sysctl kern.memorystatus_vm_pressure_level` (1/2/4) and `kern.memorystatus_level` (% available); `DispatchSource.makeMemoryPressureSource` for warn/critical events | sysctls undocumented but stable for a decade; dispatch source public | No | µs | Low | v1 |
| Swap | `sysctl vm.swapusage` | Public | No | µs | None | v1 |
| Network rates | `sysctl(NET_RT_IFLIST2)` → `if_data64` 64-bit counters | Public | No | ~94 µs for all interfaces (cheaper per index) | Low. `getifaddrs`' counters are 32-bit and wrap at 4 GB | v1 |
| Primary interface, IP | `NWPathMonitor` (events), `SCDynamicStoreCopyValue("State:/Network/Global/IPv4")`, `getifaddrs` | Public | No | event-driven | None | v1 |
| Wi-Fi name | CoreWLAN | Public | Location permission | — | Prompt; Stats' "allow Wi-Fi details" broke on 27 (#3675) | later |
| Per-app bandwidth | `/usr/bin/nettop` spawn or private `NetworkStatistics.framework` | Tool / private | No | a process spawn per sample | Energy (Stats #2066: network module raised energy impact to 6–7) | skip |
| Disk free | `URLResourceValues.volumeAvailableCapacityForImportantUsage`, `statfs` | Public | No | µs per volume | Network volumes can block: read off the main actor with a timeout | v1 |
| Volumes appear/disappear | `NSWorkspace` mount/unmount notifications or DiskArbitration callbacks | Public | No | event-driven | None | v1 |
| Disk read/write rate | `IOBlockStorageDriver` "Statistics" dictionary (`kIOBlockStorageDriverStatistics*` keys are in IOKit headers) | Public | No | 12 drivers found here | Low | should |
| S.M.A.R.T. | IOKit SMART plug-in / NVMe properties | Semi-public | No | — | Medium; niche | skip |
| Battery %, state, time, source | `IOPSCopyPowerSourcesInfo`, `IOPSNotificationCreateRunLoopSource` | Public | No | event-driven | None | v1 |
| Adapter watts | `IOPSCopyExternalPowerAdapterDetails` | Public | No | on change | None | should |
| Cycle count, health, temperature, voltage | `AppleSmartBattery` registry: CycleCount, AppleRawMaxCapacity, DesignCapacity, NominalChargeCapacity, Temperature, Voltage, Amperage | Public IOKit, undocumented keys | No | µs | Low–medium (keys have changed before; Stats #3682 "wrong max capacity") | should (count, health) |
| System power draw | `AppleSmartBattery` "PowerTelemetryData" | Undocumented | No | µs | Medium | later |
| Thermal state | `ProcessInfo.thermalState` + `thermalStateDidChangeNotification` | Public | No | event-driven | None | v1 |
| GPU utilisation | `IOAccelerator` → "PerformanceStatistics" → "Device Utilization %" (also Renderer/Tiler) | Public IOKit, undocumented key | No | ~20 µs | Medium: key names vary by vendor; one Stats report of 0% on an M1 Max on 27.2 (#3726). Read 39% here | should |
| Temperatures (Apple silicon) | `IOHIDEventSystemClient` (match usage page 0xFF00, usage 5; temperature event type 15) | **Private SPI** (symbols exported from IOKit, no header) | No (46 sensors found here) | — | **High**: sensor names differ per chip and don't map to cores; Apple can restrict it like IOReport | open question |
| Temperatures / fans (SMC) | `AppleSMC` user client via `IOServiceOpen` + `IOConnectCallStructMethod` key reads (e.g. fan actual speed) | Public calls, **private protocol** and key names | No for reads (opened fine here) | — | **High**: key maps change every generation (Stats #3731: M6 renamed a key) | open question |
| Fan control | SMC writes | Private | **Yes: privileged helper** (SMAppService daemon) | — | **Very high**: Stats' helper fails to re-register after updates on 27 (#3716); iStat's daemon had a critical security fix in 7.2 | skip, never in v1 |
| Process CPU and memory | `proc_listallpids` + `proc_pid_rusage(RUSAGE_INFO_V4)` (user+system time, `ri_phys_footprint`, disk bytes) | Public libproc | No for own-user processes | ~1.9 ms for ~1,100 processes | 22% fail (root and other users' processes, e.g. WindowServer) | v1 |
| Root processes | `/bin/ps -Aceo pid,time,rss,comm` (setuid root) | Public tool | No (setuid) | ~30 ms CPU per spawn | Low; parse defensively | v1, only while open, every 5 s |
| (avoid) | `/usr/bin/top -l 1` | Public tool | setuid | **~650 ms CPU per call** | Cost | never |

Summary: everything in v1 is public API or a long-stable undocumented sysctl/registry key read
as the logged-in user. **No root, no helper, no permission prompts.** The only things that
need private SPI are temperatures, fan speeds, frequencies and component power, and the
only thing that needs a helper is fan control.

## Sampling design (the hard requirement)

- **One timer** (`DispatchSourceTimer` on a utility queue, default 2 s, generous leeway so the
  system coalesces wakeups). Stats runs one timer per module; we run one for everything.
- **Each tick reads every cheap counter** (CPU ticks, VM stats, network counters, GPU %,
  disk I/O counters: about 0.15 ms together, measured) so history exists for every section
  when the dropdown opens. Reading is cheap; **drawing is the cost**, so only the visible
  readout is drawn.
- **Hop to the main actor only when the rendered menu bar string changes.** Quantise first:
  CPU to whole percent, rates to two significant figures, "0 KB/s" below 1 KB/s, so an idle
  Mac produces identical strings and no redraw.
- **Fixed status item width** computed once per readout configuration from the widest
  possible strings ("100%", "999 KB/s"), so the item never jitters and never pushes other
  menu bar items around (a real Stats bug, #3708). Recompute only on settings or font change.
- **Text, not images**, in the status item: `button.title`/`attributedTitle` with the menu bar
  font and monospaced digits, plus one template SF Symbol. No per-tick image rendering, no
  SwiftUI in the status item.
- **Event-driven where possible**: battery (IOPS run-loop source), thermal state, memory
  pressure warnings (dispatch source), network path (`NWPathMonitor`), volumes (mount
  notifications). Disk free space every 30 s.
- **History in memory**: `Float` ring buffers per metric, one at the tick rate for 10 min and
  one of 30 s averages for 1 h. A few hundred KB at most. Nothing written to disk.
- **Dropdown open**: 1 s refresh; process sweep with `proc_pid_rusage` every second (CPU % =
  delta of user+system time over wall time, Activity Monitor style where 100% = one core);
  unreadable PIDs filled from one `/bin/ps -Aceo pid,time,rss,comm` every 5 s (CPU from
  deltas of its cumulative time column, not its decayed `pcpu`). Key processes by PID +
  start time (PID reuse). Everything stops when the dropdown closes.
- **First open**: take a sweep at open and a second one ~300 ms later so the list appears in
  well under a second; reserve the rows' space so nothing jumps.
- **Pause** on `screensDidSleep`/`willSleep`, resume on wake; the first sample after wake
  is discarded (counters jumped) and history records a gap.
- Gauge lists itself honestly in its own process list.

### Budgets and how to measure them

Gauge is never really idle, so "idle" means "running with the dropdown closed". The house
budget (`scripts/perf.sh`: idle CPU < 0.2%, footprint < 50 MB, launch < 300 ms, first status
item < 600 ms) is the floor; Gauge sets stricter, scenario-based ones:

| Scenario | Budget |
|---|---|
| A. Defaults (CPU + network, 2 s), dropdown closed | CPU **< 0.10%** averaged over 60 s; ≤ 1 wakeup per tick (≤ 0.6/s) |
| B. All five readouts, 2 s | CPU **< 0.20%** |
| C. All five readouts, 1 s | CPU **< 0.35%** |
| D. Dropdown open, 1 s, with processes | CPU **< 2%** while open; back to scenario A within 2 s of closing |
| Memory | footprint < 35 MB closed, < 50 MB after opening the dropdown, < 2 MB growth over 1 h |
| Energy | Activity Monitor Energy Impact ≤ 0.5 average in A; `top` POWER column ≤ 0.3 |
| Launch | < 300 ms; first status item < 600 ms |
| System side | WindowServer (and the menu bar host) CPU delta with Gauge vs without: recorded, not gated |

How to measure (build/test step):

1. `scripts/perf.sh Gauge --windows 6 --seconds 10` for A (longer windows so 2 s ticks average
   out). The app needs a `GAUGE_DEFAULTS_SUITE`-style env hook (as Awake has) to start with
   scenario B/C settings without touching the owner's preferences, and a review hook to open
   the dropdown for D (like Awake's `AWAKE_SHOW=menu`).
2. Wakeups: deltas of `ri_interrupt_wkups + ri_pkg_idle_wkups` from `proc_pid_rusage` over
   60 s. `scripts/drive stats` doesn't report wakeups yet; adding that field is a small
   tooling change for the build step.
3. Energy: `top -l 7 -s 10 -pid <pid> -stats pid,cpu,idlew,power` (works without root);
   average samples 2–7. Cross-check Activity Monitor's Energy tab once by hand.
4. Per-tick cost: `os_signpost` intervals around sample and redraw; check in Instruments
   once, and log the p95 in the research doc.
5. System side: CPU time of WindowServer from `ps -o time= -p <pid>` over 60 s with Gauge
   shown, then quit; compare. Noisy, so record it only.
6. **Spike first.** Before building the dropdown, measure what one status item title update
   costs on macOS 27 (Zones' per-minute clock costs ~30–37 ms of CPU per minute, partly
   measuring widths). If one update costs over ~1 ms, the 2 s default and the scenario A budget
   are at risk: raise the default interval to 3 s or redraw less often, and tell the owner.

## Key flows

### Flow 1: glance and find the culprit (the main job)
1. The menu bar shows a small CPU symbol, "12%", then "↓ 1.2 MB/s ↑ 40 KB/s" (defaults).
2. Click the item: a 320 pt panel opens under it, sections top to bottom: CPU (big %, 10 min
   sparkline, user/system, load, uptime, top 5 processes), Memory (pressure first, then
   app/wired/compressed/cached, swap, top 5), Network (rates, sparkline, interface, local IP),
   Disks (free per volume), Battery (only when present), and one Thermal line.
3. The process lists fill in within ~0.3 s; rows show icon, name, value (`.monospacedDigit()`).
4. Click a row (or arrow to it and press Return): Activity Monitor opens. Right-click a user
   app's row: Quit, or Force Quit (asks first). ⌘C copies the row as text.
5. Esc, a click outside, or a second click on the item closes the panel; sampling drops back
   to the menu bar readout only.

### Flow 2: first run
1. Launch: the status item appears with the defaults. No window, no permission prompt, no
   tour.
2. If macOS hides the item (full or notched menu bar): on macOS 27 it's behind the system
   overflow arrow; relaunching Gauge opens Settings (SlopAppDelegate) where General says the
   menu bar is full and suggests fewer readouts or the keyboard shortcut.

### Flow 3: choose what's in the menu bar
1. Panel footer → Settings… (⌘,) → General.
2. "Menu bar shows": checkboxes for CPU, Memory, Network, Disk, Battery (Battery absent on
   desktops), up to three, in a reorderable list. The status item updates live.
3. "Update every": 1 s / 2 s / 5 s.

### Flow 4: unplugged laptop
1. Unplug: the battery readout (if chosen) switches from "charging" to "%, 3:12 left"
   immediately (event-driven). With Low Power Mode on, sampling slows to 5 s automatically.

### Flow 5: sleep and wake
1. Lid closes: the timer stops. On wake: the first sample is discarded, the readout shows "—"
   for one tick, history shows a gap.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Launch at login | off | toggle | must (SlopKit) |
| Show in menu bar | on | toggle | must (SlopKit) |
| Menu bar shows | CPU (was CPU, Network; owner, 2026-11-07: calmer by default) | up to 3 of CPU, GPU, Memory, Network, Disk, Battery; ordered | must |
| Show symbols beside values | on | toggle | should |
| Update every | 2 s | 1 s, 2 s, 5 s | must |
| Slow down in Low Power Mode | on | toggle | should |
| Network units | bytes/s | bytes/s, bits/s | should |
| Group processes by app | on | toggle | should |
| Readout style | text | text, mini bar | later |
| Dropdown sections | all | hide/reorder | later |
| Keyboard shortcut: open Gauge | unset | recorder | should (Shortcuts tab) |

## Menus and shortcuts

- **Status item**: click opens the panel. No right-click menu: on macOS 27 third-party status
  items no longer receive right-clicks, so every action lives in the panel.
- **Panel footer**: Open Activity Monitor, Settings… (⌘,), About, Quit Gauge (⌘Q). Text-only
  items, per Golden Gate.
- **In the panel**: ↑/↓ move through process rows, Return opens Activity Monitor, ⌘C copies
  the selected row ("Safari, 34% CPU, PID 812"), Esc closes, ⌘Q quits.
- **Global**: one optional shortcut to open the panel, unset by default.

## Permissions and system integration

- None. No Accessibility, Screen Recording, Location, Full Disk Access, network, root or
  helper tool. Every v1 sensor reads as the logged-in user.
- Login item via SlopKit's `LaunchAtLogin` (`SMAppService.mainApp`). The original's known
  issues show login items breaking after macOS upgrades; ours is the plain main-app kind.
- No Control Center control, widget or App Intents in v1.

## macOS 26/27 menu bar specifics

- **macOS 26 Tahoe: "Allow in the Menu Bar".** System Settings › Menu Bar has per-app toggles
  for third-party items. Apps can't read that state (Apple DTS, forum 788101). Setting
  `behavior = .removalAllowed` lets people ⌘-drag the item out; observe `isVisible` with KVO
  and offer "Show in menu bar" again in Settings (SlopKit does this).
- **Tahoe's transparent menu bar.** Use `button.title` and template images so the system
  picks the right vibrancy on any wallpaper; never draw fixed colours. Don't hard-code the
  menu bar height (developers report it changed); use `NSStatusBar.system.thickness` and let
  the button centre content. iStat Menus shipped a fix for its items sitting at the wrong
  vertical offset on Tahoe, a sign custom-drawn content is fragile.
- **Control Center controls (macOS 26).** WidgetKit `ControlWidget` buttons/toggles can sit in
  Control Center or the menu bar, but they show a symbol and short label refreshed by the app,
  aren't meant for second-by-second values, and need a widget extension target that SwiftPM
  doesn't build. Skip.
- **macOS 27 Golden Gate: one window for the whole menu bar.** Status items no longer get
  their own windows. Consequences reported by developers: occlusion state no longer says
  whether an item is visible (FB23349447; this affects the hidden-item detection Zones uses),
  `button.highlight(true)` does nothing, right-clicks and drags don't reach third-party items,
  and hover tracking in status items was broken during the betas.
- **macOS 27 `expandedInterfaceDelegate`.** New in the 27 SDK (read from `NSStatusItem.h`): an
  item that shows its own window instead of an `NSMenu` should set
  `statusItem.expandedInterfaceDelegate`, show the panel in
  `statusItem(_:didBegin:)`, hide it in `statusItemDidEndExpandedInterfaceSession(_:animated:)`,
  and call `expandedInterfaceSession?.cancel()` when it closes the panel itself. That gives the
  system highlight, keyboard navigation and menu-tracking behaviour. Gauge targets macOS 14+,
  so use it under `if #available(macOS 27, *)` and keep the button action on 14–26. No Slopapp
  app uses it yet; Gauge would be the first, so it's worth moving into SlopKit afterwards.
- **macOS 27 overflow arrow.** Items that don't fit sit behind a system chevron instead of
  disappearing, which makes one combined item plus a shortcut enough.
- **Golden Gate menus are text-only**: no decorative icons in the footer or any context menu.

## UX patterns worth adopting

- **Memory pressure as the headline**, not "used": used memory is always high on macOS.
- **Sparklines with a fixed, labelled span** ("last 10 min") so a spike's age is readable,
  and **gaps for sleep** instead of a line drawn through it.
- **Combined item** that puts several readouts in one status item and everything else in the
  dropdown: protects the notched menu bar.
- **Children rolled up into their app** (all of a browser's helpers counted as the browser),
  with the plain per-process view one toggle away.
- **Per-state battery display** (time left when draining, nothing extra when charging).
- **History graphs average each sample** so they read calmly; the menu bar shows the instant
  value. Say which is which.
- A **glossary-style tooltip** on load average and pressure explains them in one sentence.

## What we won't copy, and what we'll do better

- **Not copying**: name, icon, menu bar graph styles, themes, circle gauges, weather, clocks,
  paid weather credits, the settings app's layout, help text.
- **A stated, measured budget**: forum users disagree about how much iStat Menus costs (one
  measured ~3% CPU), and Stats users report Energy Impact around 5 over 12 hours versus about
  1 for iStat. We publish our numbers in the README and gate on them in `perf.sh`.
- **Processes sampled only while you look**, never in the background.
- **No network at all**: the original and Stats both contact servers (updates, public IP,
  connectivity pings, weather).
- **No helper, no daemon, no admin password**: nothing to re-register after updates, no
  privileged attack surface (iStat had a critical daemon-communication fix in 7.2 and an
  installer fix in 7.2 (2273)).
- **Far fewer knobs**: reviewers describe the original's dropdowns as dense with a learning
  curve; App Store reviews complain about settings not applying, light/dark not following the
  system, and broken import/export. One combined item, a short settings form, system
  appearance always.
- **No width jitter, no double-toggle on second click** (Stats bugs #3708, #3711): fixed item
  width; the expanded interface session owns open/close.
- **Act on the culprit**: quit an app from the list, which neither original's docs mention.

## Edge cases

- **Desktop Macs**: no battery → battery section and option hidden. Fans/thermal still fine.
- **Counter wrap and resets**: interfaces appearing/disappearing (VPN, Thunderbolt, Wi-Fi
  off), counters reset on sleep: a negative delta drops the sample. Use 64-bit counters.
- **Duplicate traffic**: VPN tunnels (`utun*`), bridges and loopback double-count; count
  physical interfaces (or the primary one) and say which.
- **Many cores**: 14 here; up to 32 on Ultra chips. Per-core view stays compact. Core types
  from `hw.perflevelN`, not assumed as two, not assumed ordered.
- **Process churn**: processes exiting between sweeps; PID reuse (key by PID + start time);
  names truncated mid-UTF-8 by `ps` (a real Stats freeze, #3730): decode leniently.
- **Two CPU scales**: menu bar total is 0–100% of the whole chip; process rows use Activity
  Monitor's 100% per core (a process at 300% while the total says 25%). Label it.
- **Network volumes** that hang `statfs`: read off the main actor with a timeout; unmounted
  volumes vanish without errors; read-only and hidden system volumes (Preboot, VM) excluded.
- **Sleep, wake, clock changes**: monotonic time (`CLOCK_UPTIME_RAW`) for rates; first sample
  after wake discarded; history gap.
- **Hidden status item**: full or notched menu bar, "Allow in the Menu Bar" off, ⌘-dragged
  out; relaunch opens Settings, shortcut still opens the panel (anchored under the menu bar).
- **Multiple displays**: the panel opens on the display whose menu bar was clicked.
- **Light/dark, tinted glass, accent colours**: sparklines use the accent; red/orange only
  for warning/critical pressure, as `.textRed`/`.textOrange` text or plain fills next to
  labels.
- **Huge and tiny numbers**: "0 B/s", "1.2 GB/s", 10 GbE, 512 GB vs 8 TB volumes, 0 swap,
  uptime over 100 days. Fixed slots, no layout shift.
- **VoiceOver**: the status item reads "Gauge, CPU 12 percent, network down 1.2 megabytes
  per second"; live updates don't spam announcements; every row and sparkline has a label
  ("CPU, last 10 minutes, peak 84 percent").
- **Reduce Motion**: no animated sparkline scrolling.
- **Low Power Mode toggled mid-run**: interval changes without restart.
- **Non-English**: localised number and byte formatting (`ByteCountFormatStyle`), thousands
  separators (Stats #3722).

## Our v1 scope

- [ ] One status item; defaults CPU % and network ↓/↑; choose and order up to three of CPU,
      Memory, Network, Disk free, Battery; fixed width, no jitter.
- [ ] Panel (320 pt): CPU (total, user/system, 10 min/1 h sparkline, load, uptime, top 5),
      Memory (pressure, app/wired/compressed/cached, swap, top 5), Network (rates, sparkline,
      primary interface, local IP), Disks (free per volume), Battery when present (%, state,
      time left, source), Thermal state line.
- [ ] Process rows: icon, name, value; root processes included (via `ps` fill-in); click or
      Return opens Activity Monitor; ⌘C copies; Esc closes.
- [ ] macOS 27: panel driven by `expandedInterfaceDelegate`; macOS 14–26: button action.
- [ ] Update interval 1/2/5 s; battery, thermal, pressure, network path and volumes
      event-driven; sampling pauses on sleep with a history gap.
- [ ] Settings: General (launch at login, show in menu bar, readouts, interval), Shortcuts
      (open Gauge, unset), About.
- [ ] Budgets met and recorded: scenario A < 0.10%, B < 0.20%, C < 0.35%, D < 2%, wakeups,
      footprint, energy; `scripts/check.sh Gauge --perf` green.
- [ ] Unit tests: tick deltas (incl. wrap and reset), rate maths and quantising, pressure
      mapping, ring buffers and averaging, sleep gaps, process deltas with PID reuse,
      `ps` output parsing (truncated names, odd locales), app grouping, byte/percent
      formatting, fixed-width calculation.
- [ ] No network traffic, no permission prompts, no `[unlabeled]` controls.
- Should, if cheap: per-core with core types, GPU %, disk I/O rate, page-ins/outs, adapter
  watts, cycle count and health, process icons, group by app, Quit from the list,
  Low Power Mode slowdown, bits/s.

## Open questions

Already decided (owner defaults, 2026-11-03: native, fast, private, no network): one combined
item by default; no public IP or connectivity checks; history in memory only; temperatures
and fans skipped in v1; GPU utilisation later unless it's stable.

Needs the owner's call (these change scope):

1. **Temperatures and fan speeds.** Forum users list temperature among the readouts they keep
   on. It needs private SPI (`IOHIDEventSystemClient`, works here without root, 46 sensors) or
   SMC key reads (work here without root), both with per-chip names that break with new
   chips, and Apple has already started returning zeros from a similar private source on
   macOS 27. Options: (a) never; (b) v1.1 as an opt-in "Experimental: CPU temperature" (one
   averaged number, off by default, hidden when nothing is found); (c) v1. Recommendation: (b).
2. **GPU utilisation in v1?** Public IOKit, undocumented key, ~20 µs per read, works here.
   Recommendation: v1 as a dropdown row and optional readout, hidden when the key is missing.
3. **Quit / Force Quit from the process list.** Useful for the main job, but it's an action on
   other apps. Recommendation: v1, Quit for the user's GUI apps, Force Quit behind a
   confirmation, nothing for system or root processes.
4. **Spawning `/bin/ps` every 5 s while the panel is open** to include root processes
   (WindowServer, kernel_task, backupd). The alternative is a list that silently misses ~22%
   of processes. Recommendation: yes, only while open.
5. **Separate status items per metric** (the original's default) vs one combined item only.
   macOS 27's overflow arrow lowers the risk. Recommendation: combined only in v1.
6. **Budget strictness.** Is "< 0.10% with defaults, < 0.20% with everything shown" right, and
   if the status item redraw spike shows it can't be met at 2 s, is a 3 s default acceptable?
7. **Persistent history** (hours to days, written to disk) for "what happened overnight": later?
8. **Notifications** ("CPU above X% for Y minutes", "low disk space"): later?

## Sources

- [iStat Menus product page](https://bjango.com/mac/istatmenus/)
- [iStat Menus version history](https://bjango.com/mac/istatmenus/versionhistory/)
- iStat Menus 7 help: [Welcome](https://bjango.com/help/istatmenus7/welcome/),
  [Menu bar items not showing](https://bjango.com/help/istatmenus7/hiddenitems/),
  [Mac App Store differences](https://bjango.com/help/istatmenus7/macappstore/),
  [Helper](https://bjango.com/help/istatmenus7/helper/),
  [Global](https://bjango.com/help/istatmenus7/global/),
  [Combined](https://bjango.com/help/istatmenus7/combined/),
  [Memory](https://bjango.com/help/istatmenus7/memory/),
  [History graphs](https://bjango.com/help/istatmenus7/historygraphs/),
  [Menus](https://bjango.com/help/istatmenus7/menus/),
  [Hotkeys](https://bjango.com/help/istatmenus7/hotkeys/),
  [Known issues](https://bjango.com/help/istatmenus7/knownissues/),
  [Domains contacted](https://bjango.com/help/istatmenus7/domains/),
  [Glossary](https://bjango.com/help/istatmenus7/glossary/),
  [CPU & GPU](https://bjango.com/help/istatmenus7/cpugpu/),
  [Sensors](https://bjango.com/help/istatmenus7/sensors/),
  [Power](https://bjango.com/help/istatmenus7/power/)
- [iStat Menus 7 on the Mac App Store](https://apps.apple.com/us/app/istat-menus-7/id6499559693?mt=12)
- [MacRumors: iStat Menus 7.0](https://www.macrumors.com/2024/07/31/istat-menus-7-0-brings-new-features)
- [Michael Tsai on iStat Menus 7](https://mjtsai.com/blog/2024/08/01/istat-menus-7)
- [Cloudspress review of iStat Menus 7](https://www.cloudspress.com/?p=622288)
- MacRumors forums: [iStat Menus vs Stats](https://forums.macrumors.com/threads/menu-bar-monitoring-app-istat-menus-vs-stats.2342009/),
  [battery consumption](https://forums.macrumors.com/threads/istats-menu-vs-stats-which-is-better-battery-consumption.2354863/),
  [CPU usage / power](https://forums.macrumors.com/threads/istat-menus-cpu-usage-power-consumption.2131152)
- [Stats (MIT)](https://github.com/exelban/stats) and issues
  [#2066 energy impact](https://github.com/exelban/stats/issues/2066),
  [#3621 IOReport zeros on macOS 27](https://github.com/exelban/stats/issues/3621),
  [#3716 fan helper on macOS 27](https://github.com/exelban/stats/issues/3716),
  [#3726 GPU 0% on 27.2](https://github.com/exelban/stats/issues/3726),
  [#3731 SMC key change on M6](https://github.com/exelban/stats/issues/3731),
  [#3708 width jitter](https://github.com/exelban/stats/issues/3708),
  [#3711 second click reopens](https://github.com/exelban/stats/issues/3711),
  [#3730 truncated UTF-8 names](https://github.com/exelban/stats/issues/3730)
- Apple Developer Forums: [can I tell if my menu bar item is disallowed](https://developer.apple.com/forums/thread/788101),
  [NSStatusItem issues on macOS 27](https://developer.apple.com/forums/thread/836113),
  [are NSStatusItem interactions still allowed](https://developer.apple.com/forums/thread/832823),
  [right-click at the menu bar edge on Tahoe](https://developer.apple.com/forums/thread/811718)
- Apple docs: [`NSStatusItem.expandedInterfaceDelegate`](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate),
  [WidgetKit controls](https://developer.apple.com/documentation/widgetkit/controls-collection);
  macOS 27 SDK header `AppKit/NSStatusItem.h`
- [macOS 27 Golden Gate menu bar changes (Badgeify)](https://badgeify.app/macos-27-golden-gate-menu-bar-changes/)
- [Tahoe Menu Bar settings (OWC)](https://eshop.macsales.com/blog/97824-macos-tahoe-makes-it-extremely-easy-to-clean-up-a-messy-menu-bar/)
- [9to5Mac: Tahoe Control Center controls](https://9to5mac.com/2025/06/28/new-macos-tahoe-feature-solves-common-complaint/)
- [Chromium Apple silicon sensor reader (private HID API reference)](https://chromium.googlesource.com/chromium/src/+/e9b1018/components/power_metrics/m1_sensors_mac.h)
- Apple: `host_processor_info`, `host_statistics64`, `IOPSCopyPowerSourcesInfo`,
  `ProcessInfo.thermalState`, libproc (`proc_pid_rusage`), `IOBlockStorageDriver.h`.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

## Owner decisions (2026-11-07)

- **Temperatures: never.** Public APIs only; no SMC or private sensor reads, not even opt-in.
- **GPU usage: in v1** (IOKit `PerformanceStatistics`), hidden if the key ever disappears.
- **Process list: no Quit or Force Quit.** Show the culprits; the only action is "Open Activity Monitor".
- **Menu bar: one combined item only** (up to three readouts, fixed width).

## Build notes (2026-11-07)

Built per the owner decisions above: no temperatures or fans, GPU % in v1, no Quit or Force
Quit (process rows only open Activity Monitor or copy), one combined item with up to three
readouts. 93 Swift Testing tests in `GaugeCoreTests`. The Mac was locked with its display
asleep for most of the session; the walkthrough ran once it was unlocked (see "Gates").

### Spike: what one menu bar redraw costs on macOS 27

Measured first, before the panel existed, with a throwaway status item app
(`NSStatusItem` + timer, `getrusage` for CPU) on this Mac (M4 Max, macOS 27.2):

| Change per update | CPU per update |
|---|---|
| Nothing (timer only) | 0.04–0.15 ms |
| `button.title` | 6–14 ms |
| `button.attributedTitle` | 14 ms |
| A text subview (`NSTextField`) | 145 ms (pathological) |
| A custom `NSView` with `needsDisplay` | 6–12 ms |
| `button.image` (template, drawing handler) | 6–13 ms |
| `button.image` (pre-rendered bitmap) | 6–8 ms |
| Layer `contents` swap | 0.5 ms, but the menu bar never updates |

Why: on Golden Gate every visible change makes AppKit re-render the item into a bitmap once
per menu bar copy ("replicant": one per Space and display; counted with a swizzle in the
scratch spike only, never in the app) and send it to MenuBarAgent. Here that's 10 copies at
~0.4 ms each plus the button's own display and a Core Animation commit. The cost is the same
for text, attributed text or an image, and it doesn't depend on what's drawn. So each redraw
costs **10–17 ms of CPU** in the app, cold, at 2 s spacing (the probe's 15-redraw average:
11–17 ms). That is 10× the ~1 ms the plan assumed, so per the plan: **redraw less often, and
tell the owner** (see "Needs the owner's call").

### What was built to fit that

- **Ticks are cheap**: one `DispatchSourceTimer` (2 s, 20% leeway) reads CPU ticks, VM stats,
  memory pressure, swap, network counters, GPU %, disk I/O and load. Measured per source
  (warm): CPU 5 µs, memory 3 µs, network 80 µs (per-interface reads of the en* interfaces with
  a link, a full listing every 10 s), GPU 25 µs, disk I/O 16 µs (physical drivers found once a
  minute; disk images left out), load <1 µs. A whole tick: p50 0.4–0.8 ms, p95 0.5–1.4 ms
  cold (`GAUGE_PROBE`). With no readouts drawn, Gauge costs 0.07% CPU and exactly 0.50
  wakeups/s (one per tick).
- **Redraw only when it matters** (`RedrawPolicy`): the menu bar redraws when the drawn text
  changes *and* the change is noticeable (CPU or memory by 8 points, GPU by 15, a rate by ×3
  either way, a rate crossing 100 KB/s to or from idle, any disk or battery change), or when a
  small change has waited for the catch-up: 30 s (15 s at the 1 s setting, 60 s at 5 s).
  These are the "calmer by default" values (below); the first build used 5/10 points, ×2 and
  20/10/30 s.
- **Menu bar values are smoothed** (`ReadoutSmoother`, exponential average, 4 s time
  constant): a bursty upload flipping between 0 and 700 KB/s each tick reads as a steady
  rate instead of redrawing every tick. Big changes jump instead of ramping (CPU/GPU by 15
  points either way, a rate tripling past 100 KB/s), so a spike is one redraw, not five;
  rates ease down so a finished download fades. The panel shows each tick's value; the
  README says so.
- **One template image** for the whole item, rendered once per change into 1x/2x bitmaps
  (symbols and text in fixed, right-aligned slots measured once per configuration), so the
  width never changes and macOS tints it for any menu bar; skipped entirely while the item is
  hidden.
- **Processes only while the panel is open**: a sweep at open, 0.3 s later, then every 2 s
  (it's most of the open panel's cost); `ps` at open, a second later, then every 5 s; top-5 by
  a single pass, not a sort; app bundle resolved once per process.
- **Panel graphs are SwiftUI shapes, not `Canvas`**: a `Canvas` filled with any saturated
  colour (the accent, even resolved to plain RGB) made the open panel allocate ~220 MB of
  graphics memory on macOS 27 (footprint 264 MB vs 42 MB). Worth knowing for SlopKit: its
  `Hairline` is a Canvas but draws `separatorColor`, which doesn't trigger it.

### Owner decision: calmer by default (2026-11-07, after the first build)

The owner's call on budget A: **calmer by default**. The default menu bar readout is now
**CPU only** (network, GPU, memory, disk and battery are still in Settings), and the change
thresholds were raised so the menu bar redraws less often: CPU/memory 5 → 8 points, GPU
10 → 15, rates ×2 → ×3, and the periodic catch-up for small changes 20 → 30 s (1 s setting
10 → 15 s, 5 s setting 30 → 60 s). Big changes still show at once (the smoother still jumps
on a 15-point or ×3 move); the 1 s option stays. README updated.

Re-measured the same way (120 s each, release build, test defaults suite, other agents
building: load 1.5–3.4):

| Scenario | Budget | Before | Now | Redraws now | Wakeups/s now | top POWER now |
|---|---|---|---|---|---|---|
| A. Defaults, 2 s (now CPU only) | < 0.10% | 0.17–0.34% (CPU + network) | **0.103%, 0.130%** | 2.0–2.5/min | 0.83–0.87 (budget ≤ 0.6) | 0.05–0.06 |
| B. CPU, memory, network, 2 s | < 0.20% | 0.16–0.18% | 0.206% | 5/min | 1.37 | 0.15 |
| C. CPU, GPU, network, 1 s | < 0.35% | 0.43–0.52% | 0.353% | 7.5/min | 2.37 | 0.31 |
| CPU only, 1 s | | | 0.228% | 4/min | 1.55 | 0.18 |
| House gate `perf.sh` | < 0.2% | | 0.056% lowest window | | | |

An intermediate run (new thresholds, catch-up still 20 s) gave A 0.145% / 0.159%, CPU +
network 0.229%, B 0.21–0.24%, C 0.368%; the 30 s catch-up brought A down to the numbers
above. A is now at its budget within noise (0.10–0.13%: about 0.07% is the ticks, the rest
two or three redraws a minute); B and C sit right at theirs. Wakeups are still over (0.83/s
vs 0.6): 0.50/s is the timer itself, and each redraw brings about six more from AppKit and
Core Animation, which Gauge can't avoid. On this Mac most remaining redraws are real CPU
bursts from the other agents (5% → 52% → 5%), which the menu bar should show.

`scripts/check.sh Gauge --perf` passes after the change (launch 137 ms, first status item
246 ms, idle 0.056% lowest window, 21.8 MB).

### Budgets, measured before the decision (release build, this Mac, other agents building in parallel: load 1.4–7.8)

`scripts/drive stats`/`proc_pid_rusage` over 120 s per scenario, 8 s after launch, test
settings via `GAUGE_READOUTS`/`GAUGE_INTERVAL` (never the real defaults), wakeups =
`ri_interrupt_wkups + ri_pkg_idle_wkups`, energy = `top -stats power` averaged.

| Scenario | Budget | Measured | Redraws | Wakeups/s | top POWER | Pass |
|---|---|---|---|---|---|---|
| A. Defaults (CPU + network, 2 s) | < 0.10% | 0.17%, 0.24%, 0.22%, 0.34% (four runs, load 3, 1.4, 14, 6) | 5.5–13/min | 1.24–2.63 (budget ≤ 0.6) | 0.13–0.29 (≤ 0.3) | **No** (CPU, wakeups); energy yes |
| B. Three readouts, 2 s (CPU, GPU, network) | < 0.20% | 0.156% | 3/min | 1.04 | 0.09 | Yes |
| B. (CPU, memory, network) | < 0.20% | 0.182%, 0.162% (final build) | 2.5–4.5/min | 0.83–1.18 | 0.11–0.13 | Yes |
| B. (disk, battery, memory) | < 0.20% | 0.141% | 3.5/min | 1.08 | 0.08 | Yes |
| C. Three readouts, 1 s (CPU, GPU, network) | < 0.35% | 0.43% (6 s settle), 0.46% (10 s settle; load 6), 0.52% (final build, load 2–6) | 17–20/min | 3.4–4.4 | 0.38–0.46 | **No** |
| D. Panel open, 1 s, processes | < 2% | 1.44% final (1.65%; 2.5% before the fixes below) | 9/min | 2.8–3.4 | 1.40–1.60 | Yes |
| No readouts (ticks only) | | 0.07% | 0 | 0.50 | 0.00 | |
| Memory, closed | < 35 MB | 22.5 MB | | | | Yes |
| Memory, panel open | < 50 MB | 36.0–42.3 MB (264 MB before the Canvas fix) | | | | Yes |
| Memory growth, 1 h | < 2 MB | +0.8 MB (22.5 → 23.3 MB over 61 min; range 22.2–23.3; sampling paused for part of it by display sleep) | | | | Yes |
| Launch / first status item | < 300 / < 600 ms | 117–149 / 224–280 ms | | | | Yes |
| House gate `perf.sh` (lowest of 3 × 5 s) | < 0.2% | 0.006–0.092% (2 of 9 runs failed at 0.52%: a redraw in every window) | | | | Yes (flaky on a busy Mac) |

Where A misses: the cost is ~0.07% for ticks plus ~14 ms per redraw. On this busy Mac the
network readout has real bursts (agents streaming) and CPU moves by 5+ points often, so A
sees 5–13 redraws a minute; on a quiet Mac it falls to the 20 s settle (3/min), about 0.14%.
Hitting 0.10% would mean a settle of ~40 s or dropping the network readout from the
defaults. Wakeups: one per tick from Gauge's timer (0.50/s); the rest come with redraws
(AppKit's replicant update timer, the Core Animation commit), about 6 per redraw.

System side (recorded, not gated), 120 s each, defaults: **MenuBarAgent 0.025% without
Gauge, 0.30% with it** (12.5 redraws a minute at load 14), so each redraw costs MenuBarAgent
about as much again as it costs Gauge (~13 ms). WindowServer 45.3% → 46.3%: within its noise
(other agents' windows kept it at 45% with the display asleep).

Not measured: Activity Monitor's Energy Impact column (needs a person at an unlocked Mac;
`top`'s POWER is above), Instruments signposts (the `tick` interval is signposted under
`app.slopapp.gauge`; the probe's timings are above instead).

### Decisions made while building

1. **Panel layout: an overview row per section plus one detail**, instead of every section
   stacked. All of them stacked was ~850 pt tall; this is 320 × 653 pt, never scrolls, keeps
   every live value visible at a glance (each row has its value and a 10-minute mini graph),
   and the detail has room for a real graph and the top 5. Switching sections: click, 1–6,
   ← →, Tab. The detail area has one fixed height so switching never resizes the panel.
2. **The panel is SlopKit's `FloatingPanel`** (non-activating glass) at pop-up-menu level,
   centred under the item; on macOS 27 it's driven by `expandedInterfaceDelegate`
   (`statusItem(_:didBegin:)` shows it, the session's end hides it, closing it ourselves
   cancels the session); on 14–26 by the button's action with a 0.3 s guard against the
   reopening second click. Guarded with `#if compiler(>=6.4)` + `#available(macOS 27, *)`
   so CI's Xcode 26 still builds. Hidden item: it opens at the top right of the screen with
   the pointer (shortcut or relaunch).
3. **Network counts en* interfaces only** (Wi-Fi, Ethernet, USB/Thunderbolt adapters), so a
   VPN's traffic isn't counted twice; the primary connection and IP are read from
   SystemConfiguration when the panel opens and every 5 s while it's open, not with an
   `NWPathMonitor` running all day (zero cost while closed).
4. **Default readout: CPU only** (owner, after the first build; it was CPU + network).
   **"Show symbols beside values" was dropped**: symbols are always on (three bare
   percentages would be ambiguous) and it's one knob fewer.
5. **Memory readout = memory pressure %**; battery readout = percent with a level symbol (a
   bolt on the adapter), time left in the panel only (a time would make the slot wide).
6. **GPU**: `IOAccelerator` → `PerformanceStatistics` → "Device Utilization %" (Intel/AMD
   "GPU Activity(%)" as a fallback), the busiest GPU wins. Hidden everywhere after 3 failed
   reads at launch, or 30 in a row if it ever worked. No per-app GPU list (no public API);
   the GPU detail says so.
7. **Per-core**: the performance and efficiency core averages (from `hw.perflevelN` and the
   device tree's `cluster-type`, any number of levels) instead of per-core bars. Bars later.
8. **After waking**: a baseline is taken at wake and real values appear a second later
   (no "–" flash); history shows a gap. Sleep and display sleep both pause sampling.
9. **Process rows**: icon, name, value; no process-count badge (it read as noise; the
   tooltip and VoiceOver say "4 processes"). Context menu: Copy, Open Activity Monitor.
   Activity Monitor can't be told which process to select (no API).
10. **Root processes** come from `/bin/ps -Aceo pid,time,rss,comm` (owner question 4,
    recommendation taken): their memory is resident size, and the row's tooltip says so.
11. **Icon**: a dial instrument face-on (case = tile, face bleeding off the bottom, scale cut
    by 45° ticks, lingonberry needle). All tile colours were taken, so a new one, **tarn
    `#4F7D78`** (a muted lake teal), was added to `TILES`. Plate: **dandelion, Taraxacum
    officinale** (Köhler plate 5): a dandelion clock is the gauge children read by blowing on
    it, and its jagged leaves print well. `herbarium.py check Gauge` passes. The website
    export (`export_web.py`, writes to `web/`) was not run: out of this build's scope.
12. **Menu bar "full" hint in Settings** (Flow 2) not built: on macOS 27 an app can't tell
    whether its item is hidden (occlusion is broken there, FB23349447). Relaunching opens
    Settings and the shortcut opens the panel anywhere.

### Gates

- `scripts/check.sh Gauge --perf`: **green** on the final build (lint, icon, 92 tests,
  universal bundle, smoke, perf: launch 123 ms, first status item 229 ms, idle 0.056% lowest
  window, 22.7 MB). Not every run passes: 2 of 9 perf runs failed the lowest idle window
  (0.52%) because every 5 s window happened to contain a redraw (heavy CPU and upload bursts
  from other agents). The gate assumes an app's idle work is steady; Gauge's follows what the
  Mac is doing. Its "first status item" probe also read -1 once: the owner's menu bar is
  full, so macOS 27 puts the item behind the overflow arrow.
- `scripts/lint.sh Gauge`: passes.
- Walkthrough with `scripts/drive` on the release build, demo data (`GAUGE_DEMO=1`, a test
  defaults suite), light and dark, once the Mac was unlocked and idle ≥ 60 s (note: `drive
  key` itself resets the HID idle timer, so the gate is checked before each pass, not
  between steps). Done: the status item is in the menu bar's accessibility tree; pressing it
  opens the panel (320 × 653); 1–6 switch sections (CPU, Memory, Network, Disk, Battery,
  GPU shots); ↓ ↓ selects the second process row; Return closes the panel and shows "Would
  open Activity Monitor" (`GAUGE_NO_OPEN`); Esc closes the panel; ⌘, opens Settings;
  Settings checkboxes add Disk free, move it left and remove CPU, and the menu bar redraws
  with the new layout each time (render log). `drive tree` of the panel, Settings and the
  menu bar item: **no `[unlabeled]`**. Settings' close button is 16 × 16.
- Found and fixed in the walkthrough: on macOS 27 an Accessibility press (VoiceOver,
  scripts) reaches the button's action, not the expanded session, so the action is kept on
  27 too, de-duplicated against the session; the readout move buttons were 5 × 9 pt hit
  targets (now 20 × 20).
- Not walked: the status item's own pixels (the owner's menu bar is full, so it sits behind
  macOS 27's overflow arrow; its drawing is the same bitmap reviewed offscreen in light and
  dark via `GAUGE_SNAPSHOT_DIR`), a real click on it (needs the mouse in the menu bar; the
  27 session path is untested by hand), ⌘C (would write the owner's clipboard; `copyText` is
  unit-tested), sleep/wake, Low Power Mode and unplugging (system changes). The soak run
  shows sampling stopping during display sleep (CPU time flat for 30 min).
- Screenshots (not committed): `/tmp/gauge-test/walk/` (on-screen panel, every section,
  light and dark; Settings) and `/tmp/gauge-test/snap/` (offscreen renders incl. the menu
  bar item).

### Design review (design-system §10)

1 one click (or the optional shortcut) ✓ · 2 native: FloatingPanel glass, system controls,
accent only, no hex, light and dark ✓ · 3 keyboard: 1–6, ← → Tab, ↑ ↓, Return, Esc, ⌘C, ⌘,,
⌘Q, the panel's menu rows show their shortcuts ✓ · 4 Esc / ⌘, / ⌘Q ✓ · 5 General (launch at
login, show in menu bar) + About ✓ · 6 HIG copy ✓ · 7 empty states ("Measuring…", "No
volumes to show.", reserved process rows) ✓ · 8 no permissions ✓ · 9 nothing destructive ✓
· 10 no network APIs at all ✓ · 11 house budgets ✓, Gauge's own A and C ✗ (above) · 12 no
`[unlabeled]`, every row has a value ✓ · 13 nothing animates ✓ · 14 Settings position
(SwiftUI), last panel section remembered ✓ · 15 lint ✓ · 16 16 × 16 window buttons ✓ · 17
row highlights `Radius.nested(in: 16, padding: 8)`; measured panel radius 15.4 pt ✓ · 18
`Spacing` tokens only ✓ · 19 overview symbols, detail text and process icons share the
16 pt leading edge (measured on the 2x shots) ✓ · 20 SlopKit `Hairline` ✓ · 21 primary text
passes; secondary is the system's `.secondary` on glass (the accepted floor) ✓ · 22 hover,
selected (accent, grey when inactive), keyboard selection ✓ · 23 middle truncation, fixed
slots for huge numbers ✓ · 24 fixed detail height, reserved rows, monospaced digits, fixed
menu bar width ✓ · 25 text-only context menu ✓ · 26 checked in light and dark, on screen and
offscreen ✓.

### Gap review (v1 scope)

- [x] One status item; defaults CPU and network; choose and order up to three (Settings:
      checkboxes + move left/right); fixed width, no jitter.
- [x] Panel: CPU (total, user/system, 10 min / 1 h graph, load, uptime, top 5), GPU, Memory
      (pressure, app/wired/compressed/cached, swap, swapping rate, top 5), Network (rates,
      graph, connection, IP), Disks (free per volume, I/O graph), Battery when present,
      thermal state line.
- [x] Process rows: icon, name, value; root processes via `ps`; click or Return opens
      Activity Monitor; ⌘C copies; Esc closes. (Owner: no Quit.)
- [x] macOS 27 `expandedInterfaceDelegate`; 14–26 button action (kept on 27 for
      Accessibility presses). A real click on 27 not exercised (item behind the overflow).
- [x] Update interval 1/2/5 s; battery (IOPS run-loop source), thermal, volumes (mount
      notifications) event-driven; network path read on open; sampling pauses on sleep and
      display sleep with a history gap.
- [x] Settings: General (launch at login, show in menu bar, readouts, interval, Low Power
      Mode, units, combine helpers), Shortcuts (open Gauge, unset), About.
- [~] Budgets: after "calmer by default", A (0.10–0.13%), B (0.21%) and C (0.35%) are at
      their budgets within noise; D, memory, growth, energy, launch and the house gate met;
      **the wakeup budget (≤ 0.6/s) is still missed** (0.83/s, see above).
- [x] Unit tests: tick deltas (wrap, reset), rates, quantising and smoothing, pressure
      mapping, ring buffers, buckets, gaps, decimation, process deltas with PID reuse, `ps`
      parsing (truncated UTF-8, day formats, junk), app grouping, formatting (locales),
      fixed-width candidates, redraw policy, preferences (tolerant decoding), demo session,
      real-source smoke tests.
- [x] No network traffic, no permission prompts, no `[unlabeled]` controls.
- Should-haves: GPU ✓, disk I/O ✓, swapping rate ✓, adapter watts ✓, cycle count and
  health ✓ (matches System Settings' 91% here), process icons ✓, group by app ✓ (setting),
  Low Power Mode slowdown ✓, bits/s ✓, readout order ✓, global shortcut ✓ (unset).
  Per-core bars: partly (P/E averages). Quit from the list: no (owner).

### Deferred (moved to later)

Per-core bars; persisted history (days); notifications (high CPU, low disk); per-app disk
activity; Wi-Fi name; link speed; battery history graph; separate items per readout; a graph
style for the menu bar readout; the "menu bar is full" hint (can't be detected on 27);
localisation.

### Shared components built in-app (SlopKit candidates)

- `StatusItemController` + `MenuBarLayout` (`StatusItemController.swift`): a status item
  that adopts macOS 27's `expandedInterfaceDelegate` behind availability checks, and renders
  fixed-slot readouts into one template bitmap. Zones/Awake could share the 27 handling.
- `PanelMenuRow` (`PanelView.swift`): menu-style text rows (title + shortcut, hover
  highlight) for the bottom of a panel, the panel equivalent of `MenuFooter`.
- `Sparkline`/`HistoryGraph` (`Sparkline.swift`): a fixed-span history graph with gaps, as
  shapes (see the Canvas memory note).
- `Snapshots` (`Snapshots.swift`): the offscreen review renderer, same pattern as Awake's.

### Needs the owner's call

- **Budget A and wakeups: decided** ("calmer by default", see above: options (b) and (c)
  below). What remains open: the wakeup budget (≤ 0.6/s) can't be met by any app whose menu
  bar item changes on macOS 27; A, B and C now land at their budgets within measurement
  noise. The note as raised: a menu bar redraw costs 10–17 ms on macOS 27 (AppKit renders
  the item once per Space/display), so "< 0.10% with defaults" and "≤ 0.6 wakeups/s" can't
  both hold with a readout that updates when things change. Built: calm redraws + smoothing,
  0.17–0.24% on this busy Mac (≈0.14% expected at rest), passing the house gate, and
  MenuBarAgent pays about the same again per redraw. C (1 s) is 0.43–0.52% against 0.35%.
  Options: (a) accept ~0.25% (A) and ~0.5% (C) as the budgets on macOS 27; (b) default to
  CPU only (no network readout), which roughly halves redraws on a Mac with bursty traffic;
  (c) calmer thresholds (CPU by 8 points, a 40 s settle), at the cost of a readout that lags
  more; (d) drop the 1 s option.
