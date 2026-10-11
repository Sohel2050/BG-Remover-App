import 'dart:io';

/// Central place for store/legal links used in the drawer and About
/// screen.
class AppLinks {
  static const String androidPackage = 'com.albonik.bgremover';

  static String get playStoreUrl =>
      'https://play.google.com/store/apps/details?id=$androidPackage';

  // TODO: replace with your real iOS App Store numeric ID once published.
  static const String appStoreUrl = 'https://apps.apple.com/app/idXXXXXXXXX';

  static String get currentStoreUrl =>
      Platform.isIOS ? appStoreUrl : playStoreUrl;

  static const String moreAppsUrl =
      'https://play.google.com/store/apps/dev?id=5662539472191775885';

  static const String privacyPolicyUrl =
      'https://albonik.com/privacy-policy/bgremover.txt';

  static const String developerName = 'Albonik';
}
