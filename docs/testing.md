# Testing

## Automated checks

```sh
sh scripts/check.sh
```

The same command runs locally and in GitHub Actions on macOS 15 (Intel) and
macOS 26 (Apple silicon). The macOS 14 deployment target still needs manual
compatibility checks; GitHub no longer provides a macOS 14 runner.
It needs Swift 6 or later, Python 3, and Apple's developer tools. No downloaded
test framework or Python packages are needed.

| Check | Coverage |
| --- | --- |
| `sh scripts/test.sh` | Real production status/model/sampling-rule/export sources compiled directly with Swift 6, complete concurrency checking, and warnings as errors. |
| `sh build.sh` | Full release app, C warnings as errors, Swift warnings as errors, complete concurrency checks, bundle metadata, and ad-hoc signature verification. |
| Live diagnostic validator | Two JSON snapshots, valid optional temperature/counter ranges, unavailable notices, and exclusion of UI-only paths. |
| `git diff --check` | Patch whitespace errors. |

Deterministic suites cover temperature thresholds, authoritative pressure
warnings with missing sensors, invalid readings, numeric CPU-time parsing,
empty averages, helper grouping, warm-up/coverage explanations, and JSON
schema/privacy behavior. Inputs are synthetic and contain no real user data.

Tests compile selected production files directly because Command Line Tools
installations may lack XCTest and SwiftUI macro plugins. Assertions use
`precondition`, not debug-only `assert`. A failed check exits nonzero.

Live diagnostics accept absent hardware. A hosted Mac may expose no SMC
readings, no battery, or restricted process access. Passing CI verifies the
failure contract and build, not that every sensor works on every Mac. Raw
diagnostics are not logged or uploaded as CI artifacts.

## Manual UI and hardware checks

On a real Mac, build and open `.build/HeatWatch.app`:

- Check the menu temperature, context label, and panel guidance agree.
- Wait at least 15 seconds and compare likely contributors with Activity Monitor.
  100% is one CPU core; compare the same sampling interval.
- Check graph updates, CPU/GPU/battery/fan unavailable states where observable,
  scroll behavior, and stale-reading indicator.
- Sleep/wake. Confirm old history and activity evidence clear before new sampling.
- Copy JSON, inspect it locally, and verify it contains no executable paths.
- Check light/dark appearance and VoiceOver status text. Status must not rely
  on color alone.
- With a disposable app and no unsaved work, verify show/hide and normal Quit.
  Cancel must be default. Never test this on someone else's work.

Do not deliberately overheat hardware to test Warning/Critical. Those branches
are covered with deterministic inputs. There is no need for root, fan changes,
or synthetic stress tests.

## Longer diagnostics

```sh
.build/HeatWatch.app/Contents/MacOS/HeatWatch --diagnose --samples 4
```

The first snapshot establishes the process baseline. Later snapshots contain
interval CPU usage. Sampling is normally every five seconds; `--samples` is
clamped to 1–120. Output includes app/process names and PIDs. Review it before
publishing it and do not attach raw output to public issues.
