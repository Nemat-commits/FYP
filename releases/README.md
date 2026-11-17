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

## GPS / User update (0.3.1)

- Location startup waits for runtime permission and retries when the app resumes.
- Fused location updates are backed by device GPS/network updates; stale fixes and
  duplicate timestamps are rejected. Recording retains the 25m accuracy gate,
  walking-speed gate and jitter filter. Distance below 1km is displayed in metres.
- The live map includes an explicit blue position marker and no longer follows
  placeholder coordinates as if they were a real fix. GPS waiting/disabled/weak
  states replace the misleading GPS Ready label.
- User replaces 30% Check: locally editable name plus saved-path overview and
  total recorded distance. Demo walks do not contribute. Open the tab again or
  pull to refresh after saving a walk. Unfinished walks are not counted.
- CI includes profile widget tests and native GPS acceptance-policy unit tests.

On a phone: allow precise location and physical activity, turn device location
on, test outdoors, and wait for GPS accuracy <=25m before expecting route distance.
Confirm the blue marker follows you, walk 50–100m, pause/resume, finish and inspect
both GPX history and User. Deny permission and disable location in separate tests
and confirm a truthful message rather than a fake position. CI cannot validate
physical GPS reception or phone power-management behaviour.

## Stationary drift correction (0.3.2)

The previous walking-speed/jitter gates could count plausible GPS wander as
walking. A screenshot showed 142m with zero steps while seated. Recording now:

- Uses one location feed at a time: fused first; device GPS replaces it only after
  failure or 12 seconds without fresh fixes. It no longer interleaves three feeds.
- Requires NEW hardware steps before adding GPS distance on pedometer-equipped
  phones. Steps only corroborate GPS displacement; they never generate distance.
- Rejects displacement below an accuracy-aware noise floor or implausible for
  the observed step count. Re-anchors across stationary periods and large jumps.
- Uses conservative reliable-speed and uncertainty gates without step hardware.
- Displays only the native-fed blue location dot, removing the duplicate puck.

Regression checks cover 47 seconds of seated drift, stopping after walking,
GPS jumps despite steps, weak accuracy and the sensorless fallback. On-device
verification still required: sit still 2 minutes (distance stays 0), walk outdoors,
stop again, then pause/resume. With delayed step-counter batches the first few
metres may appear late or be conservatively omitted. Previously saved false
sessions are not silently modified or deleted by this update.
