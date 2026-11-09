import 'package:flutter/material.dart';

import '../render/palette.dart';
import '../services/services.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final services = AppScope.of(context);
    final profile = services.profile;
    return ListenableBuilder(
      listenable: Listenable.merge([profile, services.store]),
      builder: (context, _) {
        final s = profile.settings;
        return Narrow(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              Text(
                'Settings',
                style: AppText.display(p, 22, weight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              Panel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    _Toggle(
                      'Music',
                      s.music,
                      (v) => profile.updateSettings((s) => s.music = v),
                    ),
                    _Toggle(
                      'Sound effects',
                      s.sound,
                      (v) => profile.updateSettings((s) => s.sound = v),
                    ),
                    _Toggle(
                      'Vibration',
                      s.vibration,
                      (v) => profile.updateSettings((s) => s.vibration = v),
                      last: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Panel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    _Toggle(
                      'Light theme',
                      s.lightTheme,
                      (v) => profile.updateSettings((s) => s.lightTheme = v),
                    ),
                    _Toggle(
                      'Colour-blind marks',
                      s.colorMarks,
                      (v) => profile.updateSettings((s) => s.colorMarks = v),
                      detail: 'Adds a shape to every ring and peg slot.',
                    ),
                    _Toggle(
                      'Left-handed layout',
                      s.leftHanded,
                      (v) => profile.updateSettings((s) => s.leftHanded = v),
                    ),
                    _Toggle(
                      'Reduce motion',
                      s.reduceMotion,
                      (v) => profile.updateSettings((s) => s.reduceMotion = v),
                      detail: 'Stops the camera sway and sparkles.',
                      last: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (services.store.available) ...[
                GhostButton(
                  label: 'Restore purchases',
                  onTap: () async {
                    await services.store.restore();
                    if (context.mounted) {
                      toast(context, 'Checking the store for your purchases.');
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
              GhostButton(
                label: 'Reset progress',
                detail: 'Clears levels, coins and streak. Purchases are kept.',
                onTap: () => showCardDialog<void>(
                  context,
                  builder: (dialog) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Reset all progress?',
                          style: AppText.display(
                            p,
                            20,
                            weight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your levels, stars, coins, skins and streak will be cleared. This cannot be undone.',
                          textAlign: TextAlign.center,
                          style: AppText.body(p, 14.5, color: p.dim),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: GhostButton(
                            label: 'Reset progress',
                            onTap: () async {
                              final nav = Navigator.of(dialog);
                              await profile.resetProgress();
                              nav.pop();
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: BrassButton(
                            compact: true,
                            label: 'Keep my progress',
                            onTap: () => Navigator.of(dialog).pop(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Plays fully offline · Version 1.0.0',
                textAlign: TextAlign.center,
                style: AppText.body(p, 13, color: p.dim),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Loopsmith',
                    applicationVersion: '1.0.0',
                  ),
                  child: Text(
                    'Licences',
                    style: AppText.body(p, 13, color: p.dim),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(
    this.label,
    this.value,
    this.onChanged, {
    this.detail,
    this.last = false,
  });
  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: p.line)),
      ),
      child: MergeSemantics(
        child: InkWell(
          onTap: () {
            AppScope.of(context).tap();
            onChanged(!value);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(label, style: AppText.body(p, 16)),
                        if (detail != null)
                          Text(
                            detail!,
                            style: AppText.body(p, 13, color: p.dim),
                          ),
                      ],
                    ),
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: (v) {
                    AppScope.of(context).tap();
                    onChanged(v);
                  },
                  activeThumbColor: p.brassInk,
                  activeTrackColor: p.brass,
                  inactiveThumbColor: p.dim,
                  inactiveTrackColor: p.line,
                  trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
