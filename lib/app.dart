import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'render/palette.dart';
import 'screens/shell.dart';
import 'services/services.dart';

/// The app once its services are ready.
class LoopsmithApp extends StatefulWidget {
  const LoopsmithApp({super.key, required this.services});
  final Services services;

  @override
  State<LoopsmithApp> createState() => _LoopsmithAppState();
}

class _LoopsmithAppState extends State<LoopsmithApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Silence the game when it leaves the screen, and save.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final audio = widget.services.audio;
    if (state == AppLifecycleState.resumed) {
      audio.resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      audio.suspend();
      widget.services.profile.save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.services.profile;
    return AppScope(
      services: widget.services,
      child: ListenableBuilder(
        listenable: profile,
        builder: (context, _) {
          final palette = profile.settings.lightTheme
              ? AppPalette.day
              : AppPalette.night;
          return MaterialApp(
            title: 'Loopsmith',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(palette),
            // The player's chosen language, or the phone's if they have not
            // chosen. Anything unsupported falls back to English.
            locale: profile.settings.language == 'system'
                ? null
                : Locale(profile.settings.language),
            supportedLocales: S.locales,
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // Large system text is respected up to a point the layouts can hold.
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.25,
              child: child!,
            ),
            home: const Shell(),
          );
        },
      ),
    );
  }
}
