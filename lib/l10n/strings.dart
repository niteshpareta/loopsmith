import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'strings_de.dart';
import 'strings_en.dart';
import 'strings_es.dart';
import 'strings_fr.dart';
import 'strings_pt.dart';

/// The game's text in the player's language.
///
/// ```dart
/// final s = S.of(context);
/// Text(s('home.play', {'n': 12}));       // "Play level 12"
/// Text(s.count('count.rings', 3));        // "3 rings"
/// ```
class S {
  S(this.code) : _text = tables[code] ?? stringsEn;

  /// Language code, such as `en` or `pt`.
  final String code;
  final Map<String, String> _text;

  static const Map<String, Map<String, String>> tables = {
    'en': stringsEn,
    'es': stringsEs,
    'pt': stringsPt,
    'fr': stringsFr,
    'de': stringsDe,
  };

  /// Each language's own name, for the language picker.
  static const Map<String, String> names = {
    'en': 'English',
    'es': 'Español',
    'pt': 'Português',
    'fr': 'Français',
    'de': 'Deutsch',
  };

  static const List<Locale> locales = [
    Locale('en'),
    Locale('es'),
    Locale('pt'),
    Locale('fr'),
    Locale('de'),
  ];

  static const LocalizationsDelegate<S> delegate = _Delegate();

  static final S english = S('en');

  /// The text for the nearest [Localizations], or English outside one.
  static S of(BuildContext context) =>
      Localizations.of<S>(context, S) ?? english;

  /// The text for [key], with `{name}` placeholders filled from [args].
  String call(String key, [Map<String, Object?> args = const {}]) {
    var text = _text[key] ?? stringsEn[key];
    if (text == null) {
      assert(false, 'Missing text for "$key"');
      return key;
    }
    args.forEach((name, value) {
      text = text!.replaceAll('{$name}', '$value');
    });
    return text!;
  }

  /// Picks the `_one` or `_other` form of [key] for [n].
  String count(String key, int n, [Map<String, Object?> args = const {}]) =>
      call(n == 1 ? '${key}_one' : '${key}_other', {'n': n, ...args});
}

class _Delegate extends LocalizationsDelegate<S> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) => S.tables.containsKey(locale.languageCode);

  @override
  Future<S> load(Locale locale) => SynchronousFuture<S>(S(locale.languageCode));

  @override
  bool shouldReload(_Delegate old) => false;
}
