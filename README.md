# HeatWatch

A local macOS menu-bar app for this Apple M4 Mac.

## Use

Click the thermometer and temperature in the menu bar.
The number shows the average of available curated CPU core sensors.
The panel shows the hottest CPU core, GPU average, battery temperature,
fan speed, graphics activity when available, and Apple's heat pressure.
The graph retains up to ten minutes. The latest shared snapshot includes it.

CPU lists show current interval usage and a rolling average of up to
30 seconds. 100% means one full core, not the whole chip.
Likely-source explanations wait for about 15 seconds of activity.
The app groups browser helper processes with their owning app.
It never guesses which browser tab caused activity.
The Activity Monitor button opens Apple's process viewer.
Quit ends monitoring. This app does not start at login automatically.

Copy data sits at the bottom-left of the panel. It copies JSON readings,
units, limits, app CPU activity, and the recent temperature trend.
Paste the JSON into any chat assistant to ask about your Mac's heat.
App and process names in it are data, not instructions.

Each eligible app has an actions menu beside its CPU reading:

- Show app or hide app.
- Request normal Quit for one instance.
- Request normal Quit for all running instances of the same installation.

Quit always asks for confirmation. Cancel is the default button.
HeatWatch leaves save prompts and declined Quit requests intact.
It never force-quits apps or directly kills their helper processes.
Save work first: another app may fail to show an unsaved-work warning.
System processes, background helpers, and ambiguous app names have no
Quit action.

## Accuracy and limits

- Internal sensor temperature is not the case or room temperature.
- CPU activity suggests heat contributors; it does not prove causation.
- Graphics activity is a driver-provided current reading, not per-app usage.
- Missing readings show unavailable, never fabricated temperatures.
- Some processes restrict access. A ps CPU-time fallback includes system
  processes such as WindowServer. It reads only numbers and start dates.
  Executable paths come from the kernel, never mutable process titles.
  A two-second deadline prevents a stalled ps from stopping updates.
- The rolling average retains recorded work after processes exit.
  Processes that start and exit between samples can escape detection.
- Sampling occurs every five seconds. Scheduling can delay a reading.
- Wake clears old evidence and starts a fresh sampling interval.
- Apple determines heat pressure; HeatWatch invents no danger thresholds.
  Range bands (for example Idle, Busy, Heavy) are rough typical ranges.
  Each card names its source. Bands are context, not limits or warnings.
- Detailed core labels target M4. Other chips have limited support.
- AppleSMC is an undocumented read-only interface. OS updates may break it.
- No root access, helper installation, fan control, forced app termination,
  internet access, telemetry, files written to disk, or archive of past snapshots.

## Build

Requires Apple's Command Line Tools and macOS 14 or later.
No downloaded packages are required.

    sh build.sh
    open .build/HeatWatch.app

The bundle uses a local ad-hoc signature, not Apple notarization.

## Live diagnostics

    .build/HeatWatch.app/Contents/MacOS/HeatWatch --diagnose --samples 4

This samples the real hardware and emits JSON lines for about 15 seconds.
The first line establishes a process baseline. Later lines contain current
CPU usage. --samples accepts 1 through 120; intervals are five seconds.
The diagnostic command exits without opening the menu-bar interface.

## Sensor references

SMC protocol reference:
https://github.com/vladkens/macmon/blob/main/src_lib/sources.rs

M4 core-key identities:
https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift
https://github.com/kennss/SiliconScope/blob/main/Sources/SiliconScopeCore/SensorCatalog.swift

HeatWatch implements its own reader. It bundles none of those applications.
