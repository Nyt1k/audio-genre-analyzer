import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class GenreResult {
  const GenreResult({
    required this.window,
    required this.recent,
    required this.session,
    required this.windowsSeen,
  });

  /// Distribution of the last completed 5s window, null if no new window yet.
  final Map<String, double>? window;

  /// Exponential moving average, follows what is playing right now (~7s memory).
  final Map<String, double> recent;

  /// Running mean over the whole session.
  final Map<String, double> session;

  final int windowsSeen;
}

class ImageAnalysis {
  const ImageAnalysis({required this.distribution, required this.windows});

  final Map<String, double> distribution;
  final int windows;
}

/// Client of the local inference server. Keeps one connection alive.
class GenreClient {
  GenreClient(this.baseUrl);

  final String baseUrl;
  final http.Client _client = http.Client();

  Future<void> ping() async {
    final resp = await _client.get(Uri.parse('$baseUrl/status'));
    if (resp.statusCode != 200) {
      throw http.ClientException('status ${resp.statusCode}');
    }
  }

  Future<void> reset() async {
    await _client.post(Uri.parse('$baseUrl/reset'));
  }

  /// Sends raw float32 mono PCM, returns the updated distributions.
  Future<GenreResult> sendAudio(Uint8List pcm, int sampleRate) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/audio?sr=$sampleRate'),
      body: pcm,
    );
    if (resp.statusCode != 200) {
      throw http.ClientException('status ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return GenreResult(
      window: _distribution(json['window']),
      recent: _distribution(json['recent'])!,
      session: _distribution(json['session'])!,
      windowsSeen: json['windows_seen'] as int,
    );
  }

  /// Sends a rendered spectrogram image; the server reconstructs the log-mel
  /// array from pixels and runs the same model as for live audio.
  Future<ImageAnalysis> analyzeImage(Uint8List imageBytes) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/image'),
      body: imageBytes,
    );
    if (resp.statusCode != 200) {
      String detail;
      try {
        detail = (jsonDecode(resp.body) as Map)['detail'] as String;
      } catch (_) {
        detail = 'status ${resp.statusCode}';
      }
      throw http.ClientException(detail);
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return ImageAnalysis(
      distribution: _distribution(json['distribution'])!,
      windows: json['windows'] as int,
    );
  }

  static Map<String, double>? _distribution(dynamic raw) {
    if (raw == null) return null;
    return (raw as Map).map(
      (k, v) => MapEntry(k as String, (v as num).toDouble()),
    );
  }

  void dispose() {
    _client.close();
  }
}
