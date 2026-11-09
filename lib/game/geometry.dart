/// 3D geometry shared by the renderer and the level generator.
library;

import 'dart:math' as math;

import 'level.dart';

/// Distance between neighbouring lattice cells, in standard ring radii.
const double kSpacing = 1.3;

/// Radius of the tube a ring is made of, in standard ring radii.
const double kTubeRadius = 0.1;

/// Angular width of a ring's opening, in radians.
const double kGapAngle = 0.72;

const double kQuarterTurn = math.pi / 2;

class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;

  static const zero = Vec3(0, 0, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 normalized() {
    final l = length;
    return l == 0 ? this : Vec3(x / l, y / l, z / l);
  }

  static Vec3 lerp(Vec3 a, Vec3 b, double t) => a + (b - a) * t;
}

const List<Vec3> _axes = [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)];

Vec3 axisVec(int axis) => _axes[axis];

/// How far a shape's outline is from its centre at [theta], as a fraction of
/// the ring's radius. Every shape fits inside the round ring.
double shapeFactor(RingShape shape, double theta) {
  switch (shape) {
    case RingShape.round:
      return 1;
    case RingShape.square:
      // A rounded square: corners touch the circle, sides sit at 0.84.
      final c = math.cos(theta).abs(), s = math.sin(theta).abs();
      final c2 = c * c, s2 = s * s;
      return 0.841 / math.sqrt(math.sqrt(c2 * c2 + s2 * s2));
    case RingShape.triangle:
      // Point up, flat base. Sides sit at 0.78, corners are arcs of the circle.
      const third = 2 * math.pi / 3;
      var a = (theta - 3 * math.pi / 2) % third;
      if (a > third / 2) a -= third;
      return math.min(1.0, 0.78 / math.cos(a));
    case RingShape.dee:
      // A circle with one flat side, on the left.
      final c = math.cos(theta);
      return c < -0.7 ? 0.7 / -c : 1;
  }
}

/// World-space frame of a ring: centre, the two in-plane axes and the normal.
class RingFrame {
  RingFrame(RingDef def)
    : center = Vec3(
        def.cell[0] * kSpacing,
        def.cell[1] * kSpacing,
        def.cell[2] * kSpacing,
      ),
      radius = def.size / 100,
      shape = def.kind == RingKind.fixed
          ? (def.shape == RingShape.round ? RingShape.square : def.shape)
          : RingShape.round {
    final u0 = axisVec(planeU(def.plane));
    final v0 = axisVec(planeV(def.plane));
    final n0 = axisVec(planeN(def.plane));
    if (def.tilt == 0) {
      u = u0;
      v = v0;
      n = n0;
    } else {
      final t = def.tilt * math.pi / 180;
      final c = math.cos(t), s = math.sin(t);
      if (def.tiltAxis == 0) {
        u = u0;
        v = v0 * c + n0 * s;
        n = n0 * c - v0 * s;
      } else {
        v = v0;
        u = u0 * c - n0 * s;
        n = n0 * c + u0 * s;
      }
    }
  }

  final Vec3 center;
  late final Vec3 u;
  late final Vec3 v;
  late final Vec3 n;
  final double radius;
  final RingShape shape;

  bool get round => shape == RingShape.round;

  /// Distance from the centre to the wire at local angle [theta].
  double radiusAt(double theta) => radius * shapeFactor(shape, theta);

  /// Unit direction from the centre at local angle [theta].
  Vec3 radial(double theta) => u * math.cos(theta) + v * math.sin(theta);

  Vec3 pointAt(double theta) => center + radial(theta) * radiusAt(theta);
}

/// Smallest distance between the wires of two rings, by sampling.
double ringClearance(RingFrame a, RingFrame b, {int samples = 48}) {
  var best = double.infinity;
  final pb = [
    for (var j = 0; j < samples; j++) b.pointAt(2 * math.pi * j / samples),
  ];
  for (var i = 0; i < samples; i++) {
    final p = a.pointAt(2 * math.pi * i / samples);
    for (final q in pb) {
      final d = (p - q).length;
      if (d < best) best = d;
    }
  }
  return best;
}

/// True when ring [a]'s wire passes through the hole of ring [b].
bool ringPierces(RingFrame a, RingFrame b, {int samples = 96}) {
  double side(Vec3 p) => (p - b.center).dot(b.n);
  var prev = a.pointAt(0);
  var prevSide = side(prev);
  for (var i = 1; i <= samples; i++) {
    final p = a.pointAt(2 * math.pi * i / samples);
    final s = side(p);
    if ((prevSide <= 0 && s > 0) || (prevSide >= 0 && s < 0)) {
      final t = prevSide / (prevSide - s);
      final hit = Vec3.lerp(prev, p, t) - b.center;
      final angle = math.atan2(hit.dot(b.v), hit.dot(b.u));
      if (hit.length < b.radiusAt(angle) - 0.02) return true;
    }
    prev = p;
    prevSide = s;
  }
  return false;
}

/// Gap between two linked wires where they hook: the sum of both rings'
/// radii at the link, less the lattice spacing.
double linkSeparation(RingFrame a, int pa, RingFrame b, int pb) =>
    a.radiusAt(pa * kQuarterTurn) + b.radiusAt(pb * kQuarterTurn) - kSpacing;
