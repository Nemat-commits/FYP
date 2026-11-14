# Terrastep releases

APK builds land here after a local `flutter build`. This folder is the
**only** place where `*.apk` files are allowed in Git (see `.gitignore`
exception below). Everywhere else APKs stay blocked.

## Build (on your machine, with Flutter SDK installed)

```bash
flutter pub get
flutter analyze
flutter build apk --debug
# or, with your Mapbox public token baked in:
flutter build apk --debug --dart-define=MAPBOX_ACCESS_TOKEN=pk.xxx
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

## Save the APK here

```bash
cp build/app/outputs/flutter-apk/app-debug.apk releases/terrastep-v0.3.0-debug.apk
git add releases/terrastep-v0.3.0-debug.apk
git commit -m "Add Terrastep v0.3.0 debug APK"
git push origin arena/69fd0e77-fyp
```

## Recommended alternative (keeps Git small)

APKs are 40–55 MB each and stay in Git history forever, slowing every
clone. The preferred home for builds is Google Drive:
`TerraSteps - FYP / 04_Builds_&_Defense_Archive` (where the v0.1.10 and
v0.3.0 APKs already live), or a GitHub Release asset:

```bash
gh release create v0.3.0 releases/terrastep-v0.3.0-debug.apk --title "Terrastep v0.3.0"
```

Only commit APKs into this folder if you explicitly want them versioned
in Git history.
