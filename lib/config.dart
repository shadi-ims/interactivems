import 'dart:convert';
import 'package:http/http.dart' as http;

/// Base of the PHP output endpoint. An instance is loaded from
/// `$kBaseUrl/{instance}` and the instance index from `$kBaseUrl/`.
const String kBaseUrl = 'https://interactivems.net/ims/streampulse/app';
const String kDefaultInstance = 'default';

class StreamDef {
  const StreamDef(this.name, this.url);
  final String name;
  final String url;
}

class InstanceConfig {
  const InstanceConfig({
    required this.instance,
    required this.name,
    required this.streams,
  });
  final String instance;
  final String name;
  final List<StreamDef> streams;
}

class InstanceRef {
  const InstanceRef(this.id, this.name, this.count);
  final String id;
  final String name;
  final int count;
}

/// Load one instance's stream list from `$kBaseUrl/{instance}`.
Future<InstanceConfig> fetchInstance(String instance) async {
  final r = await http
      .get(Uri.parse('$kBaseUrl/$instance'))
      .timeout(const Duration(seconds: 12));
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  final raw = (j['streams'] as List?) ?? const [];
  final streams = raw
      .map((e) => StreamDef(
            (e['name'] ?? 'Stream').toString(),
            (e['url'] ?? '').toString(),
          ))
      .where((s) => s.url.isNotEmpty)
      .toList();
  return InstanceConfig(
    instance: (j['instance'] ?? instance).toString(),
    name: (j['name'] ?? instance).toString(),
    streams: streams,
  );
}

/// Load the list of available instances from `$kBaseUrl/`.
Future<List<InstanceRef>> fetchInstances() async {
  final r =
      await http.get(Uri.parse('$kBaseUrl/')).timeout(const Duration(seconds: 12));
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  final raw = (j['instances'] as List?) ?? const [];
  return raw
      .map((e) => InstanceRef(
            (e['id'] ?? '').toString(),
            (e['name'] ?? e['id'] ?? '').toString(),
            e['count'] is int
                ? e['count'] as int
                : int.tryParse('${e['count']}') ?? 4,
          ))
      .where((i) => i.id.isNotEmpty)
      .toList();
}
