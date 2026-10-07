import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ads_service.dart';
import '../widgets/checkerboard_background.dart';

/// Final step: preview the exported PNG, then save it to the device
/// gallery or share it via the OS share sheet.
class ExportScreen extends StatefulWidget {
  final File exportedFile;

  const ExportScreen({super.key, required this.exportedFile});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Show an interstitial once the user lands on the final export
    // preview — a natural pause point, not mid-edit.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => AdsService.instance.showInterstitial(placement: 'export_screen'),
    );
  }

  Future<void> _saveToGallery() async {
    setState(() => _isSaving = true);
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          _showMessage('Gallery permission denied');
          return;
        }
      }
      await Gal.putImage(widget.exportedFile.path, album: 'BG Remover');
      _showMessage('Saved to gallery');
    } catch (e) {
      _showMessage('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(widget.exportedFile.path)],
          text: 'Background removed with BG Remover',
        ),
      );
    } catch (e) {
      _showMessage('Share failed: $e');
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CheckerboardBackground(
                  child: Image.file(widget.exportedFile),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveToGallery,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Save to Gallery'),
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
