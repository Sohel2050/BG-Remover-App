import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

/// Shows the appropriate dialog for an [UpdateCheckResult]:
/// - forceUpdate: non-dismissible, back button disabled, only "Update Now".
/// - updateAvailable (not forced): dismissible, has a "Later" button too.
/// Does nothing if neither is true.
Future<void> showUpdateDialogIfNeeded(
  BuildContext context,
  UpdateCheckResult result,
) async {
  if (!result.forceUpdate && !result.updateAvailable) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: !result.forceUpdate,
    builder: (ctx) => PopScope(
      // Block the hardware/gesture back button on a forced update.
      canPop: !result.forceUpdate,
      child: AlertDialog(
        title: Text(result.forceUpdate ? 'Update Required' : 'Update Available'),
        content: Text(result.message),
        actions: [
          if (!result.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: () async {
              if (result.storeUrl.isNotEmpty) {
                final uri = Uri.parse(result.storeUrl);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              // A forced dialog stays open (app is unusable without the
              // update); an optional one closes once the user is sent
              // to the store.
              if (!result.forceUpdate && ctx.mounted) {
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    ),
  );
}
