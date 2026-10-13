/// Calendar dates in the user's local time, without a timezone database.
///
/// Review events are stored in UTC. Streaks, the heatmap and challenge periods
/// work on *local calendar dates*, so every computation takes a
/// [LocalCalendar] that maps a UTC instant to the user's UTC offset at that
/// instant. The default ([LocalCalendar.system]) uses the device's own zone
/// rules, which handle historical DST changes; tests pass explicit functions to
/// simulate DST and travel.
library;

import 'package:meta/meta.dart';

/// The user's UTC offset at a given UTC instant.
typedef UtcOffsetFn = Duration Function(DateTime utcInstant);

/// A date in the user's local calendar (no time, no zone).
@immutable
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  /// Takes the calendar fields of [d] as they are (no zone conversion).
  factory LocalDate.fromDateTime(DateTime d) => LocalDate(d.year, d.month, d.day);

  /// Days since 1970-01-01.
  factory LocalDate.fromEpochDay(int epochDay) {
    final u = DateTime.fromMillisecondsSinceEpoch(epochDay * Duration.millisecondsPerDay, isUtc: true);
    return LocalDate(u.year, u.month, u.day);
  }

  /// Parses `YYYY-MM-DD`.
  factory LocalDate.parse(String s) {
    final p = s.split('-');
    if (p.length != 3) throw FormatException('Not a date: $s');
    return LocalDate(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utcMidnight => DateTime.utc(year, month, day);

  /// Days since 1970-01-01 (normalizes out-of-range fields).
  int get epochDay => _utcMidnight.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  LocalDate addDays(int n) => LocalDate.fromEpochDay(epochDay + n);

  /// Whole days from this date to [other] (positive when [other] is later).
  int daysUntil(LocalDate other) => other.epochDay - epochDay;

  /// ISO weekday: 1 = Monday … 7 = Sunday.
  int get weekday => _utcMidnight.weekday;

  /// The Monday of this date's ISO week.
  LocalDate get startOfWeek => addDays(1 - weekday);

  LocalDate get startOfMonth => LocalDate(year, month, 1);

  /// First day of the next month.
  LocalDate get startOfNextMonth => month == 12 ? LocalDate(year + 1, 1, 1) : LocalDate(year, month + 1, 1);

  int get dayOfYear => LocalDate(year, 1, 1).daysUntil(this) + 1;

  /// ISO-8601 week-numbering year (the year of this week's Thursday).
  int get isoWeekYear => addDays(4 - weekday).year;

  /// ISO-8601 week number (1..53).
  int get isoWeek {
    final thursday = addDays(4 - weekday);
    return (thursday.dayOfYear - 1) ~/ 7 + 1;
  }

  bool isBefore(LocalDate o) => epochDay < o.epochDay;
  bool isAfter(LocalDate o) => epochDay > o.epochDay;

  @override
  int compareTo(LocalDate other) => epochDay.compareTo(other.epochDay);

  @override
  bool operator ==(Object other) =>
      other is LocalDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// Maps UTC instants to local calendar dates.
class LocalCalendar {
  /// [offsetAt] returns the user's UTC offset at a UTC instant.
  const LocalCalendar(this.offsetAt);

  /// A fixed offset (no DST), e.g. `Duration(hours: 2)`.
  LocalCalendar.fixed(Duration offset) : this((_) => offset);

  /// UTC itself.
  static final LocalCalendar utc = LocalCalendar.fixed(Duration.zero);

  /// The device's time zone rules (historical DST included), via [DateTime.toLocal].
  factory LocalCalendar.system() => LocalCalendar((u) => u.toLocal().timeZoneOffset);

  final UtcOffsetFn offsetAt;

  /// The local calendar date of [instant].
  LocalDate dateOf(DateTime instant) {
    final u = instant.toUtc();
    final local = u.add(offsetAt(u));
    return LocalDate(local.year, local.month, local.day);
  }
}

enum PeriodKind { week, month }

/// A challenge period: an ISO week (Monday–Sunday) or a calendar month, in local dates.
@immutable
class Period {
  const Period._(this.kind, this.start, this.end);

  /// The ISO week containing [date].
  factory Period.weekOf(LocalDate date) {
    final s = date.startOfWeek;
    return Period._(PeriodKind.week, s, s.addDays(7));
  }

  /// The calendar month containing [date].
  factory Period.monthOf(LocalDate date) =>
      Period._(PeriodKind.month, date.startOfMonth, date.startOfNextMonth);

  factory Period.of(PeriodKind kind, LocalDate date) =>
      kind == PeriodKind.week ? Period.weekOf(date) : Period.monthOf(date);

  final PeriodKind kind;

  /// First day (inclusive).
  final LocalDate start;

  /// First day after the period (exclusive).
  final LocalDate end;

  LocalDate get last => end.addDays(-1);

  int get lengthInDays => start.daysUntil(end);

  /// Stable id: `W2026-42` (ISO week) or `M2026-10`.
  String get id => kind == PeriodKind.week
      ? 'W${start.isoWeekYear}-${start.isoWeek.toString().padLeft(2, '0')}'
      : 'M${start.year}-${start.month.toString().padLeft(2, '0')}';

  bool contains(LocalDate d) => !d.isBefore(start) && d.isBefore(end);

  Period get next => Period.of(kind, end);
  Period get previous => Period.of(kind, start.addDays(-1));

  @override
  bool operator ==(Object other) => other is Period && other.kind == kind && other.start == start;

  @override
  int get hashCode => Object.hash(kind, start);

  @override
  String toString() => id;
}
