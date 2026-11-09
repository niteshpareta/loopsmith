import 'dart:convert';
import 'dart:io';

import 'package:loopsmith/game/level.dart';
import 'package:loopsmith/services/ads.dart';
import 'package:loopsmith/services/analytics.dart';
import 'package:loopsmith/services/audio.dart';
import 'package:loopsmith/services/haptics.dart';
import 'package:loopsmith/services/levels.dart';
import 'package:loopsmith/services/profile.dart';
import 'package:loopsmith/services/reminders.dart';
import 'package:loopsmith/services/services.dart';
import 'package:loopsmith/services/store.dart';

List<LevelDef> _read(String path) => [
  for (final j in jsonDecode(File(path).readAsStringSync()) as List<dynamic>)
    LevelDef.fromJson(j as Map<String, dynamic>),
];

/// The shipped level packs, read straight from the assets folder.
LevelRepository loadLevels() => LevelRepository(
  _read('assets/levels/campaign.json'),
  _read('assets/levels/daily.json'),
  _read('assets/levels/weekly.json'),
);

/// A reward ad that is always ready and always pays out.
class FakeAds extends AdsService {
  int rewardedShown = 0;
  bool ready = true;

  @override
  Future<void> init() async {}
  @override
  bool get rewardedReady => ready;
  @override
  Future<bool> showRewarded(String placement) async {
    rewardedShown++;
    return true;
  }

  @override
  Future<void> showInterstitialIfAllowed(int level) async {}
}

class TestWorld {
  TestWorld({DateTime? today, AdsService? ads})
    : clock = today ?? DateTime(2026, 11, 9, 12) {
    profile = PlayerProfile(store, clock: () => clock);
    services = Services(
      profile: profile,
      levels: loadLevels(),
      audio: audio,
      haptics: Haptics()..enabled = false,
      ads: ads ?? NoAds(),
      store: NoStore(),
      analytics: analytics,
      reminders: reminders,
    );
    // Services turns vibration on from the saved settings; keep tests quiet.
    profile.settings.vibration = false;
    services.haptics.enabled = false;
  }

  DateTime clock;
  final MemoryStore store = MemoryStore();
  final SilentAudio audio = SilentAudio();
  final RecordingAnalytics analytics = RecordingAnalytics();
  final NoReminders reminders = NoReminders();
  late final PlayerProfile profile;
  late final Services services;
}
