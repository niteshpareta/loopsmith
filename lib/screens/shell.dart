import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../render/palette.dart';
import '../services/audio.dart';
import '../services/reminders.dart';
import '../services/services.dart';
import '../ui/widgets.dart';
import 'daily_screen.dart';
import 'home_screen.dart';
import 'play_screen.dart';
import 'settings_screen.dart';
import 'workshop_screen.dart';

/// The four main screens and the bar that switches between them.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  bool _greeted = false;

  static const _tabs = [
    ('nav.home', Icons.home_rounded),
    ('nav.daily', Icons.calendar_today_rounded),
    ('nav.workshop', Icons.palette_rounded),
    ('nav.settings', Icons.tune_rounded),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_greeted) return;
    _greeted = true;
    final services = AppScope.of(context);
    final s = S.of(context);
    services.audio.setMood(MusicMood.menu);
    if (services.profile.settings.reminder) {
      // Keep the next few evenings' reminders planned, in the right language.
      services.reminders.refresh(
        ReminderText(s('remind.title'), s('remind.body'), s('remind.channel')),
        playedToday: services.profile.dailyDoneToday,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (kDemoLevel > 0) {
        final id = kDemoLevel.clamp(1, services.levels.count);
        Navigator.of(context).push(PlayScreen.route(services.levels.level(id)));
        return;
      }
      if (services.profile.claimDailyGift() &&
          services.profile.stars.isNotEmpty) {
        toast(context, s('home.gift'));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Bench(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _tab,
            children: [
              // Only the visible tab animates, to save battery.
              TickerMode(
                enabled: _tab == 0,
                child: HomeScreen(onOpenDaily: () => setState(() => _tab = 1)),
              ),
              TickerMode(enabled: _tab == 1, child: const DailyScreen()),
              const WorkshopScreen(),
              const SettingsScreen(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: p.bg,
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: Pressable(
                        onTap: () => setState(() => _tab = i),
                        label: s(_tabs[i].$1),
                        child: Semantics(
                          selected: _tab == i,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 9, 4, 7),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _tabs[i].$2,
                                  size: 23,
                                  color: _tab == i ? p.brass : p.dim,
                                ),
                                const SizedBox(height: 3),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    s(_tabs[i].$1),
                                    maxLines: 1,
                                    style: AppText.body(
                                      p,
                                      12,
                                      weight: _tab == i
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: _tab == i ? p.brass : p.dim,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
