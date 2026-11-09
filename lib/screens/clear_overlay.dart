import 'dart:async';

import 'package:flutter/material.dart';

import '../game/economy.dart';
import '../game/skins.dart';
import '../render/palette.dart';
import '../services/audio.dart';
import '../services/services.dart';
import '../ui/widgets.dart';
import 'play_controller.dart';

/// Shown over the play screen when the knot is cleared: the reward first,
/// then progress toward the next unlock, then what to do next.
class ClearOverlay extends StatefulWidget {
  const ClearOverlay({
    super.key,
    required this.controller,
    required this.onNext,
    required this.onReplay,
    required this.onLeave,
  });

  final PlayController controller;
  final VoidCallback onNext;
  final VoidCallback onReplay;
  final VoidCallback onLeave;

  @override
  State<ClearOverlay> createState() => _ClearOverlayState();
}

class _ClearOverlayState extends State<ClearOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in;
  final List<Timer> _timers = [];
  int _starsShown = 0;
  bool _doubled = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    final outcome = widget.controller.outcome!;
    for (var i = 0; i < outcome.stars; i++) {
      _timers.add(
        Timer(Duration(milliseconds: 520 + i * 260), () {
          if (!mounted) return;
          setState(() => _starsShown = i + 1);
          services.audio.play(Sfx.star, pitch: kPentatonic[i * 2]);
        }),
      );
    }
    if (outcome.unlockedSkins.isNotEmpty) {
      _timers.add(
        Timer(const Duration(milliseconds: 1500), () {
          if (mounted) services.audio.play(Sfx.unlock);
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final services = AppScope.of(context);
    final c = widget.controller;
    final outcome = c.outcome!;
    final profile = services.profile;
    final daily = c.mode == PlayMode.daily;
    final last = !daily && c.level.id >= services.levels.count;
    final title = switch (outcome.stars) {
      3 => 'Clean release',
      2 => 'Nicely done',
      _ => 'Knot cleared',
    };
    final coins = outcome.coins * (_doubled ? 2 : 1);

    return Positioned.fill(
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _in, curve: Curves.easeOut),
        child: ColoredBox(
          color: p.bg.withValues(alpha: 0.9),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.title.toUpperCase(), style: AppText.label(p)),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppText.display(p, 28),
                    ),
                    const SizedBox(height: 14),
                    Semantics(
                      label: '${outcome.stars} of 3 stars',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: AnimatedScale(
                                scale: i < _starsShown ? 1 : 0.7,
                                duration: const Duration(milliseconds: 320),
                                curve: Curves.easeOutBack,
                                child: Icon(
                                  i < _starsShown
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  size: 50,
                                  color: i < _starsShown ? p.brass : p.line,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Panel(
                      child: Column(
                        children: [
                          _row(
                            p,
                            'Moves',
                            '${c.knot.moves} · par ${c.level.par}',
                          ),
                          if (coins > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Reward',
                                    style: AppText.body(p, 15, color: p.dim),
                                  ),
                                ),
                                Coins(coins, size: 16),
                              ],
                            ),
                          ],
                          if (daily && outcome.firstClear) ...[
                            const SizedBox(height: 8),
                            _row(
                              p,
                              'Streak',
                              outcome.streak == 1
                                  ? '1 day'
                                  : '${outcome.streak} days',
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (daily &&
                        (outcome.saverUsed || outcome.saverEarned)) ...[
                      const SizedBox(height: 10),
                      Text(
                        outcome.saverUsed
                            ? 'A streak saver covered the day you missed.'
                            : 'You earned a streak saver. It forgives one missed day.',
                        textAlign: TextAlign.center,
                        style: AppText.body(p, 13.5, color: p.dim),
                      ),
                    ],
                    ..._collection(
                      p,
                      services,
                      outcome.ringEarned,
                      outcome.unlockedSkins,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: BrassButton(
                        label: daily || last ? 'Done' : 'Next level',
                        onTap: daily || last ? widget.onLeave : widget.onNext,
                      ),
                    ),
                    if (outcome.coins > 0 &&
                        !_doubled &&
                        services.ads.rewardedReady) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: GhostButton(
                          label: 'Double coins',
                          detail: 'watch ad',
                          onTap: () async {
                            services.analytics.log('ad_offered', {
                              'placement': 'double',
                            });
                            if (await services.ads.showRewarded('double') &&
                                mounted) {
                              services.analytics.log('ad_watched', {
                                'placement': 'double',
                              });
                              profile.addCoins(outcome.coins);
                              services.audio.play(Sfx.coin);
                              setState(() => _doubled = true);
                            }
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: widget.onReplay,
                      child: Text(
                        'Play again',
                        style: AppText.body(p, 14, color: p.dim),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(AppPalette p, String label, String value) => Row(
    children: [
      Expanded(
        child: Text(label, style: AppText.body(p, 15, color: p.dim)),
      ),
      Text(value, style: AppText.body(p, 15, weight: FontWeight.w700)),
    ],
  );

  List<Widget> _collection(
    AppPalette p,
    Services services,
    bool ringEarned,
    List<String> unlocked,
  ) {
    final profile = services.profile;
    if (unlocked.isNotEmpty) {
      final skin = skinById(unlocked.first);
      return [
        const SizedBox(height: 12),
        Panel(
          highlight: true,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New skin: ${skin.name}',
                      style: AppText.body(p, 16, weight: FontWeight.w700),
                    ),
                    Text(
                      'Find it in the Workshop.',
                      style: AppText.body(p, 13.5, color: p.dim),
                    ),
                  ],
                ),
              ),
              if (profile.skin != skin.id)
                Pill(
                  onTap: () => setState(() => profile.selectSkin(skin.id)),
                  child: const Text('Wear it'),
                ),
            ],
          ),
        ),
      ];
    }
    final collecting = profile.collecting;
    if (collecting == null || !ringEarned) return const [];
    final left = Economy.ringsPerSet - profile.rings;
    return [
      const SizedBox(height: 12),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${collecting.name} set',
                    style: AppText.body(p, 15, weight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${profile.rings} of ${Economy.ringsPerSet}',
                  style: AppText.body(p, 14, color: p.dim),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ProgressBar(value: profile.rings / Economy.ringsPerSet),
            const SizedBox(height: 8),
            Text(
              left == 1
                  ? 'One more ring unlocks the ${collecting.name} skin.'
                  : '$left more rings unlock the ${collecting.name} skin.',
              style: AppText.body(p, 13.5, color: p.dim),
            ),
          ],
        ),
      ),
    ];
  }
}
