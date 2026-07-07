import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../session_controller.dart';
import '../theme.dart';

/// Bottom strip of technical readouts.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Item(
          listenable: controller.chunksReceived,
          builder: (_) => 'chunks ${controller.chunksReceived.value}',
        ),
        _Item(
          listenable: controller.result,
          builder: (_) =>
              'windows ${controller.result.value?.windowsSeen ?? 0}',
        ),
        _Item(
          listenable: controller.wave,
          builder: (_) =>
              'rms ${controller.wave.lastRmsDb.toStringAsFixed(1)} dB',
        ),
        _Item(
          listenable: controller.wave,
          builder: (_) =>
              'peak ${controller.wave.lastPeakDb.toStringAsFixed(1)} dB',
        ),
        _Item(
          listenable: controller.postLatencyMs,
          builder: (_) =>
              'server ${controller.postLatencyMs.value.toStringAsFixed(0)} ms',
        ),
        const Spacer(),
        const _VersionLabel(),
      ],
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) => Text(
        snapshot.hasData ? 'v${snapshot.data!.version}' : '',
        style: AppText.mono,
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.listenable, required this.builder});

  final Listenable listenable;
  final String Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: AnimatedBuilder(
        animation: listenable,
        builder: (context, _) => Text(builder(context), style: AppText.mono),
      ),
    );
  }
}
