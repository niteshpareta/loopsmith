import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../game/economy.dart';

/// Ad unit ids. These are Google's public TEST ids, which always serve test
/// ads. Replace them with your own before release, and replace the two app
/// ids in android/app/src/main/AndroidManifest.xml and ios/Runner/Info.plist.
class AdIds {
  static const androidRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const androidInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const iosRewarded = 'ca-app-pub-3940256099942544/1712485313';
  static const iosInterstitial = 'ca-app-pub-3940256099942544/4411468910';
}

/// Advertising behind one interface, so a publisher's mediation SDK can
/// replace the implementation without touching the game.
abstract class AdsService extends ChangeNotifier {
  Future<void> init();

  /// Whether a reward ad can be shown right now. Notifies when it changes.
  bool get rewardedReady;

  /// Shows a reward ad. Completes with true if the player earned the reward.
  Future<bool> showRewarded(String placement);

  /// Shows a between-level ad if the rules in [canShowInterstitial] allow it.
  /// Completes when play can continue.
  Future<void> showInterstitialIfAllowed(int level);

  bool adsRemoved = false;
}

/// No advertising: used on the web, on desktop, and in tests.
class NoAds extends AdsService {
  @override
  Future<void> init() async {}

  @override
  bool get rewardedReady => false;

  @override
  Future<bool> showRewarded(String placement) async => false;

  @override
  Future<void> showInterstitialIfAllowed(int level) async {}
}

/// AdMob through package:google_mobile_ads.
class GoogleAds extends AdsService {
  GoogleAds({this.onOpened, this.onClosed, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  /// Called when an ad covers the screen, so the game can pause its audio.
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;
  final DateTime Function() _now;

  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  DateTime? _lastInterstitial;
  bool _started = false;
  bool _showing = false;
  int _rewardedRetries = 0;

  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;
  String get _rewardedUnit => _ios ? AdIds.iosRewarded : AdIds.androidRewarded;
  String get _interstitialUnit =>
      _ios ? AdIds.iosInterstitial : AdIds.androidInterstitial;

  @override
  bool get rewardedReady => _rewarded != null && !_showing;

  @override
  Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      await _askConsent();
      await MobileAds.instance.initialize();
      // Ads start muted and stay within a PG rating. Block gambling and other
      // sensitive categories in the AdMob console as well.
      await MobileAds.instance.setAppMuted(true);
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.pg),
      );
      _loadRewarded();
      if (!adsRemoved) _loadInterstitial();
    } catch (e) {
      debugPrint('Ads unavailable: $e');
    }
  }

  /// Shows Google's consent form where the law requires one (for example in
  /// the EEA and UK). Does nothing elsewhere.
  Future<void> _askConsent() {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired((_) => finish()),
        (_) => finish(),
      );
    } catch (_) {
      finish();
    }
    return done.future.timeout(const Duration(seconds: 12), onTimeout: () {});
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: _rewardedUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _rewardedRetries = 0;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _rewarded = null;
          notifyListeners();
          // Back off: 15 s, 30 s, 60 s, then every two minutes.
          final wait = [15, 30, 60, 120][_rewardedRetries.clamp(0, 3)];
          _rewardedRetries++;
          Timer(Duration(seconds: wait), _loadRewarded);
        },
      ),
    );
  }

  void _loadInterstitial() {
    if (adsRemoved || _interstitial != null) return;
    InterstitialAd.load(
      adUnitId: _interstitialUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (error) => _interstitial = null,
      ),
    );
  }

  @override
  Future<bool> showRewarded(String placement) {
    final ad = _rewarded;
    if (ad == null || _showing) return Future.value(false);
    _rewarded = null;
    _showing = true;
    notifyListeners();
    var earned = false;
    final done = Completer<bool>();
    void finish() {
      _showing = false;
      onClosed?.call();
      if (!done.isCompleted) done.complete(earned);
      _loadRewarded();
      notifyListeners();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => onOpened?.call(),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        finish();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        finish();
      },
    );
    ad.show(onUserEarnedReward: (_, _) => earned = true);
    return done.future;
  }

  @override
  Future<void> showInterstitialIfAllowed(int level) {
    final ad = _interstitial;
    final allowed = canShowInterstitial(
      level: level,
      adsRemoved: adsRemoved,
      now: _now(),
      lastShown: _lastInterstitial,
    );
    if (ad == null || !allowed || _showing) {
      _loadInterstitial();
      return Future.value();
    }
    _interstitial = null;
    _showing = true;
    final done = Completer<void>();
    void finish() {
      _showing = false;
      _lastInterstitial = _now();
      onClosed?.call();
      if (!done.isCompleted) done.complete();
      _loadInterstitial();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => onOpened?.call(),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        finish();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        finish();
      },
    );
    ad.show();
    return done.future;
  }
}

/// Picks the right implementation for the device.
AdsService createAds({VoidCallback? onOpened, VoidCallback? onClosed}) {
  final mobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  return mobile ? GoogleAds(onOpened: onOpened, onClosed: onClosed) : NoAds();
}
