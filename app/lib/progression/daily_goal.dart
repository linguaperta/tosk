/// Daily XP goal and the reminder plan. Pure functions of the review log
/// (through the replay's XP per local day), the goal setting and "now".
///
/// **Model.** The goal is an amount of XP per local day (20, 50 or 100; 0 =
/// off), counted over every course like the header's "+N today". XP rather
/// than lessons: every mode earns it (lessons, the lab, non-stop, reviews),
/// it already weighs due and new words above re-practice, and it comes from
/// the log, so it syncs and replays like everything else.
library;

import 'package:meta/meta.dart';

import 'calendar.dart';

/// Today's progress toward the goal.
@immutable
class DailyGoalStatus {
  const DailyGoalStatus({required this.goalXp, required this.todayXp});

  /// 0 when there is no goal.
  final int goalXp;
  final int todayXp;

  bool get enabled => goalXp > 0;
  bool get met => enabled && todayXp >= goalXp;
  int get remaining => enabled ? (goalXp - todayXp).clamp(0, goalXp) : 0;

  /// 0..1.
  double get progress => enabled ? (todayXp / goalXp).clamp(0.0, 1.0) : 0;
}

/// The local dates on which [xpByDay] reached [goalXp] (none without a goal).
Set<LocalDate> goalMetDays(Map<LocalDate, int> xpByDay, int goalXp) => goalXp <= 0
    ? const {}
    : {
        for (final e in xpByDay.entries)
          if (e.value >= goalXp) e.key,
      };

/// One scheduled reminder.
@immutable
class ReminderSlot {
  const ReminderSlot(this.date, this.at);

  /// The local date it belongs to.
  final LocalDate date;

  /// When it fires (UTC instant).
  final DateTime at;

  @override
  bool operator ==(Object other) => other is ReminderSlot && other.date == date && other.at == at;

  @override
  int get hashCode => Object.hash(date, at);

  @override
  String toString() => 'ReminderSlot($date, $at)';
}

/// Turns a local date and wall-clock time into a UTC instant (the device's
/// zone rules by default, DST included).
typedef LocalWallClock = DateTime Function(LocalDate date, int hour, int minute);

DateTime systemWallClock(LocalDate d, int hour, int minute) => DateTime(d.year, d.month, d.day, hour, minute).toUtc();

/// Which reminders to schedule: one at [hour]:[minute] local time on each of
/// the next [days] days (today included), except
///
/// * none at all without a goal or with the reminder off;
/// * none whose time has passed ([now]);
/// * none today when today's goal is already met ([todayXp] >= [goalXp]).
///
/// Days after today are always scheduled: whether their goal will be met is
/// unknown, and the plan is recomputed (today's reminder dropped) whenever
/// the log changes, the app starts or the settings change. Re-planning at
/// least every [days] days keeps the chain going; the platform keeps the
/// scheduled reminders across reboots.
List<ReminderSlot> planReminders({
  required bool enabled,
  required int goalXp,
  required int todayXp,
  required LocalDate today,
  required DateTime now,
  required int hour,
  required int minute,
  int days = 7,
  LocalWallClock wallClock = systemWallClock,
}) {
  if (!enabled || goalXp <= 0) return const [];
  final out = <ReminderSlot>[];
  for (var k = 0; k < days; k++) {
    final date = today.addDays(k);
    if (k == 0 && todayXp >= goalXp) continue;
    final at = wallClock(date, hour, minute).toUtc();
    if (!at.isAfter(now.toUtc())) continue;
    out.add(ReminderSlot(date, at));
  }
  return out;
}
