import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/study/sat_plan.dart';

void main() {
  final today = DateTime(2026, 11, 3);
  String inDays(int n) {
    final d = DateTime(2026, 11, 3 + n);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  test('no exam date: unset, and the wake time does not move', () {
    const plan = SatPlan(usualWakeMin: 480);
    expect(plan.phase(today), SatPhase.unset);
    expect(plan.daysLeft(today), isNull);
    expect(plan.targetWakeMin(today), 480);
  });

  test('phases follow the days left', () {
    SatPhase at(int n) => SatPlan(examDay: inDays(n)).phase(today);
    expect(at(30), SatPhase.build);
    expect(at(14), SatPhase.ramp);
    expect(at(2), SatPhase.ramp);
    expect(at(1), SatPhase.eve);
    expect(at(0), SatPhase.testDay);
    expect(at(-1), SatPhase.done);
  });

  test('outside the ramp the plan keeps the usual wake', () {
    expect(SatPlan(examDay: inDays(30), usualWakeMin: 480).targetWakeMin(today),
        480);
    // Tomorrow is still 14 days out: the walk has not started.
    expect(SatPlan(examDay: inDays(15), usualWakeMin: 480).targetWakeMin(today),
        480);
  });

  test('inside the ramp the wake walks halfway at the midpoint, in 5 min steps',
      () {
    // Tomorrow is 7 days before the exam: half of 8:00 → 6:15 is 52.5 min,
    // so 7:07.5, shown on the 5-minute grid.
    final m = SatPlan(examDay: inDays(8), usualWakeMin: 480).targetWakeMin(today);
    expect(m % 5, 0);
    expect(m, inInclusiveRange(425, 430));
  });

  test('the eve plans test-day wake, lights-out and a caffeine cut-off', () {
    final plan = SatPlan(examDay: inDays(1), usualWakeMin: 480);
    expect(plan.targetWakeMin(today), SatPlan.testWakeMin);
    // 6:15 − 8:30 sleep − 15 min to fall asleep = 21:30.
    expect(SatPlan.clock(plan.bedtimeMin(today)), '21:30');
    expect(SatPlan.clock(plan.caffeineCutoffMin(today)), '13:30');
  });

  test('an early riser is never moved later', () {
    final plan = SatPlan(examDay: inDays(5), usualWakeMin: 6 * 60);
    expect(plan.targetWakeMin(today), 6 * 60);
  });

  test('clock wraps past midnight', () {
    expect(SatPlan.clock(-30), '23:30');
    expect(SatPlan.clock(1440 + 75), '1:15');
  });
}
