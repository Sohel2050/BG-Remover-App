# Add inside target 'Runner' do ... end in ios/Podfile.
# The LevelPlay core SDK pod comes bundled with the
# unity_levelplay_mediation Flutter plugin — don't add it separately.
# Each adapter pod pulls in its own network's SDK automatically (unlike
# Android, where you add both the adapter AND the SDK).
#
# Version numbers below mirror the Android versions you're using (Unity
# publishes LevelPlay adapters for both platforms under the same version
# number per release — confirmed for AppLovin 5.9.0 existing on both
# platforms). This is a reasonable best-effort mapping, NOT independently
# verified per network — if `pod install` can't resolve one of these
# exact versions, check https://cocoapods.org/pods/IronSource<Name>Adapter
# for the closest available version and adjust that one line.

target 'Runner' do
  # ... your existing Flutter/Runner pods ...

  pod 'IronSourceChartboostAdapter', '5.9.0'
  pod 'IronSourceFacebookAdapter', '5.4.0'
  pod 'IronSourceInMobiAdapter', '5.9.0'
  pod 'IronSourceMintegralAdapter', '5.19.0'
  pod 'IronSourceMobileFuseAdapter', '5.4.0'
  pod 'IronSourceMolocoAdapter', '5.17.0'
  pod 'IronSourceOguryAdapter', '5.5.0'
  pod 'IronSourcePubMaticAdapter', '5.9.0'
  pod 'IronSourceSmaatoAdapter', '5.6.0'
  pod 'IronSourceUnityAdsAdapter', '5.11.0'
  pod 'IronSourceVerveAdapter', '5.8.0'
  pod 'IronSourceYandexAdapter', '5.14.0'
  pod 'IronSourceVungleAdapter', '5.14.0'
  pod 'IronSourceAppLovinAdapter', '5.9.0'
end
