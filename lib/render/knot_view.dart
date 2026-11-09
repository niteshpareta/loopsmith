import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/geometry.dart';
import 'knot_painter.dart';
import 'palette.dart';
import 'scene.dart';

/// Shows a [KnotScene] and turns touches into ring turns and camera orbits.
///
/// - Tap a ring: one quarter turn.
/// - Drag a ring: it follows the finger and snaps to the nearest quarter.
/// - Drag anywhere else: look around the knot.
class KnotView extends StatefulWidget {
  const KnotView({
    super.key,
    required this.scene,
    required this.skin,
    this.marks = false,
    this.interactive = true,
    this.groundShadow = true,
    this.canTurn,
    this.onTap,
    this.onDragEnd,
    this.onBlocked,
    this.onTouch,
  });

  final KnotScene scene;
  final RingSkin skin;
  final bool marks;
  final bool interactive;
  final bool groundShadow;

  /// Whether a ring may be turned. Rings that may not are shaken instead.
  final bool Function(int ring)? canTurn;
  final void Function(int ring)? onTap;

  /// A drag ended with the ring [quarters] quarter turns from where it began.
  final void Function(int ring, int quarters)? onDragEnd;
  final void Function(int ring)? onBlocked;

  /// A finger went down on a ring (used to highlight a geared partner).
  final void Function(int ring)? onTouch;

  @override
  State<KnotView> createState() => _KnotViewState();
}

class _KnotViewState extends State<KnotView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _dragRing = -1;
  double _grabTheta = 0;
  double _dragAngle = 0;
  bool _orbiting = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    widget.scene.tick(dt.clamp(0.0, 0.05));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _panStart(DragStartDetails d) {
    final hit = widget.scene.hit(d.localPosition);
    if (hit != null && (widget.canTurn?.call(hit.ring) ?? true)) {
      _dragRing = hit.ring;
      _grabTheta = hit.theta;
      _dragAngle = 0;
      widget.onTouch?.call(hit.ring);
    } else {
      if (hit != null) widget.onBlocked?.call(hit.ring);
      _orbiting = true;
    }
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_dragRing >= 0) {
      _dragAngle += widget.scene.dragDelta(
        _dragRing,
        _grabTheta + _dragAngle,
        d.delta,
      );
      widget.scene.dragTo(_dragRing, _dragAngle);
    } else if (_orbiting) {
      widget.scene.orbit(d.delta.dx, d.delta.dy);
    }
  }

  void _panEnd([DragEndDetails? d]) {
    if (_dragRing >= 0) {
      final quarters = (_dragAngle / kQuarterTurn).round();
      widget.onDragEnd?.call(_dragRing, quarters);
    }
    _dragRing = -1;
    _orbiting = false;
  }

  void _tapUp(TapUpDetails d) {
    final hit = widget.scene.hit(d.localPosition);
    if (hit == null) return;
    if (widget.canTurn?.call(hit.ring) ?? true) {
      widget.onTap?.call(hit.ring);
    } else {
      widget.onBlocked?.call(hit.ring);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final paint = LayoutBuilder(
      builder: (context, box) {
        widget.scene.resize(box.biggest);
        return RepaintBoundary(
          child: CustomPaint(
            size: box.biggest,
            painter: KnotPainter(
              scene: widget.scene,
              skin: widget.skin,
              palette: palette,
              marks: widget.marks,
              groundShadow: widget.groundShadow,
            ),
          ),
        );
      },
    );
    if (!widget.interactive) return IgnorePointer(child: paint);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _tapUp,
      onPanStart: _panStart,
      onPanUpdate: _panUpdate,
      onPanEnd: _panEnd,
      onPanCancel: _panEnd,
      child: paint,
    );
  }
}
