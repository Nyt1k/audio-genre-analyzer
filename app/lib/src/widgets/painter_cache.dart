import 'package:flutter/material.dart';

import '../theme.dart';

final Map<String, TextPainter> _labels = {};

/// Axis labels are static text; laying them out on every paint was the main
/// source of jank. Cache one TextPainter per (label, color) pair.
TextPainter cachedLabel(String text, {Color? color}) {
  return _labels.putIfAbsent('$text#${color?.toARGB32() ?? 0}', () {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppText.mono.copyWith(fontSize: 9, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  });
}
