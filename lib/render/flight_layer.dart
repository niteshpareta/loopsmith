import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'ring_paint.dart';
import 'scene.dart';

class _Flight {
  _Flight({
    required this.from,
    required this.to,
    required this.radius,
    required this.tube,
    required this.color,
    required this.gloss,
    required this.start,
    required this.seconds,
    required this.onLand,
  });
  final FlightStart from;
  final Offset to;
  final double radius;
  final double tube;
  final Color color;
  final double gloss;
  final double start;
  final double seconds;
  final VoidCallback onLand;
}

/// An overlay that carries freed rings from the knot to their slots, above
/// everything else on the play screen.
class FlightLayer extends StatefulWidget {
  const FlightLayer({super.key, this.calm = false});

  /// Reduce motion: rings arrive almost at once.
  final bool calm;

  @override
  State<FlightLayer> createState() => FlightLayerState();
}

class FlightLayerState extends State<FlightLayer>
    with SingleTickerProviderStateMixin {
  final List<_Flight> _flights = [];
  final ValueNotifier<double> _clock = ValueNotifier(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  int get active => _flights.length;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  void _onTick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    final time = _clock.value + dt.clamp(0.0, 0.05);
    final landed = [
      for (final f in _flights)
        if (time - f.start >= f.seconds) f,
    ];
    _flights.removeWhere(landed.contains);
    _clock.value = time;
    if (_flights.isEmpty) {
      _ticker.stop();
      _last = Duration.zero;
    }
    for (final f in landed) {
      f.onLand();
    }
  }

  /// Sends a ring from [from] to the point [to], shrinking to [radius].
  void launch({
    required FlightStart from,
    required Offset to,
    required double radius,
    required double tube,
    required Color color,
    required double gloss,
    required VoidCallback onLand,
    double seconds = 0.5,
  }) {
    _flights.add(
      _Flight(
        from: from,
        to: to,
        radius: radius,
        tube: tube,
        color: color,
        gloss: gloss,
        start: _clock.value,
        seconds: widget.calm ? 0.12 : seconds,
        onLand: onLand,
      ),
    );
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  /// Drops every flight without calling its landing callback.
  void clear() {
    _flights.clear();
    if (_ticker.isActive) _ticker.stop();
    _last = Duration.zero;
    _clock.value = _clock.value + 0.0001;
  }

  /// Centre of the widget with [key], in this layer's coordinates.
  Offset? centerOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final mine = context.findRenderObject() as RenderBox?;
    if (box == null || mine == null || !box.attached || !box.hasSize) {
      return null;
    }
    return mine.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
  }

  /// Converts a point in another widget's coordinates to this layer's.
  Offset? fromBox(GlobalKey key, Offset local) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final mine = context.findRenderObject() as RenderBox?;
    if (box == null || mine == null || !box.attached) return null;
    return mine.globalToLocal(box.localToGlobal(local));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _FlightPainter(_flights, _clock),
      size: Size.infinite,
    ),
  );
}

class _FlightPainter extends CustomPainter {
  _FlightPainter(this.flights, this.clock) : super(repaint: clock);
  final List<_Flight> flights;
  final ValueNotifier<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in flights) {
      final raw = ((clock.value - f.start) / f.seconds).clamp(0.0, 1.0);
      final t = Curves.easeInOutCubic.transform(raw);
      // Arc: a control point above the straight line gives a tossed feel.
      final a = f.from.center, b = f.to;
      final control = Offset(
        (a.dx + b.dx) / 2,
        (a.dy < b.dy ? a.dy : b.dy) - 40 - (a - b).distance * 0.12,
      );
      final p = Offset.lerp(
        Offset.lerp(a, control, t),
        Offset.lerp(control, b, t),
        t,
      )!;
      // The ring turns to face the viewer and closes its opening as it flies.
      final turn = Curves.easeOut.transform(raw);
      final u = Offset.lerp(f.from.u, Offset(f.radius, 0), turn)!;
      final v = Offset.lerp(f.from.v, Offset(0, -f.radius), turn)!;
      final tube = lerpDouble(f.from.tube, f.tube, turn)!;
      final gap = f.from.gapWidth * (1 - (raw * 2.2).clamp(0.0, 1.0));
      paintFlatRing(
        canvas,
        p,
        u,
        v,
        tube,
        f.color,
        gloss: f.gloss,
        gaps: f.from.gaps,
        gapWidth: gap,
      );
    }
  }

  @override
  bool shouldRepaint(_FlightPainter old) => true;
}
