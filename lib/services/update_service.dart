import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Result of checking the remote update config against the installed
/// app version.
class UpdateCheckResult {
  final bool forceUpdate; // installed version < min_version
  final bool updateAvailable; // installed version < latest_version
  final String message;
  final String storeUrl; // play_store_url or app_store_url for this platform

  UpdateCheckResult({
    required this.forceUpdate,
    required this.updateAvailable,
    required this.message,
    required this.storeUrl,
  });
}

/// Checks a JSON file hosted on GitHub for the app's minimum/latest
/// supported version and shows a forced or optional update prompt
/// accordingly. Schema (see Sohel2050/Background-Remover-Controller):
/// ```json
/// {
///   "min_version": "1.0.0",
///   "latest_version": "1.1.0",
///   "update_message": "...",
///   "play_store_url": "...",
///   "app_store_url": "..."
/// }
/// ```
class UpdateService {
  // GitHub's "blob" page (what you get from clicking a file in the repo)
  // is an HTML page, not the raw JSON — this uses the raw content URL.
  // Raw JSON (not the GitHub "blob" page). Empty disables the check.
  static const String _configUrl =
      'https://raw.githubusercontent.com/Sohel2050/Background-Remover-Controller/main/update_config.json';

  /// Returns null if the check couldn't be completed (offline, bad JSON,
  /// etc.) — callers should treat that as "nothing to show", never block
  /// the app on a failed network call.
  Future<UpdateCheckResult?> check() async {
    if (_configUrl.isEmpty) return null;
    try {
      final response = await http
          .get(Uri.parse(_configUrl))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final minVersion = (json['min_version'] as String?) ?? '0.0.0';
      final latestVersion = (json['latest_version'] as String?) ?? '0.0.0';
      final message = (json['update_message'] as String?) ??
          'A new version is available.';
      final storeUrl = Platform.isIOS
          ? (json['app_store_url'] as String? ?? '')
          : (json['play_store_url'] as String? ?? '');

      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      return UpdateCheckResult(
        forceUpdate: _compareVersions(current, minVersion) < 0,
        updateAvailable: _compareVersions(current, latestVersion) < 0,
        message: message,
        storeUrl: storeUrl,
      );
    } catch (_) {
      // Network error, malformed JSON, etc. — fail open, never block.
      return null;
    }
  }

  /// Returns negative if [a] < [b], 0 if equal, positive if [a] > [b].
  /// Compares dotted numeric versions (e.g. "1.2.10" vs "1.3.0");
  /// non-numeric segments compare as 0.
  int _compareVersions(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }
}
