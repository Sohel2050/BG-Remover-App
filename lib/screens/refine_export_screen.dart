import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/export_utils.dart';
import '../services/advanced_effects.dart';
import '../services/sky_segmentation_service.dart';
import '../widgets/checkerboard_background.dart';
import 'export_screen.dart';

/// Extended editing step (Part 8) between the raw export and final
/// save/share: rotate, crop to a social-media or ID-photo preset, and
/// tweak brightness/contrast. Each action re-saves to a new temp file so
/// the user can keep stacking adjustments before moving on to Export.
class RefineExportScreen extends StatefulWidget {
  final File initialFile;

  const RefineExportScreen({super.key, required this.initialFile});

  @override
  State<RefineExportScreen> createState() => _RefineExportScreenState();
}

class _RefineExportScreenState extends State<RefineExportScreen> {
  late File _currentFile;
  bool _isBusy = false;
  double _brightness = 0;
  double _contrast = 0;
  final SkySegmentationService _skyService = SkySegmentationService();

  @override
  void initState() {
    super.initState();
    _currentFile = widget.initialFile;
  }

  @override
  void dispose() {
    _skyService.dispose();
    super.dispose();
  }

  Future<void> _run(Future<File> Function() action) async {
    setState(() => _isBusy = true);
    try {
      final result = await action();
      setState(() => _currentFile = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Operation failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _applyFilters() async {
    if (_brightness == 0 && _contrast == 0) return;
    await _run(
      () => ExportUtils.applyBrightnessContrast(
        _currentFile,
        brightness: _brightness,
        contrast: _contrast,
      ),
    );
    setState(() {
      _brightness = 0;
      _contrast = 0;
    });
  }

  Future<void> _pickPreset(List<SizePreset> presets) async {
    final preset = await showModalBottomSheet<SizePreset>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: presets
            .map(
              (p) => ListTile(
                title: Text(p.label),
                subtitle: Text('${p.width} x ${p.height}px'),
                onTap: () => Navigator.pop(ctx, p),
              ),
            )
            .toList(),
      ),
    );
    if (preset == null) return;
    await _run(
      () => ExportUtils.cropToAspectAndResize(
        _currentFile,
        targetWidth: preset.width,
        targetHeight: preset.height,
      ),
    );
  }

  Future<void> _promptForText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Text Behind Subject'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter text'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    await _run(
      () => AdvancedEffects.addTextBehindSubject(
        _currentFile,
        text: text,
        textColor: Colors.white,
        fontSize: 72,
      ),
    );
  }

  Future<void> _handleAddFrame() async {
    final style = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.crop_square),
            title: const Text('Solid Border'),
            onTap: () => Navigator.pop(ctx, 'solid'),
          ),
          ListTile(
            leading: const Icon(Icons.filter_none),
            title: const Text('Double Line'),
            onTap: () => Navigator.pop(ctx, 'double'),
          ),
          ListTile(
            leading: const Icon(Icons.photo),
            title: const Text('Polaroid Style'),
            onTap: () => Navigator.pop(ctx, 'polaroid'),
          ),
        ],
      ),
    );
    if (style == null) return;
    await _run(() => AdvancedEffects.addFrame(_currentFile, style: style));
  }

  Future<void> _handleWatermark() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add Watermark'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'text'),
            child: const Text('Text (e.g. your name)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'logo'),
            child: const Text('Logo image from gallery'),
          ),
        ],
      ),
    );

    if (choice == 'text') {
      final controller = TextEditingController();
      final text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Watermark Text'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (text == null || text.trim().isEmpty) return;
      await _run(
        () => AdvancedEffects.addWatermark(_currentFile, text: text),
      );
    } else if (choice == 'logo') {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      await _run(
        () => AdvancedEffects.addWatermark(
          _currentFile,
          logoFile: File(picked.path),
        ),
      );
    }
  }

  Future<void> _handleReplaceSky() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    await _run(
      () => _skyService.replaceSky(_currentFile, File(picked.path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Refine'),
        actions: [
          TextButton(
            onPressed: _isBusy
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ExportScreen(exportedFile: _currentFile),
                      ),
                    ),
            child: const Text('Next'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _isBusy
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: CheckerboardBackground(
                        child: Image.file(_currentFile),
                      ),
                    ),
            ),
          ),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _isBusy ? null : () => _run(() => ExportUtils.rotate90(_currentFile)),
                  icon: const Icon(Icons.rotate_right),
                  label: const Text('Rotate 90°'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isBusy
                      ? null
                      : () => _run(() => ExportUtils.autoCropToSubject(_currentFile)),
                  icon: const Icon(Icons.center_focus_strong),
                  label: const Text('Auto Crop'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed:
                      _isBusy ? null : () => _pickPreset(ExportUtils.socialPresets),
                  icon: const Icon(Icons.crop),
                  label: const Text('Social Size'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed:
                      _isBusy ? null : () => _pickPreset(ExportUtils.idPhotoPresets),
                  icon: const Icon(Icons.badge),
                  label: const Text('ID Photo Size'),
                ),
              ],
            ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isBusy
                      ? null
                      : () => _run(() => AdvancedEffects.autoEnhance(_currentFile)),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Auto Enhance'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isBusy
                      ? null
                      : () => _run(() => AdvancedEffects.addDropShadow(_currentFile)),
                  icon: const Icon(Icons.blur_circular),
                  label: const Text('Shadow'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isBusy
                      ? null
                      : () => _run(() => AdvancedEffects.addStickerOutline(
                            _currentFile,
                            outlineColor: Colors.white,
                          )),
                  icon: const Icon(Icons.emoji_emotions_outlined),
                  label: const Text('Sticker Outline'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _promptForText,
                  icon: const Icon(Icons.text_fields),
                  label: const Text('Text Behind'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _handleReplaceSky,
                  icon: const Icon(Icons.wb_cloudy),
                  label: const Text('Replace Sky'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _handleWatermark,
                  icon: const Icon(Icons.branding_watermark),
                  label: const Text('Watermark'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _handleAddFrame,
                  icon: const Icon(Icons.filter_frames),
                  label: const Text('Frame'),
                ),
              ],
            ),
            ),
            const SizedBox(height: 12),
            const Text('Brightness', style: TextStyle(fontSize: 12)),
            Slider(
              value: _brightness,
              min: -100,
              max: 100,
              onChanged: (v) => setState(() => _brightness = v),
              onChangeEnd: (_) => _applyFilters(),
            ),
            const Text('Contrast', style: TextStyle(fontSize: 12)),
            Slider(
              value: _contrast,
              min: -100,
              max: 100,
              onChanged: (v) => setState(() => _contrast = v),
              onChangeEnd: (_) => _applyFilters(),
            ),
          ],
        ),
      ),
    );
  }
}
