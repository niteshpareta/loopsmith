/// Ring skins: six distinguishable colours plus a finish.
library;

enum SkinUnlock { owned, collect, level, coins, streak }

/// What a skin's rings look like they are made of.
enum Finish {
  /// Glossy painted enamel: clear colour with a sharp highlight.
  gloss,

  /// Polished metal: reflects a bright sky and a dark horizon.
  metal,

  /// Soft, matte stone.
  stone,

  /// Lit from within.
  neon,
}

class SkinDef {
  const SkinDef({
    required this.id,
    required this.name,
    required this.colors,
    required this.unlock,
    this.amount = 0,
    this.gloss = 0.6,
    this.glow = 0.0,
    this.finish = Finish.gloss,
  });

  final String id;
  final String name;

  /// Six ARGB colours. Index is the ring's colour in the level data.
  final List<int> colors;
  final SkinUnlock unlock;

  /// Level to reach, coins to pay, or streak days, depending on [unlock].
  final int amount;

  /// 0 matte to 1 mirror-bright highlight.
  final double gloss;

  /// 0 none to 1 strong neon glow.
  final double glow;
  final Finish finish;
}

const List<SkinDef> kSkins = [
  SkinDef(
    id: 'enamel',
    name: 'Enamel',
    unlock: SkinUnlock.owned,
    gloss: 0.6,
    colors: [
      0xFF35BFAE,
      0xFFE0AD4A,
      0xFFF0705F,
      0xFFA184F0,
      0xFF5AA9F2,
      0xFF86CF62,
    ],
  ),
  SkinDef(
    id: 'brass',
    name: 'Brass',
    unlock: SkinUnlock.collect,
    gloss: 1.0,
    finish: Finish.metal,
    colors: [
      0xFF4FA890,
      0xFFD8A63C,
      0xFFC9703D,
      0xFF9488C4,
      0xFF7D9BB8,
      0xFFA3B25A,
    ],
  ),
  SkinDef(
    id: 'jade',
    name: 'Jade',
    unlock: SkinUnlock.level,
    amount: 80,
    gloss: 0.25,
    finish: Finish.stone,
    colors: [
      0xFF5FB89A,
      0xFFD9C27A,
      0xFFD98A7A,
      0xFF9B8FD0,
      0xFF7AB0D6,
      0xFFA8C66C,
    ],
  ),
  SkinDef(
    id: 'neon',
    name: 'Neon',
    unlock: SkinUnlock.coins,
    amount: 900,
    gloss: 0.8,
    glow: 1.0,
    finish: Finish.neon,
    colors: [
      0xFF2FFFD5,
      0xFFFFD23F,
      0xFFFF5A7A,
      0xFFB86BFF,
      0xFF4CC3FF,
      0xFF9DFF4A,
    ],
  ),
  SkinDef(
    id: 'silver',
    name: 'Silver',
    unlock: SkinUnlock.streak,
    amount: 30,
    gloss: 1.0,
    finish: Finish.metal,
    colors: [
      0xFFA3E0D5,
      0xFFEFD79A,
      0xFFF2ABA0,
      0xFFC9B8F5,
      0xFFACD0F7,
      0xFFC3E6A6,
    ],
  ),
  SkinDef(
    id: 'coral',
    name: 'Coral',
    unlock: SkinUnlock.level,
    amount: 120,
    gloss: 0.5,
    colors: [
      0xFF1FA59A,
      0xFFF2B134,
      0xFFEF5D43,
      0xFFC95BD1,
      0xFF3F8FE0,
      0xFF8ECF3C,
    ],
  ),
];

SkinDef skinById(String id) =>
    kSkins.firstWhere((s) => s.id == id, orElse: () => kSkins.first);
