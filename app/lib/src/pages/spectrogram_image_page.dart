import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../genre_client.dart';
import '../logger.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// Upload a rendered spectrogram image; the local model classifies it.
class SpectrogramImagePage extends StatefulWidget {
  const SpectrogramImagePage({super.key, required this.client});

  final GenreClient client;

  @override
  State<SpectrogramImagePage> createState() => _SpectrogramImagePageState();
}

class _SpectrogramImagePageState extends State<SpectrogramImagePage> {
  Uint8List? _image;
  String? _fileName;
  ImageAnalysis? _result;
  bool _busy = false;
  String? _error;

  Future<void> _pickImage() async {
    const group = XTypeGroup(
      label: 'images',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _image = bytes;
      _fileName = file.name;
      _result = null;
      _error = null;
    });
    log('image', 'picked ${file.name} (${bytes.length} bytes)');
  }

  Future<void> _analyze() async {
    final image = _image;
    if (image == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.analyzeImage(image);
      log('image', 'verdict: ${result.windows} windows');
      if (mounted) setState(() => _result = result);
    } catch (e) {
      log('image', 'analyze failed: $e');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Panel(
            title: 'spectrogram image',
            child: _ImageSide(
              image: _image,
              fileName: _fileName,
              busy: _busy,
              error: _error,
              onPick: _pickImage,
              onAnalyze: _analyze,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Panel(
            title: 'model verdict  ·  same CNN as live',
            child: _ResultSide(result: _result, busy: _busy),
          ),
        ),
      ],
    );
  }
}

class _ImageSide extends StatelessWidget {
  const _ImageSide({
    required this.image,
    required this.fileName,
    required this.busy,
    required this.error,
    required this.onPick,
    required this.onAnalyze,
  });

  final Uint8List? image;
  final String? fileName;
  final bool busy;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: image == null
              ? Center(
                  child: Text(
                    'pick a spectrogram image (png / jpg / webp)\n'
                    'plain spectrogram works best: no axes, no colorbar',
                    textAlign: TextAlign.center,
                    style: AppText.mono.copyWith(fontSize: 12, height: 1.6),
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.panelBorder),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.memory(image!, fit: BoxFit.contain),
                  ),
                ),
        ),
        if (fileName != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(fileName!, style: AppText.mono),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            _ActionButton(label: 'PICK IMAGE', onTap: busy ? null : onPick),
            const SizedBox(width: 10),
            _ActionButton(
              label: busy ? 'ANALYZING...' : 'ANALYZE',
              accent: true,
              onTap: busy || image == null ? null : onAnalyze,
            ),
            const SizedBox(width: 12),
            if (error != null)
              Expanded(
                child: Text(
                  error!,
                  style: const TextStyle(color: AppColors.warn, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ResultSide extends StatelessWidget {
  const _ResultSide({required this.result, required this.busy});

  final ImageAnalysis? result;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accent,
          ),
        ),
      );
    }
    final r = result;
    if (r == null) {
      return Center(
        child: Text(
          'no verdict yet',
          style: AppText.mono.copyWith(fontSize: 12),
        ),
      );
    }

    final entries = r.distribution.entries.toList()
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
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(best.value * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 16, color: AppColors.accent),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) => _PredictionRow(
              genre: entries[i].key,
              probability: entries[i].value,
            ),
          ),
        ),
        Text('windows analyzed: ${r.windows}', style: AppText.mono),
      ],
    );
  }
}

class _PredictionRow extends StatelessWidget {
  const _PredictionRow({required this.genre, required this.probability});

  final String genre;
  final double probability;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: probability.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 9,
                  backgroundColor: AppColors.grid,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${(probability * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: AppText.monoBright,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.dim
        : (accent ? AppColors.accent : AppColors.text);
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(4),
            color: accent && onTap != null
                ? AppColors.accent.withValues(alpha: 0.10)
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
