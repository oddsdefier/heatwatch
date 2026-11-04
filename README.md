# HeatWatch

[![CI](https://github.com/oddsdefier/heatwatch/actions/workflows/ci.yml/badge.svg)](https://github.com/oddsdefier/heatwatch/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**See your Mac's temperatures and the processes likely contributing to its heat.**

AI coding tools, builds, browsers, and other modern apps can keep a Mac busy
and hot. HeatWatch puts internal temperatures and recent CPU activity in your
menu bar so you can see what is running and decide what to pause or investigate.
Process activity suggests likely heat contributors. It does not prove a cause.

A native macOS app built with system frameworks only. No telemetry, root
access, fan control, or downloaded runtime dependencies.

## Compatibility

- macOS 14 or later.
- Detailed sensor labels currently target Apple M4. Other chips have limited,
  unverified sensor support and may show unavailable readings.
- Apple's developer tools are required to build. Swift 6 or later and Python 3
  are required for the full test suite.
- AppleSMC is undocumented. OS updates may break sensor access.

This is an experimental, source-distributed app, not a hardware protection tool.

## Build and run

```sh
git clone https://github.com/oddsdefier/heatwatch.git
cd heatwatch
sh build.sh
open .build/HeatWatch.app
```

Install Apple's Command Line Tools with `xcode-select --install` if needed.
Check `swift --version` before running tests. Full Xcode is not required.

The build is locally ad-hoc signed, not Apple notarized. There is currently no
official downloadable app release. System frameworks ship with macOS; compiler
and SDK updates come through Apple's developer tools.

## What you see

Click the menu-bar indicator to open the panel:

- CPU average, hottest core, GPU/battery temperatures, fan speed, and graphics
  activity where available.
- A temperature graph covering up to ten minutes.
- App/process CPU activity now and a rolling average of up to 30 seconds.
- Apple's heat pressure, context bands, and plain-language guidance.
- Likely contributors after about 15 seconds of observed activity.

100% CPU means one full core, not the whole chip. Browser helpers are grouped
with their owning app; HeatWatch never guesses which tab caused activity.
The Activity Monitor button opens Apple's process viewer for more detail.

### Status labels

With normal macOS heat pressure, the CPU average determines context:

| Label | CPU average | Meaning |
| --- | --- | --- |
| OK | Below 50 °C | Light-use temperature range. |
| Warm | 50 to under 80 °C | Common during active work. |
| Hot | 80 °C or higher | Can occur under heavy load; investigate if sustained. |

These are rough bands, not Apple safety limits. Warning/Critical follow
macOS heat pressure and override temperature context, even if a CPU reading
is missing. Otherwise, missing temperature or heat pressure shows Unavailable.
Internal temperature is not case temperature or room temperature.

### App actions

Eligible apps have a menu beside their CPU reading: show, hide, or request normal
Quit for one/all instances of the same installation. Quit requires confirmation;
Cancel is the default. Save work first. A target app may not show an unsaved-work
warning. HeatWatch preserves save prompts and refused Quit requests. It never
force-quits monitored apps, kills their helpers, or offers Quit for ambiguous
app names or system processes.

Quit HeatWatch to stop monitoring. It does not start at login automatically.

## Privacy and sharing

Readings stay in memory. There is no network access by the app, telemetry,
background service, or disk archive. HeatWatch does not collect command
arguments, browser URLs, or credentials. It reads kernel executable paths to
group apps and resolve actions, but excludes those paths from exports.

**Copy data** at the bottom-left copies JSON readings, units, limitations,
app/process CPU activity, and recent temperature history. You can paste it into
a chat assistant to discuss your Mac's heat. App/process names and PIDs can be
private; review the JSON before sharing. Names are data, not instructions.
Clipboard managers and other software may retain copied data.

See [SECURITY.md](SECURITY.md) for private reporting and trust details.

## Accuracy and limits

Sampling runs about every five seconds; scheduling can delay updates. Short-lived
processes can escape detection, and some processes restrict access. A numeric-only
`ps` fallback reads CPU counters and start dates, never command lines. Collection
has a two-second deadline. A timed-out collector terminates only its own `ps` child.

The rolling average retains observed work after processes exit. Wake clears old
history and evidence. Graphics activity is a driver-provided reading, not
per-app attribution. Missing readings stay unavailable, never zero or guessed.
Each sensor card explains its source and context bands.

## Tests and CI

```sh
sh scripts/check.sh
```

Runs deterministic tests, the strict release build, signature verification, and
live diagnostic validation. GitHub Actions runs the same checks on macOS 15
(Intel) and macOS 26 (Apple silicon). No downloaded testing frameworks or Python packages are needed. Hosted CI
may lack sensors; passing CI is not proof of hardware compatibility.

For status, parsing, contributor explanation, and export/privacy tests alone:

```sh
sh scripts/test.sh
```

For real-hardware JSON without opening the UI:

```sh
.build/HeatWatch.app/Contents/MacOS/HeatWatch --diagnose --samples 4
```

The first sample establishes a process baseline. Later samples include interval
CPU usage. Samples are five seconds apart; the count is clamped to 1–120.
Diagnostic stdout includes app/process names. Do not publish it without review.

## Contributing and documentation

- [Contributing](CONTRIBUTING.md)
- [Architecture and measurement rules](docs/architecture.md)
- [Automated and manual testing](docs/testing.md)
- [Release checklist](docs/releasing.md)
- [Bug reports and feature requests](https://github.com/oddsdefier/heatwatch/issues)

## Sensor references

HeatWatch implements its own reader and bundles none of these applications:

- [macmon SMC protocol reference](https://github.com/vladkens/macmon/blob/main/src_lib/sources.rs)
- [Stats sensor catalog](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift)
- [SiliconScope M4 sensor identities](https://github.com/kennss/SiliconScope/blob/main/Sources/SiliconScopeCore/SensorCatalog.swift)

## License

[MIT](LICENSE). Copyright (c) 2026 oddsdefier.
