/// Camera maths, ring picking and a readability score, in plain Dart so the
/// level generator and the app use exactly the same logic.
library;

import 'dart:math' as math;

import 'geometry.dart';

/// Distance from the eye to the look-at point, in ring radii.
const double kFocal = 9;

/// An orbiting perspective view. View space has x right, y up, z away.
class Projector {
  Projector(double yaw, double pitch)
    : _cy = math.cos(yaw),
      _sy = math.sin(yaw),
      _cp = math.cos(pitch),
      _sp = math.sin(pitch);

  final double _cy, _sy, _cp, _sp;

  Vec3 rotate(Vec3 d) {
    final x = d.x * _cy + d.z * _sy;
    final z = -d.x * _sy + d.z * _cy;
    return Vec3(x, d.y * _cp - z * _sp, d.y * _sp + z * _cp);
  }

  static double scaleAt(double z) => kFocal / (kFocal + z);
}

/// A ring's centre line on screen, with depth.
class RingTrace {
  RingTrace(this.ring, this.halfWidth);
  final int ring;

  /// Half the tube's width on screen, in the same units as [xs].
  final double halfWidth;
  final List<double> xs = [];
  final List<double> ys = [];
  final List<double> zs = [];
  final List<double> thetas = [];
}

class Pick {
  const Pick(this.ring, this.theta);
  final int ring;
  final double theta;
}

double _segmentDistance(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final abx = bx - ax, aby = by - ay;
  final len2 = abx * abx + aby * aby;
  var t = len2 == 0 ? 0.0 : ((px - ax) * abx + (py - ay) * aby) / len2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final dx = px - (ax + abx * t), dy = py - (ay + aby * t);
  return math.sqrt(dx * dx + dy * dy);
}

/// Which ring a finger at ([x], [y]) means.
///
/// If the finger is on a tube, the front-most tube under it wins: that is the
/// one the player sees. Otherwise the nearest tube within [reach] wins, with
/// a small preference for rings closer to the viewer.
Pick? pickRing(
  Iterable<RingTrace> traces,
  double x,
  double y, {
  required double reach,
  required double depthWeight,
}) {
  Pick? under, near;
  var underZ = double.infinity, nearScore = double.infinity;
  for (final t in traces) {
    final inside = t.halfWidth * 1.2;
    final limit = math.max(reach, inside);
    for (var i = 0; i + 1 < t.xs.length; i++) {
      if ((t.thetas[i + 1] - t.thetas[i]).abs() > 0.5) continue; // an opening
      final d = _segmentDistance(
        x,
        y,
        t.xs[i],
        t.ys[i],
        t.xs[i + 1],
        t.ys[i + 1],
      );
      if (d > limit) continue;
      final z = (t.zs[i] + t.zs[i + 1]) / 2;
      final theta = (t.thetas[i] + t.thetas[i + 1]) / 2;
      if (d <= inside && z < underZ) {
        underZ = z;
        under = Pick(t.ring, theta);
      }
      final score = d + z * depthWeight;
      if (score < nearScore) {
        nearScore = score;
        near = Pick(t.ring, theta);
      }
    }
  }
  return under ?? near;
}

class Readability {
  const Readability(this.score, this.width, this.height);

  /// 0 to 1: how reliably a slightly inaccurate tap lands on the ring it was
  /// aimed at, for the hardest-to-hit ring in the knot.
  final double score;

  /// Size of the knot on screen, in ring radii.
  final double width;
  final double height;
}

/// Scores a view of a knot by simulating taps on every ring.
Readability readability(List<RingFrame> frames, double yaw, double pitch) {
  const samples = 32;
  final view = Projector(yaw, pitch);
  var cx = 0.0, cy = 0.0, cz = 0.0;
  for (final f in frames) {
    cx += f.center.x;
    cy += f.center.y;
    cz += f.center.z;
  }
  final mid = Vec3(cx / frames.length, cy / frames.length, cz / frames.length);

  final traces = <RingTrace>[];
  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (var r = 0; r < frames.length; r++) {
    final t = RingTrace(r, kTubeRadius);
    for (var i = 0; i <= samples; i++) {
      final theta = 2 * math.pi * i / samples;
      final p = view.rotate(frames[r].pointAt(theta) - mid);
      final s = Projector.scaleAt(p.z);
      t.xs.add(p.x * s);
      t.ys.add(p.y * s);
      t.zs.add(p.z);
      t.thetas.add(theta);
      minX = math.min(minX, p.x * s);
      maxX = math.max(maxX, p.x * s);
      minY = math.min(minY, p.y * s);
      maxY = math.max(maxY, p.y * s);
    }
    traces.add(t);
  }

  // A finger misses by a little: about 6 px on a phone showing this knot.
  const miss = 0.09;
  const offsets = [
    [miss, 0.0],
    [-miss, 0.0],
    [0.0, miss],
    [0.0, -miss],
  ];
  var worst = 1.0;
  for (final t in traces) {
    var visible = 0, tries = 0, hits = 0;
    for (var i = 0; i < samples; i++) {
      final x = t.xs[i], y = t.ys[i], z = t.zs[i];
      var hidden = false;
      for (final o in traces) {
        if (identical(o, t) || hidden) continue;
        for (var k = 0; k < samples; k++) {
          if ((o.zs[k] + o.zs[k + 1]) / 2 > z - 0.12) continue;
          if (_segmentDistance(
                x,
                y,
                o.xs[k],
                o.ys[k],
                o.xs[k + 1],
                o.ys[k + 1],
              ) <
              kTubeRadius * 1.6) {
            hidden = true;
            break;
          }
        }
      }
      if (hidden) continue;
      visible++;
      for (final o in offsets) {
        tries++;
        final pick = pickRing(
          traces,
          x + o[0],
          y + o[1],
          reach: 0.34,
          depthWeight: 0.09,
        );
        if (pick?.ring == t.ring) hits++;
      }
    }
    final seen = visible / samples;
    final accuracy = tries == 0 ? 0.0 : hits / tries;
    // A ring seen edge-on collapses into a bar: its opening cannot be read.
    // 1 is face-on, 0 is edge-on.
    final facing = view.rotate(frames[t.ring].n).z.abs();
    final open = ((facing - 0.1) / 0.25).clamp(0.0, 1.0);
    // A ring that is mostly hidden is hard to find even if taps on it land.
    final ringScore = accuracy * math.min(1.0, seen / 0.35) * open;
    if (ringScore < worst) worst = ringScore;
  }
  return Readability(worst, maxX - minX, maxY - minY);
}

/// The view, from a fixed set, that shows a knot most clearly on a phone held
/// upright. Returns `[yaw, pitch, score]`.
List<double> bestView(List<RingFrame> frames) {
  // Three-quarter views only: from straight ahead or straight above, a
  // third of the rings would be edge-on.
  const yaws = [-0.9, -0.72, -0.55, 0.55, 0.72, 0.9];
  const pitches = [0.4, 0.52, 0.64];
  var best = const [-0.5, 0.42, 0.0];
  var bestScore = -1.0;
  for (final pitch in pitches) {
    for (final yaw in yaws) {
      final r = readability(frames, yaw, pitch);
      // Prefer views that also let the rings be drawn larger: the play area
      // is roughly 4 wide by 5 tall.
      final fit = math.min(4 / (r.width + 0.6), 5 / (r.height + 0.6));
      final score = r.score + 0.08 * math.min(1.0, fit);
      if (score > bestScore) {
        bestScore = score;
        best = [yaw, pitch, r.score];
      }
    }
  }
  return best;
}
