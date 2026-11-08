# Gauge

CPU, memory, network and battery in your menu bar.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to iStat Menus.

**Status:** alpha (0.1.0)

## What it does

One item in the menu bar shows up to three live readouts: CPU (default), network down and up
(default), GPU, memory pressure, free space on the startup disk, or battery. Click it (or press
the shortcut you set in Settings) for the panel:

- **An overview row per section**, each with its live value and a small graph of the last ten
  minutes. Click a row, press **1–6**, or **← →** to pick a section.
- **CPU**: total, user and system, a history graph (10 minutes or an hour), the average of
  the performance and efficiency cores, load averages, uptime, and the five apps using the most
  CPU. Helper processes are counted with their app (a browser and its renderers are one row);
  root processes such as WindowServer are included.
- **GPU**: how busy the graphics processor is, with history. (macOS doesn't say which apps use
  the GPU, so there's no list.) Hidden on Macs whose GPU doesn't report it.
- **Memory**: pressure first (used memory is always high on macOS; pressure is what slows a
  Mac down), with history, the app/wired/compressed/cached breakdown, swap, swapping rate, and
  the five apps using the most memory.
- **Network**: down and up rates with history, the connection (Wi-Fi, Ethernet…) and its IP
  addresses. Counts Wi-Fi and Ethernet interfaces only, so VPN traffic isn't counted twice.
- **Disk**: free space per volume (as Finder counts it), and read and write activity.
- **Battery** (laptops): charge, state, time left or until full, power source, adapter watts,
  cycle count and maximum capacity.
- **Thermal state**: whether macOS is slowing the Mac down to cool it.

Process rows open Activity Monitor (click, or select with **↑ ↓** and press **Return**);
**⌘C** copies the selected row. **Esc** closes the panel, **⌘,** opens Settings, **⌘Q** quits.
Gauge never quits or changes other apps.

## Settings

General: Launch at login, Show in menu bar, which readouts the menu bar shows (up to three,
in order), how often it updates (1, 2 or 5 seconds), slowing down in Low Power Mode, bytes or
bits per second, and whether helper processes are combined into their app. Shortcuts: one
optional shortcut to open the panel (unset by default; it's the way in when the menu bar is too
full to show Gauge). Opening Gauge again from Finder or Spotlight also brings back a hidden
item and opens Settings.

## What it costs

Gauge runs all day, so it's built to cost as little as possible. See "Build notes" in
[`docs/research/gauge.md`](../../docs/research/gauge.md) for the measurements.

- One timer reads every counter (about 0.5 ms of CPU) every 2 seconds. Processes are only
  sampled while the panel is open.
- Redrawing a menu bar item costs macOS 27 10–17 ms of CPU each time, in Gauge, and about as
  much again in the system's menu bar process (it renders the item again for every Space and
  display). So the menu bar redraws only when a value changes noticeably (CPU or memory by 5
  points, GPU by 10, a rate halving or doubling, a download starting or stopping), and
  catches up on small changes every 20 seconds (10 at the 1 s setting). Small wobbles are
  averaged over a few seconds so the menu bar reads calmly; big changes show at once. The
  panel shows each second's value.
- Sampling stops while the Mac or its display sleeps; the graphs show a gap.
- History is kept in memory only (an hour), nothing is written to disk.

## Permissions and privacy

None. Gauge reads public system counters as your user: no Accessibility, no Full Disk Access,
no helper tool, no administrator password, no network access. It runs `/bin/ps` every 5 seconds
while the panel is open, to include processes your user can't inspect directly (root
processes such as WindowServer). No temperatures or fan speeds: on Apple silicon those need
private interfaces.

## Not there yet

Per-core bars, persisted history (days), notifications ("CPU above 90% for 5 minutes", "low
disk space"), per-app network and disk activity, Wi-Fi network name, a battery history graph,
separate menu bar items per readout, and a graph style for the menu bar readout.

## Develop

```sh
scripts/test.sh Gauge         # unit tests
scripts/run.sh Gauge          # build a debug .app and open it
scripts/check.sh Gauge --perf # the full gate: tests, release bundle, smoke test, performance
```

Logic lives in `Sources/GaugeCore` (tested): readings (`Readings.swift`), the maths
(`CPUMath`, `MemoryMath`, `NetworkMath`), history (`TimeSeries`), formatting (`Format`), the
menu bar text and when to redraw it (`MenuBarText`), processes (`Processes`), and the engine
and session that tie them together. Every system read is behind a protocol in `Sources.swift`;
the real ones are in `System/`, and `Demo.swift` has made-up ones for screenshots. Views and
wiring live in `Sources/Gauge`.

Test hooks (environment variables), so tests never touch your settings or show your processes:

| Variable | Effect |
|---|---|
| `GAUGE_DEMO=1` | Made-up readings with an hour of history (screenshots) |
| `GAUGE_DEFAULTS_SUITE=<name>` | Settings in that suite; `GAUGE_RESET=1` starts from defaults |
| `GAUGE_READOUTS=cpu,gpu,network`, `GAUGE_INTERVAL=1`, `GAUGE_UNITS=bits`, `GAUGE_SPAN=hour` | Start with these settings without saving them |
| `GAUGE_SHOW=panel[:memory]`, `settings`, `about` | Open that after launch |
| `GAUGE_NO_OPEN=1` | "Open Activity Monitor" shows a HUD instead |
| `GAUGE_SNAPSHOT_DIR=<dir>` | Render the panel, Settings and the menu bar offscreen to PNGs (demo data), then quit |
| `GAUGE_PROBE=<file>` | Measure a tick, a panel tick and a status item redraw, write JSON, quit |
| `GAUGE_LOG_RENDERS=1` | Log every menu bar redraw to stderr |

Design follows [`docs/design-system.md`](../../docs/design-system.md). Shared pieces
(Settings, About, FloatingPanel, HUD, shortcuts) come from SlopKit.
