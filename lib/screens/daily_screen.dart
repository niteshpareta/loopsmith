import 'package:flutter/material.dart';

import '../game/daily.dart';
import '../game/economy.dart';
import '../game/knot.dart';
import '../game/level.dart';
import '../l10n/strings.dart';
import '../render/knot_view.dart';
import '../render/palette.dart';
import '../render/ring_paint.dart';
import '../render/scene.dart';
import '../services/services.dart';
import '../ui/widgets.dart';
import 'describe.dart';
import 'play_controller.dart';
import 'play_screen.dart';

/// One shared knot a day with a streak, and a run of seven knots a week.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  final KnotScene _preview = KnotScene();
  LevelDef? _shown;

  @override
  void dispose() {
    _preview.dispose();
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
        final today = services.now();
        final level = services.levels.dailyFor(today);
        if (!identical(level, _shown)) {
          _shown = level;
          _preview.load(level, Knot(level));
          _preview.glows.clear();
        }
        _preview.calm =
            profile.settings.reduceMotion ||
            MediaQuery.disableAnimationsOf(context);
        final number = dailyNumber(today);
        final streak = profile.liveStreak;
        final done = profile.dailyDoneToday;
        // The last seven days, ending today, so a streak reads left to right.
        final firstDay = today.subtract(const Duration(days: 6));
        final yesterday =
            profile.daily[dateKey(today.subtract(const Duration(days: 1)))];
        final letters = s('daily.weekdays');

        return Narrow(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s('daily.title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.display(p, 22, weight: FontWeight.w500),
                    ),
                  ),
                  Pill(
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
                        Text(s.count('count.days', streak)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Panel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final day = firstDay.add(Duration(days: i));
                            final isToday = daysBetween(day, today) == 0;
                            final cleared = profile.daily.containsKey(
                              dateKey(day),
                            );
                            final letter = letters[day.weekday - 1];
                            return Semantics(
                              label: cleared
                                  ? s('daily.day_cleared', {'day': letter})
                                  : (isToday
                                        ? s('daily.day_today', {'day': letter})
                                        : letter),
                              child: Column(
                                children: [
                                  Text(
                                    letter,
                                    style: AppText.body(
                                      p,
                                      12,
                                      weight: isToday
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isToday ? p.ink : p.dim,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  RingChip(
                                    size: 26,
                                    state: cleared
                                        ? ChipState.filled
                                        : (isToday
                                              ? ChipState.wanted
                                              : ChipState.empty),
                                    color: p.brass,
                                    next: isToday,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                s('daily.number', {'n': number}),
                textAlign: TextAlign.center,
                style: AppText.display(p, 19, weight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                describeLevel(level, s),
                textAlign: TextAlign.center,
                style: AppText.body(p, 14, color: p.dim),
              ),
              SizedBox(
                height: 230,
                child: KnotView(
                  scene: _preview,
                  skin: RingSkin.of(profile.skin),
                  marks: profile.settings.colorMarks,
                  interactive: false,
                  groundShadow: false,
                ),
              ),
              Text(
                s('daily.same'),
                textAlign: TextAlign.center,
                style: AppText.body(p, 13, color: p.dim),
              ),
              const SizedBox(height: 14),
              BrassButton(
                label: done ? s('daily.again') : s('daily.start'),
                detail: done ? s('daily.cleared') : null,
                onTap: () => Navigator.of(context).push(
                  PlayScreen.route(
                    level,
                    mode: PlayMode.daily,
                    dailyNumber: number,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Panel(
                child: Column(
                  children: [
                    _row(
                      p,
                      s('daily.yesterday'),
                      yesterday == null
                          ? s('daily.not_played')
                          : s('daily.result', {
                              'moves': yesterday.moves,
                              'par': yesterday.par,
                            }),
                    ),
                    const SizedBox(height: 6),
                    _row(
                      p,
                      s('daily.best'),
                      s.count('count.days', profile.bestStreak),
                    ),
                    const SizedBox(height: 6),
                    _row(
                      p,
                      s('daily.savers'),
                      s('daily.held', {'n': profile.streakSavers}),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _WeeklyRun(services: services),
            ],
          ),
        );
      },
    );
  }

  Widget _row(AppPalette p, String label, String value) => Row(
    children: [
      Expanded(
        child: Text(label, style: AppText.body(p, 14.5, color: p.dim)),
      ),
      Text(value, style: AppText.body(p, 14.5, weight: FontWeight.w700)),
    ],
  );
}

/// Seven knots a week, easiest first. Finishing all seven pays a bonus.
class _WeeklyRun extends StatelessWidget {
  const _WeeklyRun({required this.services});
  final Services services;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    final knots = services.levels.weeklyFor(services.now());
    if (knots.length < 7) return const SizedBox.shrink();
    final done = services.profile.weeklyProgress();
    var next = -1;
    for (var i = 0; i < 7 && next < 0; i++) {
      if (!done.contains(i)) next = i;
    }
    void play(int index) => Navigator.of(context).push(
      PlayScreen.route(knots[index], mode: PlayMode.weekly, weeklyIndex: index),
    );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s('weekly.title'),
            style: AppText.body(p, 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            s('weekly.progress', {'n': done.length}),
            style: AppText.body(p, 13.5, color: p.dim),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Pressable(
                    // Knots already cleared can be replayed.
                    onTap: done.contains(i) || i == next ? () => play(i) : null,
                    label: s('weekly.knot', {'n': i + 1}),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Center(
                        child: RingChip(
                          size: 28,
                          state: done.contains(i)
                              ? ChipState.filled
                              : (i == next
                                    ? ChipState.wanted
                                    : ChipState.empty),
                          color: p.brass,
                          next: i == next,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (next >= 0) ...[
            Text(
              s('weekly.reward', {'coins': Economy.weeklyBonus}),
              style: AppText.body(p, 13.5, color: p.dim),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GhostButton(
                label: s('weekly.play', {'n': next + 1}),
                detail: describeLevel(knots[next], s),
                onTap: () => play(next),
              ),
            ),
          ] else ...[
            Text(
              s('weekly.complete'),
              style: AppText.body(
                p,
                15,
                weight: FontWeight.w700,
                color: p.good,
              ),
            ),
            Text(
              s('weekly.complete_detail'),
              style: AppText.body(p, 13.5, color: p.dim),
            ),
          ],
        ],
      ),
    );
  }
}
