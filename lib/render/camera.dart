import 'dart:math' as math;
import 'dart:ui';

import '../game/geometry.dart';

/// An orbiting perspective camera.
///
/// View space has x to the right, y up and z away from the viewer.
class Camera {
  double yaw = -0.5;
  double pitch = 0.42;

  /// Screen pixels per world unit at the target's depth.
  double unit = 80;

  /// World point the camera looks at.
  Vec3 target = Vec3.zero;

  /// Where [target] lands on screen.
  Offset center = Offset.zero;

  /// Distance from the eye to the target, in world units. Smaller is a
  /// stronger perspective.
  static const double focal = 9;

  double _cy = 1, _sy = 0, _cp = 1, _sp = 0;

  void update() {
    _cy = math.cos(yaw);
    _sy = math.sin(yaw);
    _cp = math.cos(pitch);
    _sp = math.sin(pitch);
  }

  Vec3 rotate(Vec3 d) {
    final x = d.x * _cy + d.z * _sy;
    final z = -d.x * _sy + d.z * _cy;
    return Vec3(x, d.y * _cp - z * _sp, d.y * _sp + z * _cp);
  }

  Vec3 toView(Vec3 world) => rotate(world - target);

  double scaleAt(double z) => focal / (focal + z);

  Offset project(Vec3 view) {
    final s = scaleAt(view.z) * unit;
    return Offset(center.dx + view.x * s, center.dy - view.y * s);
  }

  Offset projectWorld(Vec3 world) => project(toView(world));
}
