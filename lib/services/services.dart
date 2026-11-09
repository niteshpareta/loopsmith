import 'dart:async';

import 'package:flutter/widgets.dart';

import '../game/economy.dart';
import 'ads.dart';
import 'analytics.dart';
import 'audio.dart';
import 'haptics.dart';
import 'levels.dart';
import 'profile.dart';
import 'store.dart';

/// Everything the screens need, created once at startup.
class Services {
  Services({
    required this.profile,
    required this.levels,
    required this.audio,
    required this.haptics,
    required this.ads,
    required this.store,
    required this.analytics,
  }) {
    store.onGranted = _grant;
    profile.addListener(_applySettings);
    _applySettings();
  }

  final PlayerProfile profile;
  final LevelRepository levels;
  final AudioService audio;
  final Haptics haptics;
  final AdsService ads;
  final StoreService store;
  final Analytics analytics;

  DateTime now() => profile.now();

  /// Loads saves and levels, then starts audio, ads and the store in the
  /// background so the first screen appears quickly.
  static Future<Services> start() async {
    final profile = PlayerProfile(await PrefsStore.open());
    await profile.load();
    final levels = await LevelRepository.load();
    final audio = SoloudAudio();
    final services = Services(
      profile: profile,
      levels: levels,
      audio: audio,
      haptics: Haptics(),
      ads: createAds(onOpened: audio.suspend, onClosed: audio.resume),
      store: createStore(),
      analytics: DebugAnalytics(),
    );
    unawaited(audio.init().then((_) => services._applySettings()));
    unawaited(services.ads.init());
    unawaited(services.store.init());
    return services;
  }

  void _applySettings() {
    audio.musicOn = profile.settings.music;
    audio.soundOn = profile.settings.sound;
    haptics.enabled = profile.settings.vibration;
    ads.adsRemoved = profile.adsRemoved;
  }

  void _grant(String productId) {
    if (productId == Economy.removeAdsId) profile.grantRemoveAds();
    if (productId == Economy.starterKitId) profile.grantStarterKit();
    analytics.log('purchase', {'product': productId});
  }

  /// A light tap sound for buttons.
  void tap() => audio.play(Sfx.tap);
}

/// Makes [Services] available to every widget below it.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final Services services;

  static Services of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
