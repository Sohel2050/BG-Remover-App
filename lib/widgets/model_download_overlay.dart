import 'package:flutter/material.dart';

import '../services/model_store.dart';

/// Shows a progress card while an AI model downloads for the first time.
class ModelDownloadOverlay extends StatelessWidget {
  final Widget child;
  const ModelDownloadOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<ModelDownloadState?>(
          valueListenable: ModelStore.downloading,
          builder: (context, state, _) {
            if (state == null) return const SizedBox.shrink();
            final percent = state.progress == null
                ? null
                : (state.progress! * 100).clamp(0, 100).round();
            return Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          percent == null
                              ? 'Downloading AI model (one time only)…'
                              : 'Downloading AI model (one time only) $percent%',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(state.fileName,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: state.progress),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
