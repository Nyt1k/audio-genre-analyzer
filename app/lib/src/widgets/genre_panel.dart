import 'package:flutter/material.dart';

import '../theme.dart';

/// One genre distribution: verdict header + sorted animated bars.
/// Used twice on the analyzer page: "now" (cyan) and "session" (violet).
class GenreDistributionView extends StatelessWidget {
  const GenreDistributionView({
    super.key,
    required this.distribution,
    required this.accent,
    required this.placeholder,
    this.footer,
  });

  final Map<String, double>? distribution;
  final Color accent;
  final String placeholder;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final dist = distribution;
    if (dist == null) {
      return Center(
        child: Text(placeholder, style: AppText.mono.copyWith(fontSize: 12)),
      );
    }

    final entries = dist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = entries.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                best.key,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(best.value * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 15, color: accent),
              ),
              const Spacer(),
              if (footer != null) Text(footer!, style: AppText.mono),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) => GenreRow(
              genre: entries[i].key,
              value: entries[i].value,
              accent: accent,
            ),
          ),
        ),
      ],
    );
  }
}

class GenreRow extends StatelessWidget {
  const GenreRow({
    super.key,
    required this.genre,
    required this.value,
    required this.accent,
  });

  final String genre;
  final double value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              genre,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
          Expanded(child: _AnimatedBar(value: value, accent: accent)),
          SizedBox(
            width: 48,
            child: Text(
              '${(value * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: AppText.monoBright,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBar extends StatelessWidget {
  const _AnimatedBar({required this.value, required this.accent});

  final double value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => CustomPaint(
        painter: _BarPainter(value: animated, accent: accent),
        child: const SizedBox(height: 9, width: double.infinity),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.value, required this.accent});

  final double value;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = AppColors.grid,
    );
    final w = value * size.width;
    if (w > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), radius),
        Paint()
          ..shader = LinearGradient(colors: [
            accent.withValues(alpha: 0.55),
            accent,
          ]).createShader(Rect.fromLTWH(0, 0, w, size.height)),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.accent != accent;
}
