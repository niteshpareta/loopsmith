import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../render/palette.dart';
import '../services/reminders.dart';
import '../services/services.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = S.of(context);
    final services = AppScope.of(context);
    final profile = services.profile;
    return ListenableBuilder(
      listenable: Listenable.merge([profile, services.store]),
      builder: (context, _) {
        final set = profile.settings;
        final language = set.language == 'system'
            ? s('settings.language_system')
            : (S.names[set.language] ?? set.language);
        return Narrow(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              Text(
                s('settings.title'),
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
                      s('settings.music'),
                      set.music,
                      (v) => profile.updateSettings((x) => x.music = v),
                    ),
                    _Toggle(
                      s('settings.sound'),
                      set.sound,
                      (v) => profile.updateSettings((x) => x.sound = v),
                    ),
                    _Toggle(
                      s('settings.vibration'),
                      set.vibration,
                      (v) => profile.updateSettings((x) => x.vibration = v),
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
                      s('settings.light'),
                      set.lightTheme,
                      (v) => profile.updateSettings((x) => x.lightTheme = v),
                    ),
                    _Toggle(
                      s('settings.marks'),
                      set.colorMarks,
                      (v) => profile.updateSettings((x) => x.colorMarks = v),
                      detail: s('settings.marks_detail'),
                    ),
                    _Toggle(
                      s('settings.left'),
                      set.leftHanded,
                      (v) => profile.updateSettings((x) => x.leftHanded = v),
                    ),
                    _Toggle(
                      s('settings.calm'),
                      set.reduceMotion,
                      (v) => profile.updateSettings((x) => x.reduceMotion = v),
                      detail: s('settings.calm_detail'),
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
                      s('settings.reminder'),
                      set.reminder,
                      (v) => _setReminder(context, v),
                      detail: s('settings.reminder_detail'),
                    ),
                    _Choice(
                      label: s('settings.language'),
                      value: language,
                      onTap: () => _pickLanguage(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (services.store.available) ...[
                GhostButton(
                  label: s('settings.restore'),
                  onTap: () async {
                    await services.store.restore();
                    if (context.mounted) {
                      toast(context, s('settings.restore_toast'));
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
              GhostButton(
                label: s('settings.reset'),
                detail: s('settings.reset_detail'),
                onTap: () => showCardDialog<void>(
                  context,
                  builder: (dialog) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s('settings.reset_question'),
                          textAlign: TextAlign.center,
                          style: AppText.display(
                            p,
                            20,
                            weight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s('settings.reset_body'),
                          textAlign: TextAlign.center,
                          style: AppText.body(p, 14.5, color: p.dim),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: GhostButton(
                            label: s('settings.reset'),
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
                            label: s('settings.keep'),
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
                s('settings.version', {'v': '1.1.0'}),
                textAlign: TextAlign.center,
                style: AppText.body(p, 13, color: p.dim),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Loopsmith',
                    applicationVersion: '1.1.0',
                  ),
                  child: Text(
                    s('settings.licences'),
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

  /// Turning reminders on asks the phone for permission. If the answer is
  /// no, the switch stays off and the player is told why.
  Future<void> _setReminder(BuildContext context, bool on) async {
    final services = AppScope.of(context);
    final s = S.of(context);
    final profile = services.profile;
    if (!on) {
      profile.updateSettings((x) => x.reminder = false);
      await services.reminders.disable();
      return;
    }
    final allowed = await services.reminders.enable(
      ReminderText(s('remind.title'), s('remind.body'), s('remind.channel')),
      playedToday: profile.dailyDoneToday,
    );
    if (allowed) {
      profile.updateSettings((x) => x.reminder = true);
    } else if (context.mounted) {
      toast(context, s('settings.reminder_denied'));
    }
  }

  void _pickLanguage(BuildContext context) {
    final services = AppScope.of(context);
    final p = AppPalette.of(context);
    final s = S.of(context);
    final current = services.profile.settings.language;
    showCardDialog<void>(
      context,
      builder: (dialog) {
        Widget option(String code, String name) {
          final selected = code == current;
          return Pressable(
            onTap: () {
              services.profile.updateSettings((x) => x.language = code);
              Navigator.of(dialog).pop();
            },
            label: name,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: AppText.body(
                        p,
                        16,
                        weight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selected) Icon(Icons.check_rounded, color: p.brass),
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s('settings.language'),
              textAlign: TextAlign.center,
              style: AppText.display(p, 20, weight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            option('system', s('settings.language_system')),
            for (final entry in S.names.entries) option(entry.key, entry.value),
          ],
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
                  trackOutlineColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row that opens a list of choices.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      label: '$label, $value',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Row(
          children: [
            Text(label, style: AppText.body(p, 16)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppText.body(p, 15, color: p.dim),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: p.dim),
          ],
        ),
      ),
    );
  }
}
