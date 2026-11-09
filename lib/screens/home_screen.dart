import 'package:flutter/material.dart';

import '../game/daily.dart';
import '../game/economy.dart';
import '../game/knot.dart';
import '../game/level.dart';
import '../l10n/strings.dart';
import '../render/knot_view.dart';
import '../render/palette.dart';
import '../render/scene.dart';
import '../services/services.dart';
import '../ui/widgets.dart';
import 'describe.dart';
import 'levels_screen.dart';
import 'play_screen.dart';

/// One button to play. Streak, coins and the daily knot are visible without
/// scrolling.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenDaily});
  final VoidCallback onOpenDaily;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final KnotScene _emblem = KnotScene();

  static final LevelDef _emblemLevel = LevelDef(
    id: 0,
    rings: const [
      RingDef(
        id: 0,
        color: 1,
        kind: RingKind.plain,
        cell: [-1, 0, 0],
        plane: RingPlane.xy,
        turn: 1,
        tilt: -14,
        size: 106,
      ),
      RingDef(
        id: 1,
        color: 0,
        kind: RingKind.plain,
        cell: [0, 0, 0],
        plane: RingPlane.xz,
        turn: 1,
        tilt: 16,
        size: 94,
      ),
      RingDef(
        id: 2,
        color: 3,
        kind: RingKind.plain,
        cell: [1, 0, 0],
        plane: RingPlane.xy,
        turn: 3,
        tilt: 12,
      ),
    ],
    pegs: const [],
    tray: 4,
    camYaw: -0.6,
    camPitch: 0.5,
  );

  @override
  void initState() {
    super.initState();
    _emblem.load(_emblemLevel, Knot(_emblemLevel));
    _emblem.glows.clear();
  }

  @override
  void dispose() {
    _emblem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    final services = AppScope.of(context);
    final profile = services.profile;
    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) {
        _emblem.calm =
            profile.settings.reduceMotion ||
            MediaQuery.disableAnimationsOf(context);
        final levels = services.levels;
        final allDone = profile.stars.length >= levels.count;
        final next = profile.unlocked.clamp(1, levels.count);
        final streak = profile.liveStreak;
        final today = services.now();
        final daily = levels.dailyFor(today);
        final collecting = profile.collecting;
        return Narrow(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Longer words in other languages shrink to fit rather
                    // than push the coins off a narrow screen.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Pill(
                          label: s.count('count.streak', streak),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_fire_department_rounded,
                                size: 17,
                                color: streak > 0 ? p.brass : p.dim,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                streak > 0
                                    ? s('home.day', {'n': streak})
                                    : s('home.no_streak'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Pill(
                      label: s.count('count.coins', profile.coins),
                      child: Coins(profile.coins),
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: KnotView(
                            scene: _emblem,
                            skin: RingSkin.of(profile.skin),
                            interactive: false,
                            groundShadow: false,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Loopsmith', style: AppText.display(p, 38)),
                      ),
                      const SizedBox(height: 14),
                      if (collecting != null) ...[
                        Text(
                          s('home.set_progress', {
                            'name': collecting.name,
                            'n': profile.rings,
                            'total': Economy.ringsPerSet,
                          }),
                          textAlign: TextAlign.center,
                          style: AppText.body(p, 13.5, color: p.dim),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 220,
                          child: ProgressBar(
                            value: profile.rings / Economy.ringsPerSet,
                          ),
                        ),
                      ] else
                        Text(
                          s('home.stars_earned', {'n': profile.totalStars}),
                          style: AppText.body(p, 13.5, color: p.dim),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: BrassButton(
                    label: allDone
                        ? s('home.replay', {'n': next})
                        : s('home.play', {'n': next}),
                    detail: allDone
                        ? s('home.all_cleared')
                        : (Economy.isKnotLevel(next)
                              ? s('home.knot_detail')
                              : null),
                    onTap: () =>
                        Navigator.of(context)
                            .push(PlayScreen.route(levels.level(next))),
                  ),
                ),
                const SizedBox(height: 16),
                Pressable(
                  onTap: widget.onOpenDaily,
                  label: s('daily.title'),
                  child: Panel(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s('daily.number', {'n': dailyNumber(today)}),
                                style: AppText.body(
                                  p,
                                  16,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                describeLevel(daily, s),
                                style: AppText.body(p, 13.5, color: p.dim),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: profile.dailyDoneToday ? p.cardHi : p.brass,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            profile.dailyDoneToday
                                ? s('common.done')
                                : s('common.new'),
                            style: AppText.body(
                              p,
                              12.5,
                              weight: FontWeight.w700,
                              color: profile.dailyDoneToday
                                  ? p.dim
                                  : p.brassInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () {
                    services.tap();
                    Navigator.of(context).push(LevelsScreen.route());
                  },
                  child: Text(
                    s('home.all_levels'),
                    style: AppText.body(p, 14, color: p.dim),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
