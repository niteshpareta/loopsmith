import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../game/geometry.dart';
import '../game/knot.dart';
import '../game/level.dart';
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

/// One short piece of a ring's tube, projected to the screen.
class Seg {
  Seg(
    this.ring,
    this.index,
    this.a,
    this.b,
    this.z,
    this.width,
    this.light,
    this.theta,
    this.alpha,
  );
  final int ring;
  final int index;
  final Offset a;
  final Offset b;
  final double z;
  final double width;
  final double light;
  final double theta;
  final double alpha;

  /// 0 none, 1 seal dot, 2 colour mark, 3 gear notch, 4 rivet.
  int deco = 0;

  /// Part of the band covering a sealed ring's opening.
  bool band = false;

  /// This segment starts or ends at an opening, so that end is rounded.
  bool capA = false;
  bool capB = false;
}

/// A ring's outline on screen, kept for hit testing and glows.
class RingOutline {
  RingOutline(this.ring, this.center, this.tube);
  final int ring;
  final Offset center;
  final double tube;
  final List<Offset> points = [];
  final List<double> thetas = [];
  final List<double> depths = [];
}

class FrameData {
  final List<Seg> segs = [];
  final Map<int, RingOutline> outlines = {};
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
  static const Vec3 _light = Vec3(-0.42, 0.72, -0.55);

  /// Shows [knot] as it is, optionally popping the rings in one by one.
  void load(LevelDef level, Knot knot, {bool animate = false}) {
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
      low = math.min(low, rv.frame.center.y - 1);
    }
    groundY = (low.isFinite ? low : -1) - 0.75;
    flashes.clear();
    particles.clear();
    hintRing = -1;
    syncGlows(knot);
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
    final scale = 1 + 0.12 * _releaseT(rv);
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
    camera.yaw = _yaw + sway * 0.07 * math.sin(time * 0.33);
    camera.pitch = _pitch + sway * 0.025 * math.sin(time * 0.24 + 1);
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
      final shortest = math.min(size.width, size.height);
      _unitGoal = math.min(
        math.min(size.width * 0.94 / w, size.height * 0.94 / h),
        shortest * 0.26,
      );
      _centerGoal = Offset(
        size.width / 2 - (minX + maxX) / 2 * _unitGoal,
        size.height / 2 + (minY + maxY) / 2 * _unitGoal,
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
  /// Projects every visible ring into depth-sorted tube segments.
  FrameData buildFrame() {
    final frame = FrameData();
    final light = _light.normalized();
    final steps = (camera.unit * 0.8).round().clamp(36, 72);
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

      final center = rv.frame.center + lift;
      final vc = camera.toView(center);
      final outline = RingOutline(
        ri,
        camera.project(vc),
        2 * kTubeRadius * camera.unit * camera.scaleAt(vc.z) * scale,
      );
      frame.outlines[ri] = outline;

      final markAngle =
          angle + (rv.def.kind == RingKind.twin ? math.pi / 2 : math.pi);
      var index = 0;
      // One seal dot and one colour mark per ring, even when the angle falls
      // on the boundary between two segments.
      var sealPlaced = false, markPlaced = false;
      for (final arc in arcs) {
        final n = math.max(2, (steps * arc.$2 / (2 * math.pi)).round());
        Offset? prev;
        var prevZ = 0.0;
        Vec3? prevN;
        var prevTheta = 0.0;
        for (var i = 0; i <= n; i++) {
          final theta = arc.$1 + arc.$2 * i / n;
          final radial = rv.frame.radial(theta);
          final world = center + radial * (rv.frame.radiusAt(theta) * scale);
          final v = camera.toView(world);
          final p = camera.project(v);
          final nv = camera.rotate(radial);
          outline.points.add(p);
          outline.thetas.add(theta);
          outline.depths.add(v.z);
          if (prev != null) {
            final z = (prevZ + v.z) / 2;
            final nx = (prevN!.x + nv.x) / 2,
                ny = (prevN.y + nv.y) / 2,
                nz = (prevN.z + nv.z) / 2;
            final l = (0.5 + 0.5 * (nx * light.x + ny * light.y + nz * light.z))
                .clamp(0.0, 1.0);
            final mid = (prevTheta + theta) / 2;
            final seg = Seg(
              ri,
              index,
              prev,
              p,
              z,
              2 * kTubeRadius * camera.unit * camera.scaleAt(z) * scale,
              l,
              mid,
              age,
            );
            if (rv.sealed && _near(mid, angle, kGapAngle / 2)) {
              seg.band = true;
              if (!sealPlaced && _near(mid, angle, arc.$2 / n * 0.51)) {
                seg.deco = 1;
                sealPlaced = true;
              }
            } else if (!markPlaced &&
                _near(mid, markAngle, arc.$2 / n * 0.51)) {
              seg.deco = 2;
              markPlaced = true;
            } else if (rv.def.kind == RingKind.geared && index % 4 == 1) {
              seg.deco = 3;
            } else if (rv.def.kind == RingKind.fixed &&
                _near(mid % (math.pi / 2), math.pi / 4, arc.$2 / n * 0.51)) {
              seg.deco = 4;
            }
            if (gapWidth > 0.001) {
              seg.capA = i == 1;
              seg.capB = i == n;
            }
            frame.segs.add(seg);
            if (z < zNear) zNear = z;
            if (z > zFar) zFar = z;
            index++;
          }
          prev = p;
          prevZ = v.z;
          prevN = nv;
          prevTheta = theta;
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
  /// The ring under [p], preferring the nearest one when several overlap.
  HitResult? hit(Offset p, {double reach = 28}) {
    final frame = lastFrame;
    if (frame == null) return null;
    var bestScore = double.infinity;
    HitResult? best;
    for (final o in frame.outlines.values) {
      final rv = rings[o.ring];
      if (rv.gone || rv.leaving || rv.releaseStart >= 0) continue;
      for (var i = 0; i + 1 < o.points.length; i++) {
        if ((o.thetas[i + 1] - o.thetas[i]).abs() > 0.5) {
          continue; // across a gap
        }
        final d = _distance(p, o.points[i], o.points[i + 1]);
        if (d > reach) continue;
        // Nearer rings win ties: 1 world unit of depth is worth 6 pixels.
        final score = d + (o.depths[i] - frame.zNear) * 6;
        if (score < bestScore) {
          bestScore = score;
          best = HitResult(o.ring, (o.thetas[i] + o.thetas[i + 1]) / 2);
        }
      }
    }
    return best;
  }

  static double _distance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  /// How far (in radians) a ring turns when the finger holding it at local
  /// angle [theta] moves by [delta] pixels: the grabbed point follows the
  /// finger along the ring.
  double dragDelta(int ring, double theta, Offset delta) {
    final f = rings[ring].frame;
    final a = camera.projectWorld(f.pointAt(theta - 0.05));
    final b = camera.projectWorld(f.pointAt(theta + 0.05));
    final tangent = (b - a) / 0.1; // pixels per radian
    final floor = camera.unit * 0.35;
    final len2 = math.max(tangent.distanceSquared, floor * floor);
    return (delta.dx * tangent.dx + delta.dy * tangent.dy) / len2;
  }
}
