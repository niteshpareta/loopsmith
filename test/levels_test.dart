import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:loopsmith/game/daily.dart';
import 'package:loopsmith/game/generator.dart';
import 'package:loopsmith/game/geometry.dart';
import 'package:loopsmith/game/level.dart';
import 'package:loopsmith/game/projection.dart';
import 'package:loopsmith/services/reminders.dart';

import 'support.dart';

RingDef _ring(
  int id,
  List<int> cell,
  RingPlane plane, {
  int tilt = 0,
  int tiltAxis = 0,
  int size = 100,
  RingKind kind = RingKind.plain,
  RingShape shape = RingShape.round,
}) => RingDef(
  id: id,
  color: 0,
  kind: kind,
  cell: cell,
  plane: plane,
  turn: 0,
  tilt: tilt,
  tiltAxis: tiltAxis,
  size: size,
  shape: shape,
);

void main() {
  final levels = loadLevels();
  final all = [...levels.campaign, ...levels.daily, ...levels.weekly];

  group('shipped levels', () {
    test('no knot is too big to read on a phone', () {
      for (final l in all) {
        expect(l.rings.length, lessThanOrEqualTo(kMaxKnotRings));
      }
    });

    test('every hooked pair really hooks and nothing else touches', () {
      for (final l in all) {
        expect(geometryProblem(l.rings), isNull, reason: 'level ${l.id}');
      }
    });

    test(
      'from the starting view, a slightly-off tap still hits every ring',
      () {
        for (final l in all) {
          final frames = [for (final r in l.rings) RingFrame(r)];
          final view = readability(frames, l.camYaw, l.camPitch);
          expect(
            view.score,
            greaterThanOrEqualTo(kGoodView - 0.001),
            reason: 'level ${l.id}',
          );
        }
      },
    );

    test('knots lean, vary in size and use every frame shape', () {
      final rings = [for (final l in all) ...l.rings];
      expect(
        rings.where((r) => r.tilt != 0).length,
        greaterThan(rings.length ~/ 5),
      );
      expect({for (final r in rings) r.size}.length, greaterThanOrEqualTo(3));
      final frames = {
        for (final r in rings)
          if (r.kind == RingKind.fixed) r.shape,
      };
      expect(
        frames,
        containsAll([RingShape.square, RingShape.triangle, RingShape.dee]),
      );
    });

    test('the first level is cleared by a single tap', () {
      final first = levels.level(1);
      expect(first.solution, hasLength(1));
      expect(first.solution.single.delta, 1);
    });
  });

  group('geometry', () {
    test('a ring leaning about its link axis keeps its link points', () {
      final upright = RingFrame(_ring(0, [0, 0, 0], RingPlane.xy));
      final leaning = RingFrame(_ring(0, [0, 0, 0], RingPlane.xy, tilt: 30));
      for (final pos in [0, 2]) {
        final a = upright.pointAt(pos * kQuarterTurn);
        final b = leaning.pointAt(pos * kQuarterTurn);
        expect((a - b).length, lessThan(1e-9));
      }
      // The other two points do move.
      expect(
        (upright.pointAt(kQuarterTurn) - leaning.pointAt(kQuarterTurn)).length,
        greaterThan(0.3),
      );
    });

    test('a leaning ring still hooks its neighbour', () {
      final a = RingFrame(_ring(0, [0, 0, 0], RingPlane.xy, tilt: 32));
      final b = RingFrame(
        _ring(1, [1, 0, 0], RingPlane.xz, tilt: -28, size: 88),
      );
      expect(ringPierces(a, b), isTrue);
      expect(ringPierces(b, a), isTrue);
    });

    test('every frame shape fits inside the round ring', () {
      for (final shape in RingShape.values) {
        for (var i = 0; i < 360; i++) {
          final r = shapeFactor(shape, i * math.pi / 180);
          expect(r, lessThanOrEqualTo(1.001), reason: '$shape at $i');
          expect(r, greaterThan(0.6), reason: '$shape at $i');
        }
      }
    });

    test('overlapping rings are reported', () {
      final problem = geometryProblem([
        _ring(0, [0, 0, 0], RingPlane.xy),
        _ring(1, [1, 1, 0], RingPlane.xy),
      ]);
      expect(problem, isNotNull);
    });
  });

  group('picking', () {
    RingTrace line(int ring, double y, double z) => RingTrace(ring, 5)
      ..xs.addAll([0, 50, 100])
      ..ys.addAll([y, y, y])
      ..zs.addAll([z, z, z])
      ..thetas.addAll([0, 0.1, 0.2]);

    test('the front tube wins where two overlap', () {
      final pick = pickRing(
        [line(0, 10, 2.0), line(1, 12, -1.0)],
        50,
        11,
        reach: 26,
        depthWeight: 6,
      );
      expect(pick!.ring, 1);
    });

    test('a near miss picks the closest ring', () {
      final pick = pickRing(
        [line(0, 10, 0), line(1, 60, 0)],
        50,
        24,
        reach: 26,
        depthWeight: 6,
      );
      expect(pick!.ring, 0);
    });

    test('a tap far from every ring picks nothing', () {
      expect(
        pickRing([line(0, 10, 0)], 50, 200, reach: 26, depthWeight: 6),
        isNull,
      );
    });
  });

  group('calendar', () {
    test('weekly runs change on Monday', () {
      final sunday = DateTime(2026, 11, 8);
      final monday = DateTime(2026, 11, 9);
      expect(weekIndex(monday), weekIndex(sunday) + 1);
      expect(weekIndex(DateTime(2026, 11, 15)), weekIndex(monday));
      expect(levels.weeklyFor(monday), hasLength(7));
    });

    test(
      'reminders skip tonight when today is played or the hour has passed',
      () {
        final morning = DateTime(2026, 11, 9, 9);
        expect(
          reminderTimes(morning, playedToday: false).first,
          DateTime(2026, 11, 9, 19),
        );
        expect(
          reminderTimes(morning, playedToday: true).first,
          DateTime(2026, 11, 10, 19),
        );
        final night = DateTime(2026, 11, 9, 21);
        expect(
          reminderTimes(night, playedToday: false).first,
          DateTime(2026, 11, 10, 19),
        );
        // At most three evenings are planned, so reminders stop if the player
        // stays away.
        expect(reminderTimes(morning, playedToday: false), hasLength(3));
      },
    );
  });
}
