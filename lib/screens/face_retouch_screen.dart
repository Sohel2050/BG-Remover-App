import 'dart:io';
import 'package:flutter/material.dart';
import '../services/face_retouch_service.dart';
import '../widgets/before_after_slider.dart';
import '../widgets/tool_error.dart';
import 'export_screen.dart';

class FaceRetouchScreen extends StatefulWidget {
  final File image;
  const FaceRetouchScreen({super.key, required this.image});

  @override
  State<FaceRetouchScreen> createState() => _FaceRetouchScreenState();
}

class _FaceRetouchScreenState extends State<FaceRetouchScreen> {
  final FaceRetouchService _service = FaceRetouchService();
  File? _result;
  double _strength = 0.6;
  bool _busy = false;

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final out = await _service.smoothSkin(widget.image, strength: _strength);
      if (mounted) setState(() => _result = out);
    } catch (e) {
      showToolError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skin Smoothing'),
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
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _result == null
                    ? Image.file(widget.image, fit: BoxFit.contain)
                    : BeforeAfterSlider(
                        before: widget.image,
                        after: Image.file(_result!, fit: BoxFit.contain),
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('Strength'),
                      Expanded(
                        child: Slider(
                          value: _strength,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _strength = v),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _apply,
                      icon: const Icon(Icons.face_retouching_natural),
                      label: Text(_result == null ? 'Apply' : 'Re-apply'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Smooths skin-toned areas by color (not face detection), '
                    'so hands and skin-colored objects can soften too.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
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
