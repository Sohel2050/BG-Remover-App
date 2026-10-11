import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

class AdIds {
  static const String appKey = '2820a4965';
  static const String banner = '4cafh3jwdbyn6ohp';

  static const String mrec = 'shsn7enqstxc5qpi';
  static const String interstitial = 'hu149fj6h72r1ebj';
  static const String native = 'ypo41rpcpf7pvcnq';
  static const String rewarded = 'mn5ikgnzdo1xdlgh';

  /// Native ads are off until a native ad network is added in LevelPlay.
  /// Where a native card would show, an MREC is shown instead.
  static const bool useNative = false;
}

class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  LevelPlayInterstitialAd? _interstitial;
  LevelPlayRewardedAd? _rewarded;

  Future<void> init() async {
    if (_initialized) return;

    // These ids are Android ids; iOS needs its own key and units.
    if (!Platform.isAndroid) return;

    try {
      final initRequest =
      LevelPlayInitRequest.builder(AdIds.appKey).build();

      await LevelPlay.init(
        initRequest: initRequest,
        initListener: _InitListener(
          onSuccess: () {
            _initialized = true;
            _loadInterstitial();
            _loadRewarded();
          },
        ),
      );
    } catch (e) {
      debugPrint('AdsService init failed: $e');
    }
  }

  void _loadInterstitial() {
    _interstitial ??= LevelPlayInterstitialAd(
      adUnitId: AdIds.interstitial,
    );

    _interstitial!.setListener(
      _InterstitialListener(
        onClosed: _loadInterstitial,
      ),
    );

    _interstitial!.loadAd();
  }

  Future<bool> showInterstitial({
    String? placement,
  }) async {
    if (_interstitial == null) return false;

    final ready = await _interstitial!.isAdReady();

    if (!ready) return false;

    await _interstitial!.showAd();

    return true;
  }

  VoidCallback? _pendingRewardCallback;

  void _loadRewarded() {
    _rewarded ??= LevelPlayRewardedAd(
      adUnitId: AdIds.rewarded,
    );

    _rewarded!.setListener(
      _RewardedListener(
        onReward: (reward) {
          _pendingRewardCallback?.call();
          _pendingRewardCallback = null;
        },
        onClosed: () {
          _pendingRewardCallback = null;
          _loadRewarded();
        },
      ),
    );

    _rewarded!.loadAd();
  }

  Future<bool> showRewarded({
    required VoidCallback onRewardEarned,
    String? placement,
  }) async {
    if (_rewarded == null) return false;

    final ready = await _rewarded!.isAdReady();

    if (!ready) return false;

    _pendingRewardCallback = onRewardEarned;

    await _rewarded!.showAd();

    return true;
  }
}

class _InitListener with LevelPlayInitListener {
  final VoidCallback onSuccess;

  _InitListener({
    required this.onSuccess,
  });

  @override
  void onInitSuccess(
      LevelPlayConfiguration configuration,
      ) {
    onSuccess();
  }

  @override
  void onInitFailed(
      LevelPlayInitError error,
      ) {
    debugPrint('LevelPlay init failed: $error');
  }
}

class _InterstitialListener
    with LevelPlayInterstitialAdListener {
  final VoidCallback onClosed;

  _InterstitialListener({
    required this.onClosed,
  });

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLoadFailed(LevelPlayAdError error) {}

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(
      LevelPlayAdError error,
      LevelPlayAdInfo adInfo,
      ) {}

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) {
    onClosed();
  }
}

class _RewardedListener
    with LevelPlayRewardedAdListener {
  final void Function(LevelPlayReward reward) onReward;
  final VoidCallback onClosed;

  _RewardedListener({
    required this.onReward,
    required this.onClosed,
  });

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLoadFailed(LevelPlayAdError error) {}

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(
      LevelPlayAdError error,
      LevelPlayAdInfo adInfo,
      ) {}

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) {
    onClosed();
  }

  @override
  void onAdRewarded(
      LevelPlayReward reward,
      LevelPlayAdInfo adInfo,
      ) {
    onReward(reward);
  }
}