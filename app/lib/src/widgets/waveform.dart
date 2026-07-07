import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio_analysis.dart';
import '../theme.dart';
import 'painter_cache.dart';

/// Level history, meter-style: RMS bars colored by level, a peak trace on
/// top, and the band between them showing the dynamics (crest factor).
/// Narrow band = heavily compressed material, wide band = dynamic material.
class WaveformView extends StatelessWidget {
  const WaveformView({super.key, required this.wave});

  final WaveHistory wave;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: const _WaveGridPainter(),
        foregroundPainter: _WaveDataPainter(wave),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// modern music lives between -30 and 0 dBFS; a wider range wastes resolution
const _minDb = -48.0;
const _gridDb = [0.0, -6.0, -12.0, -18.0, -24.0, -36.0];
const _rightAxis = 36.0;
const _clipDb = -1.0;

double _y(double db, Size size) =>
    size.height * (db.clamp(_minDb, 0.0) / _minDb);

Color _levelColor(double db) {
  final t = ((db - _minDb) / -_minDb).clamp(0.0, 1.0);
  if (t < 0.6) {
    return Color.lerp(AppColors.accent2, AppColors.accent, t / 0.6)!;
  }
  if (t < 0.85) {
    return Color.lerp(AppColors.accent, AppColors.amber, (t - 0.6) / 0.25)!;
  }
  return Color.lerp(AppColors.amber, AppColors.warn, (t - 0.85) / 0.15)!;
}

class _WaveGridPainter extends CustomPainter {
  const _WaveGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppColors.grid
      ..strokeWidth = 1;
    for (final db in _gridDb) {
      final y = _y(db, size);
      canvas.drawLine(Offset(0, y), Offset(size.width - _rightAxis, y), grid);
      final tp = cachedLabel('${db.toInt()} dB');
      tp.paint(canvas, Offset(size.width - _rightAxis + 4, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_WaveGridPainter oldDelegate) => false;
}

class _WaveDataPainter extends CustomPainter {
  _WaveDataPainter(this.wave) : super(repaint: wave);

  final WaveHistory wave;

  // one history entry is a 100ms chunk, so 50 entries = one 5s model window
  static const _chunksPerWindow = 50;

  @override
  void paint(Canvas canvas, Size size) {
    final n = wave.length;
    if (n == 0) return;
    final plotWidth = size.width - _rightAxis;
    final barWidth = plotWidth / wave.capacity;

    _paintSegments(canvas, size, plotWidth, barWidth);

    final peakPath = Path();
    var peakStarted = false;
    final dynamicsPaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.14);

    for (var i = 0; i < n; i++) {
      final x = plotWidth - (n - i) * barWidth;
      if (x < 0) continue;
      final rmsDb = wave.rmsAt(i);
      final rmsY = _y(rmsDb, size);
      final peakY = _y(wave.peakAt(i), size);

      // rms body, colored by how hot the signal is
      canvas.drawRect(
        Rect.fromLTRB(x, rmsY, x + barWidth * 0.85, size.height),
        Paint()..color = _levelColor(rmsDb).withValues(alpha: 0.80),
      );
      // dynamics band: the headroom between peak and rms
      if (peakY < rmsY) {
        canvas.drawRect(
          Rect.fromLTRB(x, peakY, x + barWidth * 0.85, rmsY),
          dynamicsPaint,
        );
      }

      final px = x + barWidth * 0.42;
      if (peakStarted) {
        peakPath.lineTo(px, peakY);
      } else {
        peakPath.moveTo(px, peakY);
        peakStarted = true;
      }
    }

    canvas.drawPath(
      peakPath,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (wave.lastPeakDb >= _clipDb) {
      final tp = cachedLabel('CLIP', color: AppColors.warn);
      canvas.drawCircle(
        Offset(plotWidth - tp.width - 14, 9),
        3,
        Paint()..color = AppColors.warn,
      );
      tp.paint(canvas, Offset(plotWidth - tp.width - 8, 4));
    }
  }

  /// 5s slices tied to the audio itself: block boundaries sit at fixed
  /// positions in the stream and scroll left together with the bars.
  /// Alternating shading makes each 5s piece readable at a glance.
  void _paintSegments(
      Canvas canvas, Size size, double plotWidth, double barWidth) {
    final n = wave.length;
    final firstGlobal = wave.total - n;
    final shade = Paint()..color = AppColors.text.withValues(alpha: 0.03);
    final boundary = Paint()
      ..color = AppColors.panelBorder
      ..strokeWidth = 1;

    var blockStart =
        (firstGlobal ~/ _chunksPerWindow) * _chunksPerWindow;
    for (; blockStart < wave.total; blockStart += _chunksPerWindow) {
      final startIndex = blockStart - firstGlobal;
      final x0 = plotWidth - (n - startIndex) * barWidth;
      final x1 = x0 + _chunksPerWindow * barWidth;
      if ((blockStart ~/ _chunksPerWindow).isEven) {
        canvas.drawRect(
          Rect.fromLTRB(math.max(x0, 0), 0,
              math.min(x1, plotWidth), size.height),
          shade,
        );
      }
      if (x0 >= 0) {
        canvas.drawLine(Offset(x0, 0), Offset(x0, size.height), boundary);
      }
    }
  }

  @override
  bool shouldRepaint(_WaveDataPainter oldDelegate) => oldDelegate.wave != wave;
}
