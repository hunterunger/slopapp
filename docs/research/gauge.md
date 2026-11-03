# Gauge research (inspired by iStat Menus)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: iStat
> Menus 7 (not installed on this Mac) from Bjango's product page, the 7.0 launch coverage
> and comments, App Store listing, forum threads, and the MIT-licensed Stats app (an
> open-source equivalent), plus probes of the public system APIs on this Mac (macOS 27.2,
> Apple Silicon), on 2026-11-03. We never copy its name, icons, artwork, wording, sounds or
> signature visuals.

## The job

Gauge answers "why is my Mac slow / hot / loud / draining?" and "is the download still
going?" at a glance, without opening Activity Monitor. People keep a tiny CPU or network
readout in the menu bar all day and click it when something feels off, to see a short
history and which app is to blame. "Done" is knowing the culprit within two seconds, and
a monitor that never becomes the culprit itself.

The one interaction that matters most: **glance at a live number in the menu bar; click
it, see sparklines for the last minutes and the top processes, click a process to see it
in Activity Monitor.**

## Who and when

- Fans spin up: click, see which process is at 300% CPU.
- Mac feels sluggish: check memory pressure and swap.
- A big download/upload: watch the network rate in the menu bar.
- Unplugged in a meeting: battery %, time remaining, what's draining it.
- Disk almost full warnings: free space per volume.

Frequency: passive glances all day; a click a few times a day (5–20 seconds).

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | CPU in the menu bar | Percentage, graph, bars, per-core, stacked label/value modes | must | One status item; CPU % text (`.monospacedDigit()`) or a tiny bar. Data: `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` tick deltas (7 µs per sample measured). |
| 2 | CPU dropdown | Per-core, history graphs, load averages, uptime, frequency, top apps, P/E core styling | must (total, user/system, history, top 5, load, uptime) / should (per-core, P/E split via `hw.perflevel*`) / skip (frequency: private) | Sparkline 2 min at 1 s while open, 1 h at the idle interval. |
| 3 | Memory | Usage, pressure, compressed, swap, history, top apps | must | `host_statistics64(HOST_VM_INFO64)`; pressure via `kern.memorystatus_vm_pressure_level` (sysctl); swap via `vm.swapusage`. Show pressure first (it's the honest signal), then used/wired/compressed/cached. |
| 4 | Network | Up/down rates, history, per-app bandwidth, public/private IP, connectivity, Wi-Fi name | must (rates, history, interface, local IP) / skip (public IP: network call; per-app bandwidth: private `NetworkStatistics`) / later (Wi-Fi name needs Location) | `sysctl(NET_RT_IFLIST2)` → `if_data64` 64-bit counters (`getifaddrs`'s `if_data` is 32-bit and wraps at 4 GB). Exclude loopback/utun duplicates. |
| 5 | Disks | Used/free, activity, S.M.A.R.T., per-app disk use | must (free space per mounted volume) / should (read/write rate from `IOBlockStorageDriver` "Statistics") / skip (S.M.A.R.T., per-app) | Free = `volumeAvailableCapacityForImportantUsage` (matches Finder, includes purgeable). |
| 6 | Battery and power | Status, configurable icon, Bluetooth device batteries | must (%, charging state, time remaining, power source) / should (cycle count, max capacity, adapter watts from `AppleSmartBattery` registry) / later (Bluetooth device batteries) | `IOPSCopyPowerSourcesInfo` + `IOPSNotificationCreateRunLoopSource`: event-driven, no polling. Hidden on Macs without a battery. |
| 7 | Sensors (temperatures, fans, voltages, power) and fan control | SMC + HID sensor reads; fan control via a privileged helper | skip (v1) | No public API on Apple Silicon: temperatures need the private `IOHIDEventSystemClient` or the `AppleSMC` user client, with per-model sensor maps that change every chip. Public substitute: `ProcessInfo.thermalState` (nominal/fair/serious/critical) + its change notification. See Open questions. |
| 8 | GPU usage/memory/temp/frequency | Supported Macs | later | Utilization is readable via public IOKit (`IOAccelerator` → "PerformanceStatistics"), but the key names are undocumented and vary; temp/frequency are private. |
| 9 | Combined mode | Merge items into one menu bar item, choose sections | must (as the default shape) | One status item showing 1–2 chosen metrics; the dropdown shows all sections. Protects the crowded/notched menu bar. |
| 10 | Separate menu bar items per module | Default in the original | later | Multiple `NSStatusItem`s; re-evaluate after v1. |
| 11 | Top processes | Per module (CPU, memory, disk, network) | must (CPU, memory) | Only sampled while the dropdown is open. See sampling design. |
| 12 | Notifications / rules | High CPU, low disk, IP change, connectivity loss… | later | "Low disk space" and "CPU above X% for Y min" are the useful two. |
| 13 | Weather, astronomy, clocks, calendar | Weather (paid credits, network), time/world clocks | skip | Not the job; network; Zones and Glance cover time. |
| 14 | Themes, colors, menu backgrounds | Many | skip | System materials and semantic colors only. |
| 15 | Update interval | Configurable | must | 1 s / 2 s (default) / 5 s for the menu bar readout. |
| 16 | Open Activity Monitor | Links from sections | should | Click a process → reveal it in Activity Monitor (`open -b com.apple.ActivityMonitor`); ⌘-click copies PID. |
| 17 | Remote monitoring / widgets | Stats has widgets and a remote module | later (widgets) / skip (remote) | |
| 18 | Launch at login / Show in menu bar | Yes | must | SlopKit General tab. Launch at login: off by default. |

### Must-haves, counted

1 CPU readout, 2 CPU section, 3 memory, 4 network rates, 5 free space, 6 battery basics,
9 one combined item, 11 top processes, 15 interval, 18 General. Ten, all on public APIs.

## Sampling design (the requirement)

Measured on this Mac: `host_processor_info` + `host_statistics64` ≈ 7 µs per sample;
a `proc_pid_rusage` sweep of all 1,239 processes ≈ 2.4 ms; spawning `/bin/ps` ≈ 20–30 ms
of CPU. `proc_pid_rusage` fails for ~23% of processes (root and other users' processes,
e.g. WindowServer) without privileges; `/bin/ps` and `/usr/bin/top` are setuid root and
can see them.

- **One timer for everything** (`DispatchSourceTimer`, default 2 s, 25% leeway so the
  system can coalesce wakeups). Each tick reads only what the visible readout needs.
- **Menu bar redraws only when the rendered text changes.** Text, not images, where possible.
- **Battery and thermal state are event-driven** (IOPS run-loop source, thermal-state
  notification): never polled.
- **History**: fixed-size ring buffers of `Float` in memory (1 h at the idle interval; 2 min
  at 1 s while open). Nothing written to disk.
- **Dropdown open**: switch to 1 s; sweep processes with `proc_pid_rusage` (CPU = delta of
  user+system time; memory = `ri_phys_footprint`, the same metric as Activity Monitor's
  "Memory"); fill unreadable PIDs from one `/bin/ps -Aceo pid,pcpu,rss,comm` every 5 s.
  All of it stops the moment the dropdown closes.
- **Pause** sampling while displays sleep (`NSWorkspace.screensDidSleepNotification`).
- Budget: < 0.2% CPU averaged at 2 s with CPU + network shown, < 50 MB footprint. Gauge
  must show its own CPU in its own list honestly.

## Key flows

### Flow 1: glance and drill in (main job)
1. Menu bar shows "12%" with a small CPU symbol (default metrics: CPU and network down/up).
2. Click: a 320 pt `.window`-style panel opens: CPU (big %, sparkline, user/system, load,
   uptime, top 5), Memory (pressure, used, swap, top 5), Network (↓/↑ rates, sparkline,
   interface, local IP), Disk (free per volume), Battery (if present), Thermal state.
3. Click a process row → Activity Monitor opens. Esc closes the panel.

### Flow 2: first run
1. Launch: the status item appears showing CPU and network. No window, no permission.
2. Settings → General has "Show in menu bar: CPU / Memory / Network / Battery / Disk"
   (choose up to two to keep the item short) and the update interval.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Metrics in the menu bar | CPU + Network | any 1–2 of CPU, Memory, Network, Disk free, Battery | must |
| Readout style | Text | Text, mini bar | should (bar) |
| Update interval | 2 s | 1 s, 2 s, 5 s | must |
| Sections in the dropdown | all | reorder/hide | later |
| Network units | bytes/s | bytes/s, bits/s | should |
| Launch at login / Show in menu bar | off / on | toggles | must |

## Menus and shortcuts

Panel footer: Open Activity Monitor (⌘O) · Settings… ⌘, · About · Quit ⌘Q. In the panel:
↑/↓ move through process rows, Return opens the selected one in Activity Monitor, ⌘C
copies the row ("Safari, 34% CPU, PID 812"), Esc closes. Global shortcut to open the panel: unset by default, recorder in Settings.

## Permissions and system integration

None. No Accessibility, no Location (Wi-Fi name skipped), no network, no helper tool, no
root. Everything above is public API, readable as the logged-in user.

## UX patterns worth adopting

- Memory **pressure** as the headline, not "used": used memory is always high on macOS.
- Sparklines with a fixed, labelled time span so a spike's age is readable.
- Combined mode as the default protects the notch area (lesson from Zones' build).

## What we won't copy, and what we'll do better

- Not copying: name, icon, themes, graph styles, weather, paid credits.
- Better: radically fewer knobs; zero network traffic (Stats and iStat fetch public IP and
  updates); a stated, tested CPU budget (forum complaints: monitors costing ~3% CPU);
  processes sampled only while you look.

## Edge cases

- Desktop Macs (no battery): battery section and option hidden.
- Counter wrap and interface resets (VPN connects/disconnects, sleep): negative deltas → drop
  the sample. First sample after wake shows "—" not a spike.
- Many cores (e.g. 32 on M-series Ultra): per-core view must stay compact.
- External/network volumes appearing and disappearing; read-only volumes.
- Processes exiting between sweeps; PID reuse (key by PID + start time).
- Time changes (sleep, clock change): use monotonic time for rates.
- Dark/light and accent colors in sparklines; VoiceOver reads "CPU 12 percent".

## Our v1 scope

- [ ] One status item with CPU % and network ↓/↑ by default; choose up to two metrics.
- [ ] Dropdown: CPU (total, user/system, sparkline, load, uptime, top 5), Memory (pressure,
      used/wired/compressed, swap, top 5), Network (rates, sparkline, interface, IP), Disk
      free per volume, Battery (%, state, time left, source) when present, Thermal state.
- [ ] Process rows open Activity Monitor; include root processes via `/bin/ps` fill-in.
- [ ] Update interval 1/2/5 s; battery/thermal event-driven; sampling pauses on display sleep.
- [ ] Settings: General (launch at login, menu bar metrics, interval), Shortcuts, About.
- [ ] perf.sh: idle < 0.2% CPU with the default readout, < 50 MB.
- [ ] Unit tests: tick-delta math (incl. wrap/reset), rate math, pressure mapping, ring
      buffer, process delta with PID reuse, formatting ("1.2 MB/s").

## Open questions

Decisions (owner defaults, 2026-11-03: native, fast, private, no network):

1. **Temperatures/fans/GPU temp:** skip in v1. They need private APIs (SMC user client or
   `IOHIDEventSystemClient`) with per-chip sensor maps; Thermal state is the public
   stand-in. Revisit as an opt-in "experimental sensors" later only if the owner accepts a
   private API.
2. **GPU utilization:** later, via public IOKit with undocumented keys; ship only if it's
   stable across this Mac's chips.
3. **One combined item by default**, not one per module.
4. **No public IP / connectivity check** (needs network).
5. **History in memory only**; persistent history is later.

## Sources

- [iStat Menus product page](https://bjango.com/mac/istatmenus/)
- [Michael Tsai on iStat Menus 7](https://mjtsai.com/blog/2024/08/01/istat-menus-7)
- [MacRumors: iStat Menus 7.0](https://www.macrumors.com/2024/07/31/istat-menus-7-0-brings-new-features)
- [MacRumors thread on iStat CPU usage](https://forums.macrumors.com/threads/istat-menus-cpu-usage-power-consumption.2131152)
- [Stats (MIT)](https://github.com/exelban/stats)
- [Chromium Apple Silicon sensor reader (private HID API reference)](https://chromium.googlesource.com/chromium/src/+/e9b1018/components/power_metrics/m1_sensors_mac.h)
- [macmon](https://docs.rs/crate/macmon/0.8.0)
- Apple: `host_processor_info`, `host_statistics64`, `IOPSCopyPowerSourcesInfo`, `ProcessInfo.thermalState`, libproc.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
