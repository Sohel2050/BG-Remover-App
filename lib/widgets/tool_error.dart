import 'package:flutter/material.dart';
import '../services/tool_utils.dart';

/// Shows a missing-model error as a dialog (with the exact fix), and any
/// other error as a snackbar.
void showToolError(BuildContext context, Object error) {
  if (!context.mounted) return;
  if (error is ModelMissingException) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Model file missing'),
        content: Text(error.toString()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } else {
    var msg = error.toString().replaceFirst('Exception: ', '');
    if (msg.length > 160) msg = '${msg.substring(0, 160)}...';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
