# Terrastep v0.3.3 — core milestone scope

- Live walking map, one location dot, steps, distance, cadence, recording controls.
- GPX history, XML inspection/copy, Downloads export and Android share.
- User: editable local name and completed walking distance in km only.
- **No hex functionality, demo generator, or User route drawing.**

Full project history, problems/solutions, architecture, function reference, build
instructions and testing limitations: [Implementation document](../docs/TERRASTEP_IMPLEMENTATION.md).

## APK

`terrastep-milestone30-arm64.apk` is produced by GitHub Actions for ARM64 Android
(API 26+), with the configured Mapbox Actions secret injected at build time.
Verify from repository root: `sha256sum -c releases/SHA256SUMS`.
It is a release-mode **evaluation APK signed with a debug key**, not a production
Play Store build. Android may require reinstalling if a runner's signing key
changes. Export important GPX files before uninstalling: app-local data is removed.

The publication bot updates the APK after successful checks/build/tests. Until
that run completes, a pre-existing APK can still be the previous version; verify
the release commit/run before distributing it.

Physical GPS, sensor batching, background battery limits and OS share/export
behaviour must be checked on the target phone; CI does not emulate a real walk.
