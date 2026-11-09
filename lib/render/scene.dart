import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../game/geometry.dart';
import '../game/knot.dart';
import '../game/level.dart';
import '../game/projection.dart';
import 'camera.dart';

/// How one ring looks right now: where its opening is, and any animation
/// it is in the middle of.
class RingVisual {
  RingVisual(this.def)
    : frame = RingFrame(def),
      rest = def.turn * kQuarterTurn,
      spin = def.turn * kQuarterTurn;

  final RingDef def;
  final RingFrame frame;

  /// Angle the opening settles at. Accumulates, so direction is preserved.
  double rest;

  /// Angle shown now, before any live drag.
  double spin;
  double spinFrom = 0;
  double spinStart = -1;

  /// Extra angle while a finger is spinning the ring.
  double drag = 0;

  /// Scene time at which the ring pops in.
  double born = -10;
  double shakeStart = -1;
  double releaseStart = -1;
  bool gone = false;

  /// Freed by the rules but not yet lifted: ignored by touch and the camera.
  bool leaving = false;
  bool sealed = false;
  double unsealStart = -1;
  double glowUntil = -1;

  double get angle => spin + drag;
}

/// One cross-section of a ring's tube, ready to be lit and drawn.
class Station {
  Station(
    this.theta,
    this.screen,
    this.z,
    this.lateral,
    this.along,
    this.side,
    this.front,
    this.tangent,
    this.eye,
  );

  /// Local angle around the ring.
  final double theta;

  /// Centre of the tube on screen, and its depth.
  final Offset screen;
  final double z;

  /// Screen offset from the centre to the tube's edge, and one tube radius
  /// along the tube.
  final Offset lateral;
  final Offset along;

  /// View-space unit vectors: across the tube, toward the viewer, along the
  /// tube, and from this point to the eye.
  final Vec3 side;
  final Vec3 front;
  final Vec3 tangent;
  final Vec3 eye;

  /// Part of the band covering a sealed ring's opening.
  bool band = false;

  /// A groove on a geared ring.
  bool rib = false;

  /// Index of this station's first vertex, set while the mesh is built.
  int base = 0;
}

/// An unbroken stretch of tube: a whole ring, or one arc between openings.
class TubeRun {
  TubeRun(this.ring, this.alpha, this.releasing, this.capped);
  final int ring;
  final double alpha;
  final bool releasing;

  /// The run ends at openings, so both ends are rounded off.
  final bool capped;

  /// Position around the ring of this run's first piece of tube.
  int firstIndex = 0;
  final List<Station> stations = [];
}

/// The piece of tube between two neighbouring stations.
class TubeSeg {
  TubeSeg(this.run, this.i, this.index, this.z);
  final TubeRun run;

  /// Joins `run.stations[i]` to `run.stations[i + 1]`.
  final int i;

  /// Position around the whole ring, across all its runs.
  final int index;
  final double z;

  /// 0 none, 1 seal dot, 2 colour mark, 4 rivet.
  int deco = 0;
}

/// What the painter and the touch code need to know about a ring on screen.
class RingOutline {
  RingOutline(this.ring, this.center, this.tube);
  final int ring;
  final Offset center;

  /// Width of the tube in pixels.
  final double tube;
  final List<Offset> points = [];
  final List<double> thetas = [];
}

class FrameData {
  final List<TubeRun> runs = [];
  final List<TubeSeg> segs = [];
  final Map<int, RingOutline> outlines = {};
  final List<RingTrace> traces = [];
  int stationCount = 0;
  double zNear = 0, zFar = 1;
}

/// Everything the flight overlay needs to carry a ring away from the knot.
class FlightStart {
  FlightStart(this.center, this.u, this.v, this.tube, this.gaps, this.gapWidth);
  final Offset center;
  final Offset u;
  final Offset v;
  final double tube;
  final List<double> gaps;
  final double gapWidth;
}

class LinkGlow {
  LinkGlow(this.ring, this.pos);
  final int ring;
  final int pos;
}

class Flash {
  Flash(this.ring, this.pos, this.start);
  final int ring;
  final int pos;
  final double start;
}

class Particle {
  Particle(this.pos, this.vel, this.born, this.life, this.color, this.size);
  Offset pos;
  Offset vel;
  final double born;
  final double life;
  final int color;
  final double size;
}

class HitResult {
  HitResult(this.ring, this.theta);
  final int ring;
  final double theta;
}

/// The visual state of a knot: camera, ring animations and effects.
///
/// The scene knows nothing about rules. The play controller tells it what
/// happened and it animates.
class KnotScene extends ChangeNotifier {
  final Camera camera = Camera();
  List<RingVisual> rings = [];
  double time = 0;
  Size size = Size.zero;

  /// Reduce motion: no idle sway, no particles, instant camera moves.
  bool calm = false;

  /// Height at the top of the view covered by something else (a coaching
  /// tip); the knot is fitted into what is left.
  double topInset = 0;

  final List<LinkGlow> glows = [];
  final List<Flash> flashes = [];
  final List<Particle> particles = [];
  int hintRing = -1;
  int hintPos = 0;
  double groundY = -2;

  double _yaw = -0.5, _pitch = 0.42;
  double _unitGoal = 80;
  Offset _centerGoal = Offset.zero;
  Vec3 _targetGoal = Vec3.zero;
  bool _snap = true;
  FrameData? lastFrame;
  final math.Random _rng = math.Random(5);

  static const double spinTime = 0.2;
  static const double releaseTime = 0.24;

  /// Shows [knot] as it is, optionally popping the rings in one by one.
  void load(LevelDef level, Knot knot, {bool animate = false}) {
    final sameLevel =
        rings.length == level.rings.length &&
        rings.isNotEmpty &&
        identical(rings.first.def, level.rings.first);
    rings = [for (final r in level.rings) RingVisual(r)];
    for (var i = 0; i < rings.length; i++) {
      final rv = rings[i];
      rv.rest = rv.spin = knot.turns[i] * kQuarterTurn;
      rv.gone = knot.freed[i];
      rv.sealed = !knot.freed[i] && knot.isSealed(i);
      rv.born = animate && !calm ? time + 0.06 + 0.045 * i : -10;
    }
    var low = double.infinity;
    for (final rv in rings) {
      low = math.min(low, rv.frame.center.y - rv.frame.radius);
    }
    groundY = (low.isFinite ? low : -1) - 0.75;
    flashes.clear();
    particles.clear();
    hintRing = -1;
    syncGlows(knot);
    // Start from the view the generator found clearest. An undo keeps
    // whatever view the player has turned to.
    if (!sameLevel || animate) {
      _yaw = level.camYaw;
      _pitch = level.camPitch;
    }
    _snap = true;
    notifyListeners();
  }

  /// Marks every opening that currently sits on a live link.
  void syncGlows(Knot knot) {
    glows.clear();
    for (var i = 0; i < knot.level.links.length; i++) {
      if (!knot.linkLive(i)) continue;
      final l = knot.level.links[i];
      if (((knot.openings(l.a) >> l.pa) & 1) == 1) {
        glows.add(LinkGlow(l.a, l.pa));
      }
      if (((knot.openings(l.b) >> l.pb) & 1) == 1) {
        glows.add(LinkGlow(l.b, l.pb));
      }
    }
  }

  // ------------------------------------------------------------ animation
  void tick(double dt) {
    time += dt;
    for (final rv in rings) {
      if (rv.spinStart >= 0) {
        final t = (time - rv.spinStart) / spinTime;
        if (t >= 1 || calm) {
          rv.spin = rv.rest;
          rv.spinStart = -1;
        } else {
          rv.spin = rv.spinFrom + (rv.rest - rv.spinFrom) * _backOut(t);
        }
      }
    }
    for (final p in particles) {
      p.pos += p.vel * dt;
      p.vel = p.vel * (1 - 2.2 * dt) + Offset(0, 60 * dt);
    }
    particles.removeWhere((p) => time - p.born > p.life);
    flashes.removeWhere((f) => time - f.start > 0.45);
    _updateCamera(dt);
    notifyListeners();
  }

  static double _backOut(double t) {
    const c1 = 1.70158, c3 = c1 + 1;
    final x = t - 1;
    return 1 + c3 * x * x * x + c1 * x * x;
  }

  /// Turns a ring by [quarters] quarter turns from where it rests. Any live
  /// drag is folded in, so the ring continues smoothly from under the finger.
  void turnBy(int ring, int quarters) {
    final rv = rings[ring];
    rv.spin = rv.angle;
    rv.drag = 0;
    rv.spinFrom = rv.spin;
    rv.rest += quarters * kQuarterTurn;
    rv.spinStart = time;
  }

  /// Follows a finger: offsets a ring (and its geared partner) by [delta].
  void dragTo(int ring, double delta) {
    final rv = rings[ring];
    rv.drag = delta;
    final p = rv.def.partner;
    if (rv.def.kind == RingKind.geared && p >= 0 && !rings[p].gone) {
      rings[p].drag = -delta;
    }
  }

  void shake(int ring) => rings[ring].shakeStart = time;

  void highlight(int ring, {double seconds = 0.9}) =>
      rings[ring].glowUntil = time + seconds;

  void flash(int ring, int pos) {
    if (!calm) flashes.add(Flash(ring, pos, time));
  }

  void setHint(int ring, int pos) {
    hintRing = ring;
    hintPos = pos;
  }

  void clearHint() => hintRing = -1;

  void unseal(int ring) {
    final rv = rings[ring];
    rv.sealed = false;
    rv.unsealStart = time;
    _burst(ring, 8);
  }

  /// Starts the short lift a ring makes before it flies to its slot.
  void beginRelease(int ring) {
    rings[ring].releaseStart = time;
    _burst(ring, 10);
  }

  void _burst(int ring, int count) {
    if (calm) return;
    final outline = lastFrame?.outlines[ring];
    if (outline == null) return;
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * math.pi;
      final speed = 60 + _rng.nextDouble() * 120;
      final at = outline.points.isEmpty
          ? outline.center
          : outline.points[_rng.nextInt(outline.points.length)];
      particles.add(
        Particle(
          at,
          Offset(math.cos(a), math.sin(a)) * speed,
          time,
          0.35 + _rng.nextDouble() * 0.3,
          rings[ring].def.color,
          1.5 + _rng.nextDouble() * 2.2,
        ),
      );
    }
  }

  /// Hands a ring over to the flight overlay and stops drawing it here.
  FlightStart? handOff(int ring) {
    final rv = rings[ring];
    final frame = buildFrame();
    final outline = frame.outlines[ring];
    rv.gone = true;
    if (outline == null) return null;
    final lift = _lift(rv);
    final scale = (1 + 0.12 * _releaseT(rv)) * rv.frame.radius;
    final c = rv.frame.center + lift;
    final pc = camera.projectWorld(c);
    final pu = camera.projectWorld(c + rv.frame.u * scale) - pc;
    final pv = camera.projectWorld(c + rv.frame.v * scale) - pc;
    return FlightStart(
      pc,
      pu,
      pv,
      outline.tube,
      rv.sealed ? const [] : _gaps(rv),
      rv.sealed ? 0 : kGapAngle,
    );
  }

  List<double> _gaps(RingVisual rv) => rv.def.kind == RingKind.twin
      ? [rv.angle, rv.angle + math.pi]
      : [rv.angle];

  double _releaseT(RingVisual rv) => rv.releaseStart < 0
      ? 0
      : ((time - rv.releaseStart) / releaseTime).clamp(0.0, 1.0);

  Vec3 _lift(RingVisual rv) {
    final t = _releaseT(rv);
    if (t == 0) return Vec3.zero;
    final e = 1 - (1 - t) * (1 - t);
    final away = (rv.frame.center - _targetGoal);
    final dir = away.length < 0.01 ? const Vec3(0, 1, 0) : away.normalized();
    return (dir * 0.35 + const Vec3(0, 0.45, 0)) * e;
  }

  // ------------------------------------------------------------ camera
  /// Orbits the camera by a finger drag.
  void orbit(double dx, double dy) {
    _yaw += dx * 0.008;
    _pitch = (_pitch + dy * 0.006).clamp(-0.3, 1.2);
  }

  void resize(Size s) {
    if (s == size) return;
    size = s;
    _snap = true;
  }

  void _updateCamera(double dt) {
    final sway = calm ? 0.0 : 1.0;
    camera.yaw = _yaw + sway * 0.06 * math.sin(time * 0.33);
    camera.pitch = _pitch + sway * 0.02 * math.sin(time * 0.24 + 1);
    camera.update();
    if (size.isEmpty) return;

    final live = [
      for (final rv in rings)
        if (!rv.gone && !rv.leaving && rv.releaseStart < 0) rv,
    ];
    if (live.isNotEmpty) {
      var c = Vec3.zero;
      for (final rv in live) {
        c = c + rv.frame.center;
      }
      _targetGoal = c * (1 / live.length);
      // Fit the projected bounds of the remaining rings to the view.
      var minX = double.infinity, maxX = -double.infinity;
      var minY = double.infinity, maxY = -double.infinity;
      for (final rv in live) {
        for (var i = 0; i < 12; i++) {
          final v = camera.rotate(
            rv.frame.pointAt(i * math.pi / 6) - _targetGoal,
          );
          final s = camera.scaleAt(v.z);
          minX = math.min(minX, v.x * s);
          maxX = math.max(maxX, v.x * s);
          minY = math.min(minY, v.y * s);
          maxY = math.max(maxY, v.y * s);
        }
      }
      final w = math.max(0.5, maxX - minX) + 0.5;
      final h = math.max(0.5, maxY - minY) + 0.5;
      final top = math.min(topInset, size.height * 0.3);
      final room = size.height - top;
      final shortest = math.min(size.width, room);
      _unitGoal = math.min(
        math.min(size.width * 0.94 / w, room * 0.94 / h),
        shortest * 0.27,
      );
      _centerGoal = Offset(
        size.width / 2 - (minX + maxX) / 2 * _unitGoal,
        top + room / 2 + (minY + maxY) / 2 * _unitGoal,
      );
    }
    if (_snap || calm) {
      camera.unit = _unitGoal;
      camera.center = _centerGoal;
      camera.target = _targetGoal;
      _snap = false;
    } else {
      final k = 1 - math.exp(-4.5 * dt);
      camera.unit += (_unitGoal - camera.unit) * k;
      camera.center = Offset.lerp(camera.center, _centerGoal, k)!;
      camera.target = Vec3.lerp(camera.target, _targetGoal, k);
    }
  }

  // ------------------------------------------------------------ geometry
  /// Projects every visible ring into lit cross-sections and depth-sorted
  /// tube segments.
  FrameData buildFrame() {
    final frame = FrameData();
    const eyePoint = Vec3(0, 0, -Camera.focal);
    var zNear = double.infinity, zFar = -double.infinity;

    for (var ri = 0; ri < rings.length; ri++) {
      final rv = rings[ri];
      if (rv.gone) continue;
      final age = calm ? 1.0 : ((time - rv.born) / 0.34).clamp(0.0, 1.0);
      if (age <= 0) continue;
      final pop = age >= 1 ? 1.0 : _backOut(age).clamp(0.0, 1.2);
      final rel = _releaseT(rv);
      final scale = pop * (1 + 0.12 * rel);
      final lift = _lift(rv);
      var shake = 0.0;
      if (rv.shakeStart >= 0) {
        final t = (time - rv.shakeStart) / 0.3;
        if (t >= 1) {
          rv.shakeStart = -1;
        } else {
          shake = math.sin(t * math.pi * 5) * 0.11 * (1 - t);
        }
      }
      final angle = rv.angle + shake;
      final f = rv.frame;
      // Round rings turn; frames stay put and only their opening is placed.
      final turnShape = f.round ? 0.0 : shake;

      // Openings. A sealed ring is closed; its opening grows in when unsealed.
      var gapWidth = kGapAngle;
      if (rv.sealed) {
        gapWidth = 0;
      } else if (rv.unsealStart >= 0) {
        final t = ((time - rv.unsealStart) / 0.3).clamp(0.0, 1.0);
        gapWidth = kGapAngle * t;
        if (t >= 1) rv.unsealStart = -1;
      }
      final gapCentres = rv.def.kind == RingKind.twin
          ? [angle, angle + math.pi]
          : [angle];
      final arcs = _arcsFor(gapCentres, gapWidth);
      final capped = gapWidth > 0.001;

      final center = f.center + lift;
      final vc = camera.toView(center);
      final tubeWorld = kTubeRadius * scale;
      final outline = RingOutline(
        ri,
        camera.project(vc),
        2 * tubeWorld * camera.unit * camera.scaleAt(vc.z),
      );
      frame.outlines[ri] = outline;
      final trace = RingTrace(ri, outline.tube / 2);
      frame.traces.add(trace);

      // Enough stations that each piece of tube is a few pixels long.
      final ringPx = f.radius * camera.unit * camera.scaleAt(vc.z);
      final steps = (ringPx * 0.55).round().clamp(32, 72);
      final markAngle =
          angle + (rv.def.kind == RingKind.twin ? math.pi / 2 : math.pi);
      final geared = rv.def.kind == RingKind.geared;
      var index = 0;
      var sealPlaced = false, markPlaced = false;

      for (final arc in arcs) {
        final n = math.max(4, (steps * arc.$2 / (2 * math.pi)).round());
        final run = TubeRun(ri, age, rel > 0, capped)..firstIndex = index;
        frame.runs.add(run);
        Vec3? prevSide;
        for (var i = 0; i <= n; i++) {
          final theta = arc.$1 + arc.$2 * i / n;
          final shapeTheta = theta + turnShape;
          final world =
              center + f.radial(shapeTheta) * (f.radiusAt(shapeTheta) * scale);
          // Direction of travel along the tube, found numerically so it is
          // right for frames as well as circles.
          const h = 0.02;
          final ahead =
              f.radial(shapeTheta + h) * f.radiusAt(shapeTheta + h) -
              f.radial(shapeTheta - h) * f.radiusAt(shapeTheta - h);
          final v = camera.toView(world);
          final tangent = camera.rotate(ahead).normalized();
          final eye = (eyePoint - v).normalized();
          var side = tangent.cross(eye);
          final sideLength = side.length;
          side = sideLength < 1e-4
              ? (prevSide ?? const Vec3(1, 0, 0))
              : side * (1 / sideLength);
          // Keep the same side of the tube on the same side of the strip.
          if (prevSide != null && side.dot(prevSide) < 0) side = side * -1;
          // Where the tube points almost straight at the viewer, "across"
          // is poorly defined: lean on the previous station so the strip
          // does not twist.
          if (prevSide != null && sideLength < 0.22) {
            final keep = 1 - sideLength / 0.22;
            side = (side * (1 - keep) + prevSide * keep).normalized();
          }
          prevSide = side;
          var front = eye - tangent * tangent.dot(eye);
          final frontLength = front.length;
          front = frontLength < 1e-4 ? eye : front * (1 / frontLength);

          final p = camera.project(v);
          final station = Station(
            theta,
            p,
            v.z,
            camera.project(v + side * tubeWorld) - p,
            camera.project(v + tangent * tubeWorld) - p,
            side,
            front,
            tangent,
            eye,
          );
          if (rv.sealed && _near(theta, angle, kGapAngle / 2)) {
            station.band = true;
          }
          station.rib = geared && i % 3 == 0 && i != 0 && i != n;
          run.stations.add(station);
          frame.stationCount++;

          outline.points.add(p);
          outline.thetas.add(theta);
          trace.xs.add(p.dx);
          trace.ys.add(p.dy);
          trace.zs.add(v.z);
          trace.thetas.add(theta);

          if (i > 0) {
            final before = run.stations[i - 1];
            final z = (before.z + v.z) / 2;
            final seg = TubeSeg(run, i - 1, index, z);
            final mid = (before.theta + theta) / 2;
            final half = arc.$2 / n * 0.51;
            if (rv.sealed && !sealPlaced && _near(mid, angle, half)) {
              seg.deco = 1;
              sealPlaced = true;
            } else if (!markPlaced && _near(mid, markAngle, half)) {
              seg.deco = 2;
              markPlaced = true;
            } else if (!f.round &&
                f.shape == RingShape.square &&
                _near(mid % (math.pi / 2), math.pi / 4, half)) {
              seg.deco = 4;
            }
            frame.segs.add(seg);
            if (z < zNear) zNear = z;
            if (z > zFar) zFar = z;
            index++;
          }
        }
      }
    }
    frame.segs.sort((a, b) => b.z.compareTo(a.z));
    frame.zNear = zNear.isFinite ? zNear : 0;
    frame.zFar = zFar.isFinite ? zFar : 1;
    lastFrame = frame;
    return frame;
  }

  static bool _near(double a, double b, double tolerance) {
    var d = (a - b) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return d.abs() <= tolerance;
  }

  static List<(double, double)> _arcsFor(List<double> gaps, double width) {
    if (width <= 0.001) return const [(0, 2 * math.pi)];
    final out = <(double, double)>[];
    for (var i = 0; i < gaps.length; i++) {
      final start = gaps[i] + width / 2;
      final next = i + 1 < gaps.length ? gaps[i + 1] : gaps[0] + 2 * math.pi;
      out.add((start, next - width / 2 - start));
    }
    return out;
  }

  /// Screen position of the point on [ring] at quarter position [pos].
  Offset pointAt(int ring, int pos) {
    final f = rings[ring].frame;
    return camera.projectWorld(f.pointAt(pos * kQuarterTurn));
  }

  // ------------------------------------------------------------ touch
  /// The ring a finger at [p] means. See [pickRing] for the rule.
  HitResult? hit(Offset p, {double reach = 26}) {
    final frame = lastFrame;
    if (frame == null) return null;
    final pick = pickRing(
      frame.traces.where((t) {
        final rv = rings[t.ring];
        return !rv.gone && !rv.leaving && rv.releaseStart < 0;
      }),
      p.dx,
      p.dy,
      reach: reach,
      depthWeight: 6,
    );
    return pick == null ? null : HitResult(pick.ring, pick.theta);
  }

  /// How far (in radians) a ring turns when the finger holding it at local
  /// angle [theta] moves by [delta] pixels: the grabbed point follows the
  /// finger along the ring.
  double dragDelta(int ring, double theta, Offset delta) {
    final f = rings[ring].frame;
    final a = camera.projectWorld(f.center + f.radial(theta - 0.05) * f.radius);
    final b = camera.projectWorld(f.center + f.radial(theta + 0.05) * f.radius);
    final tangent = (b - a) / 0.1; // pixels per radian
    final floor = camera.unit * 0.35;
    final len2 = math.max(tangent.distanceSquared, floor * floor);
    return (delta.dx * tangent.dx + delta.dy * tangent.dy) / len2;
  }
}
