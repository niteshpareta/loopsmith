import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The words a reminder shows, in the player's language.
class ReminderText {
  const ReminderText(this.title, this.body, this.channel);
  final String title;
  final String body;
  final String channel;
}

/// An optional evening nudge to play the Daily Knot.
///
/// Reminders are off until the player turns them on in Settings, there is
/// never more than one a day, and they stop after three days away.
abstract class Reminders {
  /// Asks the phone for permission and schedules reminders. Returns false if
  /// the player (or the phone's settings) said no.
  Future<bool> enable(ReminderText text, {required bool playedToday});

  /// Re-plans the next reminders, for example after today's knot is cleared.
  Future<void> refresh(ReminderText text, {required bool playedToday});

  Future<void> disable();
}

/// No reminders: used on the web, on desktop, and in tests.
class NoReminders implements Reminders {
  bool enabled = false;

  @override
  Future<bool> enable(ReminderText text, {required bool playedToday}) async {
    enabled = true;
    return true;
  }

  @override
  Future<void> refresh(ReminderText text, {required bool playedToday}) async {}

  @override
  Future<void> disable() async => enabled = false;
}

/// The hour (24-hour clock, local time) a reminder is shown.
const int kReminderHour = 19;

/// When the next reminders should appear: one each evening for up to three
/// days, skipping this evening if today's knot is done or the hour has passed.
List<DateTime> reminderTimes(DateTime now, {required bool playedToday}) {
  var first = DateTime(now.year, now.month, now.day, kReminderHour);
  if (playedToday || !first.isAfter(now)) {
    first = DateTime(now.year, now.month, now.day + 1, kReminderHour);
  }
  return [
    for (var i = 0; i < 3; i++)
      DateTime(first.year, first.month, first.day + i, kReminderHour),
  ];
}

/// Reminders through package:flutter_local_notifications. Everything stays
/// on the phone; no server is involved.
class LocalReminders implements Reminders {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _ids = [7101, 7102, 7103];

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_ring'),
          // Permission is asked for when the player turns reminders on,
          // not when the app starts.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Reminders unavailable: $e');
    }
    return _ready;
  }

  Future<bool> _askPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<bool> enable(ReminderText text, {required bool playedToday}) async {
    if (!await _init()) return false;
    try {
      if (!await _askPermission()) return false;
      await refresh(text, playedToday: playedToday);
      return true;
    } catch (e) {
      debugPrint('Reminder could not be set: $e');
      return false;
    }
  }

  @override
  Future<void> refresh(ReminderText text, {required bool playedToday}) async {
    if (!await _init()) return;
    try {
      for (final id in _ids) {
        await _plugin.cancel(id: id);
      }
      final times = reminderTimes(DateTime.now(), playedToday: playedToday);
      for (var i = 0; i < times.length; i++) {
        final t = times[i];
        await _plugin.zonedSchedule(
          id: _ids[i],
          title: text.title,
          body: text.body,
          scheduledDate: tz.TZDateTime(
            tz.local,
            t.year,
            t.month,
            t.day,
            t.hour,
          ),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'daily_reminder',
              text.channel,
              importance: Importance.defaultImportance,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          // "About 7 pm" is fine, and needs no special alarm permission.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Reminder could not be set: $e');
    }
  }

  @override
  Future<void> disable() async {
    if (!await _init()) return;
    try {
      for (final id in _ids) {
        await _plugin.cancel(id: id);
      }
    } catch (e) {
      debugPrint('Reminder could not be cancelled: $e');
    }
  }
}

Reminders createReminders() {
  final mobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  return mobile ? LocalReminders() : NoReminders();
}
