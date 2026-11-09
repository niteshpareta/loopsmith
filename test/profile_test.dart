import 'package:flutter_test/flutter_test.dart';
import 'package:loopsmith/game/daily.dart';
import 'package:loopsmith/game/economy.dart';
import 'package:loopsmith/game/skins.dart';
import 'package:loopsmith/services/profile.dart';

import 'support.dart';

void main() {
  test('stars: three at par, two within three moves, one beyond', () {
    expect(Economy.starsFor(7, 7), 3);
    expect(Economy.starsFor(6, 7), 3);
    expect(Economy.starsFor(10, 7), 2);
    expect(Economy.starsFor(11, 7), 1);
  });

  test('clearing a level unlocks the next and pays once in full', () {
    final w = TestWorld();
    final first = w.profile.completeLevel(1, 1, 1, levelCount: 300);
    expect(first.stars, 3);
    expect(first.firstClear, isTrue);
    expect(w.profile.unlocked, 2);
    expect(w.profile.coins, Economy.startCoins + Economy.clearReward(3));
    final again = w.profile.completeLevel(1, 1, 1, levelCount: 300);
    expect(again.firstClear, isFalse);
    expect(again.coins, lessThan(first.coins));
  });

  test('a worse replay never lowers the stars already earned', () {
    final w = TestWorld();
    w.profile.completeLevel(3, 2, 2, levelCount: 300);
    w.profile.completeLevel(3, 9, 2, levelCount: 300);
    expect(w.profile.stars[3], 3);
    expect(w.profile.bestMoves[3], 2);
  });

  test('progress survives saving and loading', () async {
    final w = TestWorld();
    w.profile.completeLevel(1, 1, 1, levelCount: 300);
    w.profile.updateSettings((s) => s.lightTheme = true);
    await w.profile.save();
    final again = PlayerProfile(w.store);
    await again.load();
    expect(again.unlocked, 2);
    expect(again.stars[1], 3);
    expect(again.settings.lightTheme, isTrue);
    expect(again.coins, w.profile.coins);
  });

  test('a damaged save starts fresh instead of crashing', () async {
    final store = MemoryStore()..data['loopsmith.profile.v1'] = '{not json';
    final p = PlayerProfile(store);
    await p.load();
    expect(p.unlocked, 1);
  });

  group('streak', () {
    test('grows on consecutive days and resets after a gap', () {
      final w = TestWorld(today: DateTime(2026, 11, 9));
      expect(w.profile.completeDaily(8, 8).streak, 1);
      w.clock = DateTime(2026, 11, 10);
      expect(w.profile.completeDaily(8, 8).streak, 2);
      w.clock = DateTime(2026, 11, 13);
      expect(w.profile.liveStreak, 0);
      expect(w.profile.completeDaily(8, 8).streak, 1);
      expect(w.profile.bestStreak, 2);
    });

    test('replaying the same day earns nothing more', () {
      final w = TestWorld(today: DateTime(2026, 11, 9));
      final a = w.profile.completeDaily(9, 8);
      final b = w.profile.completeDaily(8, 8);
      expect(a.coins, Economy.dailyReward);
      expect(b.coins, 0);
      expect(b.streak, 1);
      expect(w.profile.daily[dateKey(w.clock)]!.moves, 8);
    });

    test('a saver is earned on day seven and forgives one missed day', () {
      final w = TestWorld(today: DateTime(2026, 11, 1));
      for (var d = 1; d <= 7; d++) {
        w.clock = DateTime(2026, 11, d);
        w.profile.completeDaily(8, 8);
      }
      expect(w.profile.streak, 7);
      expect(w.profile.streakSavers, 1);
      w.clock = DateTime(2026, 11, 9); // the 8th was missed
      expect(w.profile.liveStreak, 7);
      final out = w.profile.completeDaily(8, 8);
      expect(out.saverUsed, isTrue);
      expect(out.streak, 8);
      expect(w.profile.streakSavers, 0);
    });
  });

  group('collection', () {
    test('knot levels award rings and six rings unlock the Brass skin', () {
      final w = TestWorld();
      var unlocked = <String>[];
      for (var id = 12; id <= 32; id += 4) {
        expect(Economy.isKnotLevel(id), isTrue);
        final out = w.profile.completeLevel(id, 5, 5, levelCount: 300);
        expect(out.ringEarned, isTrue);
        unlocked = out.unlockedSkins;
      }
      expect(unlocked, ['brass']);
      expect(w.profile.ownedSkins, contains('brass'));
      expect(w.profile.rings, 0);
    });

    test('a skin is bought with coins only when there are enough', () {
      final w = TestWorld();
      expect(w.profile.activeSkin.id, 'enamel');
      expect(w.profile.buySkin(skinById('neon')), isFalse);
      w.profile.addCoins(1000);
      expect(w.profile.buySkin(skinById('neon')), isTrue);
      expect(w.profile.skin, 'neon');
      expect(
        w.profile.coins,
        Economy.startCoins + 1000 - skinById('neon').amount,
      );
    });
  });

  test('the daily gift is one hint, once a day', () {
    final w = TestWorld(today: DateTime(2026, 11, 9));
    expect(w.profile.claimDailyGift(), isTrue);
    expect(w.profile.claimDailyGift(), isFalse);
    expect(w.profile.hints, Economy.startHints + 1);
    w.clock = DateTime(2026, 11, 10);
    expect(w.profile.claimDailyGift(), isTrue);
  });

  group('ads between levels', () {
    final now = DateTime(2026, 11, 9, 12);
    test('never before level 12', () {
      expect(
        canShowInterstitial(
          level: 11,
          adsRemoved: false,
          now: now,
          lastShown: null,
        ),
        isFalse,
      );
      expect(
        canShowInterstitial(
          level: 12,
          adsRemoved: false,
          now: now,
          lastShown: null,
        ),
        isTrue,
      );
    });
    test('at most one every three minutes', () {
      expect(
        canShowInterstitial(
          level: 30,
          adsRemoved: false,
          now: now,
          lastShown: now.subtract(const Duration(minutes: 2)),
        ),
        isFalse,
      );
      expect(
        canShowInterstitial(
          level: 30,
          adsRemoved: false,
          now: now,
          lastShown: now.subtract(const Duration(minutes: 4)),
        ),
        isTrue,
      );
    });
    test('never once ads are removed', () {
      expect(
        canShowInterstitial(
          level: 30,
          adsRemoved: true,
          now: now,
          lastShown: null,
        ),
        isFalse,
      );
    });
  });

  test('daily numbering counts days from the first Daily Knot', () {
    expect(dailyNumber(DateTime(2026, 11, 1, 23, 59)), 1);
    expect(dailyNumber(DateTime(2026, 11, 9, 0, 1)), 9);
    expect(weekStart(DateTime(2026, 11, 11)).weekday, DateTime.monday);
  });
}
