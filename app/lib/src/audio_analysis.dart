import 'dart:math' as math;

import 'package:fftea/fftea.dart';
import 'package:flutter/foundation.dart';

double _toDb(double amplitude) =>
    amplitude <= 1e-9 ? -90.0 : 20 * math.log(amplitude) / math.ln10;

/// Ring buffer of per-chunk RMS and peak levels in dBFS.
/// Painters subscribe to it directly; no widget rebuilds involved.
class WaveHistory extends ChangeNotifier {
  WaveHistory(this.capacity)
      : _rms = Float64List(capacity),
        _peak = Float64List(capacity);

  final int capacity;
  final Float64List _rms;
  final Float64List _peak;
  int _next = 0;
  int _filled = 0;
  int _total = 0;

  /// Chunks added since the session started (not capped by capacity).
  int get total => _total;

  void add(Float32List samples) {
    var sumSq = 0.0;
    var peak = 0.0;
    for (final s in samples) {
      sumSq += s * s;
      final a = s.abs();
      if (a > peak) peak = a;
    }
    final rms = samples.isEmpty ? 0.0 : math.sqrt(sumSq / samples.length);
    _rms[_next] = _toDb(rms);
    _peak[_next] = _toDb(peak);
    _next = (_next + 1) % capacity;
    if (_filled < capacity) _filled++;
    _total++;
    notifyListeners();
  }

  void clear() {
    _next = 0;
    _filled = 0;
    _total = 0;
    notifyListeners();
  }

  int get length => _filled;

  /// i = 0 is the oldest stored value, dBFS.
  double rmsAt(int i) => _rms[(_next - _filled + i + capacity) % capacity];
  double peakAt(int i) => _peak[(_next - _filled + i + capacity) % capacity];

  double get lastRmsDb => _filled == 0 ? -90 : rmsAt(_filled - 1);
  double get lastPeakDb => _filled == 0 ? -90 : peakAt(_filled - 1);
}

/// Live spectrum in log-spaced bands. Levels are raw per-frame values;
/// display ballistics (attack/release smoothing) happen in the view at the
/// frame rate. Peak hold with slow decay is kept here.
class SpectrumAnalyzer extends ChangeNotifier {
  SpectrumAnalyzer({
    required this.sampleRate,
    this.bands = 72,
    this.minHz = 20,
    this.maxHz = 20000,
    this.floorDb = -90,
  })  : levels = Float64List(bands)..fillRange(0, bands, -90),
        peaks = Float64List(bands)..fillRange(0, bands, -90) {
    _fft = FFT(fftSize);
    _hann = Float64List.fromList(List.generate(
        fftSize,
        (i) =>
            0.5 - 0.5 * math.cos(2 * math.pi * i / (fftSize - 1))));
    _binForBand = _buildBandEdges();
  }

  static const fftSize = 4096;
  static const _peakRelease = 0.985;

  final int sampleRate;
  final int bands;
  final double minHz;
  final double maxHz;
  final double floorDb;

  /// Raw band levels and peak-hold levels, dBFS.
  final Float64List levels;
  final Float64List peaks;

  /// Spectral centroid ("brightness" of the sound), Hz. 0 when silent.
  double centroidHz = 0;

  late final FFT _fft;
  late final Float64List _hann;
  late final List<int> _binForBand; // band edges in FFT bin indices
  final Float64List _frame = Float64List(fftSize);
  int _framePos = 0;

  List<int> _buildBandEdges() {
    final edges = List<int>.filled(bands + 1, 0);
    final logMin = math.log(minHz);
    final logMax = math.log(math.min(maxHz, sampleRate / 2));
    for (var b = 0; b <= bands; b++) {
      final hz = math.exp(logMin + (logMax - logMin) * b / bands);
      edges[b] = (hz * fftSize / sampleRate).round().clamp(1, fftSize ~/ 2);
    }
    return edges;
  }

  /// Center frequency of a band, for axis labels.
  double bandHz(int b) =>
      math.exp(math.log(minHz) +
          (math.log(math.min(maxHz, sampleRate / 2)) - math.log(minHz)) *
              (b + 0.5) /
              bands);

  void add(Float32List samples) {
    // slide samples into the analysis frame; analyze when it fills up
    var offset = 0;
    while (offset < samples.length) {
      final take = math.min(samples.length - offset, fftSize - _framePos);
      for (var i = 0; i < take; i++) {
        _frame[_framePos + i] = samples[offset + i];
      }
      _framePos += take;
      offset += take;
      if (_framePos == fftSize) {
        _analyze();
        // 50% overlap keeps the display responsive
        _frame.setRange(0, fftSize ~/ 2, _frame, fftSize ~/ 2);
        _framePos = fftSize ~/ 2;
      }
    }
  }

  void _analyze() {
    final windowed = Float64List(fftSize);
    for (var i = 0; i < fftSize; i++) {
      windowed[i] = _frame[i] * _hann[i];
    }
    final spectrum = _fft.realFft(windowed);

    // spectral centroid over raw FFT bins (power-weighted mean frequency)
    var powerSum = 0.0;
    var weighted = 0.0;
    for (var k = 1; k < fftSize ~/ 2; k++) {
      final re = spectrum[k].x;
      final im = spectrum[k].y;
      final p = re * re + im * im;
      powerSum += p;
      weighted += p * k * sampleRate / fftSize;
    }
    centroidHz = powerSum > 1e-12 ? weighted / powerSum : 0;

    // 2/N normalization for a Hann-windowed one-sided spectrum
    const norm = 2 / (fftSize * 0.5);
    for (var b = 0; b < bands; b++) {
      final lo = _binForBand[b];
      final hi = math.max(_binForBand[b + 1], lo + 1);
      var power = 0.0;
      for (var k = lo; k < hi; k++) {
        final re = spectrum[k].x;
        final im = spectrum[k].y;
        power += re * re + im * im;
      }
      final magnitude = math.sqrt(power / (hi - lo)) * norm;
      final db = _toDb(magnitude).clamp(floorDb, 0.0);

      levels[b] = db;
      final held = peaks[b] * _peakRelease + floorDb * (1 - _peakRelease);
      peaks[b] = math.max(db, held);
    }
    notifyListeners();
  }

  void clear() {
    levels.fillRange(0, bands, floorDb);
    peaks.fillRange(0, bands, floorDb);
    _framePos = 0;
    notifyListeners();
  }
}
