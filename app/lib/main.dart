import 'package:flutter/material.dart';

import 'src/audio_capture.dart';
import 'src/genre_client.dart';
import 'src/pages/analyzer_page.dart';
import 'src/pages/spectrogram_image_page.dart';
import 'src/session_controller.dart';
import 'src/theme.dart';

const serverUrl = 'http://127.0.0.1:8000';

void main() => runApp(const GenreApp());

class GenreApp extends StatelessWidget {
  const GenreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Genre Analyzer',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final SessionController _controller;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _controller = SessionController(
      capture: AudioCapture(),
      client: GenreClient(serverUrl),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('GENRE ANALYZER', style: AppText.title),
                const SizedBox(width: 24),
                _TabButton(
                  label: 'LIVE',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                const SizedBox(width: 8),
                _TabButton(
                  label: 'SPECTROGRAM',
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  AnalyzerPage(controller: _controller),
                  SpectrogramImagePage(client: _controller.client),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.dim;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.panelBorder,
            ),
            borderRadius: BorderRadius.circular(4),
            color: selected
                ? AppColors.accent.withValues(alpha: 0.10)
                : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
