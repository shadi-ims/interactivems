# IMS StreamPulse

A sleek HLS multiview monitor for Android TV / Mi Box, styled after the IMS
HLS-Streamer console: near-black panels, monospace type, amber/teal/green
signal colors. Plays four live channels at once in a 2×2 grid.

## Channels

Al Mashhad · Al Sharq · Al Arabia · Al Hadath
(all from `wd-stream11.widekhaliji.com:8446`)

## Per-stream controls

Each panel has three D-pad / touch-friendly buttons (amber focus glow):

- **Audio** — routes sound to that panel and mutes the others (four
  simultaneous audio tracks would be unusable, so all start muted).
- **Refresh** (⟳) — tears down and re-initializes just that stream without
  touching the other three, and re-reads its master playlist.
- **Info** (ⓘ) — opens a full **Stream Monitor** for that channel.

## Live info on each panel

Every tile overlays real telemetry: channel name, a pulsing **LIVE** badge,
the active **resolution**, **buffer** seconds, and a **profile count**
(`N PROF`) parsed live from the channel's master playlist.

The Stream Monitor expands this into the dashboard view: source URL, current
status / resolution / active bitrate / buffer, and a **STREAM PROFILES** grid
— one card per variant with resolution, peak & average Mbps, FPS, codec
string, and chunk path, with the currently-playing variant marked **ACTIVE**.

## Build command for Mi Box

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

## Codemagic

Push to GitHub, connect to Codemagic, run the `android-tv` workflow.

## Notes

- Requires `INTERNET` (declared). Profile parsing uses `package:http`;
  video uses `video_player` (ExoPlayer/media3, native HLS).
- Profile parsing validates TLS. If a feed ever uses a self-signed cert the
  video will still play but the profile panel will read "unreachable".
- Decoding four hardware video feeds at once can exceed the simultaneous
  decoder limit on low-end TV boxes; a black tile (others fine) points there.
- Release build still uses the debug key and `com.example.interactivems`
  application id — set a real keystore and package before store distribution.
