import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/edit_state.dart';
import '../services/prefs_service.dart';
import '../services/project_storage.dart';
import '../widgets/checkerboard_background.dart';
import 'edit_screen.dart';

/// Grid of past projects. Tap to reopen one in the editor (with its saved
/// brush strokes restored); long-press to delete it.
class RecentProjectsScreen extends StatefulWidget {
  const RecentProjectsScreen({super.key});

  @override
  State<RecentProjectsScreen> createState() => _RecentProjectsScreenState();
}

class _RecentProjectsScreenState extends State<RecentProjectsScreen> {
  final PrefsService _prefs = PrefsService();
  List<RecentProject> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _prefs.getRecentProjects();
    // Skip entries whose files no longer exist on disk.
    final existing = list
        .where((p) =>
            File(p.processedPath).existsSync() &&
            File(p.originalPath).existsSync())
        .toList();
    if (mounted) {
      setState(() {
        _projects = existing;
        _loading = false;
      });
    }
  }

  void _open(RecentProject project) {
    final editState = context.read<EditState>();
    editState.setOriginalImage(File(project.originalPath));
    editState.setProcessedImage(File(project.processedPath));
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditScreen()),
    );
  }

  Future<void> _confirmDelete(RecentProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: const Text('This removes the saved images and edits.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _prefs.removeRecentProject(project.processedPath);
    await ProjectStorage.deleteProjectFiles(
      project.originalPath,
      project.processedPath,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recent Projects')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? const Center(child: Text('No recent projects yet'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _projects.length,
                  itemBuilder: (context, index) {
                    final project = _projects[index];
                    return GestureDetector(
                      onTap: () => _open(project),
                      onLongPress: () => _confirmDelete(project),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CheckerboardBackground(
                          child: Image.file(
                            File(project.processedPath),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
