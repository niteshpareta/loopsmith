// Generates the level packs in assets/levels.
//
//   dart run tool/make_levels.dart
//
// Every level is proven solvable by the solver, and the stored solution is
// replayed through the real rules before the file is written.
import 'dart:convert';
import 'dart:io';

import 'package:loopsmith/game/generator.dart';
import 'package:loopsmith/game/knot.dart';
import 'package:loopsmith/game/level.dart';

const campaignCount = 300;
const dailyCount = 90;

void main(List<String> args) {
  final watch = Stopwatch()..start();
  final campaign = <LevelDef>[];
  for (var id = 1; id <= campaignCount; id++) {
    final level = generateLevel(campaignSpec(id), id);
    _verify(level);
    campaign.add(level);
    if (id % 20 == 0 || id <= 12) _report('L$id', level);
  }
  final daily = <LevelDef>[];
  for (var i = 0; i < dailyCount; i++) {
    final level = generateLevel(dailySpec(i), 100000 + i);
    _verify(level);
    daily.add(level);
    if (i % 15 == 0) _report('D$i', level);
  }
  _write('assets/levels/campaign.json', campaign);
  _write('assets/levels/daily.json', daily);

  double avg(Iterable<num> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
  for (final band in [
    [1, 10],
    [11, 20],
    [21, 60],
    [61, 150],
    [151, 300],
  ]) {
    final slice = campaign.where((l) => l.id >= band[0] && l.id <= band[1]);
    stdout.writeln(
      'levels ${band[0]}-${band[1]}: '
      'avg rings ${avg(slice.map((l) => l.rings.length)).toStringAsFixed(1)}, '
      'avg par ${avg(slice.map((l) => l.par)).toStringAsFixed(1)}, '
      'avg rating ${avg(slice.map((l) => l.rating)).toStringAsFixed(2)}',
    );
  }
  stdout.writeln('done in ${watch.elapsed.inSeconds}s');
}

void _verify(LevelDef level) {
  final knot = Knot(level);
  for (var r = 0; r < knot.ringCount; r++) {
    if (knot.isFree(r)) {
      throw StateError('level ${level.id}: ring $r starts free');
    }
  }
  for (final m in level.solution) {
    if (knot.failed) {
      throw StateError('level ${level.id}: solution fills the tray');
    }
    knot.apply(m.ring, m.delta);
  }
  if (!knot.solved) {
    throw StateError('level ${level.id}: solution does not clear it');
  }
}

void _report(String name, LevelDef l) {
  final kinds = l.kinds
      .where((k) => k != RingKind.plain)
      .map((k) => k.name)
      .join(',');
  stdout.writeln(
    '$name: ${l.rings.length} rings, ${l.links.length} links, '
    '${l.pegs.length} pegs, par ${l.par}, rating ${l.rating.toStringAsFixed(2)}'
    '${kinds.isEmpty ? '' : ', $kinds'}',
  );
}

void _write(String path, List<LevelDef> levels) {
  final lines = levels.map((l) => jsonEncode(l.toJson())).join(',\n');
  File(path).writeAsStringSync('[\n$lines\n]\n');
  stdout.writeln(
    'wrote $path (${levels.length} levels, '
    '${(File(path).lengthSync() / 1024).toStringAsFixed(0)} KB)',
  );
}
