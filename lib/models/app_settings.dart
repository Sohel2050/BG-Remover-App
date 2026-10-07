import 'package:flutter/material.dart';
import '../services/prefs_service.dart';

/// Holds app-wide settings (theme mode, language) and persists changes.
/// Loaded once at startup in main.dart before runApp.
class AppSettings extends ChangeNotifier {
  final PrefsService _prefs;

  ThemeMode themeMode = ThemeMode.system;
  Locale locale = const Locale('en');

  AppSettings(this._prefs);

  Future<void> load() async {
    final modeStr = await _prefs.getThemeMode();
    themeMode = switch (modeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final localeCode = await _prefs.getLocaleCode();
    locale = Locale(localeCode);

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

  Future<void> setLocale(Locale newLocale) async {
    locale = newLocale;
    notifyListeners();
    await _prefs.setLocaleCode(newLocale.languageCode);
  }
}
