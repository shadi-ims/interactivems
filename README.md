# IMS StreamPulse

Flutter Android TV app for Mi Box that plays four live HLS channels at once
in a 2×2 multiview grid.

## Channels

- Al Mashhad
- Al Sharq
- Al Arabia
- Al Hadath

## How it works

- Each quadrant loads its HLS stream independently and shows a loading
  spinner until the first frame is ready; a failed stream shows a
  **Retry** button instead of blocking the others.
- All tiles play muted by default to avoid four overlapping audio tracks.
  On the Mi Box remote, move the D-pad to focus a tile (amber border) and
  press OK/center to route audio to that tile; press again to mute. The
  active tile shows a speaker badge.

## Build command for Mi Box

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

The APK is created at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Codemagic

Push this project to GitHub, connect it to Codemagic, then run the
`android-tv` workflow to produce the APK.

## Notes

- Requires the `INTERNET` permission (declared in the manifest).
- Streaming four hardware-decoded video feeds at once can exceed the
  simultaneous decoder limit on lower-end Android TV boxes. If a tile
  stays black on the device, that's the most likely cause — drop to a
  lower ABR variant or fewer tiles.
- The release build is still signed with the debug key and uses the
  `com.example.interactivems` application id; set a real keystore and
  package name before any Play Store distribution.
