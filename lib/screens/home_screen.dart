import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/edit_state.dart';
import '../services/image_service.dart';
import '../l10n/strings.dart';

import 'edit_screen.dart';
import 'batch_screen.dart';
import 'collage_screen.dart';
import 'tools_screen.dart';

import '../widgets/levelplay_ads.dart';
import '../widgets/app_drawer.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final imageService = ImageService();
    final strings = AppStrings.of(context);

    Future<void> pickAndGo(
        Future<dynamic> Function() pickFn,
        ) async {
      final file = await pickFn();

      if (file == null || !context.mounted) {
        return;
      }

      context.read<EditState>().setOriginalImage(file);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const EditScreen(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_fix_high,
                      size: 72,
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'Remove backgrounds instantly — '
                          '100% on-device, free.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 32),

                    FilledButton.icon(
                      onPressed: () => pickAndGo(
                        imageService.pickFromGallery,
                      ),
                      icon: const Icon(
                        Icons.photo_library,
                      ),
                      label: Text(
                        strings.chooseFromGallery,
                      ),
                    ),

                    const SizedBox(height: 12),

                    OutlinedButton.icon(
                      onPressed: () => pickAndGo(
                        imageService.pickFromCamera,
                      ),
                      icon: const Icon(
                        Icons.camera_alt,
                      ),
                      label: Text(
                        strings.takeAPhoto,
                      ),
                    ),

                    const SizedBox(height: 24),

                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                            const BatchScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.dynamic_feed,
                      ),
                      label: Text(
                        strings.batchProcess,
                      ),
                    ),

                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                            const CollageScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.dashboard,
                      ),
                      label: const Text(
                        'Collage Maker',
                      ),
                    ),

                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                            const ToolsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.auto_awesome,
                      ),
                      label: const Text(
                        'AI Tools '
                            '(Remove Object, Upscale...)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const LevelPlayBanner(
            placementName: 'home_banner',
          ),
        ],
      ),
    );
  }
}