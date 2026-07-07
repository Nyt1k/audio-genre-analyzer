import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio_analysis.dart';
import '../theme.dart';
import 'painter_cache.dart';

/// EQ-style live spectrum. The static grid and the moving curve are separate
/// painters: the grid never repaints, the curve is driven by a 60fps ticker
/// that applies attack/release smoothing toward the analyzer's raw levels.
class SpectrumView extends StatefulWidget {
  const SpectrumView({super.key, required this.spectrum});

  final SpectrumAnalyzer spectrum;

  @override
  State<SpectrumView> createState() => _SpectrumViewState();
}

class _SpectrumViewState extends State<SpectrumView>
    with SingleTickerProviderStateMixin {
  static const _attack = 0.55;
  static const _release = 0.10;

  late final Ticker _ticker;
  late Float64List _display;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _display = Float64List(widget.spectrum.bands)
      ..fillRange(0, widget.spectrum.bands, widget.spectrum.floorDb);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final s = widget.spectrum;
    if (_display.length != s.bands) {
      _display = Float64List(s.bands)..fillRange(0, s.bands, s.floorDb);
    }
    var changed = false;
    for (var b = 0; b < s.bands; b++) {
      final current = _display[b];
      final target = s.levels[b];
      final k = target > current ? _attack : _release;
      final next = current + (target - current) * k;
      if ((next - current).abs() > 0.02) changed = true;
      _display[b] = next;
    }
    if (changed) _frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SpectrumGridPainter(widget.spectrum),
        foregroundPainter: _SpectrumCurvePainter(
          spectrum: widget.spectrum,
          display: _display,
          repaint: _frame,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

const _gridDb = [0.0, -20.0, -40.0, -60.0, -80.0];
const _gridHz = [50, 100, 200, 500, 1000, 2000, 5000, 10000];
const _rightAxis = 36.0;
const _bottomAxis = 14.0;

class _SpectrumGridPainter extends CustomPainter {
  _SpectrumGridPainter(this.spectrum);

  final SpectrumAnalyzer spectrum;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Size(size.width - _rightAxis, size.height - _bottomAxis);
    final grid = Paint()
      ..color = AppColors.grid
      ..strokeWidth = 1;

    for (final db in _gridDb) {
      final y = plot.height * (db / spectrum.floorDb);
      canvas.drawLine(Offset(0, y), Offset(plot.width, y), grid);
      final tp = cachedLabel('${db.toInt()}');
      tp.paint(canvas, Offset(plot.width + 6, y - tp.height / 2));
    }

    final bandW = plot.width / spectrum.bands;
    for (final hz in _gridHz) {
      var x = -1.0;
      for (var b = 0; b < spectrum.bands; b++) {
        if (spectrum.bandHz(b) >= hz) {
          x = b * bandW;
          break;
        }
      }
      if (x < 0) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, plot.height), grid);
      final label = hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';
      final tp = cachedLabel(label);
      tp.paint(canvas, Offset(x - tp.width / 2, plot.height + 2));
    }
  }

  @override
  bool shouldRepaint(_SpectrumGridPainter oldDelegate) =>
      oldDelegate.spectrum != spectrum;
}

class _SpectrumCurvePainter extends CustomPainter {
  _SpectrumCurvePainter({
    required this.spectrum,
    required this.display,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final SpectrumAnalyzer spectrum;
  final Float64List display;

  double _y(double db, Size plot) =>
      plot.height * (db.clamp(spectrum.floorDb, 0.0) / spectrum.floorDb);

  /// Catmull-Rom spline through the band points: keeps the curve smooth
  /// instead of showing 72 polyline corners.
  Path _smoothPath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[math.max(i - 1, 0)];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[math.min(i + 2, pts.length - 1)];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  List<Offset> _points(Float64List values, Size plot, double bandW) => [
        for (var b = 0; b < values.length; b++)
          Offset((b + 0.5) * bandW, _y(values[b], plot)),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Size(size.width - _rightAxis, size.height - _bottomAxis);
    final n = display.length;
    if (n == 0) return;
    final bandW = plot.width / n;

    // peak hold: a smooth trace behind everything, violet underlay for depth
    // (no blur - MaskFilter is a raster op and kills the frame rate)
    final peakPath = _smoothPath(_points(spectrum.peaks, plot, bandW));
    canvas.drawPath(
      peakPath,
      Paint()
        ..color = AppColors.accent2.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawPath(
      peakPath,
      Paint()
        ..color = AppColors.text.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    final points = _points(display, plot, bandW);
    final fill = _smoothPath(points)
      ..lineTo(plot.width, plot.height)
      ..lineTo(points.first.dx, plot.height)
      ..close();
    canvas.drawPath(fill, _fillPaint(plot));

    final stroke = _smoothPath(points);
    // fake glow: a wide translucent stroke under the bright one, blur-free
    canvas.drawPath(
      stroke,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      stroke,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );

    _paintCentroid(canvas, plot, bandW);
  }

  // the gradient shader only depends on the plot size - cache it
  Paint? _cachedFill;
  Size? _cachedFillSize;

  Paint _fillPaint(Size plot) {
    if (_cachedFill == null || _cachedFillSize != plot) {
      _cachedFillSize = plot;
      _cachedFill = Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.accent2.withValues(alpha: 0.45),
            AppColors.accent.withValues(alpha: 0.38),
            AppColors.ok.withValues(alpha: 0.30),
          ],
        ).createShader(Offset.zero & plot);
    }
    return _cachedFill!;
  }

  // vertical marker at the spectral centroid: the "brightness" of the sound
  void _paintCentroid(Canvas canvas, Size plot, double bandW) {
    final hz = spectrum.centroidHz;
    if (hz < spectrum.minHz) return;
    var x = -1.0;
    for (var b = 0; b < spectrum.bands; b++) {
      if (spectrum.bandHz(b) >= hz) {
        x = (b + 0.5) * bandW;
        break;
      }
    }
    if (x < 0) return;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, plot.height),
      Paint()
        ..color = AppColors.amber.withValues(alpha: 0.55)
        ..strokeWidth = 1,
    );
    final label = hz >= 1000
        ? '${(hz / 1000).toStringAsFixed(1)}k'
        : '${(hz / 10).round() * 10}';
    final tp = cachedLabel('centroid $label', color: AppColors.amber);
    final tx = (x + 4 + tp.width > plot.width) ? x - tp.width - 4 : x + 4;
    tp.paint(canvas, Offset(tx, 2));
  }

  @override
  bool shouldRepaint(_SpectrumCurvePainter oldDelegate) =>
      oldDelegate.display != display || oldDelegate.spectrum != spectrum;
}
