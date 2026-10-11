import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/edit_state.dart';
import '../services/ai_service.dart';
import '../services/image_ops.dart';
import '../services/image_decode.dart';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../services/prefs_service.dart';
import '../services/project_storage.dart';
import '../widgets/checkerboard_background.dart';
import '../widgets/brush_canvas.dart';
import '../widgets/before_after_slider.dart';
import 'package:image_picker/image_picker.dart';
import 'export_screen.dart';
import 'crop_screen.dart';
import '../widgets/levelplay_ads.dart';
import '../services/crop_service.dart';
import 'refine_export_screen.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({super.key});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  final AiService _aiService = AiService();
  final GlobalKey<BrushCanvasState> _canvasKey = GlobalKey<BrushCanvasState>();

  BrushMode _brushMode = BrushMode.move;
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
            Text('• Erase / Restore: draw with one finger'),
            SizedBox(height: 6),
            Text('• Move: drag to pan, pinch to zoom and check quality'),
            SizedBox(height: 6),
            Text('• Two fingers always pinch-zoom and pan'),
            SizedBox(height: 6),
            Text('• Restore brings back anything erased too far'),
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
      File file;
      try {
        // Pro finish: bake edits, smooth the cut-out border, then place it
        // on the chosen background.
        final baked = await canvasState.bakeTransparent();
        final px = await ImageDecode.rgbaFromFile(baked);
        int opaque = 0;
        for (int i = 3; i < px.rgba.length; i += 4) {
          if (px.rgba[i] > 8) opaque++;
        }
        if (opaque < 16) throw StateError('empty cut-out');
        final smoothPng =
            await _refineInIsolate(px.rgba, px.width, px.height, 0);
        final dir = await getTemporaryDirectory();
        final smoothFile = File(
            '${dir.path}/smooth_${DateTime.now().millisecondsSinceEpoch}.png');
        await smoothFile.writeAsBytes(smoothPng);
        file = await canvasState.exportComposite(
          background: _backgroundChoice,
          solidColor: _solidColor,
          customBackgroundFile: _customBgFile,
          subjectOverride: smoothFile,
        );
      } catch (_) {
        // Fall back to the plain export if the smoothing step fails.
        file = await canvasState.exportComposite(
          background: _backgroundChoice,
          solidColor: _solidColor,
          customBackgroundFile: _customBgFile,
        );
      }
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

  /// Crop the photo before removing the background.
  Future<void> _cropOriginal(EditState editState) async {
    final original = editState.originalImage;
    if (original == null) return;
    final rect = await Navigator.of(context).push<Rect>(
      MaterialPageRoute(builder: (_) => CropScreen(image: original)),
    );
    if (rect == null || !mounted) return;
    setState(() => _isExporting = true);
    try {
      final f = await CropService.cropPhoto(original, rect);
      editState.setOriginalImage(f);
    } catch (e) {
      _showSnack('Crop failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Crop the finished cut-out (with your edits) and the photo together.
  Future<void> _cropResult() async {
    final canvasState = _canvasKey.currentState;
    final editState = context.read<EditState>();
    final original = editState.originalImage;
    if (canvasState == null || original == null) return;
    final baked = await canvasState.bakeTransparent();
    if (!mounted) return;
    final rect = await Navigator.of(context).push<Rect>(
      MaterialPageRoute(builder: (_) => CropScreen(image: baked)),
    );
    if (rect == null || !mounted) return;
    setState(() => _isExporting = true);
    try {
      final p = await CropService.cropPng(baked, rect);
      final o = await CropService.cropPhoto(original, rect);
      final saved = await ProjectStorage.persistProject(o, p);
      editState.setOriginalImage(saved.original);
      editState.setProcessedImage(saved.processed);
    } catch (e) {
      _showSnack('Crop failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  static Future<Uint8List> _refineInIsolate(
      Uint8List rgba, int w, int h, int s) {
    return Isolate.run(() => refineEdgePng(rgba, w, h, s, 1));
  }

  /// Bakes the current edits, then shrinks the matte and removes colour
  /// fringes left from the old background.
  Future<void> _cleanEdges() async {
    final canvasState = _canvasKey.currentState;
    final editState = context.read<EditState>();
    final original = editState.originalImage;
    if (canvasState == null || original == null) return;
    double shrink = 2;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Clean edges'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Removes the leftover background border and tint.'),
              Slider(
                value: shrink,
                min: 0,
                max: 8,
                divisions: 8,
                label: '${shrink.round()} px',
                onChanged: (v) => setD(() => shrink = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isExporting = true);
    try {
      final baked = await canvasState.bakeTransparent();
      final decoded = await ImageDecode.rgbaFromFile(baked);
      final s = shrink.round();
      final png = await _refineInIsolate(
          decoded.rgba, decoded.width, decoded.height, s);
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/edge_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(png);
      final saved = await ProjectStorage.persistProject(original, f);
      editState.setOriginalImage(saved.original);
      editState.setProcessedImage(saved.processed);
    } catch (e) {
      _showSnack('Clean edges failed: $e');
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
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'reset') _canvasKey.currentState?.resetView();
                      if (v == 'edge') _cleanEdges();
                      if (v == 'crop') _cropResult();
                      if (v == 'clear') {
                        _canvasKey.currentState?.clearStrokes();
                        _refreshUndoRedo();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'crop', child: Text('Crop')),
                      PopupMenuItem(
                          value: 'edge', child: Text('Clean edges')),
                      PopupMenuItem(value: 'reset', child: Text('Reset zoom')),
                      PopupMenuItem(
                          value: 'clear', child: Text('Clear all edits')),
                    ],
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
          if (showControls && !_compareMode) _buildExportBar(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (processed == null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: editState.isProcessing || original == null
                                ? null
                                : () => _cropOriginal(editState),
                            icon: const Icon(Icons.crop),
                            label: const Text('Crop'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: editState.isProcessing || original == null
                                ? null
                                : () => _handleRemoveBackground(editState),
                            icon: const Icon(Icons.auto_fix_high),
                            label: const Text('Remove Background'),
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: editState.isProcessing || original == null
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      RefineExportScreen(initialFile: original),
                                ),
                              ),
                      child: const Text('Skip background removal and export'),
                    ),
                  ],
                ),
              ),
            ),
          const SafeArea(
            top: false,
            child: LevelPlayBanner(placementName: 'edit_banner'),
          ),
        ],
      ),
    );
  }

  Widget _buildExportBar() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isExporting ? null : _handleExport,
            icon: _isExporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download),
            label: Text(_isExporting ? 'Exporting...' : 'Export'),
          ),
        ),
      ),
    );
  }

  Widget _buildBrushControls() {
    final brushing = _brushMode != BrushMode.move;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<BrushMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: BrushMode.erase,
                  icon: Icon(Icons.auto_fix_normal, size: 18),
                  label: Text('Erase'),
                ),
                ButtonSegment(
                  value: BrushMode.restore,
                  icon: Icon(Icons.restore, size: 18),
                  label: Text('Restore'),
                ),
                ButtonSegment(
                  value: BrushMode.move,
                  icon: Icon(Icons.pan_tool_alt, size: 18),
                  label: Text('Move'),
                ),
              ],
              selected: {_brushMode},
              onSelectionChanged: (s) => setState(() => _brushMode = s.first),
            ),
          ),
          if (brushing)
            Row(
              children: [
                const Icon(Icons.brush, size: 18),
                Expanded(
                  child: Slider(
                    value: _brushSize,
                    min: 10,
                    max: 100,
                    onChanged: (v) => setState(() => _brushSize = v),
                  ),
                ),
                const Icon(Icons.blur_on, size: 18),
                Expanded(
                  child: Slider(
                    value: _edgeSoftness,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setState(() => _edgeSoftness = v),
                  ),
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Drag to pan, pinch to zoom',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBackgroundPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
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
    );
  }
}
