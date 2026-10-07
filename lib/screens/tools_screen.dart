import 'dart:io';
import 'package:flutter/material.dart';
import '../services/image_service.dart';
import '../widgets/levelplay_ads.dart';
import 'face_retouch_screen.dart';
import 'object_removal_screen.dart';
import 'subject_select_screen.dart';
import 'upscale_screen.dart';

/// Hub for the extra on-device AI tools. Each tool picks an image, then
/// opens its own screen.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  Future<void> _pickAndOpen(
    BuildContext context,
    Widget Function(File image) builder,
  ) async {
    final file = await ImageService().pickFromGallery();
    if (file == null || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => builder(file)));
  }

  @override
  Widget build(BuildContext context) {
    final tools = <_Tool>[
      _Tool(
        Icons.cleaning_services,
        'Object Removal',
        'Paint over something to erase it from the photo',
        (c) => _pickAndOpen(c, (f) => ObjectRemovalScreen(image: f)),
      ),
      _Tool(
        Icons.hd,
        'Upscale 4×',
        'Make a small photo bigger and sharper',
        (c) => _pickAndOpen(c, (f) => UpscaleScreen(image: f)),
      ),
      _Tool(
        Icons.people_alt,
        'Select Subjects',
        'Detect people/objects and keep only the ones you pick',
        (c) => _pickAndOpen(c, (f) => SubjectSelectScreen(image: f)),
      ),
      _Tool(
        Icons.face_retouching_natural,
        'Skin Smoothing',
        'Soften skin — no AI model needed',
        (c) => _pickAndOpen(c, (f) => FaceRetouchScreen(image: f)),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('AI Tools')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Object Removal, Upscale and Select Subjects each need a '
                'model file added to assets/models/ — see MODELS_SETUP.md. '
                'Skin Smoothing works out of the box.',
              ),
            ),
          ),
          const LevelPlayNativeCard(placementName: 'tools_list'),
          for (final t in tools)
            Card(
              child: ListTile(
                leading: Icon(t.icon, size: 32),
                title: Text(t.title),
                subtitle: Text(t.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => t.onTap(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tool {
  final IconData icon;
  final String title;
  final String subtitle;
  final void Function(BuildContext) onTap;
  _Tool(this.icon, this.title, this.subtitle, this.onTap);
}
