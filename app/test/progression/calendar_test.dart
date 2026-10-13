import 'package:tosk/progression/calendar.dart';
import 'package:tosk/progression/prng.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalDate', () {
    test('arithmetic across month, year and leap day', () {
      expect(const LocalDate(2026, 1, 31).addDays(1), const LocalDate(2026, 2, 1));
      expect(const LocalDate(2024, 2, 28).addDays(1), const LocalDate(2024, 2, 29));
      expect(const LocalDate(2026, 12, 31).addDays(1), const LocalDate(2027, 1, 1));
      expect(const LocalDate(2026, 3, 1).addDays(-1), const LocalDate(2026, 2, 28));
      expect(const LocalDate(2026, 1, 1).daysUntil(const LocalDate(2027, 1, 1)), 365);
      expect(LocalDate.parse('2026-10-13'), const LocalDate(2026, 10, 13));
      expect(const LocalDate(2026, 10, 3).toString(), '2026-10-03');
    });

    test('weekday and start of week', () {
      expect(const LocalDate(2026, 10, 13).weekday, DateTime.tuesday);
      expect(const LocalDate(2026, 10, 13).startOfWeek, const LocalDate(2026, 10, 12));
      expect(const LocalDate(2026, 10, 18).startOfWeek, const LocalDate(2026, 10, 12)); // Sunday
      expect(const LocalDate(2026, 10, 19).startOfWeek, const LocalDate(2026, 10, 19)); // Monday
    });

    test('ISO weeks at year boundaries', () {
      expect(const LocalDate(2026, 1, 1).isoWeek, 1); // Thursday
      expect(const LocalDate(2026, 1, 1).isoWeekYear, 2026);
      expect(const LocalDate(2025, 12, 29).isoWeek, 1); // Monday of 2026-W01
      expect(const LocalDate(2025, 12, 29).isoWeekYear, 2026);
      expect(const LocalDate(2027, 1, 1).isoWeek, 53); // Friday in 2026-W53
      expect(const LocalDate(2027, 1, 1).isoWeekYear, 2026);
      expect(const LocalDate(2026, 10, 13).isoWeek, 42);
    });
  });

  group('Period', () {
    test('week ids and bounds', () {
      final w = Period.weekOf(const LocalDate(2026, 10, 15));
      expect(w.id, 'W2026-42');
      expect(w.start, const LocalDate(2026, 10, 12));
      expect(w.end, const LocalDate(2026, 10, 19));
      expect(w.contains(const LocalDate(2026, 10, 18)), isTrue);
      expect(w.contains(const LocalDate(2026, 10, 19)), isFalse);
      expect(w.next.id, 'W2026-43');
      expect(w.previous.id, 'W2026-41');
      expect(Period.weekOf(const LocalDate(2027, 1, 2)).id, 'W2026-53');
    });

    test('month ids and bounds', () {
      final m = Period.monthOf(const LocalDate(2026, 12, 15));
      expect(m.id, 'M2026-12');
      expect(m.lengthInDays, 31);
      expect(m.next.id, 'M2027-01');
      expect(Period.monthOf(const LocalDate(2024, 2, 10)).lengthInDays, 29);
    });
  });

  group('LocalCalendar', () {
    test('fixed offsets move the date across midnight', () {
      final i = DateTime.utc(2026, 6, 10, 23, 30);
      expect(LocalCalendar.utc.dateOf(i), const LocalDate(2026, 6, 10));
      expect(LocalCalendar.fixed(const Duration(hours: 2)).dateOf(i), const LocalDate(2026, 6, 11));
      expect(LocalCalendar.fixed(const Duration(hours: -4)).dateOf(i), const LocalDate(2026, 6, 10));
      expect(LocalCalendar.fixed(const Duration(hours: -4)).dateOf(DateTime.utc(2026, 6, 10, 3, 59)),
          const LocalDate(2026, 6, 9));
    });

    test('non-UTC DateTime inputs are converted to UTC first', () {
      final local = DateTime.utc(2026, 6, 10, 23, 30).toLocal();
      expect(LocalCalendar.utc.dateOf(local), const LocalDate(2026, 6, 10));
    });

    test('system calendar agrees with DateTime.toLocal', () {
      final cal = LocalCalendar.system();
      final i = DateTime.utc(2026, 3, 29, 12);
      final l = i.toLocal();
      expect(cal.dateOf(i), LocalDate(l.year, l.month, l.day));
    });
  });

  group('prng', () {
    test('fnv1a32 matches reference vectors', () {
      expect(fnv1a32(''), 0x811C9DC5);
      expect(fnv1a32('a'), 0xE40C292C);
      expect(fnv1a32('foobar'), 0xBF9CF968);
    });

    test('xorshift is deterministic and in range', () {
      final a = XorShift32.fromString('x'), b = XorShift32.fromString('x');
      for (var i = 0; i < 100; i++) {
        final v = a.nextInt(7);
        expect(v, b.nextInt(7));
        expect(v, inInclusiveRange(0, 6));
      }
      expect(XorShift32(0).nextUint32(), isNot(0));
      final s = XorShift32(42).shuffled([1, 2, 3, 4, 5]);
      expect(s..sort(), [1, 2, 3, 4, 5]);
    });
  });
}
