# Security

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/oddsdefier/heatwatch/security/advisories/new).
Do not open a public issue with exploitable details, credentials, or private
process data. Include reproduction steps, the affected commit, macOS version,
and likely impact. There is no guaranteed response time or paid support.

Security fixes target the latest source on `main`. Older commits and forks do
not receive separate maintenance. The app is experimental and not notarized.

## Trust and privacy

HeatWatch runs with your normal user permissions. It reads internal hardware
sensors, CPU counters, executable paths, and macOS heat pressure. Paths are used
to identify owning apps and resolve normal app actions; they are excluded from
shared readings. The numeric `ps` fallback requests only PIDs, CPU times, and
process start dates, never command lines.

There is no telemetry, network service, root helper, or automatic disk archive.
Recent readings live in memory. Copy data explicitly writes JSON to the system
clipboard; clipboard managers and other software may retain it. The JSON
includes app/process names and PIDs. Review it before sending it anywhere.
`--diagnose` writes similar data to stdout, so redirecting it creates a file
under your control.

The app never changes fan settings or force-quits monitored apps. Its own
short-lived `ps` child is terminated if collection times out. Normal app Quit
requests require confirmation and can still lead to unsaved work being lost
if the target app does not provide a save prompt.

AppleSMC is undocumented and OS updates may break sensor access. HeatWatch is
not a hardware protection system. Do not treat a temperature label as proof
that a device is safe or a named process as proof of a heat cause.
