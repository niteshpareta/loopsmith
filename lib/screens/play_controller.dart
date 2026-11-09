import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../game/economy.dart';
import '../game/knot.dart';
import '../game/level.dart';
import '../game/solver.dart';
import '../l10n/strings.dart';
import '../render/scene.dart';
import '../services/audio.dart';
import '../services/profile.dart';
import '../services/reminders.dart';
import '../services/services.dart';

enum PlayMode { campaign, daily, weekly }

enum PlayPhase {
  playing,

  /// The last move ended the level; rings are still flying to their slots.
  settling,
  failed,
  cleared,
}

enum SlotKind { peg, tray, bowl }

/// A place a freed ring can sit on the play screen.
class SlotRef {
  const SlotRef(this.kind, this.peg, this.slot);
  const SlotRef.peg(int peg, int slot) : this(SlotKind.peg, peg, slot);
  const SlotRef.tray(int slot) : this(SlotKind.tray, -1, slot);
  const SlotRef.bowl(int slot) : this(SlotKind.bowl, -1, slot);
  final SlotKind kind;
  final int peg;
  final int slot;

  String get id => '${kind.name}:$peg:$slot';
}

/// The play screen, as seen by the controller: it can fly rings around.
abstract class PlayHost {
  void flyFromKnot(int ring, SlotRef to, VoidCallback onLand);
  void flyFromSlot(int ring, SlotRef from, SlotRef to, VoidCallback onLand);
  void clearFlights();
}

enum HintOutcome { shown, needHints, noSolution, ignored }

class _HintJob {
  _HintJob(this.level, this.turns, this.freed, this.capacity);
  final Map<String, dynamic> level;
  final List<int> turns;
  final List<bool> freed;
  final int capacity;
}

/// Runs on a background isolate where the platform has them.
List<int> _solveHint(_HintJob job) {
  final level = LevelDef.fromJson(job.level);
  final result = Solver(level).solveFrom(
    Solver.packTurns(job.turns),
    Solver.packFreed(job.freed),
    job.capacity,
    maxNodes: 120000,
  );
  if (!result.solved) return const [-1];
  return [result.moves.first.ring, result.moves.first.delta];
}

/// Runs one attempt at a level: applies moves, sequences the animation and
/// sound that follow, and handles hints, undo and the extra-slot booster.
class PlayController extends ChangeNotifier {
  PlayController({
    required this.services,
    required this.level,
    required this.mode,
    required this.scene,
    this.dailyNumber = 0,
    this.weeklyIndex = 0,
  });

  final Services services;
  final LevelDef level;
  final PlayMode mode;
  final KnotScene scene;
  final int dailyNumber;

  /// Which of the week's seven knots this is (0..6), in weekly mode.
  final int weeklyIndex;
  PlayHost? host;

  /// The player's language, set by the screen. English until then.
  S strings = S.english;

  late Knot knot;
  PlayPhase phase = PlayPhase.playing;

  // What the pegs, tray and bowl show. This trails the rules while rings fly.
  List<List<int?>> hudPegs = [];
  List<int?> hudTray = [];
  List<int> hudBowl = [];

  int freeUndos = Economy.freeUndos;
  bool slotAdded = false;
  Move? hint;
  bool hintBusy = false;

  /// Coaching text shown above the knot.
  String? tip;

  /// A short message that fades on its own.
  String? notice;
  ClearOutcome? outcome;
  int hintsUsed = 0;
  int undosUsed = 0;

  final List<Knot> _history = [];
  final List<Timer> _timers = [];
  Timer? _noticeTimer;
  int _chain = 0;
  int _lastRing = -1;
  bool _lastQuiet = false;
  int _pending = 0;
  bool _disposed = false;
  final Stopwatch _watch = Stopwatch();

  PlayerProfile get _profile => services.profile;
  bool get _firstLevel => mode == PlayMode.campaign && level.id == 1;

  String get title => switch (mode) {
    PlayMode.campaign => strings('play.level', {'n': level.id}),
    PlayMode.daily => strings('daily.number', {'n': dailyNumber}),
    PlayMode.weekly => strings('weekly.knot', {'n': weeklyIndex + 1}),
  };
  bool get canUndo =>
      _history.isNotEmpty &&
      (phase == PlayPhase.playing || phase == PlayPhase.failed);
  bool get undoIsFree => freeUndos > 0;
  bool get canAddSlot =>
      level.hasPegs &&
      !slotAdded &&
      (phase == PlayPhase.playing || phase == PlayPhase.failed);

  /// How the extra slot will be paid for, in the order the game prefers.
  String get slotCost {
    if (slotAdded) return strings('booster.used');
    if (_profile.slotTokens > 0) {
      return strings('booster.left', {'n': _profile.slotTokens});
    }
    if (services.ads.rewardedReady) return strings('booster.watch');
    return strings.count('count.coins', Economy.slotPrice);
  }

  String get undoCost => undoIsFree
      ? strings('booster.free')
      : strings.count('count.coins', Economy.undoPrice);

  void start() {
    _cancelPending();
    knot = Knot(level);
    _history.clear();
    phase = PlayPhase.playing;
    freeUndos = Economy.freeUndos;
    slotAdded = false;
    hint = null;
    outcome = null;
    notice = null;
    _chain = 0;
    _lastRing = -1;
    hintsUsed = 0;
    undosUsed = 0;
    scene.calm = _profile.settings.reduceMotion;
    scene.load(level, knot, animate: true);
    _syncHud();
    services.audio.setMood(MusicMood.levelStart);
    services.analytics.log('level_start', {
      'level': level.id,
      'mode': mode.name,
    });
    tip = _pickTip();
    if (_firstLevel && level.solution.isNotEmpty) {
      _later(
        const Duration(milliseconds: 700),
        () => _showHint(level.solution.first, silent: true),
      );
    }
    _watch
      ..reset()
      ..start();
    notifyListeners();
  }

  String? _pickTip() {
    if (mode == PlayMode.campaign) {
      switch (level.id) {
        case 1:
          return strings('tip.first');
        case 2:
          return strings('tip.hook');
        case 3:
          return strings('tip.look');
        case 5:
          return strings('tip.pegs');
      }
    }
    const kindTips = {
      RingKind.twin: 'tip.twin',
      RingKind.geared: 'tip.geared',
      RingKind.fixed: 'tip.fixed',
      RingKind.sealed: 'tip.sealed',
    };
    for (final entry in kindTips.entries) {
      if (level.kinds.contains(entry.key) &&
          _profile.firstTime('kind.${entry.key.name}')) {
        return strings(entry.value);
      }
    }
    return null;
  }

  // ------------------------------------------------------------ input
  bool canTurn(int ring) => phase == PlayPhase.playing && knot.canTurn(ring);

  /// A finger went down on a ring: show which ring is geared to it.
  void touched(int ring) {
    final d = level.rings[ring];
    if (d.kind == RingKind.geared && d.partner >= 0 && !knot.freed[d.partner]) {
      scene.highlight(d.partner, seconds: 0.7);
    }
  }

  /// The player tapped or dragged a ring that cannot turn.
  void blocked(int ring) {
    if (phase != PlayPhase.playing || knot.freed[ring]) return;
    scene.shake(ring);
    services.audio.play(Sfx.blocked);
    final d = level.rings[ring];
    if (d.kind == RingKind.fixed) {
      _say(strings('notice.fixed'));
    } else if (knot.isSealed(ring)) {
      scene.highlight(d.partner);
      _say(strings('notice.sealed'));
    }
  }

  void tap(int ring) => _turn(ring, 1, 1);

  /// A drag ended [quarters] quarter turns from where the ring started.
  void dragEnd(int ring, int quarters) {
    final delta = ((quarters % 4) + 4) % 4;
    if (delta == 0 || !canTurn(ring)) {
      // Back where it began (or a full circle): settle without a move.
      scene.turnBy(ring, quarters);
      final d = level.rings[ring];
      if (d.kind == RingKind.geared &&
          d.partner >= 0 &&
          !knot.freed[d.partner]) {
        scene.turnBy(d.partner, -quarters);
      }
      return;
    }
    _turn(ring, delta, quarters);
  }

  void _turn(int ring, int delta, int visualQuarters) {
    if (!canTurn(ring)) return;
    // Turning the same ring again, with nothing freed in between, is still
    // one move: three taps cost the same as one three-quarter drag. One undo
    // takes the whole turn back.
    final sameMove = ring == _lastRing && _lastQuiet && knot.moves > 0;
    if (!sameMove) {
      _history.add(knot.copy());
      if (_history.length > 60) _history.removeAt(0);
    }
    final result = knot.apply(ring, delta);
    if (sameMove) knot.moves--;
    _lastRing = ring;
    _lastQuiet = result.events.isEmpty;

    hint = null;
    scene.clearHint();
    if (!_firstLevel) tip = null;

    scene.turnBy(ring, visualQuarters);
    for (final other in result.turned.keys) {
      if (other != ring) scene.turnBy(other, -visualQuarters);
    }
    services.audio.play(Sfx.turn);
    services.haptics.tick();
    touched(ring);

    if (result.solved || result.failed) phase = PlayPhase.settling;

    final released = result.releases.isNotEmpty;
    if (!released) _chain = 0;
    for (final e in result.releases) {
      scene.rings[e.ring].leaving = true;
    }

    // When the turn animation ends: light up openings that now sit on a link.
    _later(const Duration(milliseconds: 170), () {
      scene.syncGlows(knot);
      if (result.openedLinks.isNotEmpty && !released) {
        for (final i in result.openedLinks) {
          final l = level.links[i];
          if (((knot.openings(l.a) >> l.pa) & 1) == 1) scene.flash(l.a, l.pa);
          if (((knot.openings(l.b) >> l.pb) & 1) == 1) scene.flash(l.b, l.pb);
        }
        services.audio.play(Sfx.align);
        services.haptics.bump();
      }
    });

    // Then each freed ring lifts, flies to its slot and lands, one after another.
    var at = 190;
    var lastLanding = 0;
    for (final event in result.events) {
      switch (event) {
        case RingUnsealed():
          _later(Duration(milliseconds: at), () {
            scene.unseal(event.ring);
            services.audio.play(Sfx.unseal);
          });
        case RingReleased():
          final step = _chain++;
          final to = switch (event.destination) {
            Destination.peg => SlotRef.peg(event.peg, event.slot),
            Destination.tray => SlotRef.tray(event.slot),
            Destination.bowl => SlotRef.bowl(event.slot),
          };
          _pending++;
          _later(Duration(milliseconds: at), () {
            services.audio.play(
              Sfx.free,
              pitch: kPentatonic[math.min(step, kPentatonic.length - 1)],
            );
            services.haptics.release();
            scene.beginRelease(event.ring);
            _later(
              Duration(milliseconds: (KnotScene.releaseTime * 1000).round()),
              () {
                _fly(
                  () => host?.flyFromKnot(
                    event.ring,
                    to,
                    () => _landed(event.ring, to),
                  ),
                  () {
                    scene.rings[event.ring].gone = true;
                    _landed(event.ring, to);
                  },
                );
              },
            );
          });
          lastLanding = at + 760;
          at += 130;
        case RingPromoted():
          final from = SlotRef.tray(event.fromSlot);
          final to = SlotRef.peg(event.peg, event.slot);
          // Leave the tray just after the ring that made room has landed.
          final when = math.max(at, lastLanding + 40);
          lastLanding = when + 460;
          _pending++;
          _later(Duration(milliseconds: when), () {
            if (event.fromSlot < hudTray.length &&
                hudTray[event.fromSlot] == event.ring) {
              hudTray[event.fromSlot] = null;
              notifyListeners();
            }
            _fly(
              () => host?.flyFromSlot(
                event.ring,
                from,
                to,
                () => _landed(event.ring, to),
              ),
              () => _landed(event.ring, to),
            );
          });
      }
    }
    _pending++;
    _later(Duration(milliseconds: math.max(at, 260)), _eventDone);

    if (_firstLevel && !result.solved) {
      final next = Solver(level).solve(knot);
      if (next.solved && next.moves.isNotEmpty) {
        _later(
          const Duration(milliseconds: 260),
          () => _showHint(next.moves.first, silent: true),
        );
      }
    }
    notifyListeners();
  }

  /// Uses the host's flight if there is a screen, otherwise lands at once.
  void _fly(void Function() withHost, VoidCallback without) {
    if (host != null) {
      withHost();
    } else {
      without();
    }
  }

  void _landed(int ring, SlotRef to) {
    if (_disposed) return;
    switch (to.kind) {
      case SlotKind.peg:
        if (to.slot < hudPegs[to.peg].length) hudPegs[to.peg][to.slot] = ring;
        services.audio.play(Sfx.peg);
      case SlotKind.tray:
        // Only show it if the rules still have it there.
        if (to.slot < knot.traySlots.length &&
            knot.traySlots[to.slot] == ring) {
          while (hudTray.length <= to.slot) {
            hudTray.add(null);
          }
          hudTray[to.slot] = ring;
        }
        final filled = hudTray.where((r) => r != null).length;
        services.audio.play(
          Sfx.tray,
          pitch: 1.0 - 0.07 * (filled - 1).clamp(0, 4),
        );
      case SlotKind.bowl:
        if (!hudBowl.contains(ring)) hudBowl.add(ring);
        services.audio.play(Sfx.peg, pitch: 1.1);
    }
    services.haptics.land();
    if (knot.remaining <= 2 && !knot.solved) {
      services.audio.setMood(MusicMood.levelClose);
    } else if (!knot.solved) {
      services.audio.setMood(MusicMood.levelFlow);
    }
    notifyListeners();
    _eventDone();
  }

  void _eventDone() {
    if (_disposed) return;
    _pending--;
    if (_pending > 0) return;
    _pending = 0;
    _syncHud();
    scene.syncGlows(knot);
    if (knot.solved) {
      _clear();
    } else if (knot.failed) {
      _fail();
    }
    notifyListeners();
  }

  void _clear() {
    if (phase == PlayPhase.cleared) return;
    phase = PlayPhase.cleared;
    _watch.stop();
    outcome = switch (mode) {
      PlayMode.campaign => _profile.completeLevel(
        level.id,
        knot.moves,
        level.par,
        levelCount: services.levels.count,
      ),
      PlayMode.daily => _profile.completeDaily(knot.moves, level.par),
      PlayMode.weekly => _profile.completeWeekly(
        weeklyIndex,
        knot.moves,
        level.par,
      ),
    };
    if (mode == PlayMode.daily && _profile.settings.reminder) {
      // Today's knot is done, so tonight's reminder is no longer needed.
      services.reminders.refresh(
        ReminderText(
          strings('remind.title'),
          strings('remind.body'),
          strings('remind.channel'),
        ),
        playedToday: true,
      );
    }
    services.audio
      ..duck(const Duration(milliseconds: 2600))
      ..play(Sfx.win);
    services.haptics.success();
    services.analytics.log(
      switch (mode) {
        PlayMode.campaign => 'level_clear',
        PlayMode.daily => 'daily_done',
        PlayMode.weekly => 'weekly_done',
      },
      {
        'level': level.id,
        'moves': knot.moves,
        'par': level.par,
        'stars': outcome!.stars,
        'seconds': _watch.elapsed.inSeconds,
        'hints': hintsUsed,
        'undos': undosUsed,
      },
    );
  }

  void _fail() {
    if (phase == PlayPhase.failed) return;
    phase = PlayPhase.failed;
    services.audio.play(Sfx.fail);
    services.haptics.fail();
    services.analytics.log('level_fail', {
      'level': level.id,
      'mode': mode.name,
      'rings_left': knot.remaining,
      'moves': knot.moves,
    });
  }

  // ------------------------------------------------------------ boosters
  /// Takes back the last move. The first undo of an attempt is free.
  bool undo() {
    if (!canUndo) return false;
    if (freeUndos > 0) {
      freeUndos--;
    } else if (!_profile.spendCoins(Economy.undoPrice)) {
      _say(strings('notice.undo_coins'));
      return false;
    }
    _cancelPending();
    knot = _history.removeLast();
    scene.load(level, knot);
    _syncHud();
    phase = PlayPhase.playing;
    _chain = 0;
    _lastRing = -1;
    hint = null;
    undosUsed++;
    services.audio.play(Sfx.undo);
    services.analytics.log('booster_used', {
      'booster': 'undo',
      'level': level.id,
    });
    notifyListeners();
    return true;
  }

  void restart() {
    services.analytics.log('level_restart', {
      'level': level.id,
      'mode': mode.name,
    });
    start();
  }

  /// Adds one tray slot, once per attempt. Paid with a slot token if the
  /// player has one, otherwise a reward ad, otherwise coins.
  Future<bool> addSlot() async {
    if (!canAddSlot) return false;
    var paid = 'token';
    if (!_profile.useSlotToken()) {
      if (services.ads.rewardedReady) {
        services.analytics.log('ad_offered', {'placement': 'slot'});
        final earned = await services.ads.showRewarded('slot');
        if (_disposed || !earned) return false;
        services.analytics.log('ad_watched', {'placement': 'slot'});
        paid = 'ad';
      } else if (_profile.spendCoins(Economy.slotPrice)) {
        paid = 'coins';
      } else {
        _say(strings('notice.slot_coins'));
        return false;
      }
    }
    if (!canAddSlot) return false;
    knot.addTraySlot();
    slotAdded = true;
    _syncHud();
    if (phase == PlayPhase.failed && !knot.failed) phase = PlayPhase.playing;
    services.audio.play(Sfx.coin);
    services.analytics.log('booster_used', {
      'booster': 'slot',
      'paid': paid,
      'level': level.id,
    });
    notifyListeners();
    return true;
  }

  /// Shows the next best move. Costs one hint only when a move is found.
  Future<HintOutcome> requestHint() async {
    if (phase != PlayPhase.playing || hintBusy) return HintOutcome.ignored;
    if (hint != null) {
      scene.highlight(hint!.ring);
      return HintOutcome.shown;
    }
    if (_profile.hints <= 0) return HintOutcome.needHints;
    hintBusy = true;
    notifyListeners();
    final movesAtRequest = knot.moves;
    final answer = await compute(
      _solveHint,
      _HintJob(
        level.toJson(),
        List.of(knot.turns),
        List.of(knot.freed),
        knot.trayCapacity,
      ),
    );
    if (_disposed) return HintOutcome.ignored;
    hintBusy = false;
    if (knot.moves != movesAtRequest || phase != PlayPhase.playing) {
      notifyListeners();
      return HintOutcome.ignored;
    }
    if (answer[0] < 0) {
      _say(strings('notice.no_way'));
      return HintOutcome.noSolution;
    }
    _profile.useHint();
    hintsUsed++;
    _showHint(Move(answer[0], answer[1]));
    services.analytics.log('booster_used', {
      'booster': 'hint',
      'level': level.id,
    });
    return HintOutcome.shown;
  }

  void _showHint(Move move, {bool silent = false}) {
    if (_disposed || phase != PlayPhase.playing || knot.freed[move.ring]) {
      return;
    }
    hint = move;
    scene.setHint(move.ring, (knot.turns[move.ring] + move.delta) & 3);
    if (!silent) {
      services.audio.play(Sfx.hint);
      tip = strings('tip.hint');
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ plumbing
  void _say(String message) {
    notice = message;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(milliseconds: 2800), () {
      if (_disposed) return;
      notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void _syncHud() {
    hudPegs = [
      for (var p = 0; p < level.pegs.length; p++)
        [
          for (var i = 0; i < level.pegs[p].length; i++)
            i < knot.pegRings[p].length ? knot.pegRings[p][i] : null,
        ],
    ];
    hudTray = List.of(knot.traySlots);
    hudBowl = List.of(knot.bowl);
  }

  void _later(Duration delay, VoidCallback action) {
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      if (!_disposed) action();
    });
    _timers.add(timer);
  }

  void _cancelPending() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    host?.clearFlights();
    _pending = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPending();
    _noticeTimer?.cancel();
    super.dispose();
  }
}
