import 'dart:async';

import 'package:flutter/material.dart';

import '../game/economy.dart';
import '../game/skins.dart';
import '../l10n/strings.dart';
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
    required this.hasNext,
    required this.onNext,
    required this.onReplay,
    required this.onLeave,
  });

  final PlayController controller;

  /// There is another level (or weekly knot) to go straight on to.
  final bool hasNext;
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
    if (outcome.unlockedSkins.isNotEmpty || outcome.weeklyBonus) {
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
    final s = S.of(context);
    final services = AppScope.of(context);
    final c = widget.controller;
    final outcome = c.outcome!;
    final profile = services.profile;
    final title = switch (outcome.stars) {
      3 => s('clear.three'),
      2 => s('clear.two'),
      _ => s('clear.one'),
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
                    Text(
                      c.title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: AppText.label(p),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppText.display(p, 28),
                    ),
                    const SizedBox(height: 14),
                    Semantics(
                      label: s('clear.stars', {'n': outcome.stars}),
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
                            s('clear.moves'),
                            s('clear.moves_value', {
                              'moves': c.knot.moves,
                              'par': c.level.par,
                            }),
                          ),
                          if (coins > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s('clear.reward'),
                                    style: AppText.body(p, 15, color: p.dim),
                                  ),
                                ),
                                Coins(coins, size: 16),
                              ],
                            ),
                          ],
                          if (c.mode == PlayMode.daily &&
                              outcome.firstClear) ...[
                            const SizedBox(height: 8),
                            _row(
                              p,
                              s('clear.streak'),
                              s.count('count.days', outcome.streak),
                            ),
                          ],
                          if (c.mode == PlayMode.weekly) ...[
                            const SizedBox(height: 8),
                            _row(
                              p,
                              s('weekly.title'),
                              s('clear.of', {
                                'n': outcome.weeklyDone,
                                'total': 7,
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (outcome.saverUsed || outcome.saverEarned) ...[
                      const SizedBox(height: 10),
                      Text(
                        outcome.saverUsed
                            ? s('clear.saver_used')
                            : s('clear.saver_earned'),
                        textAlign: TextAlign.center,
                        style: AppText.body(p, 13.5, color: p.dim),
                      ),
                    ],
                    if (outcome.weeklyBonus) ...[
                      const SizedBox(height: 12),
                      Panel(
                        highlight: true,
                        child: Text(
                          s('clear.weekly_bonus', {
                            'coins': Economy.weeklyBonus,
                          }),
                          textAlign: TextAlign.center,
                          style: AppText.body(p, 15, weight: FontWeight.w700),
                        ),
                      ),
                    ],
                    ..._collection(
                      p,
                      s,
                      services,
                      outcome.ringEarned,
                      outcome.unlockedSkins,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: BrassButton(
                        label: !widget.hasNext
                            ? s('common.done')
                            : (c.mode == PlayMode.weekly
                                  ? s('clear.next_knot')
                                  : s('clear.next')),
                        onTap: widget.hasNext ? widget.onNext : widget.onLeave,
                      ),
                    ),
                    if (outcome.coins > 0 &&
                        !_doubled &&
                        services.ads.rewardedReady) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: GhostButton(
                          label: s('clear.double'),
                          detail: s('booster.watch'),
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
                        s('clear.again'),
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
    S s,
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
                      s('clear.new_skin', {'name': skin.name}),
                      style: AppText.body(p, 16, weight: FontWeight.w700),
                    ),
                    Text(
                      s('clear.find_it'),
                      style: AppText.body(p, 13.5, color: p.dim),
                    ),
                  ],
                ),
              ),
              if (profile.skin != skin.id)
                Pill(
                  onTap: () => setState(() => profile.selectSkin(skin.id)),
                  child: Text(s('clear.wear')),
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
                    s('clear.set', {'name': collecting.name}),
                    style: AppText.body(p, 15, weight: FontWeight.w700),
                  ),
                ),
                Text(
                  s('clear.of', {
                    'n': profile.rings,
                    'total': Economy.ringsPerSet,
                  }),
                  style: AppText.body(p, 14, color: p.dim),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ProgressBar(value: profile.rings / Economy.ringsPerSet),
            const SizedBox(height: 8),
            Text(
              left == 1
                  ? s('clear.one_more', {'name': collecting.name})
                  : s('clear.more', {'n': left, 'name': collecting.name}),
              style: AppText.body(p, 13.5, color: p.dim),
            ),
          ],
        ),
      ),
    ];
  }
}
