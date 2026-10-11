import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ai_service.dart';
import '../services/pdf_export_service.dart';
import '../widgets/checkerboard_background.dart';
import '../widgets/levelplay_ads.dart';

/// Batch mode: pick several images, run AI background removal on each
/// automatically (no manual brush touch-up — that's the single-image flow
/// in EditScreen), then save all results to the gallery at once.
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchJobResult {
  final File original;
  File? processed;
  String? error;
  _BatchJobResult(this.original);
}

class _BatchScreenState extends State<BatchScreen> {
  final AiService _aiService = AiService();
  final List<_BatchJobResult> _jobs = [];
  bool _isProcessing = false;
  bool _isSavingAll = false;
  bool _isExportingPdf = false;

  @override
  void dispose() {
    _aiService.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;

    setState(() {
      _jobs
        ..clear()
        ..addAll(picked.map((x) => _BatchJobResult(File(x.path))));
    });

    await _processAll();
  }

  Future<void> _processAll() async {
    setState(() => _isProcessing = true);
    for (final job in _jobs) {
      try {
        final result = await _aiService.removeBackground(job.original);
        setState(() => job.processed = result);
      } catch (e) {
        setState(() => job.error = e.toString());
      }
    }
    setState(() => _isProcessing = false);
  }

  Future<void> _saveAllToGallery() async {
    setState(() => _isSavingAll = true);
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess && !await Gal.requestAccess()) {
        _showMessage('Gallery permission denied');
        return;
      }
      int saved = 0;
      for (final job in _jobs) {
        if (job.processed == null) continue;
        await Gal.putImage(job.processed!.path, album: 'BG Remover');
        saved++;
      }
      _showMessage('Saved $saved image(s) to gallery');
    } catch (e) {
      _showMessage('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSavingAll = false);
    }
  }

  Future<void> _exportAsPdf() async {
    final processedFiles =
        _jobs.where((j) => j.processed != null).map((j) => j.processed!).toList();
    if (processedFiles.isEmpty) return;

    setState(() => _isExportingPdf = true);
    try {
      final pdfFile = await PdfExportService.createPdf(processedFiles);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(pdfFile.path)], text: 'Exported images'),
      );
    } catch (e) {
      _showMessage('PDF export failed: $e');
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = _jobs.where((j) => j.processed != null).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Batch Process')),
      body: _jobs.isEmpty
          ? Center(
              child: FilledButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.photo_library),
                label: const Text('Select Multiple Images'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _isProcessing
                        ? 'Processing $doneCount / ${_jobs.length}...'
                        : '$doneCount / ${_jobs.length} done',
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _jobs.length,
                    itemBuilder: (context, index) {
                      final job = _jobs[index];
                      if (job.error != null) {
                        return Container(
                          color: Colors.red.shade50,
                          child: Center(
                            child: Text(
                              'Failed',
                              style: TextStyle(color: Colors.red.shade900),
                            ),
                          ),
                        );
                      }
                      if (job.processed == null) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      return CheckerboardBackground(
                        child: Image.file(job.processed!, fit: BoxFit.cover),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: FilledButton.icon(
                    onPressed: (_isProcessing || _isSavingAll || doneCount == 0)
                        ? null
                        : _saveAllToGallery,
                    icon: _isSavingAll
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text('Save All ($doneCount) to Gallery'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: OutlinedButton.icon(
                    onPressed: (_isProcessing || _isExportingPdf || doneCount == 0)
                        ? null
                        : _exportAsPdf,
                    icon: _isExportingPdf
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf),
                    label: Text('Export All ($doneCount) as PDF'),
                  ),
                ),
                const LevelPlayMrec(placementName: 'batch_mrec'),
                const SizedBox(height: 8),
              ],
            ),
    );
  }
}
