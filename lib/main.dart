import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'config.dart';
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

/// Used only if the config endpoint can't be reached, so the app still runs.
const List<Channel> kFallbackStreams = [
  Channel('Al Mashhad',
      'https://wd-stream11.widekhaliji.com:8446/almashhad/abr_live/playlist.m3u8'),
  Channel('Al Sharq',
      'https://wd-stream11.widekhaliji.com:8446/alsharq/abr_live/playlist.m3u8'),
  Channel('Al Arabia',
      'https://wd-stream11.widekhaliji.com:8446/alarabia/abr_live/playlist.m3u8'),
  Channel('Al Hadath',
      'https://wd-stream11.widekhaliji.com:8446/alhadath/abr_live/playlist.m3u8'),
];

const List<int> kCountOptions = [2, 4, 6];

// ---------------------------------------------------------------------------
// Session: owns one channel's player + parsed profiles, survives a refresh.
// Pins playback to the highest variant so a tile opens at full quality
// instead of waiting for ExoPlayer's ABR estimator to ramp up.
// ---------------------------------------------------------------------------
class StreamSession extends ChangeNotifier {
  StreamSession(this.channel) {
    start();
  }

  final Channel channel;

  VideoPlayerController? controller;
  bool initializing = true;
  bool hasError = false;

  List<HlsProfile> profiles = const [];
  bool profilesLoading = true;
  String? profilesError;

  /// The variant actually being played (the highest), for the monitor.
  HlsProfile? pinned;

  bool audioOn = false;
  int _gen = 0;

  Future<void> start() async {
    final gen = ++_gen;

    final old = controller;
    controller = null;
    initializing = true;
    hasError = false;
    profilesLoading = true;
    profilesError = null;
    pinned = null;
    notifyListeners();
    await old?.dispose();

    // 1) Resolve the master playlist and pick the top profile to pin.
    var playUrl = channel.url;
    try {
      final profs = await fetchHlsProfiles(channel.url);
      if (gen != _gen) return;
      profiles = profs;
      profilesError = profs.isEmpty ? 'no variants found' : null;
      if (profs.isNotEmpty && profs.first.uri.isNotEmpty) {
        pinned = profs.first; // sorted highest-resolution first
        playUrl = Uri.parse(channel.url).resolve(profs.first.uri).toString();
      }
    } catch (_) {
      profilesError = 'master playlist unreachable';
      // Fall back to the master URL (ExoPlayer ABR) if parsing failed.
    } finally {
      profilesLoading = false;
      notifyListeners();
    }

    // 2) Play the pinned variant (or master fallback).
    final c = VideoPlayerController.networkUrl(
      Uri.parse(playUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await c.initialize();
      if (gen != _gen) {
        await c.dispose();
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
// Home: top status bar + adaptive grid (2 / 4 / 6) + settings overlay.
// ---------------------------------------------------------------------------
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _instance = kDefaultInstance;
  String _instanceName = kDefaultInstance;
  int _count = 4; // default

  List<Channel> _streams = const [];
  List<StreamSession> _sessions = [];
  int _activeAudio = -1;

  bool _configLoading = true;
  bool _usingFallback = false;

  bool _settingsOpen = false;
  List<InstanceRef> _instances = const [];
  bool _instancesLoading = false;
  String? _instancesError;

  @override
  void initState() {
    super.initState();
    _loadConfig(_instance);
  }

  @override
  void dispose() {
    for (final s in _sessions) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig(String instance) async {
    setState(() => _configLoading = true);
    try {
      final cfg = await fetchInstance(instance);
      if (cfg.streams.isEmpty) throw Exception('no streams');
      _instance = cfg.instance;
      _instanceName = cfg.name;
      _streams = cfg.streams.map((s) => Channel(s.name, s.url)).toList();
      _usingFallback = false;
    } catch (_) {
      _instance = instance;
      _instanceName = instance;
      _streams = kFallbackStreams;
      _usingFallback = true;
    }
    _configLoading = false;
    _rebuildSessions();
  }

  void _rebuildSessions() {
    for (final s in _sessions) {
      s.dispose();
    }
    final n = _count <= _streams.length ? _count : _streams.length;
    _sessions = _streams.take(n).map((c) => StreamSession(c)).toList();
    _activeAudio = -1;
    if (mounted) setState(() {});
  }

  void _setCount(int c) {
    if (c == _count) return;
    setState(() => _count = c);
    _rebuildSessions();
  }

  void _selectInstance(String id) {
    setState(() => _settingsOpen = false);
    _loadConfig(id);
  }

  Future<void> _openSettings() async {
    setState(() {
      _settingsOpen = true;
      _instancesLoading = true;
      _instancesError = null;
    });
    try {
      final list = await fetchInstances();
      if (!mounted) return;
      setState(() {
        _instances = list;
        _instancesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _instances = const [];
        _instancesLoading = false;
        _instancesError = 'instance list unavailable';
      });
    }
  }

  void _toggleAudio(int i) {
    setState(() {
      if (_activeAudio == i) {
        _sessions[i].setAudio(false);
        _activeAudio = -1;
      } else {
        if (_activeAudio >= 0 && _activeAudio < _sessions.length) {
          _sessions[_activeAudio].setAudio(false);
        }
        _sessions[i].setAudio(true);
        _activeAudio = i;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(
                  host: _hostLabel(),
                  instanceName: _instanceName,
                  count: _sessions.length,
                  usingFallback: _usingFallback,
                  onSettings: _openSettings,
                ),
                Expanded(
                  child: FocusTraversalGroup(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: _body(),
                    ),
                  ),
                ),
              ],
            ),
            if (_settingsOpen)
              _SettingsOverlay(
                instance: _instance,
                count: _count,
                instances: _instances,
                loading: _instancesLoading,
                error: _instancesError,
                onCount: _setCount,
                onInstance: _selectInstance,
                onClose: () => setState(() => _settingsOpen = false),
              ),
          ],
        ),
      ),
    );
  }

  String _hostLabel() {
    if (_streams.isNotEmpty) {
      try {
        return Uri.parse(_streams.first.url).authority;
      } catch (_) {}
    }
    return Uri.parse(kBaseUrl).authority;
  }

  Widget _body() {
    if (_configLoading) {
      return const Center(
        child: _Status(
            title: 'LOADING CONFIG…', subtitle: 'fetching instance', color: P.amber, spinner: true),
      );
    }
    if (_sessions.isEmpty) {
      return const Center(
        child: _Status(title: 'NO STREAMS', subtitle: 'check instance', color: P.magenta),
      );
    }
    return _grid();
  }

  // Adaptive layout: 2 -> 1x2, 4 -> 2x2, 6 -> 2x3.
  Widget _grid() {
    final n = _sessions.length;
    final cols = n <= 2 ? n : (n <= 4 ? 2 : 3);
    final rows = (n / cols).ceil();

    final rowWidgets = <Widget>[];
    for (var r = 0; r < rows; r++) {
      final cells = <Widget>[];
      for (var col = 0; col < cols; col++) {
        if (col > 0) cells.add(const SizedBox(width: 8));
        final idx = r * cols + col;
        cells.add(Expanded(
          child: idx < n ? _cell(idx) : const SizedBox(),
        ));
      }
      if (r > 0) rowWidgets.add(const SizedBox(height: 8));
      rowWidgets.add(Expanded(child: Row(children: cells)));
    }
    return Column(children: rowWidgets);
  }

  Widget _cell(int i) => StreamPanel(
        key: ValueKey('${_instance}_${_sessions[i].channel.url}_$i'),
        session: _sessions[i],
        index: i,
        audioActive: _activeAudio == i,
        autofocus: i == 0,
        onToggleAudio: () => _toggleAudio(i),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.host,
    required this.instanceName,
    required this.count,
    required this.usingFallback,
    required this.onSettings,
  });

  final String host;
  final String instanceName;
  final int count;
  final bool usingFallback;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: P.panel,
        border: Border(bottom: BorderSide(color: P.border)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Phones / portrait are narrow: drop the secondary metadata and
          // keep only brand + (tappable) instance + SETUP so the button can
          // never be pushed off-screen.
          final compact = c.maxWidth < 600;
          return Row(
            children: [
              const PulseDot(color: P.green),
              const SizedBox(width: 9),
              Text('IMS',
                  style: mono(color: P.amber, size: 14, weight: FontWeight.w700, spacing: 1.5)),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text('STREAMPULSE',
                    style: mono(color: Colors.white, size: 14, weight: FontWeight.w700, spacing: 1.5)),
              ],
              const SizedBox(width: 12),
              // Tappable instance — opens the picker (acts as the "dropdown").
              Expanded(
                child: InkWell(
                  onTap: onSettings,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Eyebrow('INST', color: P.greyDim, size: 9),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(instanceName,
                              overflow: TextOverflow.ellipsis,
                              style: mono(color: P.teal, size: 11, weight: FontWeight.w700)),
                        ),
                        const Icon(Icons.arrow_drop_down_rounded, color: P.teal, size: 18),
                        if (usingFallback) ...[
                          const SizedBox(width: 8),
                          const Pill('OFFLINE CFG', color: P.magenta),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (!compact) ...[
                Text('$count up', style: mono(color: P.grey, size: 11)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(host,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: mono(color: P.grey, size: 11)),
                ),
                const SizedBox(width: 12),
                const _Clock(),
                const SizedBox(width: 10),
              ],
              FocusIconButton(
                icon: Icons.tune_rounded,
                label: compact ? null : 'SETUP',
                onPressed: onSettings,
              ),
            ],
          );
        },
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
// Settings overlay: stream count (2/4/6) + instance picker.
// ---------------------------------------------------------------------------
class _SettingsOverlay extends StatelessWidget {
  const _SettingsOverlay({
    required this.instance,
    required this.count,
    required this.instances,
    required this.loading,
    required this.error,
    required this.onCount,
    required this.onInstance,
    required this.onClose,
  });

  final String instance;
  final int count;
  final List<InstanceRef> instances;
  final bool loading;
  final String? error;
  final ValueChanged<int> onCount;
  final ValueChanged<String> onInstance;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final w = screen.width - 32 < 560 ? screen.width - 32 : 560.0;
    final h = screen.height - 80 < 560 ? screen.height - 80 : 560.0;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.82),
        alignment: Alignment.center,
        child: FocusTraversalGroup(
          child: Container(
            width: w,
            constraints: BoxConstraints(maxHeight: h),
            padding: const EdgeInsets.all(22),
            decoration: panelDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('SETUP',
                        style: mono(color: P.amber, size: 16, weight: FontWeight.w700, spacing: 2)),
                    const Spacer(),
                    FocusIconButton(
                      icon: Icons.close_rounded,
                      label: 'CLOSE',
                      autofocus: true,
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Eyebrow('STREAMS', color: P.teal, size: 11),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final c in kCountOptions) ...[
                      _PickButton(
                        label: '$c',
                        selected: c == count,
                        onTap: () => onCount(c),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Eyebrow('INSTANCE', color: P.teal, size: 11),
                    const SizedBox(width: 10),
                    if (loading)
                      Text('loading…', style: mono(color: P.grey, size: 11)),
                    if (error != null)
                      Text(error!, style: mono(color: P.magenta, size: 11)),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(child: _instanceList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _instanceList() {
    if (loading) return const SizedBox(height: 40);
    if (instances.isEmpty) {
      // Still let the user keep the current instance.
      return _PickButton(
        label: instance,
        sub: 'current',
        selected: true,
        onTap: () => onInstance(instance),
      );
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          for (final ins in instances) ...[
            _PickButton(
              label: ins.name,
              sub: '${ins.id} · ${ins.count} streams',
              selected: ins.id == instance,
              wide: true,
              onTap: () => onInstance(ins.id),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Focusable selectable button (text), amber on focus, teal when selected.
class _PickButton extends StatefulWidget {
  const _PickButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.sub,
    this.wide = false,
    this.autofocus = false,
  });

  final String label;
  final String? sub;
  final bool selected;
  final bool wide;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<_PickButton> createState() => _PickButtonState();
}

class _PickButtonState extends State<_PickButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final border = _focused ? P.amber : (widget.selected ? P.teal : P.border);
    final fg = _focused ? P.amber : (widget.selected ? P.teal : P.grey);
    return InkWell(
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      onFocusChange: (f) => setState(() => _focused = f),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: widget.wide ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: widget.wide ? 14 : 20, vertical: 12),
        decoration: BoxDecoration(
          color: _focused ? P.amber.withOpacity(0.14) : Colors.black.withOpacity(0.3),
          border: Border.all(color: border, width: _focused || widget.selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(6),
          boxShadow: _focused ? [BoxShadow(color: P.amber.withOpacity(0.4), blurRadius: 10)] : null,
        ),
        child: Row(
          mainAxisSize: widget.wide ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.label,
                    style: mono(color: fg, size: 14, weight: FontWeight.w700, spacing: 0.5)),
                if (widget.sub != null) ...[
                  const SizedBox(height: 3),
                  Text(widget.sub!, style: mono(color: P.greyDim, size: 10)),
                ],
              ],
            ),
            if (widget.wide) const Spacer(),
            if (widget.selected)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Icon(Icons.check_rounded, size: 16, color: P.teal),
              ),
          ],
        ),
      ),
    );
  }
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
            Expanded(
              child: Text(widget.session.channel.name,
                  overflow: TextOverflow.ellipsis,
                  style: mono(color: Colors.white, size: 13, weight: FontWeight.w700, spacing: 0.5)),
            ),
            const SizedBox(width: 8),
            const Pill('LIVE', color: P.green),
            const SizedBox(width: 8),
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
                    children: [
                      const Eyebrow('STREAM PROFILES', color: P.teal, size: 12),
                      const SizedBox(width: 10),
                      Text(
                        session.profilesLoading
                            ? 'reading…'
                            : '${session.profiles.length} profiles',
                        style: mono(color: P.grey, size: 11),
                      ),
                      const SizedBox(width: 10),
                      const Pill('TOP PINNED', color: P.amber),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('STREAM MONITOR', color: P.grey, size: 10),
                const SizedBox(height: 3),
                Text(session.channel.name,
                    overflow: TextOverflow.ellipsis,
                    style: mono(color: Colors.white, size: 22, weight: FontWeight.w700, spacing: 0.5)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const Pill('LIVE', color: P.green, filled: true),
          const SizedBox(width: 14),
          FocusIconButton(
            icon: Icons.refresh_rounded,
            label: 'REFRESH',
            color: P.amber,
            onPressed: session.refresh,
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

    // Active bitrate = the pinned (highest) profile, else size match.
    String bitrate = '—';
    if (session.pinned?.peakMbps != null) {
      bitrate = '${session.pinned!.peakMbps} Mbps';
    } else if (init && v!.size.width > 0) {
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

    final pinned = session.pinned;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final p in session.profiles)
          _ProfileCard(
            profile: p,
            active: pinned != null && identical(p, pinned),
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
