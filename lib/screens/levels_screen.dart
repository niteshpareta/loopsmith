import 'package:flutter/material.dart';

import '../game/economy.dart';
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
                      title: 'Levels',
                      onBack: () => Navigator.of(context).pop(),
                      trailing: Pill(
                        label: '${profile.totalStars} stars',
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
                              childAspectRatio: 0.92,
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
                                ? 'Level $id, $stars of 3 stars'
                                : 'Level $id, locked',
                            child: Container(
                              decoration: BoxDecoration(
                                color: p.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: current ? p.brass : p.line,
                                  width: current ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
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
                                        for (var s = 0; s < 3; s++)
                                          Icon(
                                            s < stars
                                                ? Icons.star_rounded
                                                : Icons.star_outline_rounded,
                                            size: 13,
                                            color: s < stars ? p.brass : p.line,
                                          ),
                                      ],
                                    ),
                                  if (Economy.isKnotLevel(id) &&
                                      open &&
                                      stars == 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'knot',
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
