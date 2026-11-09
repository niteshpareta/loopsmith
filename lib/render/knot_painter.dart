import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/geometry.dart';
import '../game/level.dart';
import '../game/skins.dart';
import 'palette.dart';
import 'scene.dart';

/// Draws the knot.
///
/// There is no 3D engine here. Every ring is a tube built from lit
/// cross-sections; the pieces of tube from all rings are sorted far to near
/// and sent to the GPU as one triangle mesh. Sorting is what makes rings pass
/// over and under each other, and the per-vertex lighting is what makes them
/// read as round enamel, metal or stone.
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

  /// Positions across the tube, from one edge (-1) to the other (1). Closer
  /// together near the edges, where the shading changes fastest.
  static const _across = [
    -1.0,
    -0.86,
    -0.62,
    -0.32,
    0.0,
    0.32,
    0.62,
    0.86,
    1.0,
  ];
  static const _perStation = 11; // the nine above plus a soft edge each side

  // Light directions in view space (x right, y up, z away from the viewer).
  static const _keyX = -0.4206, _keyY = 0.7477, _keyZ = -0.5140;
  static const _fillX = 0.7245, _fillY = -0.1672, _fillZ = -0.6688;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = scene.buildFrame();
    if (frame.segs.isEmpty && scene.particles.isEmpty) return;
    if (groundShadow) _shadows(canvas);
    _underglow(canvas, frame);
    _tubes(canvas, frame);
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
      final r = cam.unit * cam.scaleAt(view.z) * 0.95 * rv.frame.radius;
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

  // ------------------------------------------------------------ lighting
  /// The colour of a point on a tube whose surface normal is (nx, ny, nz),
  /// as a packed ARGB value.
  int _lit(
    Color albedo,
    double nx,
    double ny,
    double nz,
    Vec3 eye, {
    required Finish finish,
    required double fog,
    required Color fogTo,
    required double alpha,
    double darken = 1,
    double whiten = 0,
  }) {
    final gloss = skin.def.gloss;
    final ar = albedo.r * darken,
        ag = albedo.g * darken,
        ab = albedo.b * darken;
    final nl = math.max(0.0, nx * _keyX + ny * _keyY + nz * _keyZ);
    final nf = math.max(0.0, nx * _fillX + ny * _fillY + nz * _fillZ);
    final ne = math.max(0.0, nx * eye.x + ny * eye.y + nz * eye.z);
    // Half-way vector between the key light and the eye, for highlights.
    var hx = _keyX + eye.x, hy = _keyY + eye.y, hz = _keyZ + eye.z;
    final hl = math.sqrt(hx * hx + hy * hy + hz * hz);
    hx /= hl;
    hy /= hl;
    hz /= hl;
    final nh = math.max(0.0, nx * hx + ny * hy + nz * hz);

    double r, g, b;
    var edgeFloor = 0.34;
    switch (finish) {
      case Finish.gloss:
        final diffuse = 0.26 + 0.66 * nl + 0.12 * nf;
        final shine =
            math.pow(nh, 56) * (0.25 + 0.55 * gloss) +
            math.pow(nh, 9) * 0.1 * gloss;
        r = ar * diffuse + shine;
        g = ag * diffuse + shine;
        b = ab * diffuse + shine;
      case Finish.metal:
        // Reflect the eye ray and look up a simple studio: bright sky above,
        // a dark horizon line, and one soft light box.
        final k = 2 * (nx * eye.x + ny * eye.y + nz * eye.z);
        final rx = k * nx - eye.x, ry = k * ny - eye.y;
        final sky = _smooth(-0.3, 0.7, ry);
        final horizon = math.exp(-math.pow((ry - 0.02) / 0.22, 2));
        final box = math.exp(
          -(math.pow(rx + 0.42, 2) + math.pow(ry - 0.7, 2)) / 0.035,
        );
        final env = (0.16 + 0.92 * sky - 0.3 * horizon + 0.12 * nf) * 1.18;
        final glint = box * 0.85;
        r = ar * env + (ar + (1 - ar) * 0.6) * glint;
        g = ag * env + (ag + (1 - ag) * 0.6) * glint;
        b = ab * env + (ab + (1 - ab) * 0.6) * glint;
      case Finish.stone:
        final wrap = math.pow(
          math.max(0.0, (nx * _keyX + ny * _keyY + nz * _keyZ) * 0.5 + 0.5),
          1.5,
        );
        final diffuse = 0.36 + 0.62 * wrap + 0.08 * nf + 0.1 * (1 - ne);
        final shine = math.pow(nh, 14) * 0.1;
        r = ar * diffuse + shine;
        g = ag * diffuse + shine;
        b = ab * diffuse + shine;
      case Finish.neon:
        final core = 0.5 * math.pow(ne, 6);
        final body = 0.72 + 0.28 * ne;
        r = ar * body + core;
        g = ag * body + core;
        b = ab * body + core;
        edgeFloor = 0.62;
    }

    // Darken toward the silhouette. This is the ink line that separates one
    // ring from the ring behind it.
    final edge = edgeFloor + (1 - edgeFloor) * _smooth(0, 0.42, ne);
    r *= edge;
    g *= edge;
    b *= edge;
    if (whiten > 0) {
      r += (1 - r) * whiten;
      g += (1 - g) * whiten;
      b += (1 - b) * whiten;
    }
    if (fog > 0) {
      r += (fogTo.r - r) * fog;
      g += (fogTo.g - g) * fog;
      b += (fogTo.b - b) * fog;
    }
    return _pack(r, g, b, alpha);
  }

  static double _smooth(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static int _pack(double r, double g, double b, double a) =>
      ((a.clamp(0.0, 1.0) * 255).round() << 24) |
      ((r.clamp(0.0, 1.0) * 255).round() << 16) |
      ((g.clamp(0.0, 1.0) * 255).round() << 8) |
      (b.clamp(0.0, 1.0) * 255).round();

  // ------------------------------------------------------------ the mesh
  void _tubes(Canvas canvas, FrameData frame) {
    if (frame.segs.isEmpty) return;
    final pos = <double>[];
    final col = <int>[];
    final idx = <int>[];
    final depth = math.max(0.001, frame.zFar - frame.zNear);
    final fogTo = palette.dark
        ? palette.bg
        : Color.lerp(palette.bg, palette.dim, 0.45)!;
    final finish = skin.def.finish;

    int vertex(Offset p, int color) {
      pos
        ..add(p.dx)
        ..add(p.dy);
      col.add(color);
      return col.length - 1;
    }

    // 1. Light every cross-section once.
    for (final run in frame.runs) {
      final rv = scene.rings[run.ring];
      final base = skin.color(rv.def.color);
      final whiten = run.releasing ? 0.28 : 0.0;
      for (final s in run.stations) {
        s.base = col.length;
        final fog = ((s.z - frame.zNear) / depth) * 0.22;
        final width = s.lateral.distance;
        final soft = width <= 0 ? 0.0 : 1.3 / width;
        final albedo = s.band ? _bandColor : base;
        final look = s.band ? Finish.stone : finish;
        for (var k = 0; k < _across.length; k++) {
          final t = _across[k];
          final up = math.sqrt(math.max(0.0, 1 - t * t));
          final c = _lit(
            albedo,
            s.side.x * t + s.front.x * up,
            s.side.y * t + s.front.y * up,
            s.side.z * t + s.front.z * up,
            s.eye,
            finish: look,
            fog: fog,
            fogTo: fogTo,
            alpha: run.alpha,
            darken: s.rib ? 0.5 : 1,
            whiten: whiten,
          );
          // A see-through twin of each edge vertex softens the silhouette.
          if (k == 0) vertex(s.screen + s.lateral * (t - soft), c & 0x00FFFFFF);
          vertex(s.screen + s.lateral * t, c);
          if (k == _across.length - 1) {
            vertex(s.screen + s.lateral * (t + soft), c & 0x00FFFFFF);
          }
        }
      }
    }

    // 2. Seal dots and colour marks are wider than one piece of tube, so they
    // wait until the pieces either side of them have been added.
    final order = <int, int>{};
    for (var i = 0; i < frame.segs.length; i++) {
      order[frame.segs[i].run.ring * 512 + frame.segs[i].index] = i;
    }
    final waiting = <int, List<TubeSeg>>{};
    for (var i = 0; i < frame.segs.length; i++) {
      final s = frame.segs[i];
      if (s.deco != 1 && s.deco != 2) continue;
      var last = i;
      for (var d = -4; d <= 4; d++) {
        final at = order[s.run.ring * 512 + s.index + d];
        if (at != null && at > last) last = at;
      }
      (waiting[last] ??= []).add(s);
    }

    void disc(Offset c, double radius, int color, {int sides = 14}) {
      final centre = vertex(c, color);
      final rim = col.length;
      for (var i = 0; i < sides; i++) {
        final a = 2 * math.pi * i / sides;
        vertex(c + Offset(math.cos(a), math.sin(a)) * radius, color);
      }
      final soft = col.length;
      for (var i = 0; i < sides; i++) {
        final a = 2 * math.pi * i / sides;
        vertex(
          c + Offset(math.cos(a), math.sin(a)) * (radius + 1.2),
          color & 0x00FFFFFF,
        );
      }
      for (var i = 0; i < sides; i++) {
        final j = (i + 1) % sides;
        idx
          ..add(centre)
          ..add(rim + i)
          ..add(rim + j)
          ..add(rim + i)
          ..add(soft + i)
          ..add(rim + j)
          ..add(rim + j)
          ..add(soft + i)
          ..add(soft + j);
      }
    }

    void quad(Offset a, Offset b, Offset c, Offset d, int color) {
      final i = vertex(a, color);
      vertex(b, color);
      vertex(c, color);
      vertex(d, color);
      idx
        ..add(i)
        ..add(i + 1)
        ..add(i + 2)
        ..add(i)
        ..add(i + 2)
        ..add(i + 3);
    }

    void mark(int shape, Offset c, double s, int color) {
      switch (shape % 6) {
        case 0:
          disc(c, s * 0.5, color, sides: 10);
        case 1:
          final i = vertex(c.translate(0, -s * 0.62), color);
          vertex(c.translate(s * 0.6, s * 0.45), color);
          vertex(c.translate(-s * 0.6, s * 0.45), color);
          idx
            ..add(i)
            ..add(i + 1)
            ..add(i + 2);
        case 2:
          quad(
            c.translate(-s * 0.48, -s * 0.48),
            c.translate(s * 0.48, -s * 0.48),
            c.translate(s * 0.48, s * 0.48),
            c.translate(-s * 0.48, s * 0.48),
            color,
          );
        case 3:
          quad(
            c.translate(0, -s * 0.68),
            c.translate(s * 0.68, 0),
            c.translate(0, s * 0.68),
            c.translate(-s * 0.68, 0),
            color,
          );
        case 4:
          quad(
            c.translate(-s * 0.15, -s * 0.6),
            c.translate(s * 0.15, -s * 0.6),
            c.translate(s * 0.15, s * 0.6),
            c.translate(-s * 0.15, s * 0.6),
            color,
          );
          quad(
            c.translate(-s * 0.6, -s * 0.15),
            c.translate(s * 0.6, -s * 0.15),
            c.translate(s * 0.6, s * 0.15),
            c.translate(-s * 0.6, s * 0.15),
            color,
          );
        case 5:
          const k = 0.7071;
          for (final sign in const [1.0, -1.0]) {
            final along = Offset(k, k * sign) * (s * 0.6);
            final wide = Offset(-k * sign, k) * (s * 0.15);
            quad(
              c - along - wide,
              c + along - wide,
              c + along + wide,
              c - along + wide,
              color,
            );
          }
      }
    }

    /// A rounded end where a ring has an opening: a disc lit as a ball. It
    /// is added before the tube pieces next to it, so the tube covers the
    /// inner half and only the rounded tip shows.
    void ball(TubeRun run, Station s, double outward, Color albedo) {
      final radius = s.lateral.distance;
      if (radius <= 0) return;
      final fog = ((s.z - frame.zNear) / depth) * 0.22;
      final whiten = run.releasing ? 0.28 : 0.0;
      // Screen directions across the tube and out past its end.
      final across = s.lateral / radius;
      var out = Offset(-across.dy, across.dx);
      if (out.dx * s.along.dx * outward + out.dy * s.along.dy * outward < 0) {
        out = -out;
      }
      // The same two directions in view space, so the ball's shading meets
      // the tube's shading without a seam.
      final t = s.tangent * outward;
      var out3 = t - s.eye * t.dot(s.eye);
      out3 = out3.length < 1e-3 ? Vec3(out.dx, -out.dy, 0) : out3.normalized();

      int lit(double x, double y) {
        final a = x * across.dx + y * across.dy;
        final o = x * out.dx + y * out.dy;
        final h = math.sqrt(math.max(0.0, 1 - a * a - o * o));
        final n = (s.side * a + out3 * o + s.front * h).normalized();
        return _lit(
          albedo,
          n.x,
          n.y,
          n.z,
          s.eye,
          finish: finish,
          fog: fog,
          fogTo: fogTo,
          alpha: run.alpha,
          whiten: whiten,
        );
      }

      const sides = 16;
      final centre = vertex(s.screen, lit(0, 0));
      final rings = <int>[];
      for (final rho in [0.5, 0.82, 1.0, 1.0 + 1.3 / radius]) {
        rings.add(col.length);
        final flat = math.min(rho, 1.0);
        for (var i = 0; i < sides; i++) {
          final angle = 2 * math.pi * i / sides;
          final x = math.cos(angle), y = math.sin(angle);
          final c = lit(x * flat, y * flat);
          vertex(
            s.screen + Offset(x, y) * (radius * rho),
            rho > 1 ? c & 0x00FFFFFF : c,
          );
        }
      }
      for (var i = 0; i < sides; i++) {
        final j = (i + 1) % sides;
        idx
          ..add(centre)
          ..add(rings[0] + i)
          ..add(rings[0] + j);
        for (var ring = 0; ring + 1 < rings.length; ring++) {
          final a = rings[ring], b = rings[ring + 1];
          idx
            ..add(a + i)
            ..add(b + i)
            ..add(a + j)
            ..add(a + j)
            ..add(b + i)
            ..add(b + j);
        }
      }
    }

    // Each rounded end goes in just before the first of its neighbouring
    // tube pieces to be drawn.
    final ends = <int, List<(TubeRun, Station, double)>>{};
    for (final run in frame.runs) {
      if (!run.capped || run.stations.length < 2) continue;
      final count = run.stations.length - 1;
      final base = run.firstIndex;
      for (final end in const [0, 1]) {
        var slot = frame.segs.length;
        for (var k = 0; k < math.min(6, count); k++) {
          final index = end == 0 ? base + k : base + count - 1 - k;
          final at = order[run.ring * 512 + index];
          if (at != null && at < slot) slot = at;
        }
        if (slot == frame.segs.length) continue;
        (ends[slot] ??= []).add((
          run,
          end == 0 ? run.stations.first : run.stations.last,
          end == 0 ? -1.0 : 1.0,
        ));
      }
    }

    // 3. Add the pieces of tube far to near, with their ends and details.
    final dark = palette.shadow;
    for (var i = 0; i < frame.segs.length; i++) {
      final seg = frame.segs[i];
      final run = seg.run;
      final a = run.stations[seg.i], b = run.stations[seg.i + 1];
      for (final end in ends[i] ?? const <(TubeRun, Station, double)>[]) {
        ball(
          end.$1,
          end.$2,
          end.$3,
          skin.color(scene.rings[end.$1.ring].def.color),
        );
      }
      for (var k = 0; k < _perStation - 1; k++) {
        idx
          ..add(a.base + k)
          ..add(a.base + k + 1)
          ..add(b.base + k)
          ..add(a.base + k + 1)
          ..add(b.base + k + 1)
          ..add(b.base + k);
      }
      if (seg.deco == 4) {
        // A rivet on a square frame.
        final mid = (a.screen + b.screen) / 2;
        final w = a.lateral.distance;
        disc(
          mid,
          w * 0.4,
          _pack(dark.r, dark.g, dark.b, 0.55 * run.alpha),
          sides: 8,
        );
        disc(
          mid.translate(-w * 0.1, -w * 0.1),
          w * 0.16,
          _pack(1, 1, 1, 0.4 * run.alpha),
          sides: 6,
        );
      }
      for (final w in waiting[i] ?? const <TubeSeg>[]) {
        final wr = scene.rings[w.run.ring];
        final sa = w.run.stations[w.i], sb = w.run.stations[w.i + 1];
        final mid = (sa.screen + sb.screen) / 2;
        final width = sa.lateral.distance * 2;
        final alpha = w.run.alpha;
        if (w.deco == 1) {
          // Seal: a dot in the colour of the ring that unlocks it.
          final key = wr.def.partner >= 0
              ? scene.rings[wr.def.partner].def.color
              : 0;
          final c = skin.color(key);
          disc(mid, width * 0.46, _pack(dark.r, dark.g, dark.b, 0.75 * alpha));
          disc(mid, width * 0.33, _pack(c.r, c.g, c.b, alpha));
          disc(
            mid.translate(-width * 0.09, -width * 0.1),
            width * 0.1,
            _pack(1, 1, 1, 0.45 * alpha),
            sides: 8,
          );
        } else if (marks) {
          disc(mid, width * 0.62, _pack(dark.r, dark.g, dark.b, 0.8 * alpha));
          mark(wr.def.color, mid, width * 0.5, _pack(1, 1, 1, alpha));
        }
      }
    }

    canvas.drawVertices(
      ui.Vertices.raw(
        VertexMode.triangles,
        Float32List.fromList(pos),
        colors: Int32List.fromList(col),
        indices: Uint16List.fromList(idx),
      ),
      BlendMode.dst,
      Paint(),
    );
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

/// A ring type in words, for labels and tests.
String describeKind(RingKind kind) => switch (kind) {
  RingKind.plain => 'Plain ring',
  RingKind.twin => 'Twin ring',
  RingKind.geared => 'Geared ring',
  RingKind.fixed => 'Fixed frame',
  RingKind.sealed => 'Sealed ring',
};
