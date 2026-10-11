import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RecentProject {
  final String originalPath;
  final String processedPath;
  final int timestampMs;

  RecentProject({
    required this.originalPath,
    required this.processedPath,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'originalPath': originalPath,
        'processedPath': processedPath,
        'timestampMs': timestampMs,
      };

  factory RecentProject.fromJson(Map<String, dynamic> json) => RecentProject(
        originalPath: json['originalPath'] as String,
        processedPath: json['processedPath'] as String,
        timestampMs: json['timestampMs'] as int,
      );
}

/// Thin wrapper around SharedPreferences for everything that needs to
/// survive app restarts: theme mode, language, onboarding flag, and a
/// rolling list of recent projects.
class PrefsService {
  static const _keyThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const _keyOnboardingDone = 'onboarding_done';
  static const _keyRecentProjects = 'recent_projects';
  static const _maxRecent = 20;

  Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyThemeMode) ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode);
  }

  Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingDone) ?? false;
  }

  Future<void> setOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingDone, true);
  }

  Future<List<RecentProject>> getRecentProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyRecentProjects);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => RecentProject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Brush session persistence (Undo History Persist) ---
  // Kept as raw JSON strings here (rather than typed BrushStroke objects)
  // to avoid a circular import between this file and brush_canvas.dart —
  // BrushCanvasState does the encode/decode itself.
  static String _brushSessionKey(String sessionKey) => 'brush_session_$sessionKey';

  Future<void> saveBrushSessionJson(String sessionKey, String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brushSessionKey(sessionKey), json);
  }

  Future<String?> loadBrushSessionJson(String sessionKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_brushSessionKey(sessionKey));
  }

  Future<void> clearBrushSessionJson(String sessionKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_brushSessionKey(sessionKey));
  }

  Future<void> removeRecentProject(String processedPath) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getRecentProjects();
    current.removeWhere((p) => p.processedPath == processedPath);
    await prefs.setString(
      _keyRecentProjects,
      jsonEncode(current.map((e) => e.toJson()).toList()),
    );
    await clearBrushSessionJson(processedPath);
  }

  // --- One-time tutorial tips ---
  Future<bool> hasSeenTip(String tipId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('tip_seen_$tipId') ?? false;
  }

  Future<void> markTipSeen(String tipId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tip_seen_$tipId', true);
  }

  Future<void> addRecentProject(RecentProject project) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getRecentProjects();
    current.insert(0, project);
    final trimmed = current.take(_maxRecent).toList();
    await prefs.setString(
      _keyRecentProjects,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }
}
