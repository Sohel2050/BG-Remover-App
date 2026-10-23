import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/edit_state.dart';
import '../screens/edit_screen.dart';

/// Global navigator key so we can open screens without a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Handles images sent to the app via Android "Share", "Send with" and
/// "Open with": loads the image into [EditState] and opens the editor.
class SharedImageService {
  SharedImageService._();
  static final SharedImageService instance = SharedImageService._();

  static const MethodChannel _channel =
      MethodChannel('com.albonik.bgremover/share');

  bool _started = false;
  bool _ready = false; // true once the home screen is showing
  bool _busy = false;

  void start() {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedImages') await _drain();
    });
  }

  /// Call once the app can show screens (home visible, onboarding done).
  void markReady() {
    _ready = true;
    _drain();
  }

  Future<void> _drain() async {
    if (!_ready || _busy) return;
    _busy = true;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getSharedImages');
      final paths = (raw ?? const []).cast<String>();
      if (paths.isEmpty) return;
      _open(paths);
    } catch (e) {
      debugPrint('Shared image handling failed: $e');
    } finally {
      _busy = false;
    }
  }

  void _open(List<String> paths) {
    final nav = appNavigatorKey.currentState;
    final ctx = appNavigatorKey.currentContext;
    if (nav == null || ctx == null) return;

    final file = File(paths.first);
    if (!file.existsSync()) return;

    // Back to home, then open the editor with the shared image.
    nav.popUntil((r) => r.isFirst);
    Provider.of<EditState>(ctx, listen: false).setOriginalImage(file);
    nav.push(MaterialPageRoute(builder: (_) => const EditScreen()));

    if (paths.length > 1) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
              'Opened the first of ${paths.length} images. Use Batch to process several at once.'),
        ),
      );
    }
  }
}
