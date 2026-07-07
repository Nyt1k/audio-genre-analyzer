import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../audio_capture.dart';
import '../logger.dart';
import '../session_controller.dart';
import '../theme.dart';
import '../widgets/genre_panel.dart';
import '../widgets/panel.dart';
import '../widgets/spectrum.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/waveform.dart';

/// Live analyzer: source controls, level/spectrum panels, genre verdicts.
class AnalyzerPage extends StatefulWidget {
  const AnalyzerPage({super.key, required this.controller});

  final SessionController controller;

  @override
  State<AnalyzerPage> createState() => _AnalyzerPageState();
}

class _AnalyzerPageState extends State<AnalyzerPage> {
  List<AppSource> _apps = [];
  int? _sourcePid; // null = whole system audio

  SessionController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _refreshApps();
  }

  Future<void> _refreshApps() async {
    try {
      final apps = await _controller.listApps();
      if (mounted) setState(() => _apps = apps);
    } catch (e) {
      log('capture', 'listApps failed: $e');
      _controller.error.value = 'Cannot list apps: $e';
    }
  }

  void _start() {
    final name = _sourcePid == null
        ? 'system'
        : _apps
            .firstWhere((a) => a.pid == _sourcePid,
                orElse: () => AppSource(pid: _sourcePid!, name: '?'))
            .name;
    _controller.start(pid: _sourcePid, sourceName: name);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: Listenable.merge(
              [_controller.capturing, _controller.serverOk]),
          builder: (context, _) => TopBar(
            apps: _apps,
            sourcePid: _sourcePid,
            capturing: _controller.capturing.value,
            serverOk: _controller.serverOk.value,
            startedAt: _controller.sessionStartedAt,
            onSourceChanged: (v) => setState(() => _sourcePid = v),
            onSourcesOpened: _refreshApps,
            onStart: _start,
            onStop: _controller.stop,
          ),
        ),
        _ErrorBanner(
          error: _controller.error,
          permissionIssue: _controller.permissionIssue,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Panel(
                        title: 'level  ·  rms / peak',
                        child: WaveformView(wave: _controller.wave),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 3,
                      child: Panel(
                        title: 'spectrum  ·  20 Hz - 20 kHz',
                        child: SpectrumView(spectrum: _controller.spectrum),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Expanded(
                      child: Panel(
                        title: 'now  ·  what is playing (last ~7 s)',
                        child: AnimatedBuilder(
                          animation: Listenable.merge(
                              [_controller.result, _controller.capturing]),
                          builder: (context, _) => GenreDistributionView(
                            distribution: _controller.result.value?.recent,
                            accent: AppColors.accent,
                            placeholder: _controller.capturing.value
                                ? 'listening... first verdict in ~5s'
                                : 'select a source and press start',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Panel(
                        title: 'session  ·  verdict since track start',
                        child: AnimatedBuilder(
                          animation: Listenable.merge(
                              [_controller.result, _controller.capturing]),
                          builder: (context, _) {
                            final result = _controller.result.value;
                            return GenreDistributionView(
                              distribution: result?.session,
                              accent: AppColors.accent2,
                              placeholder: _controller.capturing.value
                                  ? 'accumulating...'
                                  : 'resets on start, source change or '
                                      'a silence gap',
                              footer: result == null
                                  ? null
                                  : '${result.windowsSeen} windows',
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        StatusBar(controller: _controller),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.permissionIssue});

  final ValueNotifier<String?> error;
  final ValueNotifier<bool> permissionIssue;

  static final _screenCaptureSettings = Uri.parse(
    'x-apple.systempreferences:com.apple.preference.security'
    '?Privacy_ScreenCapture',
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([error, permissionIssue]),
      builder: (context, _) {
        final message = error.value;
        if (message == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.warn, fontSize: 12),
                ),
              ),
              if (permissionIssue.value)
                TextButton(
                  onPressed: () => launchUrl(_screenCaptureSettings),
                  child: const Text(
                    'OPEN SETTINGS',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
