import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/edit_state.dart';
import '../services/image_service.dart';
import '../l10n/strings.dart';

import 'edit_screen.dart';
import 'batch_screen.dart';
import 'collage_screen.dart';
import 'recent_projects_screen.dart';
import 'settings_screen.dart';
import 'object_removal_screen.dart';
import 'upscale_screen.dart';
import 'face_retouch_screen.dart';
import 'subject_select_screen.dart';

import '../widgets/levelplay_ads.dart';
import '../widgets/app_drawer.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final imageService = ImageService();
    final strings = AppStrings.of(context);
    final cs = Theme.of(context).colorScheme;

    void push(Widget w) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => w));

    Future<void> pickAndGo(Future<File?> Function() pickFn) async {
      final file = await pickFn();
      if (file == null || !context.mounted) return;
      context.read<EditState>().setOriginalImage(file);
      push(const EditScreen());
    }

    Future<void> toolPick(Widget Function(File) builder) async {
      final file = await imageService.pickFromGallery();
      if (file == null || !context.mounted) return;
      push(builder(file));
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      drawer: const AppDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                children: [
                  Row(
                    children: [
                      Builder(
                        builder: (ctx) => IconButton(
                          tooltip: 'Menu',
                          icon: const Icon(Icons.menu),
                          onPressed: () => Scaffold.of(ctx).openDrawer(),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                'assets/images/app_logo.png',
                                width: 28,
                                height: 28,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              strings.appTitle,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => push(const SettingsScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Remove any background in one tap',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Pick a photo and the AI cuts out the subject on '
                          'your phone.',
                          style: TextStyle(
                            color: cs.onPrimary.withOpacity(0.85),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: cs.onPrimary,
                                  foregroundColor: cs.primary,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                onPressed: () =>
                                    pickAndGo(imageService.pickFromGallery),
                                icon: const Icon(Icons.photo_library),
                                label: const Text('Gallery'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cs.onPrimary,
                                  side: BorderSide(
                                      color: cs.onPrimary.withOpacity(0.7),
                                      width: 2),
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                onPressed: () =>
                                    pickAndGo(imageService.pickFromCamera),
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Camera'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Tools',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                    children: [
                      _ToolCard(
                        icon: Icons.cleaning_services,
                        title: 'Object Removal',
                        subtitle: 'Erase anything',
                        color: const Color(0xFFEDE7F8),
                        onTap: () =>
                            toolPick((f) => ObjectRemovalScreen(image: f)),
                      ),
                      _ToolCard(
                        icon: Icons.hd,
                        title: 'Upscale 4×',
                        subtitle: 'Sharper photos',
                        color: const Color(0xFFE3F3EE),
                        onTap: () => toolPick((f) => UpscaleScreen(image: f)),
                      ),
                      _ToolCard(
                        icon: Icons.face_retouching_natural,
                        title: 'Skin Smooth',
                        subtitle: 'Natural retouch',
                        color: const Color(0xFFFBE9E4),
                        onTap: () =>
                            toolPick((f) => FaceRetouchScreen(image: f)),
                      ),
                      _ToolCard(
                        icon: Icons.people_alt,
                        title: 'Select Subject',
                        subtitle: 'Pick what to keep',
                        color: const Color(0xFFFFF1D6),
                        onTap: () =>
                            toolPick((f) => SubjectSelectScreen(image: f)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniButton(
                          icon: Icons.dynamic_feed,
                          label: strings.batchProcess,
                          onTap: () => push(const BatchScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniButton(
                          icon: Icons.dashboard,
                          label: 'Collage',
                          onTap: () => push(const CollageScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniButton(
                          icon: Icons.history,
                          label: 'Recent',
                          onTap: () => push(const RecentProjectsScreen()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const LevelPlayBanner(placementName: 'home_banner'),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 22, color: Colors.black87),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
