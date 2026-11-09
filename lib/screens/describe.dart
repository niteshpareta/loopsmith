import '../game/level.dart';
import '../l10n/strings.dart';

/// "9 rings · twin, geared" style summary of a level.
String describeLevel(LevelDef level, S s) {
  final kinds = <String>[
    for (final kind in const [
      RingKind.twin,
      RingKind.geared,
      RingKind.fixed,
      RingKind.sealed,
    ])
      if (level.kinds.contains(kind)) s('kind.${kind.name}'),
  ];
  final rings = s.count('count.rings', level.rings.length);
  return kinds.isEmpty ? rings : '$rings · ${kinds.join(', ')}';
}
