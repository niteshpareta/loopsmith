/// Finds solutions to a knot. Used by the level generator (to set par and
/// prove every level can be cleared) and in the app (for hints).
library;

import 'dart:collection';

import 'knot.dart';
import 'level.dart';

enum SolveStatus {
  /// A solution was found.
  solved,

  /// Every reachable position was searched and none clears the knot.
  unsolvable,

  /// The search hit its node limit before finishing.
  budget,
}

class SolveResult {
  const SolveResult(
    this.status,
    this.moves, {
    this.optimal = false,
    this.nodes = 0,
  });
  final SolveStatus status;
  final List<Move> moves;

  /// True when [moves] is a shortest solution.
  final bool optimal;
  final int nodes;

  bool get solved => status == SolveStatus.solved;
}

/// A compact re-implementation of the rules in [Knot], working on two
/// integers: orientations packed two bits per ring, and a freed-ring bitmask.
///
/// Because every colour belongs to exactly one peg, the peg and tray contents
/// are a function of which rings are free, so they need no extra state.
class Solver {
  Solver(this.level) : n = level.rings.length {
    assert(n <= kMaxRings);
    _all = (1 << n) - 1;
    for (final r in level.rings) {
      _kind.add(r.kind);
      _partner.add(r.partner);
      _color.add(r.color);
      _linkOther.add([for (final e in level.linksOf[r.id]) e.other]);
      _linkMine.add([for (final e in level.linksOf[r.id]) e.myPos]);
      _linkTheirs.add([for (final e in level.linksOf[r.id]) e.otherPos]);
    }
  }

  final LevelDef level;
  final int n;
  late final int _all;
  final List<RingKind> _kind = [];
  final List<int> _partner = [];
  final List<int> _color = [];
  final List<List<int>> _linkOther = [];
  final List<List<int>> _linkMine = [];
  final List<List<int>> _linkTheirs = [];
  final Map<int, int> _trayCache = {};

  int get allFreed => _all;

  static int packTurns(List<int> turns) {
    var t = 0;
    for (var i = 0; i < turns.length; i++) {
      t |= (turns[i] & 3) << (2 * i);
    }
    return t;
  }

  static int packFreed(List<bool> freed) {
    var f = 0;
    for (var i = 0; i < freed.length; i++) {
      if (freed[i]) f |= 1 << i;
    }
    return f;
  }

  int initialTurns() => packTurns([for (final r in level.rings) r.turn]);

  bool _isFreed(int f, int r) => ((f >> r) & 1) == 1;

  int openMask(int t, int f, int r) {
    final tr = (t >> (2 * r)) & 3;
    switch (_kind[r]) {
      case RingKind.twin:
        return (1 << tr) | (1 << ((tr + 2) & 3));
      case RingKind.sealed:
        return _isFreed(f, _partner[r]) ? 1 << tr : 0;
      case RingKind.plain:
      case RingKind.geared:
      case RingKind.fixed:
        return 1 << tr;
    }
  }

  bool turnable(int f, int r) {
    if (_isFreed(f, r)) return false;
    final k = _kind[r];
    if (k == RingKind.fixed) return false;
    if (k == RingKind.sealed && !_isFreed(f, _partner[r])) return false;
    return true;
  }

  int _setTurn(int t, int r, int value) =>
      (t & ~(3 << (2 * r))) | ((value & 3) << (2 * r));

  /// Orientations after turning [r] by [d] quarter turns.
  int applyTurn(int t, int f, int r, int d) {
    var nt = _setTurn(t, r, ((t >> (2 * r)) & 3) + d);
    if (_kind[r] == RingKind.geared) {
      final p = _partner[r];
      if (p >= 0 && !_isFreed(f, p)) {
        nt = _setTurn(nt, p, ((nt >> (2 * p)) & 3) - d + 4);
      }
    }
    return nt;
  }

  /// Freed mask after every ring that can slip out has done so.
  int settle(int t, int f) {
    while (true) {
      var add = 0;
      for (var r = 0; r < n; r++) {
        if (_isFreed(f, r)) continue;
        final mine = openMask(t, f, r);
        final others = _linkOther[r];
        var free = true;
        for (var k = 0; k < others.length; k++) {
          final o = others[k];
          if (_isFreed(f, o)) continue;
          if (((mine >> _linkMine[r][k]) & 1) == 1) continue;
          if (((openMask(t, f, o) >> _linkTheirs[r][k]) & 1) == 1) continue;
          free = false;
          break;
        }
        if (free) add |= 1 << r;
      }
      if (add == 0) return f;
      f |= add;
    }
  }

  /// Number of rings waiting in the tray when the rings in [f] are free.
  int trayCount(int f) {
    if (!level.hasPegs) return 0;
    final cached = _trayCache[f];
    if (cached != null) return cached;
    final avail = List.filled(kColorCount, 0);
    var freedCount = 0;
    for (var r = 0; r < n; r++) {
      if (_isFreed(f, r)) {
        avail[_color[r]]++;
        freedCount++;
      }
    }
    var placed = 0;
    for (final seq in level.pegs) {
      for (final c in seq) {
        if (avail[c] == 0) break;
        avail[c]--;
        placed++;
      }
    }
    return _trayCache[f] = freedCount - placed;
  }

  /// A key that is equal for positions with the same future.
  ///
  /// A ring's exact orientation rarely matters: any orientation is one move
  /// away, so only which of its live links its openings face is kept. Geared
  /// rings keep their exact orientation because their partner moves with them.
  int _key(int t, int f) {
    var key = 0;
    for (var r = 0; r < n; r++) {
      int digit;
      if (_isFreed(f, r)) {
        digit = 16;
      } else {
        final k = _kind[r];
        if (k == RingKind.fixed) {
          digit = 0;
        } else if (k == RingKind.geared &&
            _partner[r] >= 0 &&
            !_isFreed(f, _partner[r])) {
          digit = (t >> (2 * r)) & 3;
        } else {
          var live = 0;
          final others = _linkOther[r];
          for (var i = 0; i < others.length; i++) {
            if (!_isFreed(f, others[i])) live |= 1 << _linkMine[r][i];
          }
          digit = openMask(t, f, r) & live;
        }
      }
      key = key * 17 + digit;
    }
    return key;
  }

  /// Solves from the current state of [knot].
  SolveResult solve(
    Knot knot, {
    int maxNodes = 150000,
    bool allowGreedy = true,
  }) {
    if (knot.failed) return const SolveResult(SolveStatus.unsolvable, []);
    return solveFrom(
      packTurns(knot.turns),
      packFreed(knot.freed),
      knot.trayCapacity,
      maxNodes: maxNodes,
      allowGreedy: allowGreedy,
    );
  }

  /// Breadth-first search for a shortest solution. If the node limit is hit
  /// and [allowGreedy] is set, falls back to a best-first search that finds a
  /// valid, not necessarily shortest, solution.
  SolveResult solveFrom(
    int t0,
    int f0,
    int capacity, {
    int maxNodes = 150000,
    bool allowGreedy = true,
  }) {
    if (f0 == _all) {
      return const SolveResult(SolveStatus.solved, [], optimal: true);
    }
    final qT = <int>[t0], qF = <int>[f0], qParent = <int>[-1], qMove = <int>[0];
    final seen = HashSet<int>()..add(_key(t0, f0));
    var head = 0;
    while (head < qT.length) {
      if (qT.length > maxNodes) {
        if (allowGreedy) return _greedy(t0, f0, capacity, maxNodes);
        return SolveResult(SolveStatus.budget, const [], nodes: qT.length);
      }
      final t = qT[head], f = qF[head];
      for (var r = 0; r < n; r++) {
        if (!turnable(f, r)) continue;
        for (var d = 1; d <= 3; d++) {
          final nt = applyTurn(t, f, r, d);
          final nf = settle(nt, f);
          if (nf == _all) {
            return SolveResult(
              SolveStatus.solved,
              _path(qParent, qMove, head, r, d),
              optimal: true,
              nodes: qT.length,
            );
          }
          if (nf != f && trayCount(nf) >= capacity && level.hasPegs) continue;
          if (seen.add(_key(nt, nf))) {
            qT.add(nt);
            qF.add(nf);
            qParent.add(head);
            qMove.add(r * 4 + d);
          }
        }
      }
      head++;
    }
    return SolveResult(SolveStatus.unsolvable, const [], nodes: qT.length);
  }

  SolveResult _greedy(int t0, int f0, int capacity, int maxNodes) {
    final qT = <int>[t0], qF = <int>[f0], qParent = <int>[-1], qMove = <int>[0];
    final seen = HashSet<int>()..add(_key(t0, f0));
    final buckets = List.generate(n * 16 + 64, (_) => <int>[]);
    int score(int f) {
      var left = 0;
      for (var r = 0; r < n; r++) {
        if (!_isFreed(f, r)) left++;
      }
      return left * 16 + trayCount(f) * 4;
    }

    buckets[score(f0)].add(0);
    var lowest = score(f0);
    while (qT.length <= maxNodes) {
      while (lowest < buckets.length && buckets[lowest].isEmpty) {
        lowest++;
      }
      if (lowest >= buckets.length) {
        return SolveResult(SolveStatus.unsolvable, const [], nodes: qT.length);
      }
      final node = buckets[lowest].removeLast();
      final t = qT[node], f = qF[node];
      for (var r = 0; r < n; r++) {
        if (!turnable(f, r)) continue;
        for (var d = 1; d <= 3; d++) {
          final nt = applyTurn(t, f, r, d);
          final nf = settle(nt, f);
          if (nf == _all) {
            return SolveResult(
              SolveStatus.solved,
              _path(qParent, qMove, node, r, d),
              nodes: qT.length,
            );
          }
          if (nf != f && trayCount(nf) >= capacity && level.hasPegs) continue;
          if (seen.add(_key(nt, nf))) {
            qT.add(nt);
            qF.add(nf);
            qParent.add(node);
            qMove.add(r * 4 + d);
            final s = score(nf);
            buckets[s].add(qT.length - 1);
            if (s < lowest) lowest = s;
          }
        }
      }
    }
    return SolveResult(SolveStatus.budget, const [], nodes: qT.length);
  }

  List<Move> _path(
    List<int> parent,
    List<int> move,
    int node,
    int lastRing,
    int lastDelta,
  ) {
    final out = <Move>[Move(lastRing, lastDelta)];
    var i = node;
    while (parent[i] >= 0) {
      out.add(Move(move[i] ~/ 4, move[i] % 4));
      i = parent[i];
    }
    return out.reversed.toList();
  }
}
