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
(default **4**) — to choose **FIT vs FILL** (see below), to set **QUALITY**,
and to switch instances. The grid adapts: 2 → side-by-side, 4 → 2×2, 6 → 3×2.
If the endpoint can't be reached the app falls back to the four built-in
channels and flags `OFFLINE CFG`.

**QUALITY.** Defaults to **AUTO** (each tile sized to the grid — light on the
box). You can override it in one click for all streams: **1080p / 720p / 540p /
360p** pins every tile to the highest variant at or below that height. Use a
lower setting if a box struggles, or 1080p on a strong box/network.

**Remote Back button.** While SETUP is open, Back closes the popup instead of
exiting the app.

**Persistence.** The last stream count, FIT/FILL, QUALITY, and instance are
saved (via `shared_preferences`) and restored on next launch.

**FIT vs FILL.** Tiles often aren't exactly 16:9 (a 2-up tile is tall and
narrow), so **FILL** (crop to edges) zooms the 16:9 frame to fill the tile and
cuts off the sides/tickers. **FIT** (default) shows the entire frame with thin
letterbox bars — the right choice for monitoring, since you keep the lower-
thirds and ticker. Toggle it live in SETUP.

The instance list comes from `…/app/` and each wall from `…/app/{instance}`.
See `server/` for the PHP that produces both (and `lib/config.dart` for the
client side).

## Quality: instant + sized to the tile (no ABR ramp-up, no overload)

A tile used to open on a low rendition and only climb after a refresh, because
ExoPlayer's bitrate estimator starts conservatively — and `video_player`
exposes no track-selection API to override it. The app now reads each master
playlist and **pins a specific variant immediately**, so there's no ramp-up.

The pinned variant is **matched to how big the tile actually is**: a quarter-
screen tile in a 2×2 doesn't need 1080p. By stream count the per-tile cap is
2 → 720p, 4 → 540p, 6 → 360p (single/full-screen → highest). This keeps the
picture crisp while cutting decode work several-fold, so 4–6 streams stay
smooth on a Mi Box instead of stuttering under four simultaneous 1080p decodes.
Tune the caps in `_variantCapFor()` in `lib/main.dart` if your box is beefier.

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

- The screen is kept on while the app is foreground (`FLAG_KEEP_SCREEN_ON`
  in `MainActivity.kt`), so the Android TV screensaver never interrupts a
  monitoring wall. No permission required; it clears when the app closes.
- Requires `INTERNET` (declared). Profile parsing uses `package:http`;
  video uses `video_player` (ExoPlayer/media3, native HLS).
- Profile parsing validates TLS. If a feed ever uses a self-signed cert the
  video will still play but the profile panel will read "unreachable".
- Decoding four hardware video feeds at once can exceed the simultaneous
  decoder limit on low-end TV boxes; a black tile (others fine) points there.
- Release build still uses the debug key and `com.example.interactivems`
  application id — set a real keystore and package before store distribution.
