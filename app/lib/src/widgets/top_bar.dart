import 'package:flutter/material.dart';

import '../audio_capture.dart';
import '../theme.dart';
import 'listening_indicator.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.apps,
    required this.sourcePid,
    required this.capturing,
    required this.serverOk,
    required this.startedAt,
    required this.onSourceChanged,
    required this.onSourcesOpened,
    required this.onStart,
    required this.onStop,
  });

  final List<AppSource> apps;
  final int? sourcePid;
  final bool capturing;
  final bool serverOk;
  final ValueNotifier<DateTime?> startedAt;
  final ValueChanged<int?> onSourceChanged;
  final VoidCallback onSourcesOpened;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatusDot(ok: serverOk, label: serverOk ? 'server' : 'no server'),
        const SizedBox(width: 20),
        ListeningIndicator(startedAt: startedAt),
        const Spacer(),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: DropdownButtonFormField<int?>(
              initialValue: sourcePid,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Audio source'),
              style: const TextStyle(fontSize: 13, color: AppColors.text),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('System audio (everything)'),
                ),
                for (final app in apps)
                  DropdownMenuItem<int?>(
                    value: app.pid,
                    child: Text(app.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: capturing ? null : onSourceChanged,
              onTap: onSourcesOpened,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: onSourcesOpened,
          icon: const Icon(Icons.refresh, size: 18, color: AppColors.dim),
          tooltip: 'Refresh source list',
        ),
        const SizedBox(width: 8),
        TransportButton(capturing: capturing, onStart: onStart, onStop: onStop),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ok ? AppColors.ok : AppColors.warn,
            boxShadow: [
              BoxShadow(
                color: (ok ? AppColors.ok : AppColors.warn)
                    .withValues(alpha: 0.6),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppText.mono),
      ],
    );
  }
}

class TransportButton extends StatelessWidget {
  const TransportButton({
    super.key,
    required this.capturing,
    required this.onStart,
    required this.onStop,
  });

  final bool capturing;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final color = capturing ? AppColors.warn : AppColors.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: capturing ? onStop : onStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(4),
            color: color.withValues(alpha: 0.12),
          ),
          child: Row(
            children: [
              Icon(
                capturing ? Icons.stop : Icons.play_arrow,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                capturing ? 'STOP' : 'START',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
