# Architecture

HeatWatch is a Swift Package with one executable and a small C hardware target.
It uses AppKit, SwiftUI, Charts, Foundation, IOKit, and system process interfaces.
There are no downloaded runtime packages or services.

## Data flow

1. `Monitor` in `Sources/HeatWatch/App.swift` schedules a sample every five seconds.
2. `SamplingWorker` serializes access to `Sampler` in `Sampling.swift` through an actor.
3. `Sources/Hardware/Hardware.c` reads SMC sensors, graphics counters, charging
   state, process CPU counters, and executable paths.
4. `Sampler` filters invalid temperatures, groups helpers with owning apps,
   computes interval/rolling CPU activity, and builds a `Snapshot`.
5. `Dashboard.swift` renders the snapshot and a memory-only temperature history.
   `HeatStatus.swift` supplies the menu-bar and panel status.
6. `Sharing.swift` serializes an explicit clipboard export. `--diagnose` samples
   synchronously and emits snapshots without opening the UI.

## Modules

| File | Responsibility |
| --- | --- |
| `Models.swift` | Snapshot, sensor, contributor, process, and history data. UI-only app paths are excluded from Codable fields. |
| `Sampling.swift` | Hardware handles, serial sampling, process identity cache, CPU intervals, coverage notices, and wake reset. |
| `SamplingRules.swift` | Pure CPU-time parsing, mean calculations, owning-app path extraction, and likely-contributor explanations. |
| `HeatStatus.swift` | Context bands and authoritative macOS-pressure warnings. |
| `Ranges.swift` | Sensor-specific scales and contextual range UI. |
| `Dashboard.swift`, `Explainer.swift` | Panel, graph, process lists, and hover explanations. |
| `AppActions.swift` | Normal show/hide/Quit actions for unambiguous user apps. No raw helper termination. |
| `App.swift` | App lifecycle, menu item, sampling timer, and clipboard orchestration. |

## Measurement rules

CPU temperature is the average of available curated CPU sensors. The hottest
core is a separate reading. Valid temperature samples must be finite and in
`10..<150` °C. Missing readings are optional, not zero. Idle GPU placeholders
are discarded. M4 has curated core identities; other chips have a limited
fallback and must not be presented as fully supported.

CPU percentages use one full core as 100%. A native process counter is preferred;
a bounded, numeric-only `/bin/ps` fallback covers processes denied by the native
interface. Executable paths come from the kernel, not mutable process titles.
Process identities include birth information to avoid ordinary PID-reuse errors.
Path lookup results are cached only for processes seen in the current sample.

The rolling average uses up to six intervals, normally about 30 seconds. Missing
process samples, wake, or long delays clear old interval evidence. Explanations
wait for about 15 seconds. Sustained CPU activity suggests a likely contributor;
it cannot attribute GPU work to an app or identify a browser tab.

`HeatStatus` uses the CPU average for OK/Warm/Hot context. Apple's elevated heat
pressure overrides that context with Warning/Critical, even if a CPU sensor is
missing. Unknown pressure does not become OK. The scales share the same CPU
threshold constants as the status model.

## Safety and storage

SMC commands are read-only. No fan-control command or elevated helper exists.
Monitoring does not write snapshots to disk. Temperature history stays in memory
for up to ten minutes and resets on wake or quit. The clipboard and diagnostic
stdout are explicit export paths; review their app/process names before sharing.

App actions require a single owning installation path and a live regular app.
Quit asks for confirmation with Cancel as default, then uses the ordinary macOS
termination request. It never kills helper processes or forces a monitored app
closed. See [security and privacy](../SECURITY.md).
