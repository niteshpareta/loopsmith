import 'package:flutter/material.dart';

import '../render/palette.dart';
import '../services/services.dart';

/// The bench: a dark surface with a soft spotlight.
class Bench extends StatelessWidget {
  const Bench({
    super.key,
    required this.child,
    this.glowAt = const Alignment(0, -0.35),
  });
  final Widget child;
  final Alignment glowAt;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: glowAt,
          radius: 1.05,
          colors: [p.bgGlow, p.bg],
          stops: const [0, 0.8],
        ),
      ),
      child: child,
    );
  }
}

/// Keeps content readable on tablets by capping its width.
class Narrow extends StatelessWidget {
  const Narrow({super.key, required this.child, this.width = 520});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
}

/// Shrinks slightly while pressed and plays the tap sound.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.label,
    this.sound = true,
  });
  final Widget child;
  final VoidCallback? onTap;

  /// Read by screen readers.
  final String? label;
  final bool sound;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: enabled
            ? () {
                if (widget.sound) AppScope.of(context).tap();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: const Duration(milliseconds: 150),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The main action on every screen.
class BrassButton extends StatelessWidget {
  const BrassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.detail,
    this.compact = false,
  });
  final String label;
  final String? detail;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      label: detail == null ? label : '$label, $detail',
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 46 : 58),
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: compact ? 8 : 12,
        ),
        decoration: BoxDecoration(
          color: p.brass,
          borderRadius: BorderRadius.circular(compact ? 16 : 20),
          boxShadow: [
            BoxShadow(color: p.brassDeep, offset: const Offset(0, 4)),
          ],
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.body(
                p,
                compact ? 16 : 18,
                weight: FontWeight.w700,
                color: p.brassInk,
              ),
            ),
            if (detail != null)
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: AppText.body(
                  p,
                  12,
                  weight: FontWeight.w600,
                  color: p.brassInk.withValues(alpha: 0.72),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A quieter button for secondary actions.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onTap,
    this.detail,
  });
  final String label;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      label: detail == null ? label : '$label, $detail',
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.body(p, 15, weight: FontWeight.w700),
            ),
            if (detail != null)
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: AppText.body(p, 12, color: p.dim),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small rounded label, for counts and status.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.child, this.onTap, this.label});
  final Widget child;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final box = Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: p.line),
      ),
      child: DefaultTextStyle.merge(
        style: AppText.body(p, 14, weight: FontWeight.w700),
        child: child,
      ),
    );
    if (onTap == null) return Semantics(label: label, child: box);
    // Give small pills a comfortable touch target.
    return Pressable(
      onTap: onTap,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: box,
      ),
    );
  }
}

/// Coin count with the game's coin glyph.
class Coins extends StatelessWidget {
  const Coins(this.amount, {super.key, this.size = 14});
  final int amount;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: 0.785,
          child: Container(
            width: size * 0.62,
            height: size * 0.62,
            decoration: BoxDecoration(
              color: p.brass,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SizedBox(width: size * 0.45),
        Text(
          '$amount',
          style: AppText.body(
            p,
            size,
            weight: FontWeight.w700,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.highlight = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight ? p.brass : p.line,
          width: highlight ? 2 : 1,
        ),
      ),
      child: child,
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            Container(color: p.line),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(color: p.brass),
            ),
          ],
        ),
      ),
    );
  }
}

/// A screen title with an optional back button.
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, this.onBack, this.trailing});
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Pressable(
                onTap: onBack,
                label: 'Back',
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: p.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.line),
                  ),
                  child: Icon(Icons.arrow_back_rounded, color: p.ink, size: 22),
                ),
              ),
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.display(p, 20, weight: FontWeight.w500),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Shows a short message at the bottom of the screen.
void toast(BuildContext context, String message) {
  final p = AppPalette.of(context);
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppText.body(
            p,
            14,
            color: p.brassInk,
            weight: FontWeight.w600,
          ),
        ),
        backgroundColor: p.brass,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
}

/// A centred card over a dimmed screen. Returns what the card pops with.
Future<T?> showCardDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final p = AppPalette.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: p.shadow.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.line),
                ),
                child: builder(context),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.94,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}
