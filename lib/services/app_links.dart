import 'dart:io';

/// Central place for store/legal links used in the drawer and About
/// screen. Fill in the TODOs with your real URLs before release.
class AppLinks {
  static const String androidPackage = 'com.albonik.bgremover';

  static String get playStoreUrl =>
      'https://play.google.com/store/apps/details?id=$androidPackage';

  // TODO: replace with your real iOS App Store numeric ID once published.
  static const String appStoreUrl = 'https://apps.apple.com/app/idXXXXXXXXX';

  static String get currentStoreUrl =>
      Platform.isIOS ? appStoreUrl : playStoreUrl;

  // TODO: replace with your actual Play Store developer page
  // (Play Console → Store presence → shows your dev URL), e.g.
  // https://play.google.com/store/apps/developer?id=Albonik
  static const String moreAppsUrl =
      'https://play.google.com/store/apps/developer?id=Albonik';

  // TODO: host a real privacy policy page (required by Play Store/App
  // Store since this app uses camera/gallery and shows ads) and put its
  // URL here. A free option: a GitHub Pages page in the same org as
  // update_config.json, e.g.
  // https://sohel2050.github.io/Background-Remover-Controller/privacy
  static const String privacyPolicyUrl =
      'https://sohel2050.github.io/Background-Remover-Controller/privacy.html';

  static const String developerName = 'Albonik';
}
