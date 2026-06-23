import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'hls.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const StreamPulseApp());
}

class StreamPulseApp extends StatelessWidget {
  const StreamPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IMS StreamPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: P.bg,
        fontFamily: kMono,
        colorScheme: const ColorScheme.dark(
          primary: P.amber,
          secondary: P.teal,
          surface: P.panel,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: const HomeShell(),
    );
  }
}

class Channel {
  const Channel(this.name, this.url);
  final String name;
  final String url;
}

const List<Channel> kChannels = [
  Channel('Al Mashhad',
      'https://wd-stream11.widekhaliji.com:8446/almashhad/abr_live/playlist.m3u8'),
  Channel('Al Sharq',
      'https://wd-stream11.widekhaliji.com:8446/alsharq/abr_live/playlist.m3u8'),
  Channel('Al Arabia',
      'https://wd-stream11.widekhaliji.com:8446/alarabia/abr_live/playlist.m3u8'),
  Channel('Al Hadath',
      'https://wd-stream11.widekhaliji.com:8446/alhadath/abr_live/playlist.m3u8'),
];

// ---------------------------------------------------------------------------
// Session: owns one channel's player + parsed profiles, survives a refresh.
// ---------------------------------------------------------------------------
class StreamSession extends ChangeNotifier {
  StreamSession(this.channel) {
    start();
    loadProfiles();
  }

  final Channel channel;

  VideoPlayerController? controller;
  bool initializing = true;
  bool hasError = false;

  List<HlsProfile> profiles = const [];
  bool profilesLoading = true;
  String? profilesError;

  bool audioOn = false;

  int _gen = 0;

  Future<void> start() async {
    final gen = ++_gen;

    // Tear the old player down up front; the panel shows CONNECTING meanwhile.
    final old = controller;
    controller = null;
    initializing = true;
    hasError = false;
    notifyListeners();
    await old?.dispose();

    final c = VideoPlayerController.networkUrl(
      Uri.parse(channel.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await c.initialize();
      if (gen != _gen) {
        await c.dispose(); // a newer refresh superseded this one
        return;
      }
      await c.setVolume(audioOn ? 1.0 : 0.0);
      await c.play();
      controller = c;
      initializing = false;
      notifyListeners();
    } catch (_) {
      await c.dispose();
      if (gen != _gen) return;
      hasError = true;
      initializing = false;
      controller = null;
      notifyListeners();
    }
  }

  Future<void> refresh() => start();

  Future<void> loadProfiles() async {
    profilesLoading = true;
    profilesError = null;
    notifyListeners();
    try {
      profiles = await fetchHlsProfiles(channel.url);
      profilesError = profiles.isEmpty ? 'no variants found' : null;
    } catch (_) {
      profilesError = 'master playlist unreachable';
    } finally {
      profilesLoading = false;
      notifyListeners();
    }
  }

  void setAudio(bool on) {
    audioOn = on;
    controller?.setVolume(on ? 1.0 : 0.0);
    notifyListeners();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Home: top status bar + 2x2 grid.
// ---------------------------------------------------------------------------
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final List<StreamSession> _sessions =
      kChannels.map(StreamSession.new).toList();
  int _activeAudio = -1;

  @override
  void dispose() {
    for (final s in _sessions) {
      s.dispose();
    }
    super.dispose();
  }

  void _toggleAudio(int i) {
    setState(() {
      if (_activeAudio == i) {
        _sessions[i].setAudio(false);
        _activeAudio = -1;
      } else {
        if (_activeAudio >= 0) _sessions[_activeAudio].setAudio(false);
        _sessions[i].setAudio(true);
        _activeAudio = i;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: FocusTraversalGroup(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Column(
                    children: [
                      Expanded(child: _row(0, 1)),
                      const SizedBox(height: 8),
                      Expanded(child: _row(2, 3)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(int a, int b) => Row(
        children: [
          Expanded(child: _cell(a)),
          const SizedBox(width: 8),
          Expanded(child: _cell(b)),
        ],
      );

  Widget _cell(int i) => StreamPanel(
        session: _sessions[i],
        index: i,
        audioActive: _activeAudio == i,
        autofocus: i == 0,
        onToggleAudio: () => _toggleAudio(i),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final host = Uri.parse(kChannels.first.url).authority;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: P.panel,
        border: Border(bottom: BorderSide(color: P.border)),
      ),
      child: Row(
        children: [
          const PulseDot(color: P.green),
          const SizedBox(width: 9),
          Text('IMS', style: mono(color: P.amber, size: 14, weight: FontWeight.w700, spacing: 1.5)),
          const SizedBox(width: 6),
          Text('STREAMPULSE',
              style: mono(color: Colors.white, size: 14, weight: FontWeight.w700, spacing: 1.5)),
          const SizedBox(width: 12),
          Text('hls multiview', style: mono(color: P.grey, size: 11)),
          const Spacer(),
          Text(host, style: mono(color: P.grey, size: 11)),
          const SizedBox(width: 14),
          const _Clock(),
        ],
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _timer;
  String _now = '';

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final t = DateTime.now();
    final s =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    if (mounted) setState(() => _now = s);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(_now, style: mono(color: P.teal, size: 12, weight: FontWeight.w600, spacing: 1));
}

// ---------------------------------------------------------------------------
// One video panel.
// ---------------------------------------------------------------------------
class StreamPanel extends StatefulWidget {
  const StreamPanel({
    required this.session,
    required this.index,
    required this.audioActive,
    required this.onToggleAudio,
    this.autofocus = false,
    super.key,
  });

  final StreamSession session;
  final int index;
  final bool audioActive;
  final VoidCallback onToggleAudio;
  final bool autofocus;

  @override
  State<StreamPanel> createState() => _StreamPanelState();
}

class _StreamPanelState extends State<StreamPanel> {
  void _openMonitor() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MonitorScreen(session: widget.session),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return Container(
          clipBehavior: Clip.hardEdge,
          decoration: panelDecoration(
            accent: widget.audioActive ? P.teal : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _videoLayer(s),
              _topScrim(s),
              _bottomScrim(s),
            ],
          ),
        );
      },
    );
  }

  Widget _videoLayer(StreamSession s) {
    if (s.hasError) {
      return _Status(
        title: 'STREAM OFFLINE',
        subtitle: widget.session.channel.name,
        color: P.magenta,
      );
    }
    final c = s.controller;
    if (s.initializing || c == null || !c.value.isInitialized) {
      return _Status(
        title: 'CONNECTING…',
        subtitle: widget.session.channel.name,
        color: P.amber,
        spinner: true,
      );
    }
    final size = c.value.size;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width <= 0 ? 16 : size.width,
        height: size.height <= 0 ? 9 : size.height,
        child: VideoPlayer(c),
      ),
    );
  }

  Widget _topScrim(StreamSession s) {
    final profileChip = s.profilesLoading
        ? '··· PROF'
        : (s.profilesError != null ? '— PROF' : '${s.profiles.length} PROF');
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.75), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            const PulseDot(color: P.green, size: 7),
            const SizedBox(width: 7),
            Text(widget.session.channel.name,
                style: mono(color: Colors.white, size: 13, weight: FontWeight.w700, spacing: 0.5)),
            const SizedBox(width: 8),
            const Pill('LIVE', color: P.green),
            const Spacer(),
            Text(profileChip,
                style: mono(color: P.teal, size: 10, weight: FontWeight.w600, spacing: 0.8)),
          ],
        ),
      ),
    );
  }

  Widget _bottomScrim(StreamSession s) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 16, 8, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.8), Colors.transparent],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: _liveStats(s)),
            FocusIconButton(
              icon: widget.audioActive ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: widget.audioActive ? P.teal : P.grey,
              onPressed: widget.onToggleAudio,
              autofocus: widget.autofocus,
            ),
            const SizedBox(width: 6),
            FocusIconButton(
              icon: Icons.refresh_rounded,
              onPressed: widget.session.refresh,
            ),
            const SizedBox(width: 6),
            FocusIconButton(
              icon: Icons.info_outline_rounded,
              onPressed: _openMonitor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveStats(StreamSession s) {
    final c = s.controller;
    if (c == null || !c.value.isInitialized) {
      return Text('—', style: mono(color: P.greyDim, size: 11));
    }
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final v = c.value;
        final res =
            v.size.width > 0 ? '${v.size.width.round()}×${v.size.height.round()}' : '—';
        final buf = _bufferAhead(v).toStringAsFixed(0);
        return Row(
          children: [
            Text(res, style: mono(color: P.green, size: 12, weight: FontWeight.w700)),
            Text('  ·  ', style: mono(color: P.greyDim, size: 12)),
            Text('BUF ', style: mono(color: P.grey, size: 11)),
            Text('${buf}s', style: mono(color: P.teal, size: 12, weight: FontWeight.w700)),
          ],
        );
      },
    );
  }
}

double _bufferAhead(VideoPlayerValue v) {
  final pos = v.position;
  for (final r in v.buffered) {
    if (r.start <= pos && r.end >= pos) {
      return (r.end - pos).inMilliseconds / 1000.0;
    }
  }
  if (v.buffered.isNotEmpty) {
    return (v.buffered.last.end - pos).inMilliseconds / 1000.0;
  }
  return 0;
}

class _Status extends StatelessWidget {
  const _Status({
    required this.title,
    required this.subtitle,
    required this.color,
    this.spinner = false,
  });
  final String title;
  final String subtitle;
  final Color color;
  final bool spinner;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              )
            else
              Icon(Icons.sensors_off_rounded, color: color, size: 30),
            const SizedBox(height: 14),
            Text(title, style: mono(color: color, size: 13, weight: FontWeight.w700, spacing: 1.5)),
            const SizedBox(height: 6),
            Text(subtitle, style: mono(color: P.grey, size: 11, spacing: 0.5)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Monitor: full-screen per-stream info (what's playing + profiles).
// ---------------------------------------------------------------------------
class MonitorScreen extends StatelessWidget {
  const MonitorScreen({required this.session, super.key});
  final StreamSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: session,
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context),
                  const SizedBox(height: 18),
                  _sourceRow(),
                  const SizedBox(height: 18),
                  _metricStrip(),
                  const SizedBox(height: 22),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Eyebrow('STREAM PROFILES', color: P.teal, size: 12),
                      const SizedBox(width: 10),
                      Text(
                        session.profilesLoading
                            ? 'reading…'
                            : '${session.profiles.length} profiles',
                        style: mono(color: P.grey, size: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _profiles(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
        children: [
          FocusIconButton(
            icon: Icons.arrow_back_rounded,
            label: 'CLOSE',
            autofocus: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('STREAM MONITOR', color: P.grey, size: 10),
              const SizedBox(height: 3),
              Text(session.channel.name,
                  style: mono(color: Colors.white, size: 22, weight: FontWeight.w700, spacing: 0.5)),
            ],
          ),
          const SizedBox(width: 14),
          const Pill('LIVE', color: P.green, filled: true),
          const Spacer(),
          FocusIconButton(
            icon: Icons.refresh_rounded,
            label: 'REFRESH',
            color: P.amber,
            onPressed: () {
              session.refresh();
              session.loadProfiles();
            },
          ),
        ],
      );

  Widget _sourceRow() {
    final uri = Uri.parse(session.channel.url);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: panelDecoration(),
      child: Row(
        children: [
          const Eyebrow('SOURCE', color: P.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(session.channel.url,
                style: mono(color: P.grey, size: 11), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          Text(uri.authority, style: mono(color: P.greyDim, size: 11)),
        ],
      ),
    );
  }

  Widget _metricStrip() {
    final c = session.controller;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: panelDecoration(),
      child: c == null
          ? _metricContent(null)
          : AnimatedBuilder(
              animation: c,
              builder: (context, _) => _metricContent(c.value),
            ),
    );
  }

  Widget _metricContent(VideoPlayerValue? v) {
    final init = v != null && v.isInitialized;

    String status;
    Color statusColor;
    if (session.hasError) {
      status = 'OFFLINE';
      statusColor = P.magenta;
    } else if (!init) {
      status = 'CONNECTING';
      statusColor = P.amber;
    } else if (v!.isBuffering) {
      status = 'BUFFERING';
      statusColor = P.amber;
    } else if (v.isPlaying) {
      status = 'PLAYING';
      statusColor = P.green;
    } else {
      status = 'PAUSED';
      statusColor = P.grey;
    }

    final res = (init && v!.size.width > 0)
        ? '${v.size.width.round()}×${v.size.height.round()}'
        : '—';
    final buf = init ? '${_bufferAhead(v!).toStringAsFixed(1)}s' : '—';

    // Infer active bitrate from the profile matching the current size.
    String bitrate = '—';
    if (init && v!.size.width > 0) {
      for (final p in session.profiles) {
        if (p.matchesSize(v.size.width, v.size.height) && p.peakMbps != null) {
          bitrate = '${p.peakMbps} Mbps';
          break;
        }
      }
    }

    return Wrap(
      spacing: 40,
      runSpacing: 16,
      children: [
        StatReadout('STATUS', status, valueColor: statusColor),
        StatReadout('RESOLUTION', res, valueColor: P.green),
        StatReadout('ACTIVE BITRATE', bitrate, valueColor: P.amber),
        StatReadout('BUFFER', buf, valueColor: P.teal),
        StatReadout(
          'PROFILES',
          session.profilesLoading ? '…' : '${session.profiles.length}',
          valueColor: Colors.white,
        ),
      ],
    );
  }

  Widget _profiles() {
    if (session.profilesLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(P.teal)),
          ),
          const SizedBox(width: 12),
          Text('reading master playlist…', style: mono(color: P.grey, size: 12)),
        ],
      );
    }
    if (session.profilesError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: panelDecoration(accent: P.magenta.withOpacity(0.4)),
        child: Text('profiles unavailable — ${session.profilesError}',
            style: mono(color: P.magenta, size: 12)),
      );
    }

    final c = session.controller;
    final size = (c?.value.isInitialized ?? false) ? c!.value.size : null;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final p in session.profiles)
          _ProfileCard(
            profile: p,
            active: size != null && p.matchesSize(size.width, size.height),
          ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.active});
  final HlsProfile profile;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: panelDecoration(accent: active ? P.teal : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(p.resLabel,
                  style: mono(color: Colors.white, size: 17, weight: FontWeight.w700, spacing: 0.5)),
              const SizedBox(width: 10),
              if (active) const Pill('ACTIVE', color: P.teal, filled: true),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              if (p.peakMbps != null) _kv('PEAK', '${p.peakMbps} Mbps', P.amber),
              if (p.avgMbps != null) _kv('AVG', '${p.avgMbps} Mbps', P.grey),
              if (p.fpsLabel != null) _kv('FPS', p.fpsLabel!, P.grey),
            ],
          ),
          const SizedBox(height: 10),
          Text(p.codecLabel, style: mono(color: P.greyDim, size: 10.5)),
          const SizedBox(height: 2),
          Text(p.chunkLabel, style: mono(color: P.teal, size: 10.5)),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, Color valueColor) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$k ', style: mono(color: P.grey, size: 10.5, weight: FontWeight.w600)),
          Text(v, style: mono(color: valueColor, size: 11, weight: FontWeight.w700)),
        ],
      );
}
