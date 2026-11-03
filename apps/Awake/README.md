# Awake

Keep your Mac awake, from the menu bar.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Lungo and Amphetamine.

**Status:** alpha. This is also the reference app for the Slopapp pipeline: copy its
patterns when building a new app.

## What it does

- Click the cup in the menu bar, pick a duration: 15 minutes, 1, 2 or 4 hours, or until
  turned off. The cup fills in while Awake is on.
- **Keep Display On** (default) stops the screen from sleeping too. Turn it off to let the
  display sleep while the Mac itself stays awake (good for downloads and builds).
- Shows the time left and survives sleep/wake (re-checks the clock on wake).
- Settings (⌘, from the menu): launch at login, hide the menu bar icon (open Awake again to bring it back).

Under the hood it holds an `IOPMAssertion`, the same mechanism `caffeinate` uses. Check it
with `pmset -g assertions` (look for "Awake is keeping this Mac awake").

## Develop

```sh
scripts/test.sh Awake        # unit tests (AwakeCore)
scripts/run.sh Awake         # build a debug .app and open it
scripts/check.sh Awake       # tests, release bundle, launch smoke test
```

Start a session at launch, for testing or scripting:

```sh
AWAKE_ACTIVATE=15m build/Awake.app/Contents/MacOS/Awake   # also 90s, 2h, forever
```

## Layout

| Path | What |
|---|---|
| `Sources/AwakeCore/AwakeController.swift` | All state: session, expiry, display option |
| `Sources/AwakeCore/PowerAssertion.swift` | `PowerAssertion` protocol + the real IOKit implementation |
| `Sources/AwakeCore/Scheduler.swift` | `Scheduler` protocol + Timer implementation |
| `Sources/AwakeCore/AwakeDuration.swift`, `RemainingTime.swift` | Durations, parsing, text |
| `Sources/Awake/AwakeApp.swift` | Menu bar UI and wiring |
| `Tests/AwakeCoreTests/` | Tests with a fake assertion and a manual clock |
