import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/checkerboard_background.dart';
import 'export_screen.dart';

/// Combines 2-6 already-processed (background-removed) images into a
/// single grid collage. Pick images that were already exported with a
/// transparent or solid background from the main flow.
class CollageScreen extends StatefulWidget {
  const CollageScreen({super.key});

  @override
  State<CollageScreen> createState() => _CollageScreenState();
}

class _CollageScreenState extends State<CollageScreen> {
  final List<File> _images = [];
  bool _isBuilding = false;

  Future<void> _addImages() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 100);
    if (picked.isEmpty) return;
    setState(() {
      _images.addAll(picked.map((x) => File(x.path)).take(6 - _images.length));
    });
  }

  int get _columns => _images.length <= 2 ? _images.length.clamp(1, 2) : 2;

  Future<void> _buildCollage() async {
    if (_images.length < 2) return;
    setState(() => _isBuilding = true);
    try {
      const cellSize = 800.0;
      final rows = (_images.length / _columns).ceil();
      final canvasSize = Size(cellSize * _columns, cellSize * rows);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Offset.zero & canvasSize);
      canvas.drawRect(
        Offset.zero & canvasSize,
        Paint()..color = Colors.white,
      );

      for (int i = 0; i < _images.length; i++) {
        final bytes = await _images[i].readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final image = frame.image;

        final col = i % _columns;
        final row = i ~/ _columns;
        final cellRect = Rect.fromLTWH(
          col * cellSize,
          row * cellSize,
          cellSize,
          cellSize,
        );

        // Fit each image into its cell, preserving aspect ratio.
        final imgSize = Size(image.width.toDouble(), image.height.toDouble());
        final fitted = applyBoxFit(BoxFit.contain, imgSize, Size(cellSize, cellSize));
        final destSize = fitted.destination;
        final destOffset = Offset(
          cellRect.left + (cellSize - destSize.width) / 2,
          cellRect.top + (cellSize - destSize.height) / 2,
        );
        canvas.drawImageRect(
          image,
          Offset.zero & imgSize,
          destOffset & destSize,
          Paint(),
        );
      }

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(
        canvasSize.width.round(),
        canvasSize.height.round(),
      );
      final byteData =
          await rendered.toByteData(format: ui.ImageByteFormat.png);
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/collage_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData!.buffer.asUint8List());

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ExportScreen(exportedFile: file)),
      );
    } finally {
      if (mounted) setState(() => _isBuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collage Maker')),
      body: Column(
        children: [
          Expanded(
            child: _images.isEmpty
                ? Center(
                    child: FilledButton.icon(
                      onPressed: _addImages,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('Add Images (2-6)'),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _images.length,
                    itemBuilder: (context, index) => CheckerboardBackground(
                      child: Image.file(_images[index], fit: BoxFit.cover),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_images.isNotEmpty && _images.length < 6)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addImages,
                      icon: const Icon(Icons.add),
                      label: const Text('Add More'),
                    ),
                  ),
                if (_images.isNotEmpty) const SizedBox(width: 12),
                if (_images.length >= 2)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isBuilding ? null : _buildCollage,
                      icon: _isBuilding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.dashboard),
                      label: const Text('Create Collage'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
