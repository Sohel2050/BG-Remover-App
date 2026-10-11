import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/edit_state.dart';
import '../services/prefs_service.dart';
import '../services/project_storage.dart';
import '../services/subject_detection_service.dart';
import '../widgets/tool_error.dart';
import '../widgets/levelplay_ads.dart';
import 'edit_screen.dart';

/// Detects individual people/objects, lets you tap the ones to keep, then
/// hands the cut-out to the normal editor (brush refine, backgrounds,
/// export).
class SubjectSelectScreen extends StatefulWidget {
  final File image;
  const SubjectSelectScreen({super.key, required this.image});

  @override
  State<SubjectSelectScreen> createState() => _SubjectSelectScreenState();
}

class _SubjectSelectScreenState extends State<SubjectSelectScreen> {
  final SubjectDetectionService _service = SubjectDetectionService();
  SubjectDetectionResult? _result;
  final Set<int> _selected = {};
  bool _busy = true;
  String _busyLabel = 'Finding subjects…';

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    try {
      final r = await _service.detect(widget.image);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      showToolError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extract() async {
    final result = _result!;
    setState(() {
      _busy = true;
      _busyLabel = 'Cutting out…';
    });
    try {
      final cutout = await _service.extract(result, _selected);
      final saved = await ProjectStorage.persistProject(
        result.workingImageFile,
        cutout,
      );
      if (!mounted) return;
      final editState = context.read<EditState>();
      editState.setOriginalImage(saved.original);
      editState.setProcessedImage(saved.processed);
      await PrefsService().addRecentProject(
        RecentProject(
          originalPath: saved.original.path,
          processedPath: saved.processed.path,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const EditScreen()),
      );
    } catch (e) {
      showToolError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Select Subjects')),
      bottomNavigationBar: const SafeArea(
        child: LevelPlayBanner(placementName: 'subject_banner'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _busy
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(_busyLabel),
                      ],
                    ),
                  )
                : result == null
                    ? const Center(child: Text('Detection failed'))
                    : result.subjects.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No people or objects were detected. Try the '
                                'regular Remove Background from the home screen.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : _buildOverlay(result),
          ),
          if (!_busy && result != null && result.subjects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selected.isEmpty ? null : _extract,
                    icon: const Icon(Icons.content_cut),
                    label: Text(
                      _selected.isEmpty
                          ? 'Tap the subjects to keep'
                          : 'Keep ${_selected.length} selected',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlay(SubjectDetectionResult result) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imgSize = Size(result.width.toDouble(), result.height.toDouble());
        final fitted = applyBoxFit(BoxFit.contain, imgSize, constraints.biggest);
        final rect = Alignment.center.inscribe(
          fitted.destination,
          Offset.zero & constraints.biggest,
        );
        final k = rect.width / result.width;
        final primary = Theme.of(context).colorScheme.primary;

        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Image.file(result.workingImageFile, fit: BoxFit.fill),
            ),
            for (final s in result.subjects)
              Positioned(
                left: rect.left + s.box.left * k,
                top: rect.top + s.box.top * k,
                width: s.box.width * k,
                height: s.box.height * k,
                child: GestureDetector(
                  onTap: () => setState(() {
                    if (!_selected.remove(s.id)) _selected.add(s.id);
                  }),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _selected.contains(s.id)
                          ? primary.withOpacity(0.25)
                          : Colors.transparent,
                      border: Border.all(
                        color: _selected.contains(s.id) ? primary : Colors.white,
                        width: _selected.contains(s.id) ? 3 : 1.5,
                      ),
                    ),
                    alignment: Alignment.topLeft,
                    child: Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      child: Text(
                        '${s.label} ${(s.score * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
