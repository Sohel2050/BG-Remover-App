import 'package:flutter/material.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

import '../services/ads_service.dart';

class LevelPlayBanner extends StatefulWidget {
  final String? placementName;

  const LevelPlayBanner({
    super.key,
    this.placementName,
  });

  @override
  State<LevelPlayBanner> createState() =>
      _LevelPlayBannerState();
}

class _LevelPlayBannerState
    extends State<LevelPlayBanner>
    with LevelPlayBannerAdViewListener {
  final GlobalKey<LevelPlayBannerAdViewState>
  _bannerKey =
  GlobalKey<LevelPlayBannerAdViewState>();

  @override
  Widget build(BuildContext context) {
    if (!AdsService.instance.isInitialized) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 50,
      child: LevelPlayBannerAdView(
        key: _bannerKey,
        adUnitId: AdIds.banner,
        adSize: LevelPlayAdSize.BANNER,
        listener: this,
        placementName: widget.placementName,
        onPlatformViewCreated: () {
          _bannerKey.currentState?.loadAd();
        },
      ),
    );
  }

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLoadFailed(LevelPlayAdError error) {}

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(
      LevelPlayAdInfo adInfo,
      LevelPlayAdError error,
      ) {}

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdExpanded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdCollapsed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLeftApplication(LevelPlayAdInfo adInfo) {}
}

class LevelPlayNativeCard extends StatefulWidget {
  final String? placementName;

  const LevelPlayNativeCard({
    super.key,
    this.placementName,
  });

  @override
  State<LevelPlayNativeCard> createState() =>
      _LevelPlayNativeCardState();
}

class _LevelPlayNativeCardState
    extends State<LevelPlayNativeCard>
    with LevelPlayNativeAdListener {
  LevelPlayNativeAd? _nativeAd;

  @override
  void initState() {
    super.initState();

    if (AdsService.instance.isInitialized) {
      _nativeAd = LevelPlayNativeAd.builder()
          .withPlacementName(
        widget.placementName ?? '',
      )
          .withListener(this)
          .build();
      _nativeAd!.loadAd();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_nativeAd == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: SizedBox(
        height: 120,
        width: double.infinity,
        child: LevelPlayNativeAdView(
          height: 120,
          width: double.infinity,
          nativeAd: _nativeAd,
        ),
      ),
    );
  }

  @override
  void onAdLoaded(
      LevelPlayNativeAd nativeAd,
      AdInfo adInfo,
      ) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void onAdLoadFailed(
      LevelPlayNativeAd nativeAd,
      IronSourceError error,
      ) {}

  @override
  void onAdImpression(
      LevelPlayNativeAd nativeAd,
      AdInfo adInfo,
      ) {}

  @override
  void onAdClicked(
      LevelPlayNativeAd nativeAd,
      AdInfo adInfo,
      ) {}
}

/// 300x250 medium-rectangle ad. Collapses when no ad is available.
class LevelPlayMrec extends StatefulWidget {
  final String? placementName;

  const LevelPlayMrec({super.key, this.placementName});

  @override
  State<LevelPlayMrec> createState() => _LevelPlayMrecState();
}

class _LevelPlayMrecState extends State<LevelPlayMrec>
    with LevelPlayBannerAdViewListener {
  final GlobalKey<LevelPlayBannerAdViewState> _key =
      GlobalKey<LevelPlayBannerAdViewState>();
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    if (!AdsService.instance.isInitialized || _failed) {
      return const SizedBox.shrink();
    }
    return Center(
      child: SizedBox(
        width: 300,
        height: 250,
        child: LevelPlayBannerAdView(
          key: _key,
          adUnitId: AdIds.mrec,
          adSize: LevelPlayAdSize.MEDIUM_RECTANGLE,
          listener: this,
          placementName: widget.placementName,
          onPlatformViewCreated: () {
            _key.currentState?.loadAd();
          },
        ),
      ),
    );
  }

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    if (mounted) setState(() => _failed = true);
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(LevelPlayAdInfo adInfo, LevelPlayAdError error) {}

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdExpanded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdCollapsed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLeftApplication(LevelPlayAdInfo adInfo) {}
}
