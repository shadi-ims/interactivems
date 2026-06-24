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

## Walls (instances) & stream count

Streams are not hard-coded — the app loads them from a PHP endpoint per
**instance** (a "wall"):

```
https://interactivems.net/ims/streampulse/app/{instance}
```

Open **SETUP** (top-right) to pick how many streams to show — **2, 4, or 6**
(default **4**) — and to switch instances. The grid adapts: 2 → side-by-side,
4 → 2×2, 6 → 3×2. If the endpoint can't be reached the app falls back to the
four built-in channels and flags `OFFLINE CFG`.

The instance list comes from `…/app/` and each wall from `…/app/{instance}`.
See `server/` for the PHP that produces both (and `lib/config.dart` for the
client side).

## Always-highest quality (no ABR ramp-up)

Previously a tile opened on a low rendition and only climbed to full quality
after a refresh, because ExoPlayer's bitrate estimator starts conservatively —
and `video_player` exposes no track-selection API to override it. The app now
reads each master playlist, picks the **highest** variant, and points the
player straight at that variant's media playlist. Every tile opens at full
resolution immediately. Trade-off: a pinned variant won't auto-downswitch if
the network can't sustain it, so on a constrained link a tile may buffer
rather than drop quality — which is the right behavior for a monitoring wall.

## Server (PHP endpoint)

`server/index.php` + `server/.htaccess` go in `…/ims/streampulse/app/`. Edit
the `$INSTANCES` array to define walls and add channels. It also accepts
`?i={instance}` if your host doesn't do URL rewriting. JSON shape:

```
GET …/app/            -> { "instances": [ {"id","name","count"}, … ] }
GET …/app/{instance}  -> { "instance","name", "streams":[ {"name","url"}, … ] }
```

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
