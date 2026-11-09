import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/economy.dart';
import '../game/level.dart';
import '../l10n/strings.dart';
import '../render/flight_layer.dart';
import '../render/knot_view.dart';
import '../render/palette.dart';
import '../render/ring_paint.dart';
import '../render/scene.dart';
import '../services/audio.dart';
import '../services/services.dart';
import '../ui/widgets.dart';
import 'clear_overlay.dart';
import 'play_controller.dart';

/// The level screen: pegs on top, the knot in the middle, the tray and
/// boosters under the thumb.
/// Build with `--dart-define=DEMO=<level>` and the game opens on that level
/// and plays itself, one level after another. Meant for recording store and
/// ad videos; it is off in a normal build.
const int kDemoLevel = int.fromEnvironment('DEMO');

class PlayScreen extends StatefulWidget {
  const PlayScreen({
    super.key,
    required this.level,
    this.mode = PlayMode.campaign,
    this.dailyNumber = 0,
    this.weeklyIndex = 0,
  });

  final LevelDef level;
  final PlayMode mode;
  final int dailyNumber;
  final int weeklyIndex;

  static Route<void> route(
    LevelDef level, {
    PlayMode mode = PlayMode.campaign,
    int dailyNumber = 0,
    int weeklyIndex = 0,
  }) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => PlayScreen(
      level: level,
      mode: mode,
      dailyNumber: dailyNumber,
      weeklyIndex: weeklyIndex,
    ),
    transitionsBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> implements PlayHost {
  final KnotScene _scene = KnotScene();
  final GlobalKey<FlightLayerState> _flights = GlobalKey();
  final GlobalKey _knotKey = GlobalKey();
  final Map<String, GlobalKey> _slotKeys = {};
  PlayController? _controller;
  late Services _services;

  PlayController get c => _controller!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final strings = S.of(context);
    if (_controller != null) {
      _controller!.strings = strings;
      return;
    }
    _services = AppScope.of(context);
    _controller =
        PlayController(
            services: _services,
            level: widget.level,
            mode: widget.mode,
            scene: _scene,
            dailyNumber: widget.dailyNumber,
            weeklyIndex: widget.weeklyIndex,
          )
          ..host = this
          ..strings = strings
          ..start();
    if (kDemoLevel > 0) _runDemo();
  }

  /// Plays the stored solution at a watchable pace, then moves on.
  Future<void> _runDemo() async {
    Future<void> wait(int ms) =>
        Future<void>.delayed(Duration(milliseconds: ms));
    await wait(1700);
    for (final m in widget.level.solution) {
      if (!mounted || c.phase != PlayPhase.playing) break;
      c.dragEnd(m.ring, m.delta);
      await wait(1300 + 260 * m.delta);
    }
    for (var i = 0; i < 40 && mounted && c.phase != PlayPhase.cleared; i++) {
      await wait(200);
    }
    await wait(3400);
    if (mounted && _hasNext) _next();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _scene.dispose();
    _services.audio.setMood(MusicMood.menu);
    super.dispose();
  }

  GlobalKey _keyFor(SlotRef slot) => _slotKeys[slot.id] ??= GlobalKey();

  double get _slotSize {
    final longest = widget.level.pegs.fold<int>(
      0,
      (a, p) => p.length > a ? p.length : a,
    );
    return longest > 5 || widget.level.pegs.length > 2 ? 26 : 30;
  }

  RingSkin get _skin => RingSkin.of(_services.profile.skin);

  // ------------------------------------------------------------ PlayHost
  @override
  void flyFromKnot(int ring, SlotRef to, VoidCallback onLand) {
    final layer = _flights.currentState;
    final start = _scene.handOff(ring);
    final from = start == null ? null : layer?.fromBox(_knotKey, start.center);
    final target = layer?.centerOf(_keyFor(to));
    if (layer == null || start == null || from == null || target == null) {
      onLand();
      return;
    }
    final size = _slotSize;
    final tube = size * 0.2;
    layer.launch(
      from: FlightStart(
        from,
        start.u,
        start.v,
        start.tube,
        start.gaps,
        start.gapWidth,
      ),
      to: target,
      radius: size / 2 - tube / 2 - 1.5,
      tube: tube,
      color: _skin.color(widget.level.rings[ring].color),
      gloss: _skin.def.gloss,
      onLand: onLand,
    );
  }

  @override
  void flyFromSlot(int ring, SlotRef from, SlotRef to, VoidCallback onLand) {
    final layer = _flights.currentState;
    final a = layer?.centerOf(_keyFor(from));
    final b = layer?.centerOf(_keyFor(to));
    if (layer == null || a == null || b == null) {
      onLand();
      return;
    }
    final size = _slotSize;
    final tube = size * 0.2;
    final r = size / 2 - tube / 2 - 1.5;
    layer.launch(
      from: FlightStart(a, Offset(r, 0), Offset(0, -r), tube, const [], 0),
      to: b,
      radius: r,
      tube: tube,
      color: _skin.color(widget.level.rings[ring].color),
      gloss: _skin.def.gloss,
      onLand: onLand,
      seconds: 0.42,
    );
  }

  @override
  void clearFlights() => _flights.currentState?.clear();

  // ------------------------------------------------------------ actions
  Future<void> _hint() async {
    final outcome = await c.requestHint();
    if (!mounted || outcome != HintOutcome.needHints) return;
    await showCardDialog<void>(
      context,
      builder: (_) => _GetHints(services: _services),
    );
  }

  void _leave() => Navigator.of(context).maybePop();

  /// The weekly knot to play after this one, or -1 when the run is done.
  int get _nextWeekly {
    final done = _services.profile.weeklyProgress();
    for (var i = 0; i < 7; i++) {
      if (!done.contains(i)) return i;
    }
    return -1;
  }

  bool get _hasNext => switch (widget.mode) {
    PlayMode.campaign => widget.level.id < _services.levels.count,
    PlayMode.daily => false,
    PlayMode.weekly => _nextWeekly >= 0,
  };

  Future<void> _next() async {
    final levels = _services.levels;
    final nav = Navigator.of(context);
    if (kDemoLevel == 0) {
      await _services.ads.showInterstitialIfAllowed(widget.level.id);
    }
    if (!mounted) return;
    if (widget.mode == PlayMode.campaign && _hasNext) {
      nav.pushReplacement(PlayScreen.route(levels.level(widget.level.id + 1)));
    } else if (widget.mode == PlayMode.weekly && _hasNext) {
      final index = _nextWeekly;
      nav.pushReplacement(
        PlayScreen.route(
          levels.weeklyFor(_services.now())[index],
          mode: PlayMode.weekly,
          weeklyIndex: index,
        ),
      );
    } else {
      nav.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    final settings = _services.profile.settings;
    // Honour the phone's own reduce-motion setting as well as the game's.
    final calm =
        settings.reduceMotion || MediaQuery.disableAnimationsOf(context);
    _scene.calm = calm;
    return Scaffold(
      backgroundColor: p.bg,
      body: Bench(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([c, _services.profile, _services.ads]),
            builder: (context, _) {
              final direction = settings.leftHanded
                  ? TextDirection.rtl
                  : TextDirection.ltr;
              return Stack(
                children: [
                  Narrow(
                    child: Column(
                      children: [
                        _header(p, s, direction),
                        _goals(p, s),
                        Expanded(child: _knotArea(p)),
                        if (widget.level.hasPegs) _tray(p, s),
                        _boosters(p, s, direction),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: FlightLayer(key: _flights, calm: calm),
                  ),
                  if (c.phase == PlayPhase.failed)
                    _FailCard(controller: c, onLeave: _leave),
                  if (c.phase == PlayPhase.cleared && c.outcome != null)
                    ClearOverlay(
                      controller: c,
                      hasNext: _hasNext,
                      onNext: _next,
                      onReplay: c.restart,
                      onLeave: _leave,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(AppPalette p, S s, TextDirection direction) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
    child: Row(
      textDirection: direction,
      children: [
        _RoundButton(
          icon: Icons.arrow_back_rounded,
          label: s('play.leave'),
          onTap: _leave,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: direction == TextDirection.ltr
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Text(
                c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.display(p, 17, weight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                s('play.moves', {'n': c.knot.moves, 'par': widget.level.par}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  p,
                  13,
                  color: p.dim,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _RoundButton(
          icon: Icons.refresh_rounded,
          label: s('play.restart'),
          onTap: c.phase == PlayPhase.playing && c.knot.moves > 0
              ? c.restart
              : null,
        ),
      ],
    ),
  );

  /// Pegs, or on the first levels a simple row that fills as rings come free.
  Widget _goals(AppPalette p, S s) {
    final level = widget.level;
    final size = _slotSize;
    final marks = _services.profile.settings.colorMarks;
    final children = <Widget>[];
    if (!level.hasPegs) {
      children.add(
        _SlotGroup(
          label: s('play.freed', {
            'n': c.hudBowl.length,
            'total': level.rings.length,
          }),
          done: c.hudBowl.length == level.rings.length,
          children: [
            for (var i = 0; i < level.rings.length; i++)
              _Slot(
                key: _keyFor(SlotRef.bowl(i)),
                size: size,
                ring: i < c.hudBowl.length ? c.hudBowl[i] : null,
                level: level,
                skin: _skin,
                marks: marks,
              ),
          ],
        ),
      );
    } else {
      for (var peg = 0; peg < level.pegs.length; peg++) {
        final filled = c.hudPegs[peg];
        final firstEmpty = filled.indexOf(null);
        children.add(
          _SlotGroup(
            label: firstEmpty < 0
                ? s('play.peg_done', {'n': peg + 1})
                : s('play.peg', {'n': peg + 1}),
            done: firstEmpty < 0,
            children: [
              for (var i = 0; i < level.pegs[peg].length; i++)
                _Slot(
                  key: _keyFor(SlotRef.peg(peg, i)),
                  size: size,
                  ring: filled[i],
                  wanted: level.pegs[peg][i],
                  next: i == firstEmpty,
                  level: level,
                  skin: _skin,
                  marks: marks,
                ),
            ],
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: children,
      ),
    );
  }

  /// Height the coaching tip covers at the top of the knot area.
  double _tipHeight(AppPalette p, double width) {
    final tip = c.tip;
    if (tip == null) return 0;
    final text = TextPainter(
      text: TextSpan(text: tip, style: AppText.body(p, 14)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(40, width - 58));
    final height = text.height + 34;
    text.dispose();
    return height;
  }

  Widget _knotArea(AppPalette p) => LayoutBuilder(
    builder: (context, box) {
      // The knot moves down out of the tip's way, then eases back.
      _scene.topInset = _tipHeight(p, box.maxWidth);
      return _knotStack(p);
    },
  );

  Widget _knotStack(AppPalette p) => Stack(
    children: [
      Positioned.fill(
        child: KnotView(
          key: _knotKey,
          scene: _scene,
          skin: _skin,
          marks: _services.profile.settings.colorMarks,
          canTurn: c.canTurn,
          onTap: c.tap,
          onDragEnd: c.dragEnd,
          onBlocked: c.blocked,
          onTouch: c.touched,
        ),
      ),
      Positioned(
        left: 14,
        right: 14,
        top: 6,
        child: IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: c.tip == null
                ? const SizedBox.shrink()
                : Container(
                    key: ValueKey(c.tip),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: p.card.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.line),
                    ),
                    child: Text(
                      c.tip!,
                      textAlign: TextAlign.center,
                      style: AppText.body(p, 14),
                    ),
                  ),
          ),
        ),
      ),
      Positioned(
        left: 14,
        right: 14,
        bottom: 8,
        child: IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: c.notice == null
                ? const SizedBox.shrink()
                : Center(
                    key: ValueKey(c.notice),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: p.brass,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        c.notice!,
                        textAlign: TextAlign.center,
                        style: AppText.body(
                          p,
                          13.5,
                          weight: FontWeight.w600,
                          color: p.brassInk,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    ],
  );

  Widget _tray(AppPalette p, S s) {
    final level = widget.level;
    final free = c.hudTray.where((r) => r == null).length;
    final tight = free <= 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          decoration: BoxDecoration(
            color: p.card.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: tight ? p.danger : p.line,
              width: tight ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s('play.tray'),
                style: AppText.label(p, color: tight ? p.danger : p.dim),
              ),
              const SizedBox(width: 10),
              for (var i = 0; i < c.hudTray.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _Slot(
                    key: _keyFor(SlotRef.tray(i)),
                    size: 30,
                    ring: c.hudTray[i],
                    level: level,
                    skin: _skin,
                    marks: _services.profile.settings.colorMarks,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boosters(AppPalette p, S s, TextDirection direction) {
    final profile = _services.profile;
    final playing = c.phase == PlayPhase.playing;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        textDirection: direction,
        children: [
          Expanded(
            child: _Booster(
              icon: Icons.lightbulb_outline_rounded,
              label: s('booster.hint'),
              detail: c.hintBusy
                  ? s('booster.thinking')
                  : (profile.hints > 0
                        ? s('booster.left', {'n': profile.hints})
                        : s('booster.get_more')),
              onTap: playing && !c.hintBusy ? _hint : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Booster(
              icon: Icons.undo_rounded,
              label: s('booster.undo'),
              detail: c.undoCost,
              onTap: c.canUndo && playing ? c.undo : null,
            ),
          ),
          if (widget.level.hasPegs) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _Booster(
                icon: Icons.add_circle_outline_rounded,
                label: s('booster.slot'),
                detail: c.slotCost,
                onTap: c.canAddSlot && playing ? () => c.addSlot() : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      label: label,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: p.card,
          shape: BoxShape.circle,
          border: Border.all(color: p.line),
        ),
        child: Icon(icon, color: p.ink, size: 22),
      ),
    );
  }
}

class _Booster extends StatelessWidget {
  const _Booster({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      label: '$label, $detail',
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
        ),
        // Longer words in other languages shrink to fit rather than clip.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: p.brass),
              const SizedBox(width: 7),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppText.body(p, 14.5, weight: FontWeight.w700),
                  ),
                  Text(detail, style: AppText.body(p, 11.5, color: p.dim)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A peg (or the first levels' collection row): a labelled group of slots.
class _SlotGroup extends StatelessWidget {
  const _SlotGroup({
    required this.label,
    required this.done,
    required this.children,
  });
  final String label;
  final bool done;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: p.card.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: done ? p.brass : p.line,
            width: done ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final child in children)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: child,
              ),
            if (done)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.check_rounded, size: 18, color: p.brass),
              ),
          ],
        ),
      ),
    );
  }
}

/// One slot on a peg, in the tray or in the bowl. Pops when a ring lands.
class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.size,
    required this.ring,
    required this.level,
    required this.skin,
    required this.marks,
    this.wanted,
    this.next = false,
  });

  final double size;

  /// The ring sitting here, if any.
  final int? ring;

  /// The colour a peg slot is waiting for. Null for tray and bowl slots.
  final int? wanted;
  final bool next;
  final LevelDef level;
  final RingSkin skin;
  final bool marks;

  @override
  Widget build(BuildContext context) {
    final r = ring;
    if (r != null) {
      final color = level.rings[r].color;
      return TweenAnimationBuilder<double>(
        key: ValueKey('ring$r'),
        tween: Tween(begin: 1.45, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: RingChip(
          size: size,
          state: ChipState.filled,
          color: skin.color(color),
          colorIndex: color,
          gloss: skin.def.gloss,
          showMark: marks,
        ),
      );
    }
    if (wanted != null) {
      return RingChip(
        size: size,
        state: ChipState.wanted,
        color: skin.color(wanted!),
        colorIndex: wanted!,
        showMark: marks,
        next: next,
      );
    }
    return RingChip(size: size, state: ChipState.empty);
  }
}

class _FailCard extends StatelessWidget {
  const _FailCard({required this.controller, required this.onLeave});
  final PlayController controller;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: p.shadow.withValues(alpha: 0.7),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: p.line),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s('fail.title'),
                        textAlign: TextAlign.center,
                        style: AppText.display(p, 20, weight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.count('fail.left', controller.knot.remaining),
                        textAlign: TextAlign.center,
                        style: AppText.body(p, 14.5, color: p.dim),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: BrassButton(
                          compact: true,
                          label: s('fail.undo'),
                          detail: controller.undoCost,
                          onTap: controller.canUndo ? controller.undo : null,
                        ),
                      ),
                      if (controller.canAddSlot) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: GhostButton(
                            label: s('fail.slot'),
                            detail: controller.slotCost,
                            onTap: () => controller.addSlot(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: GhostButton(
                          label: s('play.restart'),
                          onTap: controller.restart,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: onLeave,
                        child: Text(
                          s('common.leave'),
                          style: AppText.body(p, 14, color: p.dim),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Offered when the player asks for a hint and has none left.
class _GetHints extends StatelessWidget {
  const _GetHints({required this.services});
  final Services services;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.profile, services.ads]),
      builder: (context, _) {
        final profile = services.profile;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s('hints.out'),
              textAlign: TextAlign.center,
              style: AppText.display(p, 20, weight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              s('hints.daily'),
              textAlign: TextAlign.center,
              style: AppText.body(p, 14.5, color: p.dim),
            ),
            const SizedBox(height: 16),
            if (services.ads.rewardedReady) ...[
              SizedBox(
                width: double.infinity,
                child: BrassButton(
                  compact: true,
                  label: s('hints.get_one'),
                  detail: s('booster.watch'),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    services.analytics.log('ad_offered', {'placement': 'hint'});
                    if (await services.ads.showRewarded('hint')) {
                      services.analytics.log('ad_watched', {
                        'placement': 'hint',
                      });
                      profile.addHints(1);
                      nav.pop();
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: GhostButton(
                label: s('hints.get_pack', {'n': Economy.hintPackSize}),
                detail: s('hints.pack_detail', {
                  'price': Economy.hintPackPrice,
                  'have': profile.coins,
                }),
                onTap: profile.coins >= Economy.hintPackPrice
                    ? () {
                        if (profile.spendCoins(Economy.hintPackPrice)) {
                          profile.addHints(Economy.hintPackSize);
                          services.audio.play(Sfx.coin);
                          Navigator.of(context).pop();
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                s('common.not_now'),
                style: AppText.body(p, 14, color: p.dim),
              ),
            ),
          ],
        );
      },
    );
  }
}
