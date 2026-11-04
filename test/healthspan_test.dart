// Healthspan — the arithmetic behind WHOOP Age and Pace of Aging, on
// synthetic days. Pins the published framework (targets, unlock, windows),
// the absence rules, and the one fitted constant against the white paper's
// worked example.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/healthspan.dart';

final _today = DateTime(2026, 11, 4);

String _date(int daysAgo) {
  final d = _today.subtract(Duration(days: daysAgo));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// [n] consecutive scored days ending yesterday, all alike.
List<HsDay> _days(
  int n, {
  double tstMin = 450,
  double steps = 10900,
  double rhr = 58,
  double z13 = 141 / 7,
  double z45 = 6 / 7,
  double strengthWk = 46,
  double onsetSec = 0,
  double midSec = 0,
  double? driftSecPerNight,
}) =>
    [
      for (var i = 1; i <= n; i++)
        HsDay(
          _date(i),
          tstMin: tstMin,
          onsetSec: onsetSec + (driftSecPerNight ?? 0) * (i.isEven ? 1 : -1),
          midsleepSec: midSec + (driftSecPerNight ?? 0) * (i.isEven ? 1 : -1),
          steps: steps,
          rhr: rhr,
          zone13Min: z13,
          zone45Min: z45,
          strengthMin: strengthWk / 7,
        ),
    ];

void main() {
  test('targets are the published ones', () {
    expect(HsTargets.steps(30), 8000);
    expect(HsTargets.steps(60), 5600);
    expect(HsTargets.vo2max(17, 'm'), 44);
    expect(HsTargets.vo2max(30, 'f'), 38);
    expect(HsTargets.vo2max(50, 'm'), closeTo(35.2, 0.01));
    expect(HsTargets.restingHr('m'), 60);
    expect(HsTargets.restingHr('f'), 64);
    expect(HsTargets.leanPct('m'), 80);
    expect(HsTargets.leanPct('f'), 67);
  });

  test('meeting every target is zero years', () {
    for (final (k, v) in [
      (HsKey.sleepHours, 8.0),
      (HsKey.consistency, 70.0),
      (HsKey.steps, 8000.0),
      (HsKey.zone13, 100.0),
      (HsKey.zone45, 10.0),
      (HsKey.strength, 40.0),
      (HsKey.vo2max, 44.0),
      (HsKey.restingHr, 60.0),
      (HsKey.leanMass, 80.0),
    ]) {
      expect(hsYears(k, v, age: 30, sex: 'm'), 0, reason: k.name);
    }
  });

  test('short of a target adds years, past it takes them off, both capped',
      () {
    expect(hsYears(HsKey.sleepHours, 6, age: 30, sex: 'm'), greaterThan(0));
    expect(hsYears(HsKey.sleepHours, 10, age: 30, sex: 'm'), greaterThan(0));
    expect(hsYears(HsKey.steps, 4000, age: 30, sex: 'm'), greaterThan(0));
    expect(hsYears(HsKey.steps, 11000, age: 30, sex: 'm'), lessThan(0));
    // Caps: a wild input cannot buy unlimited years.
    expect(hsYears(HsKey.steps, 30000, age: 30, sex: 'm'),
        hsYears(HsKey.steps, 11000, age: 30, sex: 'm'));
    expect(hsYears(HsKey.steps, 0, age: 30, sex: 'm'),
        hsYears(HsKey.steps, 3000, age: 30, sex: 'm'));
    expect(hsYears(HsKey.vo2max, 70, age: 30, sex: 'm'),
        hsYears(HsKey.vo2max, 54, age: 30, sex: 'm'));
  });

  test("the white paper's worked member lands within a year", () {
    // Male, 30: 7.0 h, 67 %, 10,900 steps, 141 / 6 zone minutes, 46 min
    // strength, VO2max 46.8, resting HR 58, lean 81 % — WHOOP Age -1.6.
    final r = computeHealthspan(
      days: _days(31, tstMin: 420, driftSecPerNight: 30 * 60),
      age: 30,
      sex: 'm',
      today: _today,
      vo2max: 46.8,
      leanPct: 81,
    );
    expect(r.unlocked, isTrue);
    expect(r.delta, closeTo(-1.6, 1.0));
    // The lines add up to the headline.
    final sum = r.contributors.fold<double>(0, (s, c) => s + c.years);
    expect(r.whoopAge, closeTo(30 + sum, 0.051));
  });

  test('a night that drifts an hour reads about 67 % consistent', () {
    expect(hsNightConsistency(0, 0), 100);
    expect(hsNightConsistency(3600, 3600), closeTo(66.7, 0.1));
    expect(hsNightConsistency(4 * 3600, 4 * 3600), 0);
  });

  test('unlocks at 21 scored days in 31, not before', () {
    final locked = computeHealthspan(
        days: _days(20), age: 30, sex: 'm', today: _today);
    expect(locked.unlocked, isFalse);
    expect(locked.whoopAge, isNull);
    expect(locked.pace, isNull);
    expect(locked.recentScored, 20);
    final open = computeHealthspan(
        days: _days(21), age: 30, sex: 'm', today: _today);
    expect(open.unlocked, isTrue);
    expect(open.whoopAge, isNotNull);
  });

  test('an unmeasured contributor is absent and scores nothing', () {
    final r = computeHealthspan(
      days: [
        for (var i = 1; i <= 25; i++)
          HsDay(_date(i), tstMin: 480, rhr: 70),
      ],
      age: 40,
      sex: 'f',
      today: _today,
    );
    final byKey = {for (final c in r.contributors) c.key: c};
    expect(byKey[HsKey.steps]!.absent, isTrue);
    expect(byKey[HsKey.steps]!.years, 0);
    expect(byKey[HsKey.zone13]!.absent, isTrue);
    expect(byKey[HsKey.vo2max]!.absent, isTrue);
    expect(byKey[HsKey.leanMass]!.absent, isTrue);
    expect(byKey[HsKey.consistency]!.absent, isTrue);
    // Strength is a sum: scored days with no session are a measured zero.
    expect(byKey[HsKey.strength]!.value, 0);
    expect(byKey[HsKey.restingHr]!.years, greaterThan(0));
    expect(byKey[HsKey.sleepHours]!.years, 0);
  });

  test('pace is 1x when the last 30 days match the long window', () {
    final r = computeHealthspan(
        days: _days(120), age: 30, sex: 'm', today: _today);
    expect(r.pace, 1.0);
  });

  test('a better month reads under 1x, a worse one over', () {
    final old = _days(120, steps: 5000).sublist(30);
    final better = [..._days(30, steps: 11000), ...old];
    final worse = [..._days(30, steps: 2000), ...old];
    final b = computeHealthspan(
        days: better, age: 30, sex: 'm', today: _today);
    final w = computeHealthspan(
        days: worse, age: 30, sex: 'm', today: _today);
    expect(b.pace!, lessThan(1));
    expect(w.pace!, greaterThan(1));
    expect(b.pace!, greaterThanOrEqualTo(-1));
    expect(w.pace!, lessThanOrEqualTo(3));
  });

  test('weekly rates are per calendar week of the span, not per worn day', () {
    // Worn every other day for 60 days: 30 scored days over a 59-day span.
    final days = [
      for (var i = 1; i <= 60; i += 2)
        HsDay(_date(i), tstMin: 480, rhr: 60, strengthMin: 20),
    ];
    final w = hsWindow(days, _today);
    expect(w.scored, 30);
    expect(w.span, 59);
    expect(w.strengthWk, closeTo(30 * 20 * 7 / 59, 0.01));
  });

  test('consistency skips nights after a gap', () {
    final days = [
      HsDay(_date(1), tstMin: 480, onsetSec: 0, midsleepSec: 0),
      // _date(2) missing — the band was off.
      HsDay(_date(3), tstMin: 480, onsetSec: 7200, midsleepSec: 7200),
      HsDay(_date(4), tstMin: 480, onsetSec: 7200, midsleepSec: 7200),
    ];
    final w = hsWindow(days, _today);
    expect(w.consistencyPairs, 1);
    expect(w.consistency, 100);
  });

  test('only the last six months count', () {
    final r = computeHealthspan(
      days: [..._days(40), ..._days(400).sublist(300)],
      age: 30,
      sex: 'm',
      today: _today,
    );
    expect(r.scoredDays, 40);
    expect(r.spanDays, 40);
  });
}
