/// Builds levels that are guaranteed to be solvable, rates how hard they are,
/// and checks that every ring can be seen and tapped.
library;

import 'dart:math';

import 'geometry.dart';
import 'level.dart';
import 'projection.dart';
import 'solver.dart';

class GenSpec {
  const GenSpec({
    required this.id,
    required this.rings,
    required this.pegs,
    this.tray = 4,
    this.twins = 0,
    this.gearPairs = 0,
    this.fixed = 0,
    this.sealed = 0,
    this.targetFail = 0.2,
    this.candidates = 24,
  });

  final int id;
  final int rings;

  /// Number of pegs. 0 makes a tutorial level with no pegs or tray.
  final int pegs;
  final int tray;
  final int twins;
  final int gearPairs;
  final int fixed;
  final int sealed;

  /// How often a player who frees rings at random should fill the tray.
  final double targetFail;

  /// How many candidate knots to build before keeping the best match.
  final int candidates;
}

/// The most rings a knot may have. Larger knots were hard to read on a phone.
const int kMaxKnotRings = 9;

/// A view scoring at least this lets a slightly-off tap land on the intended
/// ring for every ring in the knot.
const double kGoodView = 0.9;

class _Candidate {
  _Candidate(this.level, this.failRate, this.score);
  final LevelDef level;
  final double failRate;
  final double score;
}

/// Generates the level described by [spec]. The same spec and [seed] always
/// produce the same level.
LevelDef generateLevel(GenSpec spec, int seed) {
  final found = <_Candidate>[];
  var attempt = 0;
  while (found.length < spec.candidates && attempt < spec.candidates * 40) {
    final rng = Random(seed * 7919 + attempt * 104729 + 13);
    attempt++;
    final c = _tryBuild(spec, rng, relaxed: attempt > spec.candidates * 20);
    if (c != null) found.add(c);
  }
  if (found.isEmpty) {
    throw StateError('could not generate level ${spec.id}');
  }
  found.sort((a, b) => a.score.compareTo(b.score));

  // Of the candidates closest to the wanted difficulty, keep the first whose
  // best view is clear. If none is, keep the clearest.
  LevelDef? fallback;
  var fallbackView = -1.0;
  for (final c in found.take(4)) {
    final frames = [for (final r in c.level.rings) RingFrame(r)];
    final view = bestView(frames);
    final level = c.level.withCamera(view[0], view[1]);
    if (view[2] >= kGoodView) return level;
    if (view[2] > fallbackView) {
      fallbackView = view[2];
      fallback = level;
    }
  }
  return fallback!;
}

_Candidate? _tryBuild(GenSpec spec, Random rng, {required bool relaxed}) {
  final n = spec.rings;
  final layout = _growLayout(n, rng);
  if (layout == null) return null;

  // Ring kinds.
  final kinds = List.filled(n, RingKind.plain);
  final partner = List.filled(n, -1);
  final order = List.generate(n, (i) => i)..shuffle(rng);
  var cursor = 0;
  int? take() => cursor < order.length ? order[cursor++] : null;

  for (var i = 0; i < spec.gearPairs; i++) {
    final a = take(), b = take();
    if (a == null || b == null) return null;
    kinds[a] = RingKind.geared;
    kinds[b] = RingKind.geared;
    partner[a] = b;
    partner[b] = a;
  }
  for (var i = 0; i < spec.fixed; i++) {
    final a = take();
    if (a == null) return null;
    kinds[a] = RingKind.fixed;
  }
  for (var i = 0; i < spec.twins; i++) {
    final a = take();
    if (a == null) return null;
    kinds[a] = RingKind.twin;
  }
  for (var i = 0; i < spec.sealed; i++) {
    final a = take();
    if (a == null) return null;
    final keys = [
      for (var k = 0; k < n; k++)
        if (k != a && kinds[k] != RingKind.sealed) k,
    ];
    if (keys.isEmpty) return null;
    kinds[a] = RingKind.sealed;
    partner[a] = keys[rng.nextInt(keys.length)];
  }

  // Lean, size and frame shape: looks only, checked so nothing collides.
  final shaped = _decorate(layout, kinds, partner, rng);
  if (shaped == null) return null;

  // Starting orientations: nothing may be free before the first move.
  List<RingDef>? rings;
  late Solver solver;
  for (var tries = 0; tries < 40 && rings == null; tries++) {
    final candidate = [
      for (final r in shaped) r.copyWith(turn: rng.nextInt(4)),
    ];
    final bare = LevelDef(
      id: spec.id,
      rings: candidate,
      pegs: const [],
      tray: spec.tray,
    );
    solver = Solver(bare);
    if (solver.settle(solver.initialTurns(), 0) == 0) rings = candidate;
  }
  if (rings == null) return null;

  // A release order that works, found by playing the knot without pegs.
  final reference = _referenceOrder(solver, rng);
  if (reference == null) return null;

  if (spec.pegs == 0) {
    final colored = [
      for (final r in rings) r.copyWith(color: rng.nextInt(kColorCount)),
    ];
    final level = LevelDef(
      id: spec.id,
      rings: colored,
      pegs: const [],
      tray: spec.tray,
    );
    final res = Solver(level)
        .solveFrom(solver.initialTurns(), 0, spec.tray, allowGreedy: false);
    if (!res.solved) return null;
    // The very first level must be cleared by a single tap.
    if (spec.id == 1 && (res.moves.length != 1 || res.moves.first.delta != 1)) {
      return null;
    }
    final par = res.moves.length;
    final wanted = max(1, n - 1);
    return _Candidate(
      LevelDef(
        id: spec.id,
        rings: colored,
        pegs: const [],
        tray: spec.tray,
        par: par,
        solution: res.moves,
        rating: 0,
      ),
      0,
      (par - wanted).abs().toDouble(),
    );
  }

  // Deal the reference order onto pegs, then colour each peg's rings.
  final pegCount = spec.pegs;
  final labels = <int>[for (var i = 0; i < n; i++) i % pegCount]..shuffle(rng);
  final palette = List.generate(kColorCount, (i) => i)..shuffle(rng);
  final perPeg = kColorCount ~/ pegCount;
  final pegColors = [
    for (var p = 0; p < pegCount; p++)
      palette.sublist(p * perPeg, (p + 1) * perPeg),
  ];
  final pegs = List.generate(pegCount, (_) => <int>[]);
  final colorOf = List.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final ring = reference[i];
    final p = labels[i];
    final options = pegColors[p];
    var c = options[rng.nextInt(options.length)];
    final seq = pegs[p];
    if (seq.length >= 2 &&
        seq[seq.length - 1] == c &&
        seq[seq.length - 2] == c) {
      c = options[(options.indexOf(c) + 1) % options.length];
    }
    seq.add(c);
    colorOf[ring] = c;
  }
  if (pegs.any((p) => p.isEmpty)) return null;

  final colored = [for (final r in rings) r.copyWith(color: colorOf[r.id])];
  final level = LevelDef(
    id: spec.id,
    rings: colored,
    pegs: pegs,
    tray: spec.tray,
  );
  final full = Solver(level);
  final res = full.solveFrom(
    full.initialTurns(),
    0,
    spec.tray,
    maxNodes: 400000,
    allowGreedy: false,
  );
  if (!res.solved) return null;
  final par = res.moves.length;
  if (!relaxed && par < max(2, (n * 0.6).ceil())) return null;

  final failRate = naiveFailRate(full, spec.tray, rng);
  final parLow = n - 1, parHigh = n + 4;
  final parPenalty = par < parLow
      ? (parLow - par) * 0.06
      : (par > parHigh ? (par - parHigh) * 0.06 : 0.0);
  final score = (failRate - spec.targetFail).abs() + parPenalty;
  final rating = (0.55 * failRate + 0.45 * ((par - 2) / 12).clamp(0.0, 1.0))
      .clamp(0.0, 1.0);

  return _Candidate(
    LevelDef(
      id: spec.id,
      rings: colored,
      pegs: pegs,
      tray: spec.tray,
      par: par,
      solution: res.moves,
      rating: rating,
    ),
    failRate,
    score,
  );
}

class _Placed {
  _Placed(this.cell, this.plane);
  final List<int> cell;
  final RingPlane plane;
}

/// Grows a connected knot on the lattice, one hooked ring at a time.
List<_Placed>? _growLayout(int n, Random rng) {
  const maxSpan = [2, 3, 2]; // widest difference allowed on x, y, z
  final placed = <_Placed>[
    _Placed([0, 0, 0], RingPlane.values[rng.nextInt(3)]),
  ];
  final frames = <RingFrame>[_frame(placed[0])];
  var guard = 0;
  while (placed.length < n) {
    if (++guard > 400) return null;
    final parent = placed[rng.nextInt(placed.length)];
    final axis = rng.nextBool() ? planeU(parent.plane) : planeV(parent.plane);
    final sign = rng.nextBool() ? 1 : -1;
    final cell = List.of(parent.cell);
    cell[axis] += sign;
    if (placed.any((p) => _same(p.cell, cell))) continue;

    // The new ring's plane holds the hook axis and the parent's normal.
    final normal = planeN(parent.plane);
    final plane = RingPlane.values.firstWhere(
      (p) => planeHas(p, axis) && planeHas(p, normal),
    );

    var ok = true;
    for (var k = 0; k < 3 && ok; k++) {
      var lo = cell[k], hi = cell[k];
      for (final p in placed) {
        lo = min(lo, p.cell[k]);
        hi = max(hi, p.cell[k]);
      }
      if (hi - lo > maxSpan[k]) ok = false;
    }
    if (!ok) continue;

    final candidate = _Placed(cell, plane);
    final frame = _frame(candidate);
    for (var i = 0; i < placed.length && ok; i++) {
      final other = placed[i];
      final relation = _relation(candidate, other);
      if (relation == _Relation.overlap) {
        ok = false;
      } else if (relation == _Relation.none) {
        if (ringClearance(frame, frames[i]) < 0.42 ||
            ringPierces(frame, frames[i]) ||
            ringPierces(frames[i], frame)) {
          ok = false;
        }
      }
    }
    if (!ok) continue;
    placed.add(candidate);
    frames.add(frame);
  }
  return placed;
}

RingFrame _frame(_Placed p) => RingFrame(
  RingDef(
    id: 0,
    color: 0,
    kind: RingKind.plain,
    cell: p.cell,
    plane: p.plane,
    turn: 0,
  ),
);

bool _same(List<int> a, List<int> b) =>
    a[0] == b[0] && a[1] == b[1] && a[2] == b[2];

enum _Relation { linked, overlap, none }

_Relation _relation(_Placed a, _Placed b) {
  var axis = -1, nonZero = 0, dist = 0;
  for (var k = 0; k < 3; k++) {
    final d = b.cell[k] - a.cell[k];
    if (d != 0) {
      nonZero++;
      axis = k;
      dist = d.abs();
    }
  }
  if (nonZero != 1 || dist != 1) return _Relation.none;
  if (!planeHas(a.plane, axis) || !planeHas(b.plane, axis)) {
    return _Relation.none;
  }
  return a.plane == b.plane ? _Relation.overlap : _Relation.linked;
}

/// Gives each ring a lean, a size and (for fixed frames) a shape, so knots
/// look hand-made instead of gridded. None of this changes the rules: a ring
/// only leans about the axis through its own link points, so every hook stays
/// exactly where it was. The result is checked for collisions.
List<RingDef>? _decorate(
  List<_Placed> layout,
  List<RingKind> kinds,
  List<int> partner,
  Random rng,
) {
  final n = layout.length;
  // Which axis each ring may lean about (-1: it must stay upright).
  final leanAxis = List.filled(n, -1);
  List<RingDef> build(List<int> tilt, List<int> size, List<RingShape> shape) {
    return [
      for (var i = 0; i < n; i++)
        RingDef(
          id: i,
          color: 0,
          kind: kinds[i],
          cell: layout[i].cell,
          plane: layout[i].plane,
          turn: 0,
          partner: partner[i],
          tilt: tilt[i],
          tiltAxis: leanAxis[i] < 0 ? 0 : leanAxis[i],
          size: size[i],
          shape: shape[i],
        ),
    ];
  }

  // Only rings whose links all sit on one axis can lean without moving a
  // hook, and they lean about that axis.
  final plain = build(
    List.filled(n, 0),
    List.filled(n, 100),
    List.filled(n, RingShape.round),
  );
  final links = computeLinks(plain);
  for (var i = 0; i < n; i++) {
    var onU = false, onV = false;
    for (final l in links) {
      final pos = l.a == i ? l.pa : (l.b == i ? l.pb : -1);
      if (pos < 0) continue;
      if (pos.isEven) {
        onU = true;
      } else {
        onV = true;
      }
    }
    if (onU && !onV) leanAxis[i] = 0;
    if (onV && !onU) leanAxis[i] = 1;
  }

  const sizes = [88, 94, 100, 100, 106];
  const frameShapes = [RingShape.square, RingShape.triangle, RingShape.dee];
  var lean = 1.0;
  for (var tries = 0; tries < 8; tries++) {
    final tilt = List.filled(n, 0);
    final size = List.filled(n, 100);
    final shape = List.filled(n, RingShape.round);
    for (var i = 0; i < n; i++) {
      if (kinds[i] == RingKind.fixed) {
        shape[i] = frameShapes[rng.nextInt(frameShapes.length)];
      } else {
        size[i] = sizes[rng.nextInt(sizes.length)];
      }
      if (leanAxis[i] >= 0 && rng.nextDouble() < 0.75) {
        final degrees = ((12 + rng.nextDouble() * 22) * lean).round();
        tilt[i] = rng.nextBool() ? degrees : -degrees;
      }
    }
    final rings = build(tilt, size, shape);
    if (geometryProblem(rings) == null) return rings;
    lean *= 0.72;
  }
  // Fall back to the plain, upright knot with square frames.
  final rings = build(List.filled(n, 0), List.filled(n, 100), [
    for (var i = 0; i < n; i++)
      kinds[i] == RingKind.fixed ? RingShape.square : RingShape.round,
  ]);
  return geometryProblem(rings) == null ? rings : null;
}

/// Describes the first way a knot's shapes do not fit together, or returns
/// null when every hooked pair really hooks and nothing else touches.
String? geometryProblem(List<RingDef> rings) {
  final frames = [for (final r in rings) RingFrame(r)];
  final links = computeLinks(rings);
  final linked = <int, LinkDef>{for (final l in links) l.a * 64 + l.b: l};
  for (var i = 0; i < rings.length; i++) {
    for (var j = i + 1; j < rings.length; j++) {
      final a = frames[i], b = frames[j];
      final link = linked[i * 64 + j];
      if (link != null) {
        if (linkSeparation(a, link.pa, b, link.pb) < 0.3) {
          return 'rings $i and $j touch where they hook';
        }
        if (!ringPierces(a, b) || !ringPierces(b, a)) {
          return 'rings $i and $j no longer hook';
        }
        if (ringClearance(a, b) < 0.26) {
          return 'rings $i and $j rub together';
        }
      } else {
        if (ringClearance(a, b) < 0.42) return 'rings $i and $j collide';
        if (ringPierces(a, b) || ringPierces(b, a)) {
          return 'rings $i and $j hook without a link';
        }
      }
    }
  }
  return null;
}

/// Plays the knot with no pegs, mostly choosing moves that free something,
/// and returns the order rings came out in.
List<int>? _referenceOrder(Solver s, Random rng) {
  var t = s.initialTurns();
  var f = 0;
  final order = <int>[];
  var idle = 0;
  while (f != s.allFreed) {
    final releasing = <List<int>>[], any = <List<int>>[];
    for (var r = 0; r < s.n; r++) {
      if (!s.turnable(f, r)) continue;
      for (var d = 1; d <= 3; d++) {
        final nt = s.applyTurn(t, f, r, d);
        final nf = s.settle(nt, f);
        any.add([nt, nf]);
        if (nf != f) releasing.add([nt, nf]);
      }
    }
    if (any.isEmpty) return null;
    final pick = releasing.isNotEmpty && rng.nextDouble() < 0.85
        ? releasing[rng.nextInt(releasing.length)]
        : any[rng.nextInt(any.length)];
    if (pick[1] == f) {
      if (++idle > 60) return null;
    } else {
      idle = 0;
      for (var r = 0; r < s.n; r++) {
        if (((pick[1] >> r) & 1) == 1 && ((f >> r) & 1) == 0) order.add(r);
      }
    }
    t = pick[0];
    f = pick[1];
  }
  return order;
}

/// Share of careless playthroughs that fill the tray. The careless player
/// takes any move that frees a ring, without looking at the pegs.
double naiveFailRate(Solver s, int capacity, Random rng, {int runs = 120}) {
  var fails = 0, done = 0;
  for (var i = 0; i < runs; i++) {
    var t = s.initialTurns();
    var f = 0;
    var idle = 0;
    var failed = false;
    while (f != s.allFreed && !failed) {
      final releasing = <List<int>>[], any = <List<int>>[];
      for (var r = 0; r < s.n; r++) {
        if (!s.turnable(f, r)) continue;
        for (var d = 1; d <= 3; d++) {
          final nt = s.applyTurn(t, f, r, d);
          final nf = s.settle(nt, f);
          any.add([nt, nf]);
          if (nf != f) releasing.add([nt, nf]);
        }
      }
      if (any.isEmpty) break;
      final pick = releasing.isNotEmpty
          ? releasing[rng.nextInt(releasing.length)]
          : any[rng.nextInt(any.length)];
      if (pick[1] == f) {
        if (++idle > 40) break;
      } else {
        idle = 0;
      }
      t = pick[0];
      f = pick[1];
      if (f != s.allFreed && s.trayCount(f) >= capacity) failed = true;
    }
    if (failed) {
      fails++;
      done++;
    } else if (f == s.allFreed) {
      done++;
    }
  }
  return done == 0 ? 1 : fails / done;
}

/// The campaign's difficulty curve.
GenSpec campaignSpec(int id) {
  final knot = id >= 12 && id % 4 == 0; // every fourth level is a harder knot
  int rings;
  if (id == 1) {
    rings = 2;
  } else if (id <= 3) {
    rings = 3;
  } else if (id <= 7) {
    rings = 4;
  } else if (id <= 14) {
    rings = 5;
  } else if (id <= 24) {
    rings = 6;
  } else if (id <= 59) {
    rings = 6 + (id % 3 == 0 ? 1 : 0);
  } else if (id <= 149) {
    rings = 7 + (id % 3 == 0 ? 1 : 0);
  } else {
    rings = 8;
  }
  if (knot) rings = min(kMaxKnotRings, rings + 1);

  final pegs = id < 5 ? 0 : (rings >= 8 && id % 3 != 1 ? 3 : 2);

  // Late knots have a tighter tray, which is where their challenge comes
  // from now that knots stay small enough to read.
  final tray = knot && id >= 120 ? 3 : 4;

  // Each ring type gets a gentle first level, then appears regularly.
  var twins = 0, gears = 0, fixed = 0, sealed = 0;
  if (id >= 8) {
    twins = id == 8
        ? 1
        : (id % 2 == 0 ? 1 : 0) + (id >= 30 && id % 5 == 0 ? 1 : 0);
  }
  if (id >= 15) {
    gears = id == 15
        ? 1
        : (id % 3 == 0 ? 1 : 0) + (id >= 70 && id % 7 == 0 ? 1 : 0);
  }
  if (id >= 25) {
    fixed = id == 25
        ? 1
        : (id % 4 == 1 ? 1 : 0) + (id >= 90 && id % 9 == 0 ? 1 : 0);
  }
  if (id >= 40) {
    sealed = id == 40
        ? 1
        : (id % 5 == 2 ? 1 : 0) + (id >= 100 && id % 11 == 0 ? 1 : 0);
  }
  if (id == 8) {
    gears = fixed = sealed = 0;
  } else if (id == 15) {
    twins = fixed = sealed = 0;
  } else if (id == 25) {
    twins = gears = sealed = 0;
  } else if (id == 40) {
    twins = gears = fixed = 0;
  }
  // Keep at least two ordinary rings in every knot.
  while (twins + gears * 2 + fixed + sealed > rings - 2) {
    if (sealed > 1) {
      sealed--;
    } else if (fixed > 1) {
      fixed--;
    } else if (gears > 1) {
      gears--;
    } else if (twins > 0) {
      twins--;
    } else if (sealed > 0) {
      sealed--;
    } else if (fixed > 0) {
      fixed--;
    } else {
      gears--;
    }
  }

  double target;
  if (id <= 14) {
    target = 0.0;
  } else if (id <= 24) {
    target = 0.15;
  } else if (id <= 60) {
    target = 0.3;
  } else if (id <= 150) {
    target = 0.42;
  } else {
    target = 0.5;
  }
  if (knot) target += 0.2;
  const intro = {8, 15, 25, 40};
  if (intro.contains(id)) target = min(target, 0.1);

  return GenSpec(
    id: id,
    rings: rings,
    pegs: pegs,
    tray: tray,
    twins: twins,
    gearPairs: gears,
    fixed: fixed,
    sealed: sealed,
    targetFail: target,
  );
}

/// Daily knots are full-size and use every ring type.
GenSpec dailySpec(int index) {
  return GenSpec(
    id: index,
    rings: 8 + index % 2,
    pegs: index % 2 == 0 ? 3 : 2,
    tray: 4,
    twins: 1,
    gearPairs: index % 3 == 0 ? 1 : 0,
    fixed: index % 4 == 1 ? 1 : 0,
    sealed: index % 4 == 3 ? 1 : 0,
    targetFail: 0.5,
  );
}

/// Weekly-run knots: seven a week, from gentle on Monday's first knot to
/// hard on the seventh.
GenSpec weeklySpec(int index) {
  final step = index % 7;
  return GenSpec(
    id: index,
    rings: 6 + (step + 1) ~/ 2,
    pegs: step >= 5 ? 3 : 2,
    tray: step == 6 ? 3 : 4,
    twins: step.isOdd ? 1 : 0,
    gearPairs: step == 2 || step == 5 ? 1 : 0,
    fixed: step == 3 || step == 6 ? 1 : 0,
    sealed: step == 4 ? 1 : 0,
    targetFail: 0.25 + step * 0.06,
  );
}
