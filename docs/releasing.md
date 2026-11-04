# Releasing

The repository currently distributes source. There is no automatic notarized
binary release workflow. `sh build.sh` creates a local ad-hoc signed app.
That is not an Apple Developer ID signature, and Gatekeeper may block a
separately downloaded build. Do not tell users to disable Gatekeeper.

Before tagging a release:

1. Update the version/build in `Resources/Info.plist` and producer version in
   `Sources/HeatWatch/Sharing.swift` together.
2. Run `sh scripts/check.sh` and the manual checks in [testing](testing.md).
3. Confirm GitHub CI passes for the exact commit. Verify M4 sensor behavior on
   real hardware; CI cannot prove sensor compatibility.
4. Review the diff and release text for private process data, credentials,
   machine-specific paths, and claims of proven heat causation.
5. With maintainer approval, tag the tested commit and create a GitHub release
   describing compatibility limits, changes, and known issues.

A future downloadable app release should use Developer ID signing, hardened
runtime, notarization, and stapling before distribution. Credentials belong in
protected repository secrets, never in source or build logs. Signing and
notarization are not set up by this repository's CI.
