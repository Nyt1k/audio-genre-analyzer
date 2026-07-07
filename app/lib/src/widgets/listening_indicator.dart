import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Shown while capturing: a tiny dancing equalizer plus the elapsed time.
class ListeningIndicator extends StatefulWidget {
  const ListeningIndicator({super.key, required this.startedAt});

  final ValueNotifier<DateTime?> startedAt;

  @override
  State<ListeningIndicator> createState() => _ListeningIndicatorState();
}

class _ListeningIndicatorState extends State<ListeningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    widget.startedAt.addListener(_onStateChange);
    _onStateChange();
  }

  void _onStateChange() {
    final listening = widget.startedAt.value != null;
    if (listening && !_controller.isAnimating) {
      _controller.repeat();
      _clock = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!listening) {
      _controller.stop();
      _clock?.cancel();
      _clock = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.startedAt.removeListener(_onStateChange);
    _controller.dispose();
    _clock?.cancel();
    super.dispose();
  }

  String _elapsed(DateTime started) {
    final d = DateTime.now().difference(started);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final started = widget.startedAt.value;
    if (started == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _EqualizerPainter(_controller),
            child: const SizedBox(width: 22, height: 16),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _elapsed(started),
          style: AppText.monoBright.copyWith(
            fontSize: 13,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  _EqualizerPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const _bars = 4;
  static const _phases = [0.0, 0.55, 0.2, 0.8];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.accent;
    final barW = size.width / (_bars * 2 - 1);
    for (var i = 0; i < _bars; i++) {
      final t = (animation.value + _phases[i]) * 2 * math.pi;
      final h = size.height * (0.25 + 0.75 * (0.5 + 0.5 * math.sin(t)));
      final x = i * barW * 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, barW, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
