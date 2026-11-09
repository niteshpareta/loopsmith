/// Level data: rings on a lattice, the links between them, and the peg goals.
///
/// Everything in `lib/game` is plain Dart with no Flutter imports, so the
/// level generator in `tool/` can run on the Dart VM and the rules can be
/// unit-tested without a device.
library;

/// The plane a ring lies in. Linked rings always sit in perpendicular planes.
enum RingPlane { xy, xz, yz }

/// How a ring behaves.
enum RingKind {
  /// One opening, turns freely.
  plain,

  /// Two opposite openings.
  twin,

  /// One opening. Turning it turns its partner the opposite way.
  geared,

  /// One opening, cannot be turned. Drawn as a frame, not a circle.
  fixed,

  /// No opening until its key ring ([RingDef.partner]) has been freed.
  sealed,
}

/// The outline of a ring. Only fixed frames use the non-round shapes.
enum RingShape { round, square, triangle, dee }

/// Number of ring colours a level can use.
const int kColorCount = 6;

/// Largest knot the solver supports (its state key is base 17 per ring).
const int kMaxRings = 12;

/// Axis indices: 0 = x, 1 = y, 2 = z.
int planeU(RingPlane p) => p == RingPlane.yz ? 1 : 0;
int planeV(RingPlane p) => p == RingPlane.xy ? 1 : 2;
int planeN(RingPlane p) => switch (p) {
  RingPlane.xy => 2,
  RingPlane.xz => 1,
  RingPlane.yz => 0,
};
bool planeHas(RingPlane p, int axis) => planeU(p) == axis || planeV(p) == axis;

/// The quarter position (0..3) on a ring in [plane] that faces along [axis]
/// in direction [sign]. Position 0 is +u, 1 is +v, 2 is -u, 3 is -v.
int quarterFacing(RingPlane plane, int axis, int sign) {
  if (planeU(plane) == axis) return sign > 0 ? 0 : 2;
  return sign > 0 ? 1 : 3;
}

class RingDef {
  const RingDef({
    required this.id,
    required this.color,
    required this.kind,
    required this.cell,
    required this.plane,
    required this.turn,
    this.partner = -1,
    this.tilt = 0,
    this.tiltAxis = 0,
    this.size = 100,
    this.shape = RingShape.round,
  });

  final int id;

  /// Index into the active skin's six colours.
  final int color;
  final RingKind kind;

  /// Lattice position `[x, y, z]`.
  final List<int> cell;
  final RingPlane plane;

  /// Starting orientation in quarter turns (0..3). The opening sits at this
  /// quarter position.
  final int turn;

  /// Geared partner, or the key ring for a sealed ring. -1 when unused.
  final int partner;

  /// Lean, in degrees, about the axis through the ring's link points. It
  /// changes how the knot looks, never how it plays: the link points stay
  /// where they are.
  final int tilt;

  /// The axis the ring leans about: 0 is its u axis, 1 is its v axis.
  final int tiltAxis;

  /// Radius as a percentage of the standard ring.
  final int size;
  final RingShape shape;

  RingDef copyWith({
    int? color,
    RingKind? kind,
    int? turn,
    int? partner,
    int? tilt,
    int? tiltAxis,
    int? size,
    RingShape? shape,
  }) => RingDef(
    id: id,
    color: color ?? this.color,
    kind: kind ?? this.kind,
    cell: cell,
    plane: plane,
    turn: turn ?? this.turn,
    partner: partner ?? this.partner,
    tilt: tilt ?? this.tilt,
    tiltAxis: tiltAxis ?? this.tiltAxis,
    size: size ?? this.size,
    shape: shape ?? this.shape,
  );

  List<int> toJson() => [
    color,
    kind.index,
    cell[0],
    cell[1],
    cell[2],
    plane.index,
    turn,
    partner,
    tilt,
    tiltAxis,
    size,
    shape.index,
  ];

  static RingDef fromJson(int id, List<dynamic> j) => RingDef(
    id: id,
    color: j[0] as int,
    kind: RingKind.values[j[1] as int],
    cell: [j[2] as int, j[3] as int, j[4] as int],
    plane: RingPlane.values[j[5] as int],
    turn: j[6] as int,
    partner: j[7] as int,
    tilt: j.length > 8 ? j[8] as int : 0,
    tiltAxis: j.length > 9 ? j[9] as int : 0,
    size: j.length > 10 ? j[10] as int : 100,
    shape: j.length > 11 ? RingShape.values[j[11] as int] : RingShape.round,
  );
}

/// Two rings hooked through each other. [pa] and [pb] are the quarter
/// positions where each ring meets the other.
class LinkDef {
  const LinkDef(this.a, this.b, this.pa, this.pb);
  final int a;
  final int b;
  final int pa;
  final int pb;
}

/// One end of a link, seen from a ring.
class LinkEnd {
  const LinkEnd(this.link, this.other, this.myPos, this.otherPos);
  final int link;
  final int other;
  final int myPos;
  final int otherPos;
}

/// A single turn: rotate [ring] by [delta] quarter turns (1..3).
class Move {
  const Move(this.ring, this.delta);
  final int ring;
  final int delta;

  @override
  bool operator ==(Object other) =>
      other is Move && other.ring == ring && other.delta == delta;

  @override
  int get hashCode => ring * 4 + delta;

  @override
  String toString() => 'Move(ring $ring, +$delta)';
}

class LevelDef {
  LevelDef({
    required this.id,
    required this.rings,
    required this.pegs,
    required this.tray,
    this.par = 0,
    this.solution = const [],
    this.rating = 0,
    this.camYaw = -0.5,
    this.camPitch = 0.42,
  }) : links = computeLinks(rings),
       assert(rings.length <= kMaxRings) {
    linksOf = List.generate(rings.length, (_) => <LinkEnd>[]);
    for (var i = 0; i < links.length; i++) {
      final l = links[i];
      linksOf[l.a].add(LinkEnd(i, l.b, l.pa, l.pb));
      linksOf[l.b].add(LinkEnd(i, l.a, l.pb, l.pa));
    }
    pegOfColor = List.filled(kColorCount, -1);
    for (var p = 0; p < pegs.length; p++) {
      for (final c in pegs[p]) {
        assert(
          pegOfColor[c] == -1 || pegOfColor[c] == p,
          'a colour may only appear on one peg',
        );
        pegOfColor[c] = p;
      }
    }
  }

  final int id;
  final List<RingDef> rings;

  /// Colour sequences the pegs want, in order. Empty for tutorial levels,
  /// where freed rings are simply collected.
  final List<List<int>> pegs;

  /// Holding tray slots. The attempt ends when every slot is occupied.
  final int tray;

  /// Fewest moves that clear the level.
  final int par;

  /// One shortest solution, stored for tests and first-move hints.
  final List<Move> solution;

  /// Generator's difficulty estimate, 0 (gentle) to 1 (hard).
  final double rating;

  /// The starting view, chosen by the generator so every ring can be seen
  /// and tapped.
  final double camYaw;
  final double camPitch;

  final List<LinkDef> links;
  late final List<List<LinkEnd>> linksOf;
  late final List<int> pegOfColor;

  bool get hasPegs => pegs.isNotEmpty;

  Set<RingKind> get kinds => {for (final r in rings) r.kind};

  LevelDef withCamera(double yaw, double pitch) => LevelDef(
    id: id,
    rings: rings,
    pegs: pegs,
    tray: tray,
    par: par,
    solution: solution,
    rating: rating,
    camYaw: yaw,
    camPitch: pitch,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'r': [for (final r in rings) r.toJson()],
    'pegs': pegs,
    'tray': tray,
    'par': par,
    'sol': [
      for (final m in solution) [m.ring, m.delta],
    ],
    'rating': double.parse(rating.toStringAsFixed(2)),
    'cam': [
      double.parse(camYaw.toStringAsFixed(2)),
      double.parse(camPitch.toStringAsFixed(2)),
    ],
  };

  static LevelDef fromJson(Map<String, dynamic> j) {
    final r = j['r'] as List<dynamic>;
    final cam = j['cam'] as List<dynamic>?;
    return LevelDef(
      id: j['id'] as int,
      rings: [
        for (var i = 0; i < r.length; i++)
          RingDef.fromJson(i, r[i] as List<dynamic>),
      ],
      pegs: [
        for (final p in j['pegs'] as List<dynamic>)
          [for (final c in p as List<dynamic>) c as int],
      ],
      tray: j['tray'] as int,
      par: j['par'] as int,
      solution: [
        for (final m in j['sol'] as List<dynamic>)
          Move((m as List<dynamic>)[0] as int, m[1] as int),
      ],
      rating: (j['rating'] as num).toDouble(),
      camYaw: cam == null ? -0.5 : (cam[0] as num).toDouble(),
      camPitch: cam == null ? 0.42 : (cam[1] as num).toDouble(),
    );
  }
}

/// Finds every pair of rings that hook through each other.
///
/// Two rings link when their cells are neighbours along one axis, both planes
/// contain that axis, and the planes differ (like two links of a chain).
List<LinkDef> computeLinks(List<RingDef> rings) {
  final out = <LinkDef>[];
  for (var i = 0; i < rings.length; i++) {
    for (var j = i + 1; j < rings.length; j++) {
      final a = rings[i], b = rings[j];
      var axis = -1, sign = 0, nonZero = 0;
      for (var k = 0; k < 3; k++) {
        final d = b.cell[k] - a.cell[k];
        if (d != 0) {
          nonZero++;
          axis = k;
          sign = d;
        }
      }
      if (nonZero != 1 || sign.abs() != 1) continue;
      if (!planeHas(a.plane, axis) || !planeHas(b.plane, axis)) continue;
      if (a.plane == b.plane) {
        continue; // overlapping, rejected by the generator
      }
      out.add(
        LinkDef(
          i,
          j,
          quarterFacing(a.plane, axis, sign),
          quarterFacing(b.plane, axis, -sign),
        ),
      );
    }
  }
  return out;
}
