import 'package:flutter/material.dart';
import '../services/prefs_service.dart';

/// Holds app-wide settings (theme mode) and persists changes.
/// Loaded once at startup in main.dart before runApp.
class AppSettings extends ChangeNotifier {
  final PrefsService _prefs;

  ThemeMode themeMode = ThemeMode.system;

  AppSettings(this._prefs);

  Future<void> load() async {
    final modeStr = await _prefs.getThemeMode();
    themeMode = switch (modeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _prefs.setThemeMode(switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

}
