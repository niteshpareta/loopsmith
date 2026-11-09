/// Every tunable number in one place. Move these to remote config before a
/// wide launch so they can change without an app update.
library;

class Economy {
  static const int startCoins = 100;
  static const int startHints = 3;

  /// Coins for clearing a level: more stars, more coins.
  static int clearReward(int stars) => 10 + 5 * stars;
  static const int dailyReward = 50;

  static const int hintPackPrice = 100;
  static const int hintPackSize = 3;
  static const int undoPrice = 25;
  static const int slotPrice = 60;

  /// Rings needed to complete a collectible skin, and the coins a spare ring
  /// is worth once every collectible skin is owned.
  static const int ringsPerSet = 6;
  static const int spareRingCoins = 30;

  /// Free undos per attempt.
  static const int freeUndos = 1;

  /// Three stars at par, two within three moves of it, one otherwise.
  static int starsFor(int moves, int par) =>
      moves <= par ? 3 : (moves <= par + 3 ? 2 : 1);

  /// Every fourth level from 12 on is a harder "knot" that awards a ring.
  static bool isKnotLevel(int id) => id >= 12 && id % 4 == 0;

  // Advertising rules.
  static const int interstitialFromLevel = 12;
  static const Duration interstitialGap = Duration(minutes: 3);

  // Streaks.
  static const int saverEvery = 7;
  static const int maxSavers = 2;

  // Store product ids. Create matching products in both stores.
  static const String removeAdsId = 'remove_ads';
  static const String starterKitId = 'starter_kit';
  static const int starterKitHints = 10;
  static const int starterKitSlots = 5;
  static const String starterKitSkin = 'neon';
}

/// Whether a between-level ad may be shown now.
bool canShowInterstitial({
  required int level,
  required bool adsRemoved,
  required DateTime now,
  required DateTime? lastShown,
}) {
  if (adsRemoved) return false;
  if (level < Economy.interstitialFromLevel) return false;
  if (lastShown != null &&
      now.difference(lastShown) < Economy.interstitialGap) {
    return false;
  }
  return true;
}
