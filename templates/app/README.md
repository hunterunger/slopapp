# __NAME__

__TAGLINE__

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to __REPLACES__.

**Status:** alpha (scaffolded, not built out yet)

## Spec

__SPEC__

## Develop

```sh
scripts/test.sh __NAME__     # unit tests
scripts/run.sh __NAME__      # build a debug .app and open it
scripts/check.sh __NAME__    # the full gate: tests, release bundle, launch smoke test
```

Logic lives in `Sources/__NAME__Core` (tested). Views and wiring live in `Sources/__NAME__`.

Design follows [`docs/design-system.md`](../../docs/design-system.md). Shared pieces
(Settings, About, DropZone, FloatingPanel, HUD, PermissionGate, shortcuts) come from SlopKit.
