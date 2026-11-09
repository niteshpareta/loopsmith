/// The live state of a level and the rules that change it.
library;

import 'dart:typed_data';

import 'level.dart';

/// Where a freed ring went.
enum Destination {
  /// Onto its peg.
  peg,

  /// Into the holding tray, because its colour is not next on its peg.
  tray,

  /// Tutorial levels have no pegs: rings are simply collected.
  bowl,
}

/// Something that happened as a result of a move, in the order it happened.
sealed class KnotEvent {
  const KnotEvent(this.ring);
  final int ring;
}

/// [ring] slipped out of the knot.
class RingReleased extends KnotEvent {
  const RingReleased(super.ring, this.destination, this.peg, this.slot);
  final Destination destination;

  /// Peg index, or -1 when the ring did not go to a peg.
  final int peg;

  /// Slot on the peg, in the tray, or in the bowl.
  final int slot;
}

/// [ring] moved from the tray onto its peg because its colour came up.
class RingPromoted extends KnotEvent {
  const RingPromoted(super.ring, this.fromSlot, this.peg, this.slot);
  final int fromSlot;
  final int peg;
  final int slot;
}

/// A sealed [ring] gained its opening because its key ring was freed.
class RingUnsealed extends KnotEvent {
  const RingUnsealed(super.ring);
}

class MoveResult {
  MoveResult({
    required this.turned,
    required this.events,
    required this.openedLinks,
    required this.solved,
    required this.failed,
  });

  /// Rings whose orientation changed, with the signed quarter turns applied.
  final Map<int, int> turned;
  final List<KnotEvent> events;

  /// Links that became open and still join two rings in the knot.
  final List<int> openedLinks;
  final bool solved;
  final bool failed;

  Iterable<RingReleased> get releases => events.whereType<RingReleased>();
}

class Knot {
  Knot(this.level)
    : turns = Uint8List.fromList([for (final r in level.rings) r.turn]),
      freed = List.filled(level.rings.length, false),
      pegRings = List.generate(level.pegs.length, (_) => <int>[]),
      traySlots = List<int?>.filled(level.tray, null, growable: true),
      bowl = <int>[];

  Knot._copy(Knot o)
    : level = o.level,
      turns = Uint8List.fromList(o.turns),
      freed = List.of(o.freed),
      pegRings = [for (final p in o.pegRings) List.of(p)],
      traySlots = List.of(o.traySlots),
      bowl = List.of(o.bowl),
      moves = o.moves;

  final LevelDef level;

  /// Orientation of every ring in quarter turns (0..3).
  final Uint8List turns;
  final List<bool> freed;

  /// Ring ids on each peg, bottom first.
  final List<List<int>> pegRings;

  /// Fixed tray positions; `null` is an empty slot.
  final List<int?> traySlots;

  /// Freed rings on tutorial levels without pegs.
  final List<int> bowl;

  int moves = 0;

  Knot copy() => Knot._copy(this);

  int get ringCount => level.rings.length;
  int get remaining => freed.where((f) => !f).length;
  int get trayCount => traySlots.where((s) => s != null).length;
  int get trayCapacity => traySlots.length;
  bool get solved => freed.every((f) => f);

  /// The attempt is over when the tray has no empty slot left.
  bool get failed => level.hasPegs && !solved && trayCount >= trayCapacity;

  /// Adds one tray slot (the "+ Slot" booster).
  void addTraySlot() => traySlots.add(null);

  /// Colour the peg wants next, or -1 when the peg is complete.
  int nextColorOn(int peg) {
    final seq = level.pegs[peg];
    final n = pegRings[peg].length;
    return n < seq.length ? seq[n] : -1;
  }

  bool isSealed(int r) {
    final d = level.rings[r];
    return d.kind == RingKind.sealed && !freed[d.partner];
  }

  /// Whether the player can turn ring [r] right now.
  bool canTurn(int r) {
    if (freed[r]) return false;
    final d = level.rings[r];
    if (d.kind == RingKind.fixed) return false;
    if (isSealed(r)) return false;
    return true;
  }

  /// Bitmask of the quarter positions where ring [r] currently has an opening.
  int openings(int r) {
    final t = turns[r];
    switch (level.rings[r].kind) {
      case RingKind.twin:
        return (1 << t) | (1 << ((t + 2) & 3));
      case RingKind.sealed:
        return isSealed(r) ? 0 : 1 << t;
      case RingKind.plain:
      case RingKind.geared:
      case RingKind.fixed:
        return 1 << t;
    }
  }

  bool linkOpen(LinkDef l) =>
      ((openings(l.a) >> l.pa) & 1) == 1 || ((openings(l.b) >> l.pb) & 1) == 1;

  /// Whether link [index] still joins two rings in the knot.
  bool linkLive(int index) {
    final l = level.links[index];
    return !freed[l.a] && !freed[l.b];
  }

  /// A ring is free when every link to a ring still in the knot is open.
  bool isFree(int r) {
    if (freed[r]) return false;
    final mine = openings(r);
    for (final e in level.linksOf[r]) {
      if (freed[e.other]) continue;
      if (((mine >> e.myPos) & 1) == 1) continue;
      if (((openings(e.other) >> e.otherPos) & 1) == 1) continue;
      return false;
    }
    return true;
  }

  /// Turns [ring] by [delta] quarter turns (1..3, or negative) and settles the
  /// knot: any ring that is now free slips out, which can free others.
  MoveResult apply(int ring, int delta) {
    assert(canTurn(ring), 'ring $ring cannot be turned');
    final d = ((delta % 4) + 4) % 4;
    assert(d != 0, 'a move must change the orientation');

    final openBefore = [
      for (var i = 0; i < level.links.length; i++)
        linkLive(i) && linkOpen(level.links[i]),
    ];

    final turned = <int, int>{ring: delta};
    turns[ring] = (turns[ring] + d) & 3;
    final def = level.rings[ring];
    if (def.kind == RingKind.geared &&
        def.partner >= 0 &&
        !freed[def.partner]) {
      turns[def.partner] = (turns[def.partner] - d + 4) & 3;
      turned[def.partner] = -delta;
    }
    moves++;

    final baseSlots = traySlots.length;
    final events = <KnotEvent>[];
    while (true) {
      final batch = <int>[
        for (var r = 0; r < ringCount; r++)
          if (isFree(r)) r,
      ];
      if (batch.isEmpty) break;
      final sealedBefore = [
        for (var r = 0; r < ringCount; r++) !freed[r] && isSealed(r),
      ];
      for (final r in batch) {
        freed[r] = true;
      }
      _placeBatch(batch, events);
      for (var r = 0; r < ringCount; r++) {
        if (sealedBefore[r] && !freed[r] && !isSealed(r)) {
          events.add(RingUnsealed(r));
        }
      }
    }
    _normalizeTray(baseSlots);

    final opened = <int>[
      for (var i = 0; i < level.links.length; i++)
        if (!openBefore[i] && linkLive(i) && linkOpen(level.links[i])) i,
    ];

    return MoveResult(
      turned: turned,
      events: events,
      openedLinks: opened,
      solved: solved,
      failed: failed,
    );
  }

  /// Sends a batch of freed rings to their pegs, or to the tray when their
  /// colour is not next. Rings that can go straight to a peg always do, so the
  /// outcome depends only on which rings are free, not on their order.
  void _placeBatch(List<int> batch, List<KnotEvent> events) {
    if (!level.hasPegs) {
      for (final r in batch) {
        bowl.add(r);
        events.add(RingReleased(r, Destination.bowl, -1, bowl.length - 1));
      }
      return;
    }
    final waiting = List.of(batch);
    var moved = true;
    while (moved) {
      moved = false;
      for (var s = 0; s < traySlots.length; s++) {
        final r = traySlots[s];
        if (r == null) continue;
        final peg = level.pegOfColor[level.rings[r].color];
        if (nextColorOn(peg) == level.rings[r].color) {
          traySlots[s] = null;
          pegRings[peg].add(r);
          events.add(RingPromoted(r, s, peg, pegRings[peg].length - 1));
          moved = true;
        }
      }
      for (var i = 0; i < waiting.length; i++) {
        final r = waiting[i];
        final peg = level.pegOfColor[level.rings[r].color];
        if (nextColorOn(peg) == level.rings[r].color) {
          pegRings[peg].add(r);
          events.add(
            RingReleased(r, Destination.peg, peg, pegRings[peg].length - 1),
          );
          waiting.removeAt(i);
          i--;
          moved = true;
        }
      }
    }
    for (final r in waiting) {
      var slot = traySlots.indexOf(null);
      if (slot < 0) {
        // No room. Keep the ring visible in an overflow slot; the move fails
        // unless a later release in the same move clears space.
        traySlots.add(r);
        slot = traySlots.length - 1;
      } else {
        traySlots[slot] = r;
      }
      events.add(RingReleased(r, Destination.tray, -1, slot));
    }
  }

  /// Folds overflow slots back into the tray once a move has settled.
  void _normalizeTray(int baseSlots) {
    for (var s = traySlots.length - 1; s >= baseSlots; s--) {
      final r = traySlots[s];
      if (r == null) {
        traySlots.removeAt(s);
        continue;
      }
      final empty = traySlots.indexOf(null);
      if (empty >= 0 && empty < baseSlots) {
        traySlots[empty] = r;
        traySlots.removeAt(s);
      }
    }
  }
}
