import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../services/ads_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _watchRewardedAd(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final shown = await AdsService.instance.showRewarded(
      placement: 'settings_support',
      onRewardEarned: () {
        messenger.showSnackBar(
          const SnackBar(content: Text('Thanks for the support! 🎉')),
        );
      },
    );
    if (!shown) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No ad available right now — try again shortly.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('System default'),
            value: ThemeMode.system,
            groupValue: settings.themeMode,
            onChanged: (mode) => settings.setThemeMode(mode!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Light'),
            value: ThemeMode.light,
            groupValue: settings.themeMode,
            onChanged: (mode) => settings.setThemeMode(mode!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Dark'),
            value: ThemeMode.dark,
            groupValue: settings.themeMode,
            onChanged: (mode) => settings.setThemeMode(mode!),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Language', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          RadioListTile<String>(
            title: const Text('English'),
            value: 'en',
            groupValue: settings.locale.languageCode,
            onChanged: (code) => settings.setLocale(Locale(code!)),
          ),
          RadioListTile<String>(
            title: const Text('বাংলা (Bangla)'),
            value: 'bn',
            groupValue: settings.locale.languageCode,
            onChanged: (code) => settings.setLocale(Locale(code!)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.redAccent),
            title: const Text('Support this free app'),
            subtitle: const Text('Watch a short ad — costs you nothing extra'),
            trailing: FilledButton(
              onPressed: () => _watchRewardedAd(context),
              child: const Text('Watch'),
            ),
          ),
        ],
      ),
    );
  }
}
