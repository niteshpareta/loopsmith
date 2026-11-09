import 'package:flutter/foundation.dart';

/// Where gameplay events go. Wire this to Firebase Analytics, or your
/// publisher's SDK, by adding another implementation.
abstract class Analytics {
  void log(String event, [Map<String, Object?> params = const {}]);
}

/// Prints events in debug builds and does nothing in release.
class DebugAnalytics implements Analytics {
  @override
  void log(String event, [Map<String, Object?> params = const {}]) {
    if (kDebugMode) debugPrint('[analytics] $event $params');
  }
}

/// Keeps events in memory so tests can check them.
class RecordingAnalytics implements Analytics {
  final List<String> events = [];

  @override
  void log(String event, [Map<String, Object?> params = const {}]) =>
      events.add(event);
}
