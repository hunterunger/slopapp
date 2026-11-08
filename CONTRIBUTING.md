# Contributing

Thanks for helping. There are a few easy ways in.

## Report a problem or suggest something

- **In any app:** Report a Problem… (in its menu, or Help in apps with windows) opens a form
  with the app, version and macOS already filled in. Nothing is sent until you submit it.
- **On GitHub:** [new issue](https://github.com/hunterunger/slopapp/issues/new/choose): report a
  problem, suggest an improvement, or suggest a new app.
- **Security problems:** privately, see [SECURITY.md](SECURITY.md).

Please leave personal things out of issues: no clipboard contents, private file names or
screenshots of your whole screen.

## Code

Every app is a Swift package under `apps/`, built with SwiftPM and `scripts/` (no Xcode
project). Needs macOS 14+ and Xcode 16+.

```sh
scripts/run.sh Clips        # build and open an app
scripts/test.sh Clips       # its tests
scripts/check.sh Clips      # everything CI checks: lint, tests, bundle, smoke test
```

Before a pull request, read [`AGENTS.md`](AGENTS.md) (conventions) and
[`docs/design-system.md`](docs/design-system.md) (how the apps look and behave), and run
`scripts/check.sh` for the apps you changed. Small, focused pull requests are easiest to review.
New apps start from research: see [`docs/dev-cycle.md`](docs/dev-cycle.md).

By contributing you agree that your work is released under the [MIT license](LICENSE).
