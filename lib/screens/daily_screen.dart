import 'package:flutter/material.dart';

import '../game/daily.dart';
import '../game/knot.dart';
import '../game/level.dart';
import '../render/knot_view.dart';
import '../render/palette.dart';
import '../render/ring_paint.dart';
import '../render/scene.dart';
import '../services/services.dart';
import '../ui/widgets.dart';
import 'describe.dart';
import 'play_controller.dart';
import 'play_screen.dart';

/// One shared knot a day, a streak, and a saver that forgives a missed day.
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
        _preview.calm = profile.settings.reduceMotion;
        final number = dailyNumber(today);
        final streak = profile.liveStreak;
        final done = profile.dailyDoneToday;
        // The last seven days, ending today, so a streak reads left to right.
        final firstDay = today.subtract(const Duration(days: 6));
        final yesterday =
            profile.daily[dateKey(today.subtract(const Duration(days: 1)))];
        const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

        return Narrow(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Daily Knot',
                        style: AppText.display(p, 22, weight: FontWeight.w500),
                      ),
                    ),
                    Pill(
                      label: '$streak day streak',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department_rounded,
                            size: 17,
                            color: streak > 0 ? p.brass : p.dim,
                          ),
                          const SizedBox(width: 5),
                          Text(streak == 1 ? '1 day' : '$streak days'),
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
                              return Semantics(
                                label:
                                    '${names[day.weekday - 1]}${cleared
                                        ? ', cleared'
                                        : isToday
                                        ? ', today'
                                        : ''}',
                                child: Column(
                                  children: [
                                    Text(
                                      names[day.weekday - 1],
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
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Daily Knot #$number',
                        style: AppText.display(p, 19, weight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        describeLevel(level),
                        style: AppText.body(p, 14, color: p.dim),
                      ),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: KnotView(
                            scene: _preview,
                            skin: RingSkin.of(profile.skin),
                            marks: profile.settings.colorMarks,
                            interactive: false,
                            groundShadow: false,
                          ),
                        ),
                      ),
                      Text(
                        'Same knot for everyone today',
                        style: AppText.body(p, 13, color: p.dim),
                      ),
                    ],
                  ),
                ),
                Panel(
                  child: Column(
                    children: [
                      _row(
                        p,
                        'Yesterday',
                        yesterday == null
                            ? 'Not played'
                            : '${yesterday.moves} moves · par ${yesterday.par}',
                      ),
                      const SizedBox(height: 6),
                      _row(
                        p,
                        'Best streak',
                        profile.bestStreak == 1
                            ? '1 day'
                            : '${profile.bestStreak} days',
                      ),
                      const SizedBox(height: 6),
                      _row(p, 'Streak savers', '${profile.streakSavers} held'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: BrassButton(
                    label: done ? 'Play again' : 'Start today\'s knot',
                    detail: done ? 'Already cleared today' : null,
                    onTap: () => Navigator.of(context).push(
                      PlayScreen.route(
                        level,
                        mode: PlayMode.daily,
                        dailyNumber: number,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
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
