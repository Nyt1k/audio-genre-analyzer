import 'package:flutter/foundation.dart';

/// Timestamped tagged logs, visible in the `flutter run` console.
void log(String tag, String message) {
  final now = DateTime.now();
  final ts = '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
  debugPrint('[$ts][$tag] $message');
}
