import '../game/level.dart';

/// "9 rings · twin, geared" style summary of a level.
String describeLevel(LevelDef level) {
  final parts = <String>['${level.rings.length} rings'];
  final kinds = <String>[];
  final count = <RingKind, int>{};
  for (final r in level.rings) {
    count[r.kind] = (count[r.kind] ?? 0) + 1;
  }
  if ((count[RingKind.twin] ?? 0) > 0) kinds.add('twin');
  if ((count[RingKind.geared] ?? 0) > 0) kinds.add('geared');
  if ((count[RingKind.fixed] ?? 0) > 0) kinds.add('fixed');
  if ((count[RingKind.sealed] ?? 0) > 0) kinds.add('sealed');
  if (kinds.isNotEmpty) parts.add(kinds.join(', '));
  return parts.join(' · ');
}
