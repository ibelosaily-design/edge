// The SAT plan: what today should look like given the exam date, and how the
// sleep schedule walks from the user's usual wake time to the test-day wake
// over the last two weeks.
//
// Everything here is arithmetic on dates and clock minutes the user entered.
// Nothing reads the band, and nothing is presented as a measurement. The
// evidence behind the rules (sleep after learning, morning test timing,
// caffeine half-life) is summarised in the research report; the numbers that
// are design choices — the 14-day ramp, the 15-minute latency — are named as
// constants so they are visible and easy to change.

import '../data/day_label.dart';
import '../state/prefs.dart';

/// The phase of preparation, by days left to the exam.
enum SatPhase {
  /// No exam date set.
  unset,

  /// More than [SatPlan.rampDays] away: build the habit, keep sleep regular.
  build,

  /// Inside the ramp: move wake time toward test-day wake a little each day.
  ramp,

  /// The day before: light review, no new words, early night.
  eve,

  /// Test day.
  testDay,

  /// The date has passed.
  done,
}

class SatPlan {
  static const dateKey = 'study.sat.date';
  static const usualWakeKey = 'study.sat.usual_wake_min';

  /// Days over which the wake time walks to test-day wake. A design choice:
  /// small daily steps are easier to keep than a jump the night before.
  static const rampDays = 14;

  /// Test-day wake: doors open 7:45 (College Board), so up by 6:15 leaves
  /// time to eat and travel. A default, not a rule.
  static const testWakeMin = 6 * 60 + 15;

  /// Teens need 8–10 h (AASM); the plan aims for the middle of that plus the
  /// time it usually takes to fall asleep.
  static const sleepTargetMin = 8 * 60 + 30;
  static const latencyMin = 15;

  /// Caffeine: a cut-off this long before bed (half-life ~5 h; 6 h before
  /// bed still cost over an hour of sleep in Drake 2013).
  static const caffeineGapMin = 8 * 60;

  final String? examDay; // YYYY-MM-DD, local
  final int usualWakeMin; // minutes after midnight

  const SatPlan({this.examDay, this.usualWakeMin = 8 * 60});

  static SatPlan load() {
    final d = Prefs.getString(dateKey, '');
    return SatPlan(
      examDay: _validDay(d) ? d : null,
      usualWakeMin: Prefs.getInt(usualWakeKey, 8 * 60).clamp(0, 24 * 60 - 1),
    );
  }

  static void saveExamDay(DateTime d) => Prefs.setString(dateKey, dayLabelOf(d));
  static void clearExamDay() => Prefs.setString(dateKey, '');
  static void saveUsualWake(int minutes) =>
      Prefs.setInt(usualWakeKey, minutes.clamp(0, 24 * 60 - 1));

  static bool _validDay(String s) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) && DateTime.tryParse(s) != null;

  /// Calendar days from [today] to the exam; null with no date.
  int? daysLeft([DateTime? today]) {
    final e = examDay;
    if (e == null) return null;
    return calendarDaysBetween(today ?? DateTime.now(), DateTime.parse(e));
  }

  SatPhase phase([DateTime? today]) {
    final n = daysLeft(today);
    if (n == null) return SatPhase.unset;
    if (n < 0) return SatPhase.done;
    if (n == 0) return SatPhase.testDay;
    if (n == 1) return SatPhase.eve;
    if (n <= rampDays) return SatPhase.ramp;
    return SatPhase.build;
  }

  /// Tonight's target wake for TOMORROW morning, in minutes after midnight.
  /// Outside the ramp it is the usual wake; inside it walks linearly from the
  /// usual wake to [testWakeMin], reaching it the morning of the exam. If the
  /// user already wakes earlier than test-day wake, nothing moves.
  int targetWakeMin([DateTime? today]) {
    final n = daysLeft(today);
    if (n == null || n < 0) return usualWakeMin;
    if (usualWakeMin <= testWakeMin) return usualWakeMin;
    // Tomorrow is (n - 1) days before the exam.
    final before = n - 1;
    if (before <= 0) return testWakeMin;
    if (before >= rampDays) return usualWakeMin;
    final span = usualWakeMin - testWakeMin;
    final step = span * (rampDays - before) / rampDays;
    // Round to 5 minutes so the plan reads like a plan, not a measurement.
    final raw = usualWakeMin - step;
    return (raw / 5).round() * 5;
  }

  /// Lights-out for tonight, from tomorrow's wake.
  int bedtimeMin([DateTime? today]) =>
      _wrap(targetWakeMin(today) - sleepTargetMin - latencyMin);

  /// Last caffeine of the day.
  int caffeineCutoffMin([DateTime? today]) =>
      _wrap(bedtimeMin(today) - caffeineGapMin);

  static int _wrap(int m) => ((m % 1440) + 1440) % 1440;

  /// "6:15" — 24-hour clock, as the plan's own figure.
  static String clock(int m) {
    final h = _wrap(m) ~/ 60, mm = _wrap(m) % 60;
    return '$h:${mm.toString().padLeft(2, '0')}';
  }
}
