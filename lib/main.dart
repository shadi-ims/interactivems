import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

const Color kAccent = Color(0xFFF9AE05); // matches app icon

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
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(primary: kAccent),
      ),
      home: const MultiViewScreen(),
    );
  }
}

class Channel {
  const Channel(this.name, this.url);
  final String name;
  final String url;
}

class MultiViewScreen extends StatefulWidget {
  const MultiViewScreen({super.key});

  @override
  State<MultiViewScreen> createState() => _MultiViewScreenState();
}

class _MultiViewScreenState extends State<MultiViewScreen> {
  static const List<Channel> _channels = [
    Channel('Al Mashhad',
        'https://wd-stream11.widekhaliji.com:8446/almashhad/abr_live/playlist.m3u8'),
    Channel('Al Sharq',
        'https://wd-stream11.widekhaliji.com:8446/alsharq/abr_live/playlist.m3u8'),
    Channel('Al Arabia',
        'https://wd-stream11.widekhaliji.com:8446/alarabia/abr_live/playlist.m3u8'),
    Channel('Al Hadath',
        'https://wd-stream11.widekhaliji.com:8446/alhadath/abr_live/playlist.m3u8'),
  ];

  // Index of the tile whose audio is on; -1 = all muted.
  int _activeAudio = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FocusTraversalGroup(
          child: Column(
            children: [
              Expanded(child: _row(0, 1)),
              Expanded(child: _row(2, 3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(int a, int b) {
    return Row(
      children: [
        Expanded(child: _cell(a)),
        Expanded(child: _cell(b)),
      ],
    );
  }

  Widget _cell(int i) {
    final c = _channels[i];
    return Padding(
      padding: const EdgeInsets.all(2),
      child: VideoTile(
        key: ValueKey(c.url),
        channel: c,
        audioOn: _activeAudio == i,
        autofocus: i == 0,
        onSelected: () {
          setState(() => _activeAudio = _activeAudio == i ? -1 : i);
        },
      ),
    );
  }
}

class VideoTile extends StatefulWidget {
  const VideoTile({
    super.key,
    required this.channel,
    required this.audioOn,
    required this.onSelected,
    this.autofocus = false,
  });

  final Channel channel;
  final bool audioOn;
  final VoidCallback onSelected;
  final bool autofocus;

  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _hasError = false;
      _initialized = false;
    });
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.channel.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(widget.audioOn ? 1.0 : 0.0);
      await controller.play();
      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    }
  }

  @override
  void didUpdateWidget(covariant VideoTile old) {
    super.didUpdateWidget(old);
    if (old.audioOn != widget.audioOn && _initialized) {
      _controller?.setVolume(widget.audioOn ? 1.0 : 0.0);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _retry() {
    _controller?.dispose();
    _controller = null;
    _init();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      autofocus: widget.autofocus,
      onTap: widget.onSelected,
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(
            color: _focused ? kAccent : Colors.white12,
            width: _focused ? 3 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _videoLayer(),
            _label(),
            if (widget.audioOn) _audioBadge(),
          ],
        ),
      ),
    );
  }

  Widget _videoLayer() {
    if (_hasError) {
      return _StatusOverlay(
        icon: Icons.wifi_off_rounded,
        message: 'Stream unavailable',
        action: TextButton.icon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh, color: kAccent),
          label: const Text('Retry', style: TextStyle(color: kAccent)),
        ),
      );
    }
    if (!_initialized || _controller == null) {
      return const _StatusOverlay(
        icon: null,
        message: 'Loading stream…',
        showSpinner: true,
      );
    }
    final value = _controller!.value;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: value.size.width == 0 ? 16 : value.size.width,
        height: value.size.height == 0 ? 9 : value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
  }

  Widget _label() {
    return Positioned(
      left: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: const BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.only(topRight: Radius.circular(6)),
        ),
        child: Text(
          widget.channel.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _audioBadge() {
    return const Positioned(
      right: 8,
      top: 8,
      child: Icon(Icons.volume_up_rounded, color: kAccent, size: 22),
    );
  }
}

class _StatusOverlay extends StatelessWidget {
  const _StatusOverlay({
    required this.icon,
    required this.message,
    this.action,
    this.showSpinner = false,
  });

  final IconData? icon;
  final String message;
  final Widget? action;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(kAccent),
              ),
            ),
          if (icon != null) Icon(icon, color: Colors.white54, size: 36),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (action != null) ...[
            const SizedBox(height: 8),
            action!,
          ],
        ],
      ),
    );
  }
}
