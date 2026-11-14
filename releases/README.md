# Terrastep 30% milestone APK

`terrastep-milestone30-arm64.apk` is built by GitHub Actions for ARM64 Android
phones (Android 8.0 / API 26 or newer). Verify it with `sha256sum -c releases/SHA256SUMS`.
The release-mode APK uses the development debug signing key; it is for evaluation,
not Play Store distribution. CI rebuilds and publishes it on this working branch.

## Revised blueprint

- Mapbox token injected at build time from the `MAPBOX_ACCESS_TOKEN` Actions secret.
  Configure that repository secret before rebuilding; GitHub blocked the supplied
  token in source. The checked-in APK still represents the previous successful build.
- Dark map-first UI with GPS accuracy, hardware steps, distance, moving time and cadence.
- Outdoors, Dark, Satellite Streets and Standard styles; follow and 3D pitch controls.
- Local GPX history, raw XML inspection/copy, Downloads export and Android sharing.
- Diagnostics for the three milestone requirements. No cloud backend or authentication.

Mapbox is pinned to **2.8.0**, within the blueprint's `^2.3.0` range, because exact
2.3.0 required a private SDK download token in CI. Flutter 3.27.4, Java 17 and the
verified Gradle configuration are retained. For local builds, the public token can be supplied
with `--dart-define=MAPBOX_ACCESS_TOKEN=pk.xxx`.

## Validation on a physical phone

1. Install the APK; allow location, physical activity and notification permissions.
2. Confirm map tiles load, switch all four styles, toggle follow and 3D pitch.
3. Start walking outdoors. Check steps and route update; pause/resume and test screen-off recording.
4. Finish; open GPX & History and refresh. Inspect XML, share it and export to Downloads.
5. Generate the clearly labelled Abbottabad demo fixture and inspect its GPX.
6. Refresh 30% Check to inspect sensor availability and latest GPS fix.

CI analysis/build success does not verify token validity, GPS quality or sensor
behaviour on a physical phone. The hex overlay uses the blueprint's local Kotlin
hex approximation, not canonical globally indexed H3 cells.
