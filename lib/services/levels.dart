import 'dart:convert';

import 'package:flutter/services.dart';

import '../game/daily.dart';
import '../game/level.dart';

/// The level packs shipped in assets/levels.
class LevelRepository {
  LevelRepository(this.campaign, this.daily, [this.weekly = const []]);

  final List<LevelDef> campaign;
  final List<LevelDef> daily;

  /// Seven knots a week, cycling through the pack.
  final List<LevelDef> weekly;

  static Future<LevelRepository> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    return LevelRepository(
      _parse(await b.loadString('assets/levels/campaign.json')),
      _parse(await b.loadString('assets/levels/daily.json')),
      _parse(await b.loadString('assets/levels/weekly.json')),
    );
  }

  static List<LevelDef> _parse(String raw) => [
    for (final j in jsonDecode(raw) as List<dynamic>)
      LevelDef.fromJson(j as Map<String, dynamic>),
  ];

  int get count => campaign.length;

  /// Campaign level by its 1-based number.
  LevelDef level(int id) => campaign[(id - 1).clamp(0, campaign.length - 1)];

  /// The Daily Knot for [now]. Everyone gets the same knot on the same day.
  LevelDef dailyFor(DateTime now) => daily[dailyNumber(now) % daily.length];

  /// This week's seven knots, easiest first.
  List<LevelDef> weeklyFor(DateTime now) {
    if (weekly.isEmpty) return const [];
    final start = weekIndex(now) * 7;
    return [for (var i = 0; i < 7; i++) weekly[(start + i) % weekly.length]];
  }
}
