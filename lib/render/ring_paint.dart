import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';

/// Draws a ring flat on screen from two basis vectors. Used for rings in
/// flight and for the small rings on pegs, in the tray and in menus.
///
/// [u] and [v] are the ring's local x and y axes in pixels, so an untilted
/// ring of radius r has `u = (r, 0)` and `v = (0, -r)`.
void paintFlatRing(
  Canvas canvas,
  Offset center,
  Offset u,
  Offset v,
  double tube,
  Color color, {
  double gloss = 0.6,
  List<double> gaps = const [],
  double gapWidth = 0,
  double alpha = 1,
  Color shadow = const Color(0xFF07040A),
}) {
  if (alpha <= 0 || tube <= 0) return;
  const steps = 44;
  final path = Path();
  final arcs = _arcs(gaps, gapWidth);
  for (final arc in arcs) {
    final n = math.max(2, (steps * arc.$2 / (2 * math.pi)).ceil());
    for (var i = 0; i <= n; i++) {
      final a = arc.$1 + arc.$2 * i / n;
      final p = center + u * math.cos(a) + v * math.sin(a);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (arcs.length == 1 && gapWidth <= 0) path.close();
  }
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(
    path,
    paint
      ..color = shadow.withValues(alpha: 0.55 * alpha)
      ..strokeWidth = tube + math.max(1.5, tube * 0.22),
  );
  canvas.drawPath(
    path,
    paint
      ..color = shade(color, 0.62).withValues(alpha: alpha)
      ..strokeWidth = tube,
  );
  final lift = Offset(-tube * 0.1, -tube * 0.12);
  canvas.save();
  canvas.translate(lift.dx, lift.dy);
  canvas.drawPath(
    path,
    paint
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = tube * 0.62,
  );
  canvas.translate(lift.dx, lift.dy);
  canvas.drawPath(
    path,
    paint
      ..strokeCap = StrokeCap.butt
      ..color = Colors.white.withValues(alpha: (0.14 + 0.3 * gloss) * alpha)
      ..strokeWidth = tube * 0.2,
  );
  canvas.restore();
}

/// Arcs (start, sweep) of a ring that has openings centred on [gaps].
List<(double, double)> _arcs(List<double> gaps, double width) {
  if (gaps.isEmpty || width <= 0) return const [(0, 2 * math.pi)];
  final sorted = [for (final g in gaps) g % (2 * math.pi)]..sort();
  final out = <(double, double)>[];
  for (var i = 0; i < sorted.length; i++) {
    final start = sorted[i] + width / 2;
    final next = i + 1 < sorted.length
        ? sorted[i + 1]
        : sorted[0] + 2 * math.pi;
    final sweep = next - width / 2 - start;
    if (sweep > 0) out.add((start, sweep));
  }
  return out;
}

/// Arcs of a ring whose openings are centred on [gaps]. Shared with the 3D
/// painter.
List<(double, double)> ringArcs(List<double> gaps, double width) =>
    _arcs(gaps, width);

/// Six shapes that identify the six ring colours without relying on colour.
void paintMark(Canvas canvas, int index, Offset c, double size, Color color) {
  final fill = Paint()..color = color;
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = size * 0.3
    ..strokeCap = StrokeCap.round;
  final s = size;
  switch (index % 6) {
    case 0:
      canvas.drawCircle(c, s * 0.5, fill);
    case 1:
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - s * 0.62)
          ..lineTo(c.dx + s * 0.6, c.dy + s * 0.45)
          ..lineTo(c.dx - s * 0.6, c.dy + s * 0.45)
          ..close(),
        fill,
      );
    case 2:
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: s * 0.96, height: s * 0.96),
          Radius.circular(s * 0.12),
        ),
        fill,
      );
    case 3:
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - s * 0.68)
          ..lineTo(c.dx + s * 0.68, c.dy)
          ..lineTo(c.dx, c.dy + s * 0.68)
          ..lineTo(c.dx - s * 0.68, c.dy)
          ..close(),
        fill,
      );
    case 4:
      canvas.drawLine(
        c.translate(0, -s * 0.5),
        c.translate(0, s * 0.5),
        stroke,
      );
      canvas.drawLine(
        c.translate(-s * 0.5, 0),
        c.translate(s * 0.5, 0),
        stroke,
      );
    case 5:
      canvas.drawLine(
        c.translate(-s * 0.42, -s * 0.42),
        c.translate(s * 0.42, s * 0.42),
        stroke,
      );
      canvas.drawLine(
        c.translate(-s * 0.42, s * 0.42),
        c.translate(s * 0.42, -s * 0.42),
        stroke,
      );
  }
}

enum ChipState {
  /// An empty tray or bowl slot.
  empty,

  /// A peg slot still waiting for its colour.
  wanted,

  /// A ring is here.
  filled,
}

/// A small ring shown on a peg, in the tray, or as an icon.
class RingChip extends StatelessWidget {
  const RingChip({
    super.key,
    required this.size,
    required this.state,
    this.color,
    this.colorIndex = 0,
    this.gloss = 0.6,
    this.showMark = false,
    this.next = false,
  });

  final double size;
  final ChipState state;
  final Color? color;
  final int colorIndex;
  final double gloss;

  /// Draw the colour's shape inside the ring (colour-blind marks).
  final bool showMark;

  /// This is the colour the peg wants next.
  final bool next;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ChipPainter(
          state: state,
          color: color ?? p.dim,
          line: p.line,
          shadow: p.shadow,
          colorIndex: colorIndex,
          gloss: gloss,
          showMark: showMark,
          next: next,
        ),
      ),
    );
  }
}

class _ChipPainter extends CustomPainter {
  _ChipPainter({
    required this.state,
    required this.color,
    required this.line,
    required this.shadow,
    required this.colorIndex,
    required this.gloss,
    required this.showMark,
    required this.next,
  });

  final ChipState state;
  final Color color;
  final Color line;
  final Color shadow;
  final int colorIndex;
  final double gloss;
  final bool showMark;
  final bool next;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final tube = size.width * 0.2;
    final r = size.width / 2 - tube / 2 - 1.5;
    switch (state) {
      case ChipState.empty:
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = line;
        const dashes = 10;
        for (var i = 0; i < dashes; i++) {
          final a = 2 * math.pi * i / dashes;
          canvas.drawArc(
            Rect.fromCircle(center: c, radius: r + tube * 0.2),
            a,
            math.pi / dashes,
            false,
            paint,
          );
        }
      case ChipState.wanted:
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = next ? tube * 0.55 : tube * 0.38
            ..color = color.withValues(alpha: next ? 0.95 : 0.42),
        );
        if (showMark) {
          paintMark(
            canvas,
            colorIndex,
            c,
            r * 0.62,
            color.withValues(alpha: next ? 0.95 : 0.5),
          );
        }
      case ChipState.filled:
        paintFlatRing(
          canvas,
          c,
          Offset(r, 0),
          Offset(0, -r),
          tube,
          color,
          gloss: gloss,
          shadow: shadow,
        );
        if (showMark) paintMark(canvas, colorIndex, c, r * 0.62, color);
    }
  }

  @override
  bool shouldRepaint(_ChipPainter old) =>
      old.state != state ||
      old.color != color ||
      old.showMark != showMark ||
      old.next != next ||
      old.gloss != gloss ||
      old.line != line;
}
