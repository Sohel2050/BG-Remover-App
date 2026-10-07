import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_links.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((v) {
      if (mounted) setState(() => _info = v);
    });
  }

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(
            child: Icon(Icons.auto_fix_high, size: 72),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _info?.appName ?? 'BG Remover',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (_info != null)
            Center(
              child: Text(
                'Version ${_info!.version} (${_info!.buildNumber})',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Remove backgrounds instantly — 100% on-device, free.',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Developer'),
            subtitle: const Text(AppLinks.developerName),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            onTap: () => _open(AppLinks.privacyPolicyUrl),
            trailing: const Icon(Icons.open_in_new, size: 18),
          ),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: const Text('Rate this app'),
            onTap: () => _open(AppLinks.currentStoreUrl),
            trailing: const Icon(Icons.open_in_new, size: 18),
          ),
          ListTile(
            leading: const Icon(Icons.apps),
            title: const Text('More apps by ${AppLinks.developerName}'),
            onTap: () => _open(AppLinks.moreAppsUrl),
            trailing: const Icon(Icons.open_in_new, size: 18),
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
        ],
      ),
    );
  }
}
