import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopsmith/app.dart';
import 'package:loopsmith/screens/play_screen.dart';

import 'support.dart';

Future<TestWorld> pumpApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final w = TestWorld();
  await tester.pumpWidget(LoopsmithApp(services: w.services));
  await tester.pump(const Duration(milliseconds: 300));
  return w;
}

void main() {
  testWidgets(
    'home shows the next level, the streak, coins and the daily knot',
    (tester) async {
      final w = await pumpApp(tester);
      expect(find.text('Loopsmith'), findsOneWidget);
      expect(find.text('Play level 1'), findsOneWidget);
      expect(find.text('${w.profile.coins}'), findsWidgets);
      expect(find.textContaining('Daily Knot #'), findsWidgets);
    },
  );

  testWidgets('every tab opens without layout errors', (tester) async {
    await pumpApp(tester);
    for (final tab in ['Daily', 'Workshop', 'Settings', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: tab);
    }
  });

  testWidgets('the layout holds on a small phone and a tablet', (tester) async {
    for (final size in const [
      Size(320, 568),
      Size(360, 640),
      Size(820, 1180),
    ]) {
      await pumpApp(tester, size: size);
      for (final tab in ['Daily', 'Workshop', 'Settings', 'Home']) {
        await tester.tap(find.text(tab).last);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: '$tab at $size');
      }
      await tester.tap(find.text('Play level 1'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: 'play at $size');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('play opens level 1 and the level can be cleared by tapping', (
    tester,
  ) async {
    final w = await pumpApp(tester);
    await tester.tap(find.text('Play level 1'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.textContaining('Turn the glowing ring'), findsOneWidget);

    // Drive the controller the way taps do, then let the animations run.
    final state = tester.state(find.byType(PlayScreen));
    // ignore: avoid_dynamic_calls
    final controller = (state as dynamic).c;
    final level = w.services.levels.level(1);
    for (final m in level.solution) {
      // ignore: avoid_dynamic_calls
      controller.dragEnd(m.ring, m.delta);
    }
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Clean release'), findsOneWidget);
    expect(find.text('Next level'), findsOneWidget);
    expect(w.profile.unlocked, 2);

    await tester.tap(find.text('Next level'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Level 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings toggles change and save the profile', (tester) async {
    final w = await pumpApp(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(w.profile.settings.lightTheme, isFalse);
    await tester.tap(find.text('Light theme'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(w.profile.settings.lightTheme, isTrue);
    expect(
      Theme.of(tester.element(find.text('Settings').first)).brightness,
      Brightness.light,
    );
    expect(w.store.data.values.single, contains('"light":true'));
  });

  testWidgets('a locked skin explains how to earn it', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Workshop').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Jade'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Clear level 80 to unlock Jade.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
