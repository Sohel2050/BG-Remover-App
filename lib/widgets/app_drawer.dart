import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_links.dart';
import '../screens/about_screen.dart';
import '../screens/batch_screen.dart';
import '../screens/collage_screen.dart';
import '../screens/recent_projects_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/tools_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.auto_fix_high, size: 40),
                  SizedBox(height: 8),
                  Text(
                    'BG Remover',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text('Free, on-device background removal'),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Recent Projects'),
              onTap: () => _push(context, const RecentProjectsScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('AI Tools'),
              onTap: () => _push(context, const ToolsScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.dynamic_feed),
              title: const Text('Batch Process'),
              onTap: () => _push(context, const BatchScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Collage Maker'),
              onTap: () => _push(context, const CollageScreen()),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () => _push(context, const SettingsScreen()),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Rate this app'),
              onTap: () => _open(AppLinks.currentStoreUrl),
            ),
            ListTile(
              leading: const Icon(Icons.apps),
              title: Text('More apps by ${AppLinks.developerName}'),
              onTap: () => _open(AppLinks.moreAppsUrl),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share this app'),
              onTap: () => SharePlus.instance.share(
                ShareParams(
                  text: 'Remove photo backgrounds free, on-device: '
                      '${AppLinks.currentStoreUrl}',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              onTap: () => _open(AppLinks.privacyPolicyUrl),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () => _push(context, const AboutScreen()),
            ),
          ],
        ),
      ),
    );
  }
}
