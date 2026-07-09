import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'audio_analysis.dart';
import 'audio_capture.dart';
import 'genre_client.dart';
import 'logger.dart';

/// Owns the capture stream, live audio analysis and the server conversation.
class SessionController {
  SessionController({required this.capture, required this.client}) {
    _checkHealth();
    _healthTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _checkHealth());
  }

  final AudioCapture capture;
  final GenreClient client;

  late final Timer _healthTimer;
  final serverOk = ValueNotifier<bool>(false);

  Future<void> _checkHealth() async {
    try {
      await client.ping();
      if (!serverOk.value) log('server', 'reachable');
      serverOk.value = true;
    } catch (_) {
      if (serverOk.value) log('server', 'became unreachable');
      serverOk.value = false;
    }
  }

  final wave = WaveHistory(360); // 36s of 100ms chunks
  late SpectrumAnalyzer spectrum =
      SpectrumAnalyzer(sampleRate: _sampleRate);

  final result = ValueNotifier<GenreResult?>(null);
  final capturing = ValueNotifier<bool>(false);
  final error = ValueNotifier<String?>(null);
  // set when macOS denied the screen/audio recording permission: the UI
  // shows a button that opens the right System Settings pane
  final permissionIssue = ValueNotifier<bool>(false);
  final chunksReceived = ValueNotifier<int>(0);
  final postLatencyMs = ValueNotifier<double>(0);
  final sessionStartedAt = ValueNotifier<DateTime?>(null);

  static const _postSeconds = 0.5;

  // a gap between tracks = near-digital silence for 2.5s; quiet passages
  // inside a song (breakdowns) sit above -55 dB or end sooner
  static const _silenceDb = -55.0;
  static const _silenceChunks = 25;

  int _sampleRate = 48000;
  int _postBytes = 0;
  StreamSubscription<Uint8List>? _subscription;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  bool _posting = false;
  int _quietStreak = 0;
  bool _inGap = false;
  int _posts = 0;
  double _latencySum = 0;

  Future<List<AppSource>> listApps() async {
    if (!Platform.isMacOS) return [];
    return capture.listApps();
  }

  Future<void> start({int? pid, String? sourceName}) async {
    if (capturing.value) return;
    if (!Platform.isMacOS) {
      error.value = 'Live capture is only implemented on macOS '
          '(ScreenCaptureKit). The SPECTROGRAM tab works everywhere.';
      return;
    }
    try {
      await client.ping();
    } catch (e) {
      log('server', 'ping failed: $e');
      error.value = 'Server is not reachable. Start it with: '
          'uvicorn server.main:app --port 8000';
      return;
    }
    try {
      await client.reset();
      _sampleRate = await capture.sampleRate();
      _postBytes = (_sampleRate * _postSeconds).round() * 4;
      if (spectrum.sampleRate != _sampleRate) {
        spectrum.dispose();
        spectrum = SpectrumAnalyzer(sampleRate: _sampleRate);
      }
      _resetSessionState();

      _subscription = capture.audio.listen(
        _onChunk,
        onError: (Object e) {
          log('capture', 'stream error: $e');
          error.value = 'Capture error: $e';
        },
      );
      await capture.start(pid: pid);
      capturing.value = true;
      sessionStartedAt.value = DateTime.now();
      error.value = null;
      log('session',
          'started: source=${sourceName ?? 'system'} pid=$pid sr=$_sampleRate');
    } catch (e) {
      await _subscription?.cancel();
      _subscription = null;
      log('capture', 'start failed: $e');
      if ('$e'.contains('declined TCC')) {
        permissionIssue.value = true;
        error.value = 'macOS blocked audio capture. Allow "Genre Analyzer" '
            'under Screen & System Audio Recording, then restart the app.';
      } else {
        error.value = 'Cannot start capture: $e';
      }
    }
  }

  Future<void> stop() async {
    if (!capturing.value) return;
    capturing.value = false;
    sessionStartedAt.value = null;
    await capture.stop();
    await _subscription?.cancel();
    _subscription = null;
    _pending.clear();
    log('session',
        'stopped: chunks=${chunksReceived.value} posts=$_posts '
        'avg_latency=${_posts == 0 ? 0 : (_latencySum / _posts).toStringAsFixed(1)}ms');
  }

  /// Full reload from the refresh button: clears the meters, verdicts and
  /// the server-side session. Works both live (starts a fresh session) and
  /// stopped (unfreezes the last picture).
  Future<void> refresh() async {
    _resetSessionState();
    error.value = null;
    if (capturing.value) sessionStartedAt.value = DateTime.now();
    log('session', 'manual refresh');
    try {
      await client.reset();
    } catch (e) {
      log('server', 'reset failed: $e');
    }
  }

  void _resetSessionState() {
    _pending.clear();
    wave.clear();
    spectrum.clear();
    result.value = null;
    chunksReceived.value = 0;
    _quietStreak = 0;
    _inGap = false;
    _posts = 0;
    _latencySum = 0;
  }

  void _onChunk(Uint8List raw) {
    // the channel codec delivers a view into the message envelope whose
    // offset is not 4-byte aligned; Float32List.view requires alignment
    final bytes = raw.offsetInBytes % 4 == 0 ? raw : Uint8List.fromList(raw);
    final samples = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );

    if (chunksReceived.value == 0) {
      log('capture', 'first chunk: ${samples.length} samples');
    }
    chunksReceived.value++;

    wave.add(samples);
    spectrum.add(samples);
    _detectTrackGap(wave.lastRmsDb);
    // during a gap nothing is sent: windows made of silence would seed the
    // fresh session with garbage (the model reads silence as Instrumental)
    if (_inGap) return;
    _pending.add(bytes);
    _drainPending();
  }

  /// A silence gap means the track changed: reset once, stay quiet until
  /// the music resumes, then start the new session from the first loud chunk.
  void _detectTrackGap(double rmsDb) {
    if (rmsDb >= _silenceDb) {
      if (_inGap) log('session', 'gap ended, new session starts');
      _quietStreak = 0;
      _inGap = false;
      return;
    }
    _quietStreak++;
    if (_quietStreak == _silenceChunks) {
      final r = result.value;
      log('session',
          'silence gap detected after ${r?.windowsSeen ?? 0} windows, '
          'resetting session');
      _inGap = true;
      _pending.clear();
      result.value = null;
      client.reset().catchError((Object e) {
        log('server', 'reset failed: $e');
      });
    }
  }

  Future<void> _drainPending() async {
    if (_posting || _pending.length < _postBytes) return;
    _posting = true;
    try {
      while (_pending.length >= _postBytes) {
        final body = _pending.takeBytes();
        final sw = Stopwatch()..start();
        final r = await client.sendAudio(body, _sampleRate);
        sw.stop();

        _posts++;
        _latencySum += sw.elapsedMilliseconds;
        postLatencyMs.value = sw.elapsedMilliseconds.toDouble();
        if (sw.elapsedMilliseconds > 250) {
          log('server', 'slow post: ${sw.elapsedMilliseconds}ms');
        }
        if (r.windowsSeen > (result.value?.windowsSeen ?? 0) &&
            r.window != null) {
          final top = r.window!.entries
              .reduce((a, b) => a.value >= b.value ? a : b);
          log('window',
              '#${r.windowsSeen} ${top.key} ${(top.value * 100).toStringAsFixed(0)}%');
        }
        result.value = r;
        error.value = null;
      }
    } catch (e) {
      log('server', 'post failed: $e');
      error.value = 'Server error: $e';
    } finally {
      _posting = false;
    }
  }

  Future<void> dispose() async {
    _healthTimer.cancel();
    serverOk.dispose();
    await stop();
    client.dispose();
    wave.dispose();
    spectrum.dispose();
    result.dispose();
    capturing.dispose();
    error.dispose();
    permissionIssue.dispose();
    chunksReceived.dispose();
    postLatencyMs.dispose();
    sessionStartedAt.dispose();
  }
}
