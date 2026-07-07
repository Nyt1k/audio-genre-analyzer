import 'package:flutter/services.dart';

class AppSource {
  const AppSource({required this.pid, required this.name});

  final int pid;
  final String name;
}

/// Thin wrapper over the native ScreenCaptureKit platform channels.
class AudioCapture {
  static const _methods = MethodChannel('genre/capture');
  static const _events = EventChannel('genre/audio');

  /// Mono float32 PCM chunks (~100ms each) from the native side.
  Stream<Uint8List> get audio =>
      _events.receiveBroadcastStream().map((event) => event as Uint8List);

  Future<int> sampleRate() async =>
      (await _methods.invokeMethod<int>('sampleRate'))!;

  Future<List<AppSource>> listApps() async {
    final raw = await _methods.invokeMethod<List>('listApps');
    return [
      for (final item in raw!)
        AppSource(
          pid: (item as Map)['pid'] as int,
          name: item['name'] as String,
        ),
    ];
  }

  /// [pid] limits capture to one application, null captures everything.
  Future<void> start({int? pid}) =>
      _methods.invokeMethod('start', {'pid': pid});

  Future<void> stop() => _methods.invokeMethod('stop');
}
