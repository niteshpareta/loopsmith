import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/daily.dart';
import '../game/economy.dart';
import '../game/skins.dart';

/// Where the profile is saved. Swapped for an in-memory store in tests.
abstract class SaveStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PrefsStore implements SaveStore {
  PrefsStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<PrefsStore> open() async =>
      PrefsStore(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
}

class MemoryStore implements SaveStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class GameSettings {
  bool music = true;
  bool sound = true;
  bool vibration = true;
  bool lightTheme = false;
  bool colorMarks = false;
  bool leftHanded = false;
  bool reduceMotion = false;

  Map<String, dynamic> toJson() => {
    'music': music,
    'sound': sound,
    'vibration': vibration,
    'light': lightTheme,
    'marks': colorMarks,
    'left': leftHanded,
    'calm': reduceMotion,
  };

  void load(Map<String, dynamic> j) {
    music = j['music'] as bool? ?? true;
    sound = j['sound'] as bool? ?? true;
    vibration = j['vibration'] as bool? ?? true;
    lightTheme = j['light'] as bool? ?? false;
    colorMarks = j['marks'] as bool? ?? false;
    leftHanded = j['left'] as bool? ?? false;
    reduceMotion = j['calm'] as bool? ?? false;
  }
}

class DailyRecord {
  const DailyRecord(this.moves, this.par, this.stars);
  final int moves;
  final int par;
  final int stars;
}

/// What the player earned by clearing a level.
class ClearOutcome {
  const ClearOutcome({
    required this.stars,
    required this.coins,
    required this.firstClear,
    required this.ringEarned,
    required this.unlockedSkins,
    this.streak = 0,
    this.saverUsed = false,
    this.saverEarned = false,
  });
  final int stars;
  final int coins;
  final bool firstClear;

  /// A collectible ring was awarded (knot levels and daily knots).
  final bool ringEarned;
  final List<String> unlockedSkins;

  /// Daily knots only.
  final int streak;
  final bool saverUsed;
  final bool saverEarned;
}

/// Everything the game remembers about the player. Saved as one JSON blob.
class PlayerProfile extends ChangeNotifier {
  PlayerProfile(this._store, {DateTime Function()? clock})
    : now = clock ?? DateTime.now;

  static const _key = 'loopsmith.profile.v1';

  final SaveStore _store;
  final DateTime Function() now;

  /// Highest level the player may start.
  int unlocked = 1;
  final Map<int, int> stars = {};
  final Map<int, int> bestMoves = {};

  int coins = Economy.startCoins;
  int hints = Economy.startHints;
  int slotTokens = 0;

  final Set<String> ownedSkins = {'enamel'};
  String skin = 'enamel';

  /// Rings collected toward the next collectible skin.
  int rings = 0;

  int streak = 0;
  int bestStreak = 0;
  int streakSavers = 0;
  String? lastDaily;
  final Map<String, DailyRecord> daily = {};
  String? lastGift;

  bool adsRemoved = false;
  bool starterKit = false;
  final Set<String> seenTips = {};
  final GameSettings settings = GameSettings();

  int get totalStars => stars.values.fold(0, (a, b) => a + b);
  int get highestCleared => stars.keys.fold(0, (a, b) => a > b ? a : b);
  SkinDef get activeSkin => skinById(skin);

  /// The collectible skin the player is working toward, if any is left.
  SkinDef? get collecting {
    for (final s in kSkins) {
      if (s.unlock == SkinUnlock.collect && !ownedSkins.contains(s.id)) {
        return s;
      }
    }
    return null;
  }

  // ------------------------------------------------------------ persistence
  Future<void> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      unlocked = j['unlocked'] as int? ?? 1;
      stars
        ..clear()
        ..addAll(_intMap(j['stars']));
      bestMoves
        ..clear()
        ..addAll(_intMap(j['best']));
      coins = j['coins'] as int? ?? Economy.startCoins;
      hints = j['hints'] as int? ?? Economy.startHints;
      slotTokens = j['slots'] as int? ?? 0;
      ownedSkins
        ..clear()
        ..addAll((j['skins'] as List<dynamic>? ?? ['enamel']).cast<String>())
        ..add('enamel');
      skin = j['skin'] as String? ?? 'enamel';
      if (!ownedSkins.contains(skin)) skin = 'enamel';
      rings = j['rings'] as int? ?? 0;
      streak = j['streak'] as int? ?? 0;
      bestStreak = j['bestStreak'] as int? ?? 0;
      streakSavers = j['savers'] as int? ?? 0;
      lastDaily = j['lastDaily'] as String?;
      daily.clear();
      (j['daily'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        final l = v as List<dynamic>;
        daily[k] = DailyRecord(l[0] as int, l[1] as int, l[2] as int);
      });
      lastGift = j['lastGift'] as String?;
      adsRemoved = j['adsRemoved'] as bool? ?? false;
      starterKit = j['starterKit'] as bool? ?? false;
      seenTips
        ..clear()
        ..addAll((j['tips'] as List<dynamic>? ?? []).cast<String>());
      settings.load(j['settings'] as Map<String, dynamic>? ?? {});
    } catch (e) {
      // A damaged save should never stop the game from starting.
      debugPrint('Profile could not be read, starting fresh: $e');
    }
  }

  static Map<int, int> _intMap(dynamic j) => {
    for (final e in (j as Map<String, dynamic>? ?? {}).entries)
      int.parse(e.key): e.value as int,
  };

  Map<String, dynamic> toJson() => {
    'unlocked': unlocked,
    'stars': {for (final e in stars.entries) '${e.key}': e.value},
    'best': {for (final e in bestMoves.entries) '${e.key}': e.value},
    'coins': coins,
    'hints': hints,
    'slots': slotTokens,
    'skins': ownedSkins.toList(),
    'skin': skin,
    'rings': rings,
    'streak': streak,
    'bestStreak': bestStreak,
    'savers': streakSavers,
    'lastDaily': lastDaily,
    'daily': {
      for (final e in daily.entries)
        e.key: [e.value.moves, e.value.par, e.value.stars],
    },
    'lastGift': lastGift,
    'adsRemoved': adsRemoved,
    'starterKit': starterKit,
    'tips': seenTips.toList(),
    'settings': settings.toJson(),
  };

  Future<void> save() => _store.write(_key, jsonEncode(toJson()));

  void _changed() {
    notifyListeners();
    save();
  }

  /// Applies a settings change, saves, and tells listeners.
  void updateSettings(void Function(GameSettings s) change) {
    change(settings);
    _changed();
  }

  // ------------------------------------------------------------ progress
  /// Records a cleared campaign level and returns what it earned.
  ClearOutcome completeLevel(
    int id,
    int moves,
    int par, {
    required int levelCount,
  }) {
    final earned = Economy.starsFor(moves, par);
    final first = !stars.containsKey(id);
    if (earned > (stars[id] ?? 0)) stars[id] = earned;
    if (moves < (bestMoves[id] ?? 1 << 30)) bestMoves[id] = moves;
    if (id >= unlocked && id < levelCount) unlocked = id + 1;
    final reward = first
        ? Economy.clearReward(earned)
        : Economy.clearReward(earned) ~/ 3;
    coins += reward;
    var ring = false;
    if (first && Economy.isKnotLevel(id)) {
      ring = true;
      _awardRing();
    }
    final unlockedNow = _refreshUnlocks();
    _changed();
    return ClearOutcome(
      stars: earned,
      coins: reward,
      firstClear: first,
      ringEarned: ring,
      unlockedSkins: unlockedNow,
    );
  }

  /// Records today's Daily Knot. Replays the same day earn nothing more.
  ClearOutcome completeDaily(int moves, int par) {
    final today = now();
    final key = dateKey(today);
    final earned = Economy.starsFor(moves, par);
    final first = !daily.containsKey(key);
    final prev = daily[key];
    if (prev == null || moves < prev.moves) {
      daily[key] = DailyRecord(moves, par, earned);
    }
    // Keep three weeks of history.
    final keys = daily.keys.toList()..sort();
    while (keys.length > 21) {
      daily.remove(keys.removeAt(0));
    }

    var saverUsed = false, saverEarned = false, reward = 0, ring = false;
    if (first) {
      final gap = lastDaily == null
          ? 99
          : daysBetween(parseDateKey(lastDaily!), today);
      if (gap == 1) {
        streak++;
      } else if (gap == 2 && streakSavers > 0 && streak > 0) {
        streakSavers--;
        saverUsed = true;
        streak++;
      } else if (gap != 0) {
        streak = 1;
      }
      lastDaily = key;
      if (streak > bestStreak) bestStreak = streak;
      if (streak % Economy.saverEvery == 0 &&
          streakSavers < Economy.maxSavers) {
        streakSavers++;
        saverEarned = true;
      }
      reward = Economy.dailyReward;
      coins += reward;
      ring = true;
      _awardRing();
    }
    final unlockedNow = _refreshUnlocks();
    _changed();
    return ClearOutcome(
      stars: earned,
      coins: reward,
      firstClear: first,
      ringEarned: ring,
      unlockedSkins: unlockedNow,
      streak: streak,
      saverUsed: saverUsed,
      saverEarned: saverEarned,
    );
  }

  /// The streak as it stands today: zero once it can no longer be continued.
  int get liveStreak {
    if (lastDaily == null) return 0;
    final gap = daysBetween(parseDateKey(lastDaily!), now());
    if (gap <= 1) return streak;
    if (gap == 2 && streakSavers > 0) return streak;
    return 0;
  }

  bool get dailyDoneToday => daily.containsKey(dateKey(now()));

  void _awardRing() {
    if (collecting == null) {
      coins += Economy.spareRingCoins;
    } else {
      rings++;
    }
  }

  List<String> _refreshUnlocks() {
    final out = <String>[];
    for (final s in kSkins) {
      if (ownedSkins.contains(s.id)) continue;
      final ok = switch (s.unlock) {
        SkinUnlock.owned => true,
        SkinUnlock.collect => rings >= Economy.ringsPerSet,
        SkinUnlock.level => highestCleared >= s.amount,
        SkinUnlock.streak => bestStreak >= s.amount,
        SkinUnlock.coins => false,
      };
      if (ok) {
        if (s.unlock == SkinUnlock.collect) rings -= Economy.ringsPerSet;
        ownedSkins.add(s.id);
        out.add(s.id);
      }
    }
    return out;
  }

  /// Gives one hint the first time the game is opened each day.
  bool claimDailyGift() {
    final key = dateKey(now());
    if (lastGift == key) return false;
    lastGift = key;
    hints++;
    _changed();
    return true;
  }

  // ------------------------------------------------------------ wallet
  bool spendCoins(int amount) {
    if (coins < amount) return false;
    coins -= amount;
    _changed();
    return true;
  }

  void addCoins(int amount) {
    coins += amount;
    _changed();
  }

  void addHints(int amount) {
    hints += amount;
    _changed();
  }

  bool useHint() {
    if (hints <= 0) return false;
    hints--;
    _changed();
    return true;
  }

  bool useSlotToken() {
    if (slotTokens <= 0) return false;
    slotTokens--;
    _changed();
    return true;
  }

  bool buySkin(SkinDef s) {
    if (ownedSkins.contains(s.id) || s.unlock != SkinUnlock.coins) return false;
    if (coins < s.amount) return false;
    coins -= s.amount;
    ownedSkins.add(s.id);
    skin = s.id;
    _changed();
    return true;
  }

  void selectSkin(String id) {
    if (!ownedSkins.contains(id) || skin == id) return;
    skin = id;
    _changed();
  }

  void grantRemoveAds() {
    if (adsRemoved) return;
    adsRemoved = true;
    _changed();
  }

  void grantStarterKit() {
    if (starterKit) return;
    starterKit = true;
    hints += Economy.starterKitHints;
    slotTokens += Economy.starterKitSlots;
    ownedSkins.add(Economy.starterKitSkin);
    _changed();
  }

  /// Returns true the first time a tip is shown, and remembers it.
  bool firstTime(String tip) {
    if (seenTips.contains(tip)) return false;
    seenTips.add(tip);
    save();
    return true;
  }

  Future<void> resetProgress() async {
    unlocked = 1;
    stars.clear();
    bestMoves.clear();
    coins = Economy.startCoins;
    hints = Economy.startHints;
    slotTokens = starterKit ? Economy.starterKitSlots : 0;
    ownedSkins
      ..clear()
      ..add('enamel');
    if (starterKit) ownedSkins.add(Economy.starterKitSkin);
    skin = 'enamel';
    rings = 0;
    streak = 0;
    bestStreak = 0;
    streakSavers = 0;
    lastDaily = null;
    daily.clear();
    seenTips.clear();
    notifyListeners();
    await save();
  }
}
