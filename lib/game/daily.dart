/// Calendar helpers for the Daily Knot and streaks. Dates are the player's
/// local calendar days.
library;

/// Daily Knot #1 is this date.
final DateTime dailyEpoch = DateTime.utc(2026, 11, 1);

DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// `2026-11-09` style key for a local date.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final p = key.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Whole days from [a] to [b], ignoring the time of day.
int daysBetween(DateTime a, DateTime b) =>
    _dateOnly(b).difference(_dateOnly(a)).inDays;

/// The Daily Knot number for [now], starting at 1.
int dailyNumber(DateTime now) {
  final n = daysBetween(dailyEpoch, now) + 1;
  return n < 1 ? 1 : n;
}

/// Weeks are counted from this Monday. Weekly runs change every Monday.
final DateTime weeklyEpoch = DateTime.utc(2026, 10, 26);

/// Which weekly run [now] falls in, starting at 0.
int weekIndex(DateTime now) {
  final n = daysBetween(weeklyEpoch, weekStart(now)) ~/ 7;
  return n < 0 ? 0 : n;
}

/// Monday of the week containing [now].
DateTime weekStart(DateTime now) {
  final d = _dateOnly(now);
  return d.subtract(Duration(days: d.weekday - 1));
}
