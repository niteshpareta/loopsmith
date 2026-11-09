/// 3D geometry shared by the renderer and the level generator.
library;

import 'dart:math' as math;

import 'level.dart';

/// Distance between neighbouring lattice cells, in ring radii.
const double kSpacing = 1.3;

/// Radius of the tube a ring is made of, in ring radii.
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

/// World-space frame of a ring: centre, the two in-plane axes and the normal.
class RingFrame {
  RingFrame(RingDef def)
    : center = Vec3(
        def.cell[0] * kSpacing,
        def.cell[1] * kSpacing,
        def.cell[2] * kSpacing,
      ),
      u = axisVec(planeU(def.plane)),
      v = axisVec(planeV(def.plane)),
      n = axisVec(planeN(def.plane)),
      squared = def.kind == RingKind.fixed;

  final Vec3 center;
  final Vec3 u;
  final Vec3 v;
  final Vec3 n;

  /// Fixed rings are drawn as a squared frame.
  final bool squared;

  /// Distance from the centre to the wire at local angle [theta].
  double radiusAt(double theta) => squared ? squaredRadius(theta) : 1.0;

  /// Unit direction from the centre at local angle [theta].
  Vec3 radial(double theta) => u * math.cos(theta) + v * math.sin(theta);

  Vec3 pointAt(double theta) => center + radial(theta) * radiusAt(theta);
}

/// A rounded square that fits inside the unit circle: corners touch radius 1,
/// the middle of each side sits at 0.84.
double squaredRadius(double theta) {
  final c = math.cos(theta).abs(), s = math.sin(theta).abs();
  final c2 = c * c, s2 = s * s;
  return 0.841 / math.sqrt(math.sqrt(c2 * c2 + s2 * s2));
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
      final hit = Vec3.lerp(prev, p, t);
      if ((hit - b.center).length < 0.98) return true;
    }
    prev = p;
    prevSide = s;
  }
  return false;
}
