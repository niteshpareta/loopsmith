import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/geometry.dart';
import '../game/level.dart';
import 'palette.dart';
import 'ring_paint.dart';
import 'scene.dart';

/// Draws the knot.
///
/// There is no 3D engine here. Each ring is cut into short segments, every
/// segment is projected to the screen, and all segments from all rings are
/// painted far to near. That ordering is what makes rings pass over and under
/// each other correctly.
class KnotPainter extends CustomPainter {
  KnotPainter({
    required this.scene,
    required this.skin,
    required this.palette,
    this.marks = false,
    this.groundShadow = true,
  }) : super(repaint: scene);

  final KnotScene scene;
  final RingSkin skin;
  final AppPalette palette;

  /// Draw a shape on each ring so colours can be told apart without colour.
  final bool marks;

  /// Cast soft shadows onto the bench below the knot.
  final bool groundShadow;

  static const _bandColor = Color(0xFF2B2334);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = scene.buildFrame();
    if (frame.segs.isEmpty && scene.particles.isEmpty) return;
    if (groundShadow) _shadows(canvas);
    _underglow(canvas, frame);
    _rings(canvas, frame);
    _effects(canvas, frame);
  }

  /// One soft oval under each ring grounds the knot on the bench.
  void _shadows(Canvas canvas) {
    final cam = scene.camera;
    final squash = math.sin(cam.pitch).abs().clamp(0.18, 1.0);
    for (final rv in scene.rings) {
      if (rv.gone || rv.releaseStart >= 0) continue;
      final age = scene.calm
          ? 1.0
          : ((scene.time - rv.born) / 0.34).clamp(0.0, 1.0);
      if (age <= 0) continue;
      final c = rv.frame.center;
      final view = cam.toView(Vec3(c.x, scene.groundY, c.z));
      final p = cam.project(view);
      final r = cam.unit * cam.scaleAt(view.z) * 0.95;
      canvas.drawOval(
        Rect.fromCenter(center: p, width: r * 2, height: r * 2 * squash),
        Paint()
          ..color = palette.shadow.withValues(
            alpha: (palette.dark ? 0.2 : 0.1) * age,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cam.unit * 0.3),
      );
    }
  }

  /// Soft halos behind rings: the neon skin, a hinted ring, a geared partner.
  void _underglow(Canvas canvas, FrameData frame) {
    for (final o in frame.outlines.values) {
      final rv = scene.rings[o.ring];
      var strength = skin.def.glow * 0.55;
      var color = skin.color(rv.def.color);
      if (o.ring == scene.hintRing) {
        strength = math.max(strength, 0.55 + 0.35 * math.sin(scene.time * 5));
        color = tint(color, 0.35);
      }
      if (rv.glowUntil > scene.time) {
        strength = math.max(
          strength,
          0.8 * ((rv.glowUntil - scene.time) / 0.9).clamp(0.0, 1.0),
        );
        color = tint(color, 0.35);
      }
      if (rv.releaseStart >= 0) {
        strength = math.max(strength, 0.9);
        color = tint(color, 0.5);
      }
      if (strength <= 0.02 || o.points.length < 2) continue;
      final path = Path()..moveTo(o.points.first.dx, o.points.first.dy);
      for (var i = 1; i < o.points.length; i++) {
        if ((o.thetas[i] - o.thetas[i - 1]).abs() > 0.5) {
          path.moveTo(o.points[i].dx, o.points[i].dy);
        } else {
          path.lineTo(o.points[i].dx, o.points[i].dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = o.tube * 1.9
          ..color = color.withValues(alpha: 0.6 * strength.clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, o.tube * 0.9),
      );
    }
  }

  void _rings(Canvas canvas, FrameData frame) {
    final segs = frame.segs;
    final depth = math.max(0.001, frame.zFar - frame.zNear);
    final fogTo = palette.dark ? palette.bg : palette.dim;
    final gloss = skin.def.gloss;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    final fill = Paint();

    // Seal dots and colour marks are wider than one segment, so they wait
    // until the segments either side of them have been painted.
    final position = <int, int>{};
    for (var i = 0; i < segs.length; i++) {
      position[segs[i].ring * 256 + segs[i].index] = i;
    }
    final waiting = <int, List<Seg>>{};
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      if (s.deco != 1 && s.deco != 2) continue;
      var last = i;
      for (var d = -3; d <= 3; d++) {
        final at = position[s.ring * 256 + s.index + d];
        if (at != null && at > last) last = at;
      }
      (waiting[last] ??= []).add(s);
    }

    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      final rv = scene.rings[s.ring];
      final base = skin.color(rv.def.color);
      final alpha = s.alpha;
      final releasing = rv.releaseStart >= 0;
      final fog = ((s.z - frame.zNear) / depth) * 0.2;

      var body = shade(s.band ? _bandColor : base, s.light * 0.8);
      var core = shade(
        s.band ? tint(_bandColor, 0.1) : tint(base, 0.06 + 0.1 * gloss),
        0.55 + 0.45 * s.light,
      );
      if (releasing) {
        body = tint(body, 0.25);
        core = tint(core, 0.3);
      }
      body = Color.lerp(body, fogTo, fog)!.withValues(alpha: alpha);
      core = Color.lerp(core, fogTo, fog)!.withValues(alpha: alpha);
      // An opaque edge: neighbouring edge pieces overlap slightly, and a
      // see-through colour would darken at every overlap.
      final dark = Color.lerp(
        shade(base, 0.1),
        palette.shadow,
        palette.dark ? 0.72 : 0.5,
      )!.withValues(alpha: alpha);
      final lift = Offset(-s.width * 0.1, -s.width * 0.13);

      // The dark edge is two thin lines just outside the tube, so it never
      // paints over a neighbouring segment whatever order they arrive in.
      final edgeWidth = math.max(1.2, s.width * 0.11);
      final ext = _extend(s);
      final a = s.a - ext, b = s.b + ext;
      final along = s.b - s.a;
      final length = along.distance;
      final normal = length == 0
          ? Offset.zero
          : Offset(-along.dy / length, along.dx / length);
      final side = normal * (s.width / 2 + edgeWidth / 2 - 0.5);
      // Highlights shift toward the light, but only across the tube. Any
      // shift along it would open gaps between neighbouring segments.
      final across = normal * (lift.dx * normal.dx + lift.dy * normal.dy);

      // Rounded ends where the ring has an opening.
      if (s.capA || s.capB) {
        final at = s.capA ? s.a : s.b;
        final outward = s.capA ? s.a - s.b : s.b - s.a;
        final heading = math.atan2(outward.dy, outward.dx);
        canvas.drawArc(
          Rect.fromCircle(
            center: at,
            radius: s.width / 2 + edgeWidth / 2 - 0.5,
          ),
          heading - math.pi / 2,
          math.pi,
          false,
          line
            ..color = dark
            ..strokeWidth = edgeWidth,
        );
        canvas.drawCircle(at, s.width / 2, fill..color = body);
        canvas.drawCircle(at + lift, s.width * 0.29, fill..color = core);
      }

      line
        ..color = dark
        ..strokeWidth = edgeWidth;
      canvas.drawLine(a + side, b + side, line);
      canvas.drawLine(a - side, b - side, line);
      canvas.drawLine(
        a,
        b,
        line
          ..color = body
          ..strokeWidth = s.width,
      );
      canvas.drawLine(
        a + across,
        b + across,
        line
          ..color = core
          ..strokeWidth = s.width * 0.58,
      );
      if (!s.band && s.light >= 0.35) {
        final up = across * 2.1;
        canvas.drawLine(
          a + up,
          b + up,
          line
            ..color = Colors.white.withValues(
              alpha: (0.1 + 0.34 * gloss) * alpha,
            )
            ..strokeWidth = s.width * 0.17,
        );
      }

      // Small details that fit inside one segment.
      if (s.deco == 3) {
        final d = s.b - s.a;
        final len = d.distance;
        if (len > 0) {
          final n = Offset(-d.dy / len, d.dx / len) * (s.width * 0.42);
          final mid = (s.a + s.b) / 2;
          canvas.drawLine(
            mid - n,
            mid + n,
            line
              ..color = palette.shadow.withValues(alpha: 0.5 * alpha)
              ..strokeWidth = math.max(1.2, s.width * 0.16),
          );
        }
      } else if (s.deco == 4) {
        final mid = (s.a + s.b) / 2;
        canvas.drawCircle(
          mid,
          s.width * 0.2,
          fill..color = palette.shadow.withValues(alpha: 0.55 * alpha),
        );
        canvas.drawCircle(
          mid.translate(-s.width * 0.05, -s.width * 0.05),
          s.width * 0.09,
          fill..color = Colors.white.withValues(alpha: 0.35 * alpha),
        );
      }

      for (final w in waiting[i] ?? const <Seg>[]) {
        final wr = scene.rings[w.ring];
        final mid = (w.a + w.b) / 2;
        if (w.deco == 1) {
          // Seal: a dot in the colour of the ring that unlocks it.
          final key = wr.def.partner >= 0
              ? scene.rings[wr.def.partner].def.color
              : 0;
          canvas.drawCircle(
            mid,
            w.width * 0.46,
            fill..color = palette.shadow.withValues(alpha: 0.7 * w.alpha),
          );
          canvas.drawCircle(
            mid,
            w.width * 0.34,
            fill..color = skin.color(key).withValues(alpha: w.alpha),
          );
        } else if (marks) {
          canvas.drawCircle(
            mid,
            w.width * 0.62,
            fill..color = palette.shadow.withValues(alpha: 0.72 * w.alpha),
          );
          paintMark(
            canvas,
            wr.def.color,
            mid,
            w.width * 0.5,
            Colors.white.withValues(alpha: w.alpha),
          );
        }
      }
    }
  }

  /// A sliver to lengthen a flat-ended segment by, so neighbours overlap
  /// and no hairline shows between them.
  static Offset _extend(Seg s) {
    final d = s.b - s.a;
    final len = d.distance;
    return len == 0 ? Offset.zero : d * (math.max(0.7, s.width * 0.07) / len);
  }

  void _effects(Canvas canvas, FrameData frame) {
    final cam = scene.camera;
    final tube = 2 * kTubeRadius * cam.unit;

    // Openings that currently sit on a link glow softly.
    final pulse = 0.75 + 0.25 * math.sin(scene.time * 3.2);
    for (final g in scene.glows) {
      final rv = scene.rings[g.ring];
      if (rv.gone || rv.releaseStart >= 0 || rv.spinStart >= 0) continue;
      final p = scene.pointAt(g.ring, g.pos);
      canvas.drawCircle(
        p,
        tube * 1.25,
        Paint()
          ..color = tint(
            skin.color(rv.def.color),
            0.6,
          ).withValues(alpha: 0.5 * pulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, tube * 0.7)
          ..blendMode = palette.dark ? BlendMode.plus : BlendMode.srcOver,
      );
    }

    for (final f in scene.flashes) {
      final t = ((scene.time - f.start) / 0.45).clamp(0.0, 1.0);
      final p = scene.pointAt(f.ring, f.pos);
      canvas.drawCircle(
        p,
        tube * (0.8 + 2.6 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = tube * 0.3 * (1 - t)
          ..color = Colors.white.withValues(alpha: 0.8 * (1 - t)),
      );
    }

    // Hint: a pulsing dot where the opening should go.
    if (scene.hintRing >= 0 && !scene.rings[scene.hintRing].gone) {
      final p = scene.pointAt(scene.hintRing, scene.hintPos);
      final t = (scene.time * 1.1) % 1.0;
      canvas.drawCircle(
        p,
        tube * (0.7 + 1.9 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = palette.brass.withValues(alpha: 1 - t),
      );
      canvas.drawCircle(
        p,
        tube * 0.62,
        Paint()..color = palette.shadow.withValues(alpha: 0.75),
      );
      canvas.drawCircle(p, tube * 0.46, Paint()..color = palette.brass);
    }

    for (final p in scene.particles) {
      final t = ((scene.time - p.born) / p.life).clamp(0.0, 1.0);
      canvas.drawCircle(
        p.pos,
        p.size * (1 - 0.5 * t),
        Paint()
          ..color = tint(skin.color(p.color), 0.45).withValues(alpha: 1 - t)
          ..blendMode = palette.dark ? BlendMode.plus : BlendMode.srcOver,
      );
    }
  }

  @override
  bool shouldRepaint(KnotPainter old) =>
      old.skin != skin ||
      old.palette != palette ||
      old.marks != marks ||
      old.scene != scene;
}

/// A tiny helper so tests and previews can describe a ring type in words.
String describeKind(RingKind kind) => switch (kind) {
  RingKind.plain => 'Plain ring',
  RingKind.twin => 'Twin ring',
  RingKind.geared => 'Geared ring',
  RingKind.fixed => 'Fixed frame',
  RingKind.sealed => 'Sealed ring',
};
