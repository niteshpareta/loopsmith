import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopsmith/app.dart';
import 'package:loopsmith/l10n/strings.dart';
import 'package:loopsmith/screens/play_screen.dart';

import 'support.dart';

final _placeholder = RegExp(r'\{(\w+)\}');

List<String> _placeholders(String text) =>
    [for (final m in _placeholder.allMatches(text)) m.group(1)!]..sort();

void main() {
  final english = S.tables['en']!;

  test('every language has the same keys as English', () {
    for (final entry in S.tables.entries) {
      expect(entry.value.keys.toSet(), english.keys.toSet(), reason: entry.key);
    }
  });

  test('every translation keeps its placeholders', () {
    for (final entry in S.tables.entries) {
      for (final key in english.keys) {
        expect(
          _placeholders(entry.value[key]!),
          _placeholders(english[key]!),
          reason: '${entry.key}: $key',
        );
      }
    }
  });

  test('no translation is empty and weekday letters are complete', () {
    for (final entry in S.tables.entries) {
      for (final e in entry.value.entries) {
        expect(e.value.trim(), isNotEmpty, reason: '${entry.key}: ${e.key}');
      }
      expect(entry.value['daily.weekdays']!.length, 7, reason: entry.key);
    }
  });

  test('placeholders and plurals are filled in', () {
    final s = S('en');
    expect(s('home.play', {'n': 12}), 'Play level 12');
    expect(s.count('count.rings', 1), '1 ring');
    expect(s.count('count.rings', 5), '5 rings');
    expect(S('de').count('count.rings', 5), '5 Ringe');
    expect(S('xx')('nav.home'), 'Home', reason: 'unknown language is English');
  });

  testWidgets('every language fits every screen on a small phone', (
    tester,
  ) async {
    for (final code in S.tables.keys) {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = TestWorld();
      w.profile.settings.language = code;
      w.profile.unlocked = 60;
      await tester.pumpWidget(LoopsmithApp(services: w.services));
      await tester.pump(const Duration(milliseconds: 300));
      final s = S(code);
      expect(find.text(s('home.play', {'n': 60})), findsOneWidget);
      for (final tab in [
        'nav.daily',
        'nav.workshop',
        'nav.settings',
        'nav.home',
      ]) {
        await tester.tap(find.text(s(tab)).last);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: '$code $tab');
      }
      // A level with pegs, a tray and three boosters.
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(PlayScreen.route(w.services.levels.level(60)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(s('booster.hint')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$code play');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('choosing a language in settings changes the text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final w = TestWorld();
    await tester.pumpWidget(LoopsmithApp(services: w.services));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Settings').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('Language'), 80);
    await tester.tap(find.text('Language'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Español'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(w.profile.settings.language, 'es');
    expect(find.text('Ajustes'), findsWidgets);
    expect(find.text('Idioma'), findsOneWidget);
  });
}
