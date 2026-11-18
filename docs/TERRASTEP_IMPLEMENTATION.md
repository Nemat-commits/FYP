# Terrastep — implementation, problems solved and code explanation

## 1. Final scope: v0.3.3 (build 33)

This is a local Android walking recorder built with Flutter and Kotlin. The current scope is deliberately small:

- **Start & Map:** Mapbox map, one blue current-location dot, GPS status/accuracy, live walking route, map-style/follow/pitch controls, steps, distance, cadence and an unpaused recording timer. Start, pause, resume and finish a walk.
- **GPX & History:** saved walks, raw GPX XML inspection/copy, Downloads export and OS sharing.
- **User:** an editable locally saved name and **Path covered**, displayed as completed-walk distance in kilometres. No route drawing here.

### Removed in this revision

1. Hex overlay sources/layers, cell count, cell calculation engine, live polygon payloads and hex GPX extensions.
2. Generate Demo Walk button, Flutter bridge method and native demo-data generator.
3. Route-point loading and custom route painter from User.
4. Unused earlier models/providers and the unused diagnostics screen that retained obsolete functionality.

The live route on **Start & Map** remains: the user requested removal of path drawings from **User**, not from the live walking map. There is no login, marketplace, backend, cloud sync or extra profile information.

### Existing data compatibility

The Room database remains version 1. Its old `visitedHexIdsJson` and `hexCellId` columns are inert compatibility fields: new sessions write `[]`, and new points write an empty string. They are not calculated, sent to Flutter, rendered, or exported. Keeping the columns avoids destructive migration and preserves installed users' walks. Restore/reimplement the feature later from Git history if required; there is no hidden hex toggle.

Previously generated demo sessions are excluded from the history response and User totals by their old `Abbottabad Pilot Trail` title prefix. Their database rows/files are not deleted. Previously saved inaccurate distances are also not silently rewritten. Old GPX files may still contain the extensions written by old app versions; newly generated files do not contain hex extensions.

## 2. What we built, in order

1. Started from a minimal repository and implemented the first milestone blueprint: Flutter UI, native bridge, foreground service, sensors, Room and GPX export.
2. Added the Android build files, Gradle wrapper, resources, permissions and CI workflow required to produce an installable APK.
3. Applied a revised blueprint with dark Material 3 styling, a map-first recorder, history/XML inspection and automatic Mapbox configuration.
4. On-device feedback showed steps increasing but no recorded GPS distance or visible position. Added permission-aware location initialization, GPS preview and a physical-device fallback.
5. Replaced the visible diagnostics tab with User and local name storage.
6. Further on-device feedback showed **142m while sitting with zero steps**. Corrected distance acceptance using hardware-step corroboration, an accuracy-aware noise floor and one delivered location feed at a time. Removed duplicate location dots.
7. Reduced the scope in this release: removed hex functionality, demo generation and the User path drawing; retained the core walking/GPX workflow and kilometre total.

Prior merged milestones included PR #2 (initial/revised app) and PR #3 (GPS and profile updates). This revision is developed on the current Arena branch and merged to main only after its CI succeeds.

## 3. Problems encountered and solutions

| Problem / observation | What was established | Solution |
| --- | --- | --- |
| No local Flutter/Android toolchain in the original sandbox | Local APK compilation was unavailable | Use GitHub Actions with pinned Flutter, Java and Android build configuration. |
| Build stopped before compilation | Gradle wrapper and launcher resources were missing | Add executable Gradle wrapper, wrapper JAR/properties and Android icons/resources. |
| Gradle rejected project repositories | Settings forbade repositories declared by the project | Remove the contradictory settings policy and use the verified repository configuration. |
| Flutter plugins were not loaded correctly | Android settings lacked the standard Flutter plugin loader | Add the loader and pin Android/Kotlin plugin versions. |
| Mapbox method compilation errors | Some blueprint API calls did not match the SDK | Use `map.style.addSource/addLayer`, `setStyleSourceProperty`, `loadStyleURI` and `MapWidget(styleUri: ...)`. |
| Theme resource linking failure | Framework theme name was treated as an application resource | Use `@android:style/Theme.Light.NoTitleBar`. |
| Unresolved GPX writer | Broad `gpx/` ignore rule excluded the Kotlin source directory | Anchor the generated-data ignore rule at `/gpx/` and track the writer source. |
| Dependency drift / assembly incompatibility | Caret resolution selected a much newer Mapbox version; exact 2.3.0 required an SDK download token | Pin Mapbox 2.8.0 and the Android plugin versions that successfully built. |
| GitHub rejected the supplied Mapbox token in source | Push protection flagged it | Remove the token from source and inject the `MAPBOX_ACCESS_TOKEN` Actions secret at build time. Do not bypass scanning. |
| Full CI logs/artifacts could not be downloaded in the earlier sandbox | Downloads redirected to unavailable hosts | Emit accessible check-run annotations and retrieve the bot-published APK through Git. |
| Workspace tools returned GitHub 403 | The user had restricted Arena access to another repository | Restore the repository's GitHub installation access. This was not an application-code error. |
| Map visible, steps working, but 0km and no obvious current position | Map tiles are independent of recording GPS; permission initialization could race, and subscription failures were not surfaced | Await runtime permission, retry on resume, expose actual fix status, add native position preview/fallback and a blue location layer. Root cause on the phone was not proven by logs. |
| Two blue dots | Mapbox puck and native-fed explicit marker both rendered | Disable Mapbox's independent puck and display just the native-fed dot. |
| 142m while seated | A plausible-speed GPS displacement is not necessarily walking; multiple feeds could disagree | Deliver one feed at a time, require new steps on sensor-equipped devices, reject noise/jumps and reset anchors across stationary gaps. |
| Too much milestone functionality | Hexes, synthetic walk generation and User route drawings were out of current scope | Remove the active feature code instead of just hiding buttons; retain only inert schema fields for data compatibility. |

A build passing is evidence of compilation and automated checks, not proof that every phone's GPS, battery policy or permissions behave identically.

## 4. Architecture and data flow

```text
Flutter screens
  | commands: MethodChannel com.terrastep.fyp/methods
  v
MainActivity -> WalkRecorderService -> StepCounterManager
                    |                LocationTrackerManager
                    |                GpsFixPolicy
                    v
                 Room SQLite -> GpxFileWriter -> app files / Downloads / share
                    |
                    +-- EventChannel com.terrastep.fyp/telemetry --> live map HUD
```

Flutter owns presentation, permission requests and the local profile name. Kotlin owns sensor callbacks, GPS acceptance, session state, recorded points and GPX generation. No server is required for stored walk history. Map tiles/styles require Mapbox connectivity and a valid configured token.

### Recording lifecycle

- **IDLE:** map preview may show a real current fix but does not add walking distance.
- **RECORDING:** sensors are active; accepted GPS points produce distance and route segments.
- **PAUSED:** steps/distance recording stops; preview can continue. Resume starts a separate route segment.
- **Finish:** stops the recording inputs/ticker, writes a completed session and GPX, then the visible app restarts location preview.

Room stores checkpoints and recorded points. It is not an automatic interrupted-session recovery system: process death/reboot recovery is not implemented.

## 5. How the main features work

### 5.1 Steps and cadence

Android's `TYPE_STEP_COUNTER` reports a cumulative boot-time value. The recorder subtracts a session/segment baseline rather than displaying boot steps. Steps before a pause are retained; resume establishes a new baseline. If counter hardware is absent, `TYPE_STEP_DETECTOR` increments session steps directly.

Recent hardware step activity is tracked separately from the displayed count. A rolling window of timestamps supplies cadence. Sensor batching can delay the displayed count or the first recorded metres; GPS distance is deliberately not invented from a fixed step length.

### 5.2 Location preview, marker and follow

The live screen asks for location permission before enabling native preview. It retries after returning to the app. The native manager first subscribes to high-accuracy fused location. If the subscription fails or no fresh fix arrives for 12 seconds, device GPS replaces it. Only the selected feed delivers fixes.

A valid fresh coordinate is sent to Flutter, rendered as a GeoJSON point and blue circle. The default Abbottabad camera position is just a startup view, not a claim about the user's location. Follow updates the camera only when `hasLocationFix` is true. Preview and recording acceptance differ: a coordinate can be displayed even when its accuracy is insufficient for route distance.

### 5.3 Walking distance and stationary-drift prevention

For each recording fix:

1. Reject fixes older than 15 seconds, future fixes and non-increasing timestamps.
2. Reject poor/missing positional accuracy for recording (over 25m).
3. On step-equipped phones, require recent hardware step activity. Without it, discard the previous distance anchor so later movement cannot bridge stationary drift.
4. Compare a candidate to the accepted anchor using Android's `distanceTo` and monotonic elapsed nanoseconds.
5. Reject tiny movement and impossible walking speed (over 6.5m/s).
6. Require displacement above `max(1.8m, min(6m, accuracy * 0.5))`.
7. With step hardware, require **new steps since the anchor** and a displacement no greater than `newSteps * 1.8m + 1.2m`. This is only a plausibility gate; added distance is still the measured GPS displacement.
8. Without step hardware, require reported speed 0.8–3.5m/s, speed uncertainty <=0.5m/s and displacement beyond `max(3m, 2 * accuracy)`.
9. Reject/re-anchor large discontinuities. On acceptance, add distance, save the point and update the anchor/step baseline.

The first point establishes an anchor and adds no distance. Separate segments prevent lines across pauses/stationary gaps. These conservative rules can omit short movements or delayed first steps; seated/walking tests on the target phone remain essential.

### 5.4 Durations

Elapsed time uses Android's monotonic clock. The HUD's **Moving time** currently measures **unpaused recording time**, not independently detected physical-motion time. It can advance while sitting with the recorder running, but distance must not advance without accepted movement.

### 5.5 GPX and history

A finished walk is serialized as GPX 1.1 XML: metadata, bounds when points exist, START/FINISH waypoints, a track and segment-separated track points. Each point contains coordinates, elevation, UTC time and application extensions for steps, speed and accuracy in metres. Accuracy is not exported as HDOP: HDOP is a different dimensionless measurement.

The XML serializer escapes text; decimal formatting uses a stable locale. Serialization is synchronized to protect the shared date-format objects during concurrent exports. The inspector reads the local GPX, or regenerates a missing one from stored points. Existing files are not rewritten just to remove old extensions.

History lists saved non-demo sessions. XML can be selected/copied, the file can be shared, and Downloads export uses MediaStore on Android 10+ or a filesystem copy on older Android. Older Android storage permissions and the device's export behavior require device testing.

### 5.6 User

`user_name` in SharedPreferences stores the display name. Editing trims whitespace, ignores blank submissions and caps input length at 40 characters. User sums `totalDistanceMeters` from completed non-demo sessions and divides by 1000 for a two-decimal kilometre total. It refreshes when selected and on pull-to-refresh. It does not request individual point details, render paths or connect to a backend.

## 6. Code explanation — file and function reference

All Android paths below are under `android/app/src/main/kotlin/com/terrastep/fyp/`.

### 6.1 Flutter startup and navigation

**`lib/main.dart`**
- `main`: initialize Flutter bindings, configure Mapbox and launch the app inside ProviderScope.
- `TerrastepApp.createState` / `_TerrastepAppState.build`: construct the dark Material 3 application and home shell.

**`lib/core/app_config.dart`**
- `mapboxPublicToken`: compile-time `MAPBOX_ACCESS_TOKEN`, default empty; no credential is committed.
- `abbottabadLat`, `abbottabadLon`: startup camera defaults.
- `initializeMapbox`: pass the compile-time token to Mapbox.
- `getEffectiveMapboxToken`, `saveMapboxToken`: older preference compatibility helpers; current UI does not expose token editing and startup uses the build-time value.

**`lib/ui/home_shell.dart`**
- `createState` / `build`: manage selected tab and IndexedStack. The map/history remain mounted; User receives an `active` flag for refresh. Navigation changes only local UI state.

### 6.2 Flutter/native bridge

**`lib/services/native_tracker_bridge.dart`**
- `telemetryStream`: convert EventChannel map events into Dart maps.
- `startLocationPreview`, `stopLocationPreview`: ask Kotlin to start preview or stop it when idle.
- `getDiagnostics`: retained internal diagnostic bridge; there is no diagnostic tab.
- `startWalk`, `pauseWalk`, `resumeWalk`, `finishWalk`: invoke corresponding native lifecycle operations and decode summary maps.
- `getSavedSessions`: retrieve history rows, not route geometry.
- `getSessionDetail`: request XML/file/point details for a selected session.
- `exportToDownloads`: copy a selected session's GPX to public Downloads and return its location.
- There is no demo-generation bridge method.

### 6.3 Live map screen

**`lib/ui/screens/live_map_screen.dart`**
- `initState`: register app lifecycle observation and subscribe to native telemetry; update the HUD/map on events.
- `dispose`: unregister observer, stop idle preview and cancel the stream subscription.
- `_onMapCreated`: store the controller and initiate permission-aware location setup.
- `didChangeAppLifecycleState`: retry on resume; stop idle preview on backgrounding without stopping an active walk.
- `_enableLocation`: request permission, inspect device location availability, disable the independent Mapbox puck and start native preview; report setup problems to the UI.
- `_startWalk`: guard duplicate taps, request activity/notification permissions and invoke the native recorder, with start-error feedback.
- `_onStyleLoaded`: create only the live-route source/line layer and current-position source/circle layer, then apply the latest telemetry. No hex source or layer exists.
- `_updateMapLayersAndCamera`: build segment-separated route GeoJSON, update route/current-position sources and animate the camera when follow is enabled and a fresh fix exists. One-point segments are not rendered as LineStrings.
- `_formatDuration`: convert milliseconds to MM:SS for the HUD.
- `_cycleStyle`: cycle Outdoors, Dark, Satellite Streets and Standard, then load that style.
- `build`: construct the map, GPS message, follow/pitch/style buttons, metrics and recorder buttons. Inline callbacks pause/resume or finish/save and restart preview.
- `_MetricTile.build`: render a metric icon, value and label; it contains no sensor calculations.

### 6.4 History and User screens

**`lib/ui/screens/gpx_history_screen.dart`**
- `initState`: load history.
- `_refresh`: request saved sessions and replace the displayed list.
- `_inspectGpx`: obtain detail and open a draggable, selectable XML viewer. Its copy callback writes XML to the clipboard.
- `build`: display history/empty state and refresh, inspect, Downloads and share actions. No synthetic-data controls exist.

**`lib/ui/screens/user_screen.dart`**
- `initState`: load the saved name and kilometre total.
- `didUpdateWidget`: refresh when the tab becomes active.
- `_load`: read SharedPreferences and completed session distances, excluding legacy demos; update loading/error/data state.
- `_editName`: open the name dialog, validate and persist the trimmed name.
- `build`: display just name/edit and the total-kilometres card, with refresh/loading/error support. No CustomPainter or point-detail calls remain.

### 6.5 Native activity and channels

**`MainActivity.kt`**
- `onCreate`: start the native service while the activity is visible.
- `configureFlutterEngine`: register both channels and command dispatch.
- Event handler `onListen`: install telemetry forwarding and emit the current service state when available.
- Event handler `onCancel`: detach forwarding.
- Method handlers `startLocationPreview`, `stopLocationPreview`, `getDiagnostics`, `startWalk`, `pauseWalk`, `resumeWalk`: delegate to the service.
- `finishWalk` handler: launch a lifecycle coroutine, await completion and return the summary.
- `getSavedSessions` handler: query Room on IO, exclude legacy demo titles and return session metadata without hex payloads.
- `getSessionDetail` handler: load session/points, read or regenerate GPX and return XML, file path and point details. No polygon computation remains.
- `exportToDownloads` handler: locate/regenerate GPX, export it on IO and return an error through the channel if export fails.
- Unknown commands return not-implemented. The native demo generator was deleted.

### 6.6 Foreground recorder service

**`service/WalkRecorderService.kt`**
- `onCreate`: initialize Room, notification channel, step callbacks and location callbacks; expose the active instance for the bridge.
- `startLocationPreview`: start native location and return current telemetry.
- `stopLocationPreview`: stop location only when idle.
- `getDiagnostics`: return sensor availability, step baseline/count and last location for internal inspection.
- `startWalk`: create an ID/title, reset distance/segments/baselines, enter foreground mode, start sensors/location, insert the recording session and start the ticker. Repeated starts while active return existing state.
- `pauseWalk`: accumulate unpaused time, pause step accounting, clear the distance anchor and checkpoint.
- `resumeWalk`: create a new route segment/time baseline, resume step accounting and checkpoint.
- `finishWalk`: finalize durations/counts, stop recording inputs, read points, write GPX and completed session, remove foreground notification and emit idle state.
- `handleIncomingLocation`: enforce freshness/order/accuracy/step/displacement gates; update preview independently; persist accepted points and route coordinates. No cell calculation exists.
- `persistSessionCheckpoint`: save current session metrics to Room asynchronously.
- `startTicker`: emit telemetry once per second while recording/paused.
- `broadcastTelemetry`: build a payload and dispatch it on Android's main thread for Flutter.
- `buildTelemetryPayload`: compose lifecycle, timer, sensor, distance, fresh-fix status and route segments. No hex fields are sent.
- `promoteToForeground`: start the recorder notification using the Android service type configuration.
- `updateNotification`: refresh the notification metrics.
- `buildNotification`: construct the persistent walking notification with an intent back to the activity. Notification text shows steps and kilometres; there are no inline pause/finish notification actions.
- `createNotificationChannel`: register the Android O+ low-importance notification channel.
- `onBind`: return null because the app uses its channels/shared instance rather than bound-service IPC.

### 6.7 Native sensors and acceptance policy

**`sensors/StepCounterManager.kt`**
- `hasStepCounterHardware`, `hasStepDetectorHardware`: report sensor availability.
- `getLastRawBootSteps`, `getInitialBaseline`, `getCurrentSessionSteps`: expose sensor state.
- `hasRecentStepActivity`: true for hardware activity within six seconds.
- `startSession`: clear counts/baselines/window and register sensors.
- `pauseSession`: preserve accumulated steps and suspend counting.
- `resumeSession`: clear segment baseline and resume counting.
- `stopSession`: unregister listeners.
- `registerSensors`: register available counter/detector listeners.
- `onSensorChanged`: process counter deltas or detector fallback, track recent movement and publish count/cadence updates. Detector movement signals can corroborate activity even when a counter is present.
- `pruneOldStepTimestamps`: remove timestamps older than 30 seconds.
- `computeCadence`: estimate steps/minute from the recent window, using a minimum five-second denominator.
- `onAccuracyChanged`: required sensor callback; currently no action.

**`sensors/LocationTrackerManager.kt`**
- `startTracking`: check precise-location permission, avoid duplicate subscriptions, select fused feed and start the stall watchdog.
- Fused `onLocationResult`: forward fresh fixes only when fused is the selected feed.
- Watchdog `run`: switch to device GPS after 12 seconds without a fresh fused fix; otherwise check again.
- `activateGps`: stop delivery from fused, register device GPS and report disabled/missing/permission states. It does not simultaneously merge GPS and network feeds.
- GPS `onLocationChanged`: forward fixes only while GPS is selected.
- `onProviderEnabled`, `onProviderDisabled`: update status.
- `onStatusChanged`: legacy compatibility callback, no work.
- `stopTracking`: invalidate pending failure callbacks, cancel watchdog and remove both subscriptions.

**`sensors/GpsFixPolicy.kt`**
- `isFresh`: accept age 0–15000ms.
- `acceptsMovement`: reject invalid values, nonpositive time, sub-1.2m displacement and >6.5m/s movement.
- `acceptsWalking`: apply accuracy/noise-floor checks and either new-step plausibility or conservative sensorless speed checks. It is pure Kotlin so it can be regression-tested without GPS hardware.

### 6.8 Room persistence

**`db/Entities.kt`**
- `WalkSessionEntity`: session identity/status/times, steps, distance and GPX path; one inert legacy field retained for compatibility.
- `TrackPointEntity`: ordered session/segment point, position, altitude, accuracy, speed, UTC/monotonic timestamps and cumulative steps; one inert legacy field retained.

**`db/WalkDao.kt`**
- `upsertSession`: insert/replace a session checkpoint or completed row.
- `insertTrackPoint`: insert a recorded point and return its generated ID.
- `getSession`: find one session by ID.
- `getAllSessions`: newest-first session history.
- `getTrackPointsForSession`: ordered segment/sequence points for GPX.
- `deleteSession`, `deleteTrackPoints`: existing internal DAO operations; no deletion UI is added in this release.

**`db/TerrastepDatabase.kt`**
- `getInstance`: synchronized singleton construction for `terrastep_local.db`.
- `walkDao`: expose the generated Room DAO.
- Schema version stays 1. The existing destructive-fallback setting is not a substitute for a future explicit migration; this revision deliberately avoids schema changes.

### 6.9 GPX writer

**`gpx/GpxFileWriter.kt`**
- `writeSessionGpx`: synchronized XML serialization to an app-specific GPX file, grouped by segment; returns the File. Includes bounds/waypoints when data exists. Newly written files have no hex extension.
- `writeWaypoint`: write a named coordinate, elevation and UTC timestamp.
- `copyToPublicDownloads`: use MediaStore.Downloads on API 29+ or the legacy public Downloads path on older versions; return the destination identifier/path.

## 7. Build and repository implementation

- Flutter **3.27.4**, Java **17**, Kotlin **1.9.22**, AGP **8.5.2**, Gradle **8.7**.
- Mapbox Flutter **2.8.0**, Room **2.6.1**, Play Services Location **21.3.0**.
- Android minSdk **26**, compileSdk **35**, targetSdk **34**; output targets ARM64.
- Version **0.3.3+33**, Android version name `0.3.3-core-scope`.
- `.github/workflows/build-apk.yml`: checkout -> Mapbox-secret preflight -> Java/Flutter setup -> dependency resolution -> Dart analysis -> Flutter tests -> ARM64 APK build -> native GPS-policy tests -> artifact upload -> APK/checksum publication to the working branch.
- The workflow publishes `releases/terrastep-milestone30-arm64.apk` and `releases/SHA256SUMS` with a bot commit marked `[skip ci]`. The historical filename is retained for a stable download path; its version comes from the build configuration.
- `MAPBOX_ACCESS_TOKEN` is a repository Actions secret supplied using `--dart-define`; the user does not enter it in the installed APK. Do not commit it or include it in this document.
- Release-mode evaluation APKs currently use debug signing configuration, not a production signing key. Different runners can generate different debug keys; an update may require uninstall/reinstall if Android reports a signature mismatch. Uninstalling removes app-local data: export important GPX files first.
- Work is committed/pushed only on the session branch, then merged through an explicit pull request to main. No direct main-branch development is required.

## 8. Tests and acceptance checklist

### Automated checks

- Dart analysis: catches missing methods/imports and type errors; informational/style warnings are nonfatal in CI.
- User widget tests: saved name, trimmed-name persistence, blank-name protection, kilometre total excluding legacy demos, and failure if User tries to load route-point detail.
- History widget tests: empty state has no generator; saved walk metadata and GPX XML inspection remain usable.
- Native GPS-policy tests: freshness, ordinary walking, jitter/teleports/duplicate timestamps, 47 seconds of seated drift adding zero distance, stopping after walking, implausible displacement despite steps, and sensorless speed gates.
- Scope regression script: no hex runtime engine/layers/payloads, no demo generator endpoint/button, and no User route painter/detail calls. Legacy database fields are explicitly permitted.
- APK publication checksum: verify with `sha256sum -c releases/SHA256SUMS` from repository root.

The source document accompanies the release. Consult the linked PR/Actions run and final delivery message for the actual completed run ID and merge result; do not mistake this checklist for a claim of physical-device execution.

### Physical-device checklist (not executable by the coding sandbox)

1. Install the new APK; grant precise location, physical activity and notification permissions.
2. Confirm the map and a single blue current-position dot, with no hex count/polygons.
3. Sit still with recording active for two minutes: steps and distance must not increase due solely to GPS drift.
4. Walk outdoors 50–100m with good GPS, then stop. Check plausible steps/distance and no continued drift accumulation.
5. Pause, move, resume and finish. Inspect GPX segments; do not count paused movement.
6. Open history: no demo-generation control. Inspect/copy XML; save to Downloads and share.
7. Open User: only name/edit and completed distance in km; no path drawing. Edit/restart to confirm persistence.
8. Test denied permission, location disabled and returning from Android Settings. No fabricated location/distance should be shown.
9. Test screen-off recording and the target phone's battery management.

## 9. Honest limitations

- Tests/build success cannot guarantee GPS reception or sensor timing on every device.
- No automatic interrupted-walk recovery, login, backend, cloud sync, map-history viewer or user-path renderer exists.
- Unpaused recording time is labelled Moving time; it is not an automatic physical-motion timer.
- Historical wrong distances and legacy exported GPX files remain unchanged.
- Older Android Downloads permissions, debug-key upgrade compatibility and battery restrictions must be checked on the target device.
- The scope changes do not claim to have solved unrelated lifecycle/process-death durability concerns. Any later work should be separately requested, not silently added as extra functionality.
