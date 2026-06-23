import 'package:http/http.dart' as http;

/// One variant (profile) from an HLS master playlist (#EXT-X-STREAM-INF).
class HlsProfile {
  const HlsProfile({
    this.width,
    this.height,
    this.bandwidth,
    this.averageBandwidth,
    this.frameRate,
    this.codecs,
    required this.uri,
  });

  final int? width;
  final int? height;
  final int? bandwidth; // peak bits/s
  final int? averageBandwidth; // bits/s
  final double? frameRate;
  final String? codecs;
  final String uri;

  String get resLabel =>
      (width != null && height != null) ? '$width×$height' : '—';

  String? get peakMbps =>
      bandwidth != null ? (bandwidth! / 1e6).toStringAsFixed(2) : null;

  String? get avgMbps => averageBandwidth != null
      ? (averageBandwidth! / 1e6).toStringAsFixed(2)
      : null;

  String? get fpsLabel =>
      frameRate != null ? frameRate!.toStringAsFixed(0) : null;

  String get codecLabel => (codecs == null || codecs!.isEmpty) ? '—' : codecs!;

  String get chunkLabel {
    if (uri.isEmpty) return '—';
    final clean = uri.split('?').first;
    final parts = clean.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) {
      return parts.sublist(parts.length - 2).join('/');
    }
    return parts.isNotEmpty ? parts.last : uri;
  }

  bool matchesSize(double w, double h) =>
      width != null &&
      height != null &&
      width == w.round() &&
      height == h.round();
}

/// Fetch and parse the master playlist at [masterUrl] into its profiles,
/// sorted highest-resolution first.
Future<List<HlsProfile>> fetchHlsProfiles(String masterUrl) async {
  final resp = await http
      .get(Uri.parse(masterUrl))
      .timeout(const Duration(seconds: 12));
  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}');
  }
  return parseMasterPlaylist(resp.body);
}

List<HlsProfile> parseMasterPlaylist(String body) {
  final lines = body.split(RegExp(r'\r?\n'));
  final profiles = <HlsProfile>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;

    final attrs = _parseAttributes(line.substring('#EXT-X-STREAM-INF:'.length));

    // The URI is the next non-empty, non-comment line.
    var uri = '';
    for (var j = i + 1; j < lines.length; j++) {
      final l = lines[j].trim();
      if (l.isEmpty || l.startsWith('#')) continue;
      uri = l;
      break;
    }

    int? w, h;
    final res = attrs['RESOLUTION'];
    if (res != null && res.contains('x')) {
      final parts = res.toLowerCase().split('x');
      if (parts.length == 2) {
        w = int.tryParse(parts[0].trim());
        h = int.tryParse(parts[1].trim());
      }
    }

    profiles.add(HlsProfile(
      width: w,
      height: h,
      bandwidth: int.tryParse(attrs['BANDWIDTH'] ?? ''),
      averageBandwidth: int.tryParse(attrs['AVERAGE-BANDWIDTH'] ?? ''),
      frameRate: double.tryParse(attrs['FRAME-RATE'] ?? ''),
      codecs: attrs['CODECS'],
      uri: uri,
    ));
  }

  profiles.sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
  return profiles;
}

/// Parse an attribute list, respecting quoted values (e.g. CODECS="a,b").
Map<String, String> _parseAttributes(String s) {
  final map = <String, String>{};
  final re = RegExp(r'([A-Z0-9\-]+)=("([^"]*)"|[^,]*)');
  for (final m in re.allMatches(s)) {
    final key = m.group(1)!;
    final val = m.group(3) ?? m.group(2) ?? '';
    map[key] = val;
  }
  return map;
}
