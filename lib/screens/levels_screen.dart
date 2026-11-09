import 'package:flutter/material.dart';

import '../game/economy.dart';
import '../l10n/strings.dart';
import '../render/palette.dart';
import '../services/services.dart';
import '../ui/widgets.dart';
import 'play_screen.dart';

/// Every campaign level, for replaying to earn missing stars.
class LevelsScreen extends StatelessWidget {
  const LevelsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const LevelsScreen());

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    final services = AppScope.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Bench(
        child: SafeArea(
          child: Narrow(
            child: ListenableBuilder(
              listenable: services.profile,
              builder: (context, _) {
                final profile = services.profile;
                return Column(
                  children: [
                    TopBar(
                      title: s('levels.title'),
                      onBack: () => Navigator.of(context).pop(),
                      trailing: Pill(
                        label: s.count('count.stars', profile.totalStars),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, size: 17, color: p.brass),
                            const SizedBox(width: 4),
                            Text('${profile.totalStars}'),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 76,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              mainAxisExtent: 76,
                            ),
                        itemCount: services.levels.count,
                        itemBuilder: (context, index) {
                          final id = index + 1;
                          final open = id <= profile.unlocked;
                          final stars = profile.stars[id] ?? 0;
                          final current = id == profile.unlocked && stars == 0;
                          return Pressable(
                            onTap: open
                                ? () => Navigator.of(context).push(
                                    PlayScreen.route(services.levels.level(id)),
                                  )
                                : null,
                            label: open
                                ? s('levels.open', {'n': id, 'stars': stars})
                                : s('levels.locked', {'n': id}),
                            child: Container(
                              decoration: BoxDecoration(
                                color: p.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: current ? p.brass : p.line,
                                  width: current ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$id',
                                      style: AppText.display(
                                        p,
                                        17,
                                        weight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (!open)
                                      Icon(
                                        Icons.lock_rounded,
                                        size: 14,
                                        color: p.dim,
                                      )
                                    else
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          for (var i = 0; i < 3; i++)
                                            Icon(
                                              i < stars
                                                  ? Icons.star_rounded
                                                  : Icons.star_outline_rounded,
                                              size: 13,
                                              color: i < stars
                                                  ? p.brass
                                                  : p.line,
                                            ),
                                        ],
                                      ),
                                    if (Economy.isKnotLevel(id) &&
                                        open &&
                                        stars == 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          s('levels.knot'),
                                          style: AppText.body(
                                            p,
                                            10,
                                            color: p.brass,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
