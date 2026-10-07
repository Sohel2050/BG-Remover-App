import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Copies working images from temp/cache storage (which the OS may clear
/// at any time) into the app's permanent documents directory, so Recent
/// Projects can be reopened later and brush sessions (keyed by file path)
/// remain valid across app restarts.
class ProjectStorage {
  static Future<Directory> _projectsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/projects');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot < path.lastIndexOf('/')) return 'jpg';
    return path.substring(dot + 1);
  }

  /// Copies [original] and [processed] into permanent storage under a
  /// shared unique id. Returns the new (permanent) files.
  static Future<({File original, File processed})> persistProject(
    File original,
    File processed,
  ) async {
    final dir = await _projectsDir();
    final id = DateTime.now().millisecondsSinceEpoch;

    final permOriginal = await original.copy(
      '${dir.path}/${id}_original.${_extensionOf(original.path)}',
    );
    final permProcessed = await processed.copy(
      '${dir.path}/${id}_processed.png',
    );
    return (original: permOriginal, processed: permProcessed);
  }

  /// Deletes a project's permanent files (ignores ones already missing).
  static Future<void> deleteProjectFiles(
    String originalPath,
    String processedPath,
  ) async {
    for (final path in [originalPath, processedPath]) {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    }
  }
}
