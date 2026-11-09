import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'l10n/strings.dart';
import 'render/palette.dart';
import 'services/services.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const Boot());
}

/// Shows a quiet splash while saves and levels load, then the game.
class Boot extends StatefulWidget {
  const Boot({super.key});

  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  late Future<Services> _start = Services.start();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Services>(
      future: _start,
      builder: (context, snap) {
        if (snap.hasData) return LoopsmithApp(services: snap.data!);
        const p = AppPalette.night;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(p),
          home: Scaffold(
            backgroundColor: p.bg,
            body: Bench(
              child: Center(
                child: snap.hasError
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              S.english('boot.failed_title'),
                              textAlign: TextAlign.center,
                              style: AppText.display(
                                p,
                                20,
                                weight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              S.english('boot.failed_body'),
                              textAlign: TextAlign.center,
                              style: AppText.body(p, 15, color: p.dim),
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () =>
                                  setState(() => _start = Services.start()),
                              child: Text(S.english('common.try_again')),
                            ),
                          ],
                        ),
                      )
                    : Text('Loopsmith', style: AppText.display(p, 34)),
              ),
            ),
          ),
        );
      },
    );
  }
}
