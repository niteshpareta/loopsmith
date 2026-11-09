import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loopsmith/game/generator.dart';
import 'package:loopsmith/game/geometry.dart';
import 'package:loopsmith/game/knot.dart';
import 'package:loopsmith/game/level.dart';
import 'package:loopsmith/game/solver.dart';

RingDef ring(
  int id,
  List<int> cell,
  RingPlane plane,
  int turn, {
  int color = 0,
  RingKind kind = RingKind.plain,
  int partner = -1,
}) => RingDef(
  id: id,
  color: color,
  kind: kind,
  cell: cell,
  plane: plane,
  turn: turn,
  partner: partner,
);

void main() {
  group('links', () {
    test('neighbours in perpendicular planes hook together', () {
      final links = computeLinks([
        ring(0, [0, 0, 0], RingPlane.xy, 0),
        ring(1, [1, 0, 0], RingPlane.xz, 0),
      ]);
      expect(links, hasLength(1));
      expect(links.single.pa, 0); // +x on the first ring
      expect(links.single.pb, 2); // -x on the second
    });

    test('a ring whose plane misses the shared axis is not hooked', () {
      final links = computeLinks([
        ring(0, [0, 0, 0], RingPlane.xy, 0),
        ring(1, [1, 0, 0], RingPlane.yz, 0),
      ]);
      expect(links, isEmpty);
    });

    test('hooked rings really pass through each other', () {
      final a = RingFrame(ring(0, [0, 0, 0], RingPlane.xy, 0));
      final b = RingFrame(ring(1, [1, 0, 0], RingPlane.xz, 0));
      expect(ringPierces(a, b), isTrue);
      expect(ringPierces(b, a), isTrue);
      expect(ringClearance(a, b), greaterThan(0.4));
    });
  });

  group('rules', () {
    LevelDef chain() => LevelDef(
      id: 1,
      rings: [
        ring(0, [0, 0, 0], RingPlane.xy, 1),
        ring(1, [1, 0, 0], RingPlane.xz, 1),
        ring(2, [2, 0, 0], RingPlane.xy, 1),
      ],
      pegs: const [],
      tray: 4,
    );

    test('nothing is free at the start', () {
      final k = Knot(chain());
      expect([for (var r = 0; r < 3; r++) k.isFree(r)], everyElement(isFalse));
    });

    test('an end ring slips out when its opening meets the link', () {
      final k = Knot(chain());
      final res = k.apply(0, 3); // opening to position 0, facing ring 1
      expect(res.releases.map((e) => e.ring), [0]);
      expect(k.freed, [true, false, false]);
      expect(res.solved, isFalse);
    });

    test('a neighbour\'s opening frees a ring too', () {
      final k = Knot(chain());
      final res = k.apply(1, 1); // ring 1 opening to position 2, facing ring 0
      expect(res.releases.map((e) => e.ring), [0]);
    });

    test('the last ring leaves on its own', () {
      final k = Knot(chain());
      k.apply(0, 3);
      final res = k.apply(2, 1); // ring 2 opening to position 2
      expect(res.solved, isTrue);
      expect(k.freed, everyElement(isTrue));
    });

    test('geared partners turn opposite ways', () {
      final level = LevelDef(
        id: 1,
        rings: [
          ring(
            0,
            [0, 0, 0],
            RingPlane.xy,
            1,
            kind: RingKind.geared,
            partner: 2,
          ),
          ring(1, [1, 0, 0], RingPlane.xz, 1),
          ring(
            2,
            [2, 0, 0],
            RingPlane.xy,
            2,
            kind: RingKind.geared,
            partner: 0,
          ),
          ring(3, [3, 0, 0], RingPlane.xz, 1),
        ],
        pegs: const [],
        tray: 4,
      );
      final k = Knot(level);
      final res = k.apply(0, 1);
      expect(res.turned, {0: 1, 2: -1});
      expect(k.turns[0], 2);
      expect(k.turns[2], 1);
    });

    test('fixed and sealed rings cannot be turned', () {
      final level = LevelDef(
        id: 1,
        rings: [
          ring(0, [0, 0, 0], RingPlane.xy, 1, kind: RingKind.fixed),
          ring(
            1,
            [1, 0, 0],
            RingPlane.xz,
            1,
            kind: RingKind.sealed,
            partner: 2,
          ),
          ring(2, [2, 0, 0], RingPlane.xy, 1),
        ],
        pegs: const [],
        tray: 4,
      );
      final k = Knot(level);
      expect(k.canTurn(0), isFalse);
      expect(k.canTurn(1), isFalse);
      expect(k.openings(1), 0);
      final res = k.apply(2, 1); // ring 2 opens toward ring 1 and leaves
      expect(res.events.whereType<RingUnsealed>().map((e) => e.ring), [1]);
      expect(k.canTurn(1), isTrue);
    });
  });

  group('pegs and tray', () {
    // Four rings in a row. Peg 0 wants colours 0 then 1, peg 1 wants 2 then 3.
    LevelDef row() => LevelDef(
      id: 1,
      rings: [
        ring(0, [0, 0, 0], RingPlane.xy, 1, color: 1),
        ring(1, [1, 0, 0], RingPlane.xz, 1, color: 0),
        ring(2, [2, 0, 0], RingPlane.xy, 1, color: 2),
        ring(3, [3, 0, 0], RingPlane.xz, 1, color: 3),
      ],
      pegs: const [
        [0, 1],
        [2, 3],
      ],
      tray: 2,
    );

    test('a ring whose colour is not next waits in the tray', () {
      final k = Knot(row());
      final res = k.apply(0, 3); // frees ring 0 (colour 1); peg 0 wants 0 first
      final rel = res.releases.single;
      expect(rel.destination, Destination.tray);
      expect(k.traySlots, [0, null]);
      expect(k.failed, isFalse);
    });

    test('tray rings move to their peg when their colour comes up', () {
      final k = Knot(row());
      k.apply(0, 3);
      final res = k.apply(2, 1); // ring 2 opens toward ring 1: frees ring 1
      expect(res.releases.map((e) => e.ring), contains(1));
      expect(res.events.whereType<RingPromoted>().map((e) => e.ring), [0]);
      expect(k.pegRings[0], [1, 0]);
      expect(k.trayCount, 0);
    });

    test('a full tray ends the attempt', () {
      final k = Knot(row());
      k.apply(0, 3); // colour 1 to tray
      final res = k.apply(3, 1); // ring 3 (colour 3) frees itself: tray again
      expect(k.trayCount, 2);
      expect(res.failed, isTrue);
      k.addTraySlot();
      expect(k.failed, isFalse);
    });
  });

  group('solver', () {
    test('agrees with the rules on random play', () {
      final rng = Random(7);
      for (var id = 5; id < 45; id += 3) {
        final level = generateLevel(campaignSpec(id), id);
        final solver = Solver(level);
        for (var run = 0; run < 12; run++) {
          final k = Knot(level);
          while (!k.solved && !k.failed && k.moves < 80) {
            final options = [
              for (var r = 0; r < k.ringCount; r++)
                if (k.canTurn(r)) r,
            ];
            if (options.isEmpty) break;
            final r = options[rng.nextInt(options.length)];
            final d = 1 + rng.nextInt(3);
            final t = Solver.packTurns(k.turns), f = Solver.packFreed(k.freed);
            final nt = solver.applyTurn(t, f, r, d);
            final nf = solver.settle(nt, f);
            k.apply(r, d);
            expect(
              Solver.packTurns(k.turns) & _liveMask(k),
              nt & _liveMask(k),
              reason: 'orientations, level $id',
            );
            expect(Solver.packFreed(k.freed), nf, reason: 'freed, level $id');
            expect(
              k.trayCount,
              solver.trayCount(nf),
              reason: 'tray, level $id',
            );
          }
        }
      }
    });

    test('stored solutions clear their levels in par', () {
      for (final id in [1, 2, 4, 5, 8, 15, 25, 40, 64]) {
        final level = generateLevel(campaignSpec(id), id);
        final k = Knot(level);
        for (final m in level.solution) {
          expect(k.failed, isFalse);
          k.apply(m.ring, m.delta);
        }
        expect(k.solved, isTrue, reason: 'level $id');
        expect(level.solution.length, level.par);
      }
    });

    test('hints work from the middle of a level', () {
      final level = generateLevel(campaignSpec(30), 30);
      final solver = Solver(level);
      final k = Knot(level);
      k.apply(level.solution.first.ring, level.solution.first.delta);
      var guard = 0;
      while (!k.solved && guard++ < 40) {
        final res = solver.solve(k);
        expect(res.solved, isTrue);
        k.apply(res.moves.first.ring, res.moves.first.delta);
        expect(k.failed, isFalse);
      }
      expect(k.solved, isTrue);
    });
  });

  group('generator', () {
    test('is deterministic', () {
      final a = generateLevel(campaignSpec(20), 20).toJson().toString();
      final b = generateLevel(campaignSpec(20), 20).toJson().toString();
      expect(a, b);
    });

    test('levels survive a JSON round trip', () {
      final level = generateLevel(campaignSpec(41), 41);
      final back = LevelDef.fromJson(level.toJson());
      expect(back.toJson().toString(), level.toJson().toString());
      expect(back.links.length, level.links.length);
    });

    test('early levels cannot fill the tray', () {
      for (var id = 5; id <= 10; id++) {
        final level = generateLevel(campaignSpec(id), id);
        expect(
          level.rings.length - level.pegs.length,
          lessThan(level.tray),
          reason: 'level $id',
        );
      }
    });

    test('new ring types arrive on schedule', () {
      expect(generateLevel(campaignSpec(8), 8).kinds, contains(RingKind.twin));
      expect(
        generateLevel(campaignSpec(15), 15).kinds,
        contains(RingKind.geared),
      );
      expect(
        generateLevel(campaignSpec(25), 25).kinds,
        contains(RingKind.fixed),
      );
      expect(
        generateLevel(campaignSpec(40), 40).kinds,
        contains(RingKind.sealed),
      );
    });
  });
}

/// Orientation bits of rings still in the knot (freed rings no longer matter).
int _liveMask(Knot k) {
  var m = 0;
  for (var r = 0; r < k.ringCount; r++) {
    if (!k.freed[r]) m |= 3 << (2 * r);
  }
  return m;
}
