# Contributing

HeatWatch helps people see their Mac's temperatures and likely heat contributors.
Bug reports, documentation fixes, and hardware compatibility reports are welcome.

## Development

You need macOS 14 or later and Apple's developer tools. Swift 6 or later is
required for the test runner. Install Command Line Tools with `xcode-select --install`
if needed, then check `swift --version`. No third-party packages are required.

```sh
git clone https://github.com/oddsdefier/heatwatch.git
cd heatwatch
sh scripts/check.sh
open .build/HeatWatch.app
```

`check.sh` runs deterministic tests, a strict release build, ad-hoc bundle
signing/verification, and two live diagnostic samples. Diagnostics are kept in
a temporary file and removed on exit. Missing sensors on CI or unsupported
hardware are expected; fabricated readings and malformed snapshots are not.
Python 3 is required for the diagnostic validator, but there are no pip packages.

For a quicker loop, run `sh scripts/test.sh` or `sh build.sh` separately.
See [the architecture](docs/architecture.md) and [testing guide](docs/testing.md).

## Changes we can accept

- Use native macOS system frameworks. Discuss any dependency proposal first.
- Keep hardware access read-only. Never request root or change fan settings.
- Missing temperatures stay unavailable, never zero or guessed values.
- Use Apple's heat pressure for warnings. Temperature bands are context only.
- Describe processes as likely contributors, never proven heat causes.
- Do not collect command arguments, browser URLs, or credentials.
- Do not add telemetry, a background server, or disk archives of readings.
- App Quit actions must remain normal, confirmed, and cancellable. No force quit.
- Add tests for changed calculations and privacy behavior. Update relevant docs.

## Reporting bugs

Use the bug report template. Include your chip, macOS version, commit/version,
and reproduction steps. Detailed sensor mapping currently targets M4; reports
from other Macs help establish compatibility, not a promise of support.

Screenshots and copied JSON can reveal the apps you use. Review and redact
that information before publishing it. Never attach credentials or unreviewed
process logs. Use [private reporting](SECURITY.md) for vulnerabilities.

## Pull requests

Keep each pull request focused. Explain the problem, the change, and the checks
run. Sensor changes should name the source used for sensor identities and
include real-hardware results, including unavailable cases. Do not run synthetic
load or request elevated privileges just to validate a contribution.

Contributions are accepted under the repository's [MIT license](LICENSE).
Please be respectful, discuss the code rather than the person, and do not post
another person's private data.
