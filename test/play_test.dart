import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loopsmith/game/economy.dart';
import 'package:loopsmith/render/scene.dart';
import 'package:loopsmith/screens/play_controller.dart';
import 'package:loopsmith/services/audio.dart';

import 'support.dart';

PlayController start(
  TestWorld w,
  int level, {
  PlayMode mode = PlayMode.campaign,
}) => PlayController(
  services: w.services,
  level: mode == PlayMode.daily
      ? w.services.levels.daily[level]
      : w.services.levels.level(level),
  mode: mode,
  scene: KnotScene(),
)..start();

/// Plays careless moves until the tray fills.
Future<void> failLevel(
  WidgetTester tester,
  PlayController c, {
  int seed = 3,
}) async {
  final rng = Random(seed);
  var guard = 0;
  while (c.phase != PlayPhase.failed && guard++ < 400) {
    if (c.phase == PlayPhase.cleared) c.restart();
    if (c.phase == PlayPhase.playing) {
      final options = [
        for (var r = 0; r < c.knot.ringCount; r++)
          if (c.canTurn(r)) r,
      ];
      c.dragEnd(options[rng.nextInt(options.length)], 1 + rng.nextInt(3));
    }
    await tester.pump(const Duration(seconds: 3));
  }
  expect(c.phase, PlayPhase.failed);
}

void main() {
  testWidgets('playing the stored solution clears the level with three stars', (
    tester,
  ) async {
    final w = TestWorld();
    final c = start(w, 6);
    for (final m in c.level.solution) {
      expect(c.phase, PlayPhase.playing);
      c.dragEnd(m.ring, m.delta);
      await tester.pump(const Duration(seconds: 3));
    }
    expect(c.phase, PlayPhase.cleared);
    expect(c.outcome!.stars, 3);
    expect(w.profile.unlocked, 7);
    expect(w.profile.stars[6], 3);
    expect(w.analytics.events, containsAll(['level_start', 'level_clear']));
    expect(w.audio.played, contains(Sfx.win));
    c.dispose();
  });

  testWidgets('every shipped level is cleared by its stored solution', (
    tester,
  ) async {
    final w = TestWorld();
    for (final level in [
      ...w.services.levels.campaign,
      ...w.services.levels.daily,
    ]) {
      final c = PlayController(
        services: w.services,
        level: level,
        mode: PlayMode.campaign,
        scene: KnotScene(),
      )..start();
      for (final m in level.solution) {
        c.dragEnd(m.ring, m.delta);
      }
      await tester.pump(const Duration(seconds: 4));
      expect(c.phase, PlayPhase.cleared, reason: 'level ${level.id}');
      expect(c.knot.moves, level.par, reason: 'level ${level.id}');
      c.dispose();
    }
  });

  testWidgets('tapping turns a ring one quarter and counts a move', (
    tester,
  ) async {
    final w = TestWorld();
    final c = start(w, 20);
    final ring = [
      for (var r = 0; r < c.knot.ringCount; r++)
        if (c.canTurn(r)) r,
    ].first;
    final before = c.knot.turns[ring];
    c.tap(ring);
    expect(c.knot.moves, 1);
    expect(
      c.knot.freed[ring] || c.knot.turns[ring] == (before + 1) % 4,
      isTrue,
    );
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  });

  testWidgets(
    'taps on one ring count as a single move until something is freed',
    (tester) async {
      final w = TestWorld();
      // Level 2's solution starts with a three-quarter turn of ring 0.
      final c = start(w, 2);
      final first = c.level.solution.first;
      expect(first.delta, 3);
      c.tap(first.ring);
      c.tap(first.ring);
      expect(c.knot.moves, 1);
      c.tap(first.ring); // third tap frees a ring
      expect(c.knot.moves, 1);
      await tester.pump(const Duration(seconds: 3));
      final second = c.level.solution[1];
      for (var i = 0; i < second.delta; i++) {
        c.tap(second.ring);
      }
      await tester.pump(const Duration(seconds: 3));
      expect(c.phase, PlayPhase.cleared);
      expect(c.knot.moves, c.level.par);
      expect(c.outcome!.stars, 3);
      c.dispose();
    },
  );

  testWidgets('one undo takes back a whole run of taps on the same ring', (
    tester,
  ) async {
    final w = TestWorld();
    final c = start(w, 20);
    // Find a ring that can be tapped twice without freeing anything.
    int? ring;
    for (var r = 0; r < c.knot.ringCount && ring == null; r++) {
      if (!c.canTurn(r)) continue;
      final trial = c.knot.copy();
      if (trial.apply(r, 1).events.isEmpty &&
          trial.apply(r, 1).events.isEmpty) {
        ring = r;
      }
    }
    expect(ring, isNotNull);
    final before = List.of(c.knot.turns);
    c.tap(ring!);
    c.tap(ring);
    expect(c.knot.moves, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(c.undo(), isTrue);
    expect(c.knot.turns, before);
    expect(c.knot.moves, 0);
    c.dispose();
  });

  testWidgets('a drag that ends where it began is not a move', (tester) async {
    final w = TestWorld();
    final c = start(w, 20);
    c.dragEnd(0, 0);
    c.dragEnd(0, 4);
    expect(c.knot.moves, 0);
    await tester.pump(const Duration(seconds: 1));
    c.dispose();
  });

  testWidgets('a full tray fails, and the first undo is free', (tester) async {
    final w = TestWorld();
    final c = start(w, 44);
    await failLevel(tester, c);
    expect(w.analytics.events, contains('level_fail'));
    expect(w.audio.played, contains(Sfx.fail));
    final coins = w.profile.coins;
    expect(c.undoIsFree, isTrue);
    expect(c.undo(), isTrue);
    expect(c.phase, PlayPhase.playing);
    expect(c.knot.failed, isFalse);
    expect(w.profile.coins, coins);
    expect(c.undoIsFree, isFalse);
    await tester.pump(const Duration(seconds: 1));
    c.dispose();
  });

  testWidgets('later undos cost coins', (tester) async {
    final w = TestWorld();
    final c = start(w, 20);
    c.dragEnd(0, 1);
    await tester.pump(const Duration(seconds: 3));
    c.dragEnd(0, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(c.undo(), isTrue); // free
    final coins = w.profile.coins;
    expect(c.undo(), isTrue);
    expect(w.profile.coins, coins - Economy.undoPrice);
    c.dispose();
  });

  testWidgets('an extra slot rescues a failed attempt, once', (tester) async {
    final w = TestWorld();
    w.profile.addCoins(500);
    final c = start(w, 44);
    await failLevel(tester, c);
    final slots = c.knot.trayCapacity;
    expect(await c.addSlot(), isTrue);
    expect(c.knot.trayCapacity, slots + 1);
    expect(c.phase, PlayPhase.playing);
    expect(c.canAddSlot, isFalse);
    expect(await c.addSlot(), isFalse);
    await tester.pump(const Duration(seconds: 1));
    c.dispose();
  });

  testWidgets('the extra slot prefers a token, then an ad, then coins', (
    tester,
  ) async {
    final ads = FakeAds();
    final w = TestWorld(ads: ads);
    w.profile.grantStarterKit();
    var c = start(w, 44);
    expect(c.slotCost, '${Economy.starterKitSlots} left');
    expect(await c.addSlot(), isTrue);
    expect(w.profile.slotTokens, Economy.starterKitSlots - 1);
    expect(ads.rewardedShown, 0);
    c.dispose();

    final w2 = TestWorld(ads: ads);
    c = start(w2, 44);
    expect(c.slotCost, 'watch ad');
    expect(await c.addSlot(), isTrue);
    expect(ads.rewardedShown, 1);
    c.dispose();

    ads.ready = false;
    final w3 = TestWorld(ads: ads);
    c = start(w3, 44);
    expect(c.slotCost, '${Economy.slotPrice} coins');
    expect(await c.addSlot(), isTrue);
    expect(w3.profile.coins, Economy.startCoins - Economy.slotPrice);
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a hint shows a move that keeps the level winnable', (
    tester,
  ) async {
    final w = TestWorld();
    final c = start(w, 30);
    final hints = w.profile.hints;
    final outcome = await tester.runAsync(c.requestHint);
    expect(outcome, HintOutcome.shown);
    expect(w.profile.hints, hints - 1);
    expect(c.hint, isNotNull);
    expect(c.scene.hintRing, c.hint!.ring);
    // Following hints all the way clears the level.
    var guard = 0;
    while (c.phase == PlayPhase.playing && guard++ < 40) {
      if (c.hint == null) {
        w.profile.addHints(1);
        await tester.runAsync(c.requestHint);
      }
      c.dragEnd(c.hint!.ring, c.hint!.delta);
      await tester.pump(const Duration(seconds: 3));
    }
    expect(c.phase, PlayPhase.cleared);
    c.dispose();
  });

  testWidgets('with no hints left the player is offered more', (tester) async {
    final w = TestWorld();
    while (w.profile.useHint()) {}
    final c = start(w, 30);
    expect(await tester.runAsync(c.requestHint), HintOutcome.needHints);
    c.dispose();
  });

  testWidgets('the first level coaches with a free hint', (tester) async {
    final w = TestWorld();
    final c = start(w, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(c.tip, isNotNull);
    expect(c.hint, isNotNull);
    expect(w.profile.hints, Economy.startHints);
    c.dispose();
  });

  testWidgets('a daily knot records the streak', (tester) async {
    final w = TestWorld();
    final c = start(w, 0, mode: PlayMode.daily);
    for (final m in c.level.solution) {
      c.dragEnd(m.ring, m.delta);
    }
    await tester.pump(const Duration(seconds: 4));
    expect(c.phase, PlayPhase.cleared);
    expect(c.outcome!.streak, 1);
    expect(w.profile.dailyDoneToday, isTrue);
    expect(w.analytics.events, contains('daily_done'));
    c.dispose();
  });

  testWidgets('music follows the level', (tester) async {
    final w = TestWorld();
    final c = start(w, 6);
    expect(w.audio.mood, MusicMood.levelStart);
    c.dragEnd(c.level.solution.first.ring, c.level.solution.first.delta);
    await tester.pump(const Duration(seconds: 3));
    expect(w.audio.mood, isNot(MusicMood.levelStart));
    c.dispose();
  });
}
