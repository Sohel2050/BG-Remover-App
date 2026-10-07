import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/upscale_service.dart';
import '../widgets/tool_error.dart';
import 'export_screen.dart';

class UpscaleScreen extends StatefulWidget {
  final File image;
  const UpscaleScreen({super.key, required this.image});

  @override
  State<UpscaleScreen> createState() => _UpscaleScreenState();
}

class _UpscaleScreenState extends State<UpscaleScreen> {
  final UpscaleService _service = UpscaleService();
  Size? _size;
  File? _result;
  bool _busy = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadSize() async {
    final codec = await ui.instantiateImageCodec(
      await widget.image.readAsBytes(),
    );
    final frame = await codec.getNextFrame();
    final s = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    codec.dispose();
    if (mounted) setState(() => _size = s);
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final out = await _service.upscale(
        widget.image,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _result = out);
    } catch (e) {
      showToolError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tooBig = _size != null &&
        (_size!.width > UpscaleService.maxInputSide ||
            _size!.height > UpscaleService.maxInputSide);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upscale 4×'),
        actions: [
          if (_result != null)
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ExportScreen(exportedFile: _result!),
              )),
              child: const Text('Done'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Image.file(
                _result ?? widget.image,
                fit: BoxFit.contain,
                // Keep the on-screen preview light even for a 4x result.
                cacheWidth: 1400,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_size != null)
                    Text(
                      _result == null
                          ? 'Current: ${_size!.width.toInt()}×${_size!.height.toInt()}  →  '
                              '${(_size!.width * 4).toInt()}×${(_size!.height * 4).toInt()}'
                          : 'Done: ${(_size!.width * 4).toInt()}×${(_size!.height * 4).toInt()}',
                    ),
                  if (tooBig)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Works on images up to ${UpscaleService.maxInputSide}px on the longest side.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (_busy) ...[
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 6),
                    Text('${(_progress * 100).round()}%'),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: (_size == null || tooBig) ? null : _run,
                        icon: const Icon(Icons.hd),
                        label: Text(_result == null ? 'Upscale' : 'Run again'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
