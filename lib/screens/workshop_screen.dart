import 'package:flutter/material.dart';

import '../game/economy.dart';
import '../game/skins.dart';
import '../l10n/strings.dart';
import '../render/palette.dart';
import '../render/ring_paint.dart';
import '../services/audio.dart';
import '../services/services.dart';
import '../services/store.dart';
import '../ui/widgets.dart';

/// Skins earned by playing, streaks or coins, and two straightforward
/// purchases.
class WorkshopScreen extends StatelessWidget {
  const WorkshopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.profile, services.store]),
      builder: (context, _) {
        final profile = services.profile;
        final store = services.store;
        final error = switch (store.lastError) {
          null => null,
          StoreError.unreachable => s('store.unreachable'),
          StoreError.failed => s('store.failed'),
          StoreError.notStarted => s('store.not_started'),
          StoreError.notRestored => s('store.not_restored'),
        };
        return Narrow(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s('workshop.title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.display(p, 22, weight: FontWeight.w500),
                    ),
                  ),
                  Pill(
                    label: s.count('count.coins', profile.coins),
                    child: Coins(profile.coins),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(s('workshop.skins'), style: AppText.label(p)),
              const SizedBox(height: 10),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                // A fixed height keeps the tiles from clipping on narrow phones.
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 118,
                ),
                children: [for (final skin in kSkins) _SkinTile(skin: skin)],
              ),
              const SizedBox(height: 22),
              Text(s('workshop.boosters'), style: AppText.label(p)),
              const SizedBox(height: 10),
              Panel(
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, color: p.brass),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s('workshop.hints', {'n': Economy.hintPackSize}),
                            style: AppText.body(p, 16, weight: FontWeight.w700),
                          ),
                          Text(
                            s('workshop.have', {'n': profile.hints}),
                            style: AppText.body(p, 13.5, color: p.dim),
                          ),
                        ],
                      ),
                    ),
                    Pill(
                      label: s('workshop.buy_for', {
                        'price': s.count('count.coins', Economy.hintPackPrice),
                      }),
                      onTap: () {
                        if (profile.spendCoins(Economy.hintPackPrice)) {
                          profile.addHints(Economy.hintPackSize);
                          services.audio.play(Sfx.coin);
                        } else {
                          toast(
                            context,
                            s('workshop.need_more', {
                              'n': Economy.hintPackPrice - profile.coins,
                            }),
                          );
                        }
                      },
                      child: Coins(Economy.hintPackPrice),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(s('workshop.purchases'), style: AppText.label(p)),
              const SizedBox(height: 10),
              _Purchase(
                title: s('buy.remove_ads'),
                detail: s('buy.remove_ads_detail'),
                owned: profile.adsRemoved,
                price: store.price(Economy.removeAdsId),
                onBuy: () => store.buy(Economy.removeAdsId),
              ),
              const SizedBox(height: 10),
              _Purchase(
                title: s('buy.starter'),
                detail: s('buy.starter_detail', {
                  'hints': Economy.starterKitHints,
                  'slots': Economy.starterKitSlots,
                }),
                owned: profile.starterKit,
                price: store.price(Economy.starterKitId),
                onBuy: () => store.buy(Economy.starterKitId),
              ),
              if (!store.available) ...[
                const SizedBox(height: 10),
                Text(
                  s('buy.unavailable'),
                  style: AppText.body(p, 13.5, color: p.dim),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error, style: AppText.body(p, 13.5, color: p.danger)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SkinTile extends StatelessWidget {
  const _SkinTile({required this.skin});
  final SkinDef skin;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    final services = AppScope.of(context);
    final profile = services.profile;
    final owned = profile.ownedSkins.contains(skin.id);
    final selected = profile.skin == skin.id;
    final colors = RingSkin.of(skin.id);

    final status = owned
        ? (selected ? s('skin.wearing') : s('common.owned'))
        : switch (skin.unlock) {
            SkinUnlock.owned => s('common.owned'),
            SkinUnlock.collect => s('skin.rings', {
              'n': profile.rings,
              'total': Economy.ringsPerSet,
            }),
            SkinUnlock.level => s('skin.level', {'n': skin.amount}),
            SkinUnlock.coins => s.count('count.coins', skin.amount),
            SkinUnlock.streak => s.count('count.streak', skin.amount),
          };

    void onTap() {
      if (owned) {
        profile.selectSkin(skin.id);
        return;
      }
      switch (skin.unlock) {
        case SkinUnlock.coins:
          if (profile.coins < skin.amount) {
            toast(
              context,
              s('skin.need', {
                'n': skin.amount - profile.coins,
                'name': skin.name,
              }),
            );
          } else {
            showCardDialog<void>(
              context,
              builder: (dialog) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s('skin.buy_question', {'name': skin.name}),
                      textAlign: TextAlign.center,
                      style: AppText.display(p, 20, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s('skin.cost', {'n': skin.amount, 'have': profile.coins}),
                      textAlign: TextAlign.center,
                      style: AppText.body(p, 14.5, color: p.dim),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: BrassButton(
                        compact: true,
                        label: s('skin.buy', {'n': skin.amount}),
                        onTap: () {
                          if (profile.buySkin(skin)) {
                            services.audio.play(Sfx.unlock);
                          }
                          Navigator.of(dialog).pop();
                        },
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialog).pop(),
                      child: Text(
                        s('skin.keep'),
                        style: AppText.body(p, 14, color: p.dim),
                      ),
                    ),
                  ],
                );
              },
            );
          }
        case SkinUnlock.collect:
          toast(context, s('skin.how_collect'));
        case SkinUnlock.level:
          toast(
            context,
            s('skin.how_level', {'n': skin.amount, 'name': skin.name}),
          );
        case SkinUnlock.streak:
          toast(
            context,
            s('skin.how_streak', {'n': skin.amount, 'name': skin.name}),
          );
        case SkinUnlock.owned:
          break;
      }
    }

    return Pressable(
      onTap: onTap,
      label: s('skin.label', {'name': skin.name, 'status': status}),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? p.brass : p.line,
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        // Scale the tile's contents down rather than clip them when the
        // text is long or the player uses very large text.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: owned ? 1 : 0.55,
                child: SizedBox(
                  width: 62,
                  height: 38,
                  child: Stack(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Positioned(
                          left: i * 13.0,
                          top: i == 1 ? 0 : 4,
                          child: RingChip(
                            size: 34,
                            state: ChipState.filled,
                            color: colors.color(i == 0 ? 1 : (i == 1 ? 0 : 3)),
                            gloss: skin.gloss,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                skin.name,
                style: AppText.body(p, 14.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 1),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!owned) Icon(Icons.lock_rounded, size: 11, color: p.dim),
                  if (!owned) const SizedBox(width: 3),
                  Text(
                    status,
                    maxLines: 1,
                    style: AppText.body(
                      p,
                      11.5,
                      color: selected ? p.brass : p.dim,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Purchase extends StatelessWidget {
  const _Purchase({
    required this.title,
    required this.detail,
    required this.owned,
    required this.price,
    required this.onBuy,
  });
  final String title;
  final String detail;
  final bool owned;
  final String? price;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.body(p, 16, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(detail, style: AppText.body(p, 13.5, color: p.dim)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (owned)
            Text(
              s('common.owned'),
              style: AppText.body(
                p,
                14,
                weight: FontWeight.w700,
                color: p.good,
              ),
            )
          else
            Pill(
              label: price == null
                  ? s('workshop.unavailable')
                  : s('workshop.buy_for', {'price': price}),
              onTap: price == null ? null : onBuy,
              child: Text(price ?? '—'),
            ),
        ],
      ),
    );
  }
}
