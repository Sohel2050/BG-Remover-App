import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/edit_state.dart';
import '../services/ai_service.dart';
import '../services/prefs_service.dart';
import '../services/project_storage.dart';
import '../widgets/checkerboard_background.dart';
import '../widgets/brush_canvas.dart';
import '../widgets/before_after_slider.dart';
import 'package:image_picker/image_picker.dart';
import 'export_screen.dart';
import 'refine_export_screen.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({super.key});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  final AiService _aiService = AiService();
  final GlobalKey<BrushCanvasState> _canvasKey = GlobalKey<BrushCanvasState>();

  BrushMode _brushMode = BrushMode.erase;
  double _brushSize = 40;
  double _edgeSoftness = 0.3;
  bool _canUndo = false;
  bool _canRedo = false;

  BackgroundChoice _backgroundChoice = BackgroundChoice.transparent;
  Color _solidColor = Colors.white;
  File? _customBgFile;
  bool _compareMode = false;
  bool _isExporting = false;

  static const List<Color> _colorPresets = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.amber,
  ];

  @override
  void dispose() {
    _aiService.dispose();
    super.dispose();
  }

  Future<void> _handleRemoveBackground(EditState editState) async {
    final original = editState.originalImage;
    if (original == null) return;

    editState.setProcessing(true);
    try {
      final resultFile = await _aiService.removeBackground(original);

      // Copy into permanent storage so this project survives the OS
      // clearing temp/cache, can be reopened from Recent Projects, and its
      // saved brush session (keyed by file path) stays valid.
      final saved = await ProjectStorage.persistProject(original, resultFile);
      editState.setOriginalImage(saved.original);
      editState.setProcessedImage(saved.processed);

      await PrefsService().addRecentProject(
        RecentProject(
          originalPath: saved.original.path,
          processedPath: saved.processed.path,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _maybeShowEditTip();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Background removal failed: $e')),
        );
      }
    } finally {
      editState.setProcessing(false);
    }
  }

  /// One-time usage tip shown the first time the brush editor appears.
  Future<void> _maybeShowEditTip() async {
    final prefs = PrefsService();
    if (await prefs.hasSeenTip('edit_screen')) return;
    await prefs.markTipSeen('edit_screen');
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick tips'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• One finger: draw with the brush'),
            SizedBox(height: 6),
            Text('• Two fingers: pinch to zoom, drag to pan'),
            SizedBox(height: 6),
            Text('• Erase removes parts, Restore brings the original back'),
            SizedBox(height: 6),
            Text('• Undo/Redo are at the top; your work is saved automatically'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _refreshUndoRedo() {
    final state = _canvasKey.currentState;
    if (state == null) return;
    setState(() {
      _canUndo = state.canUndo;
      _canRedo = state.canRedo;
    });
  }

  Future<void> _handleExport() async {
    final canvasState = _canvasKey.currentState;
    if (canvasState == null) return;

    setState(() => _isExporting = true);
    try {
      final file = await canvasState.exportComposite(
        background: _backgroundChoice,
        solidColor: _solidColor,
        customBackgroundFile: _customBgFile,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RefineExportScreen(initialFile: file),
        ),
      );
    } catch (e) {
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// The subject (processed image + live brush edits) with whatever
  /// backdrop is currently selected behind it. Transparent areas of the
  /// subject layer naturally reveal this backdrop (see BrushCanvas docs).
  Widget _buildCanvasWithBackground(File original, File processed) {
    final canvas = BrushCanvas(
      key: _canvasKey,
      originalImageFile: original,
      processedImageFile: processed,
      mode: _brushMode,
      brushSize: _brushSize,
      edgeSoftness: _edgeSoftness,
      onStrokesChanged: (_) => _refreshUndoRedo(),
      // Keyed by the processed file's path. Processed images now live in
      // permanent storage (see ProjectStorage), so brush strokes are
      // restored even after the app is fully closed and reopened from
      // Recent Projects.
      sessionKey: processed.path,
    );

    switch (_backgroundChoice) {
      case BackgroundChoice.transparent:
        return CheckerboardBackground(child: canvas);
      case BackgroundChoice.solid:
        return Container(color: _solidColor, child: canvas);
      case BackgroundChoice.blur:
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Image.file(original, fit: BoxFit.cover),
            ),
            canvas,
          ],
        );
      case BackgroundChoice.custom:
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_customBgFile != null)
              Image.file(_customBgFile!, fit: BoxFit.cover)
            else
              const ColoredBox(color: Colors.grey),
            canvas,
          ],
        );
    }
  }

  Widget _buildBody(File? original, File? processed, bool isProcessing) {
    if (isProcessing) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Removing background...'),
        ],
      );
    }

    if (processed == null) {
      return original == null
          ? const Text('No image selected')
          : Image.file(original);
    }

    if (_compareMode) {
      return BeforeAfterSlider(
        before: original!,
        after: _buildCanvasWithBackground(original, processed),
      );
    }

    return _buildCanvasWithBackground(original!, processed);
  }

  @override
  Widget build(BuildContext context) {
    final editState = context.watch<EditState>();
    final original = editState.originalImage;
    final processed = editState.processedImage;
    final showControls = processed != null && !editState.isProcessing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit'),
        actions: showControls
            ? [
                IconButton(
                  icon: Icon(
                    _compareMode ? Icons.compare : Icons.compare_arrows,
                  ),
                  tooltip: 'Before / after compare',
                  onPressed: () =>
                      setState(() => _compareMode = !_compareMode),
                ),
                if (!_compareMode) ...[
                  IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: 'Undo',
                    onPressed: _canUndo
                        ? () {
                            _canvasKey.currentState?.undo();
                            _refreshUndoRedo();
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo),
                    tooltip: 'Redo',
                    onPressed: _canRedo
                        ? () {
                            _canvasKey.currentState?.redo();
                            _refreshUndoRedo();
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_out_map),
                    tooltip: 'Reset zoom',
                    onPressed: () => _canvasKey.currentState?.resetView(),
                  ),
                ],
              ]
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _buildBody(original, processed, editState.isProcessing),
            ),
          ),
          if (showControls && !_compareMode) _buildBrushControls(),
          if (showControls) _buildBackgroundPicker(),
        ],
      ),
      floatingActionButton: processed == null
          ? FloatingActionButton.extended(
              onPressed: editState.isProcessing
                  ? null
                  : () => _handleRemoveBackground(editState),
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Remove Background'),
            )
          : (_compareMode
              ? null
              : FloatingActionButton.extended(
                  onPressed: _isExporting ? null : _handleExport,
                  icon: _isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download),
                  label: Text(_isExporting ? 'Exporting...' : 'Export'),
                )),
    );
  }

  Widget _buildBrushControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.brush, size: 18),
                Expanded(
                  child: Slider(
                    value: _brushSize,
                    min: 10,
                    max: 100,
                    label: _brushSize.round().toString(),
                    onChanged: (v) => setState(() => _brushSize = v),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.blur_on, size: 18),
                Expanded(
                  child: Slider(
                    value: _edgeSoftness,
                    min: 0,
                    max: 1,
                    label: '${(_edgeSoftness * 100).round()}%',
                    onChanged: (v) => setState(() => _edgeSoftness = v),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ChoiceChip(
                  label: const Text('Erase'),
                  avatar: const Icon(Icons.auto_fix_normal, size: 18),
                  selected: _brushMode == BrushMode.erase,
                  onSelected: (_) =>
                      setState(() => _brushMode = BrushMode.erase),
                ),
                ChoiceChip(
                  label: const Text('Restore'),
                  avatar: const Icon(Icons.restore, size: 18),
                  selected: _brushMode == BrushMode.restore,
                  onSelected: (_) =>
                      setState(() => _brushMode = BrushMode.restore),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'One finger: draw · Two fingers: pinch to zoom / pan',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12)],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Background', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Transparent'),
                  selected: _backgroundChoice == BackgroundChoice.transparent,
                  onSelected: (_) => setState(
                    () => _backgroundChoice = BackgroundChoice.transparent,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Solid'),
                  selected: _backgroundChoice == BackgroundChoice.solid,
                  onSelected: (_) => setState(
                    () => _backgroundChoice = BackgroundChoice.solid,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Blur'),
                  selected: _backgroundChoice == BackgroundChoice.blur,
                  onSelected: (_) => setState(
                    () => _backgroundChoice = BackgroundChoice.blur,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Custom'),
                  selected: _backgroundChoice == BackgroundChoice.custom,
                  onSelected: (_) async {
                    final picked = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                    );
                    if (picked == null) return;
                    setState(() {
                      _customBgFile = File(picked.path);
                      _backgroundChoice = BackgroundChoice.custom;
                    });
                  },
                ),
              ],
            ),
            if (_backgroundChoice == BackgroundChoice.solid) ...[
              const SizedBox(height: 8),
              Row(
                children: _colorPresets.map((color) {
                  final isSelected = color.value == _solidColor.value;
                  return GestureDetector(
                    onTap: () => setState(() => _solidColor = color),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
