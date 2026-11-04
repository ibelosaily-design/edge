// Healthspan — a physiological age and its pace, from the nine habits WHOOP's
// Healthspan feature scores, computed on this phone from the days already on
// disk.
//
// THE METHOD, as WHOOP's Healthspan white paper (2025) publishes it: each of
// nine contributors is compared with a health target drawn from public-health
// guidance, the gap is turned into a mortality hazard ratio from the
// epidemiology that links that habit to all-cause mortality, and the hazard
// ratio is turned into years by Gompertz' law — mortality risk doubles about
// every eight to ten years of adult age, so a risk ratio IS an age offset:
// years = 10 · ln(HR). The nine offsets are summed onto the calendar age
// (WHOOP Age), and the last 30 days are compared with the long window to say
// where that age is heading (Pace of Aging, -1x..3x, 1x = aging at calendar
// speed).
//
// WHAT IS WHOOP'S AND WHAT IS OURS. The framework, the nine inputs, their
// targets (7-9 h, 70 % consistency, 8,000 steps, 100 and 10 zone minutes a
// week, 40 strength minutes, VO2max 44/38 at 30, resting HR 60/64, lean
// mass 80/67 %) and the two headline definitions are WHOOP's, published. The
// per-contributor hazard slopes are NOT published; the ones here come from
// the cited meta-analyses and are flagged below, one line each. The
// cross-domain shrink (0.6) is this file's one fitted constant, set so the
// white paper's two worked examples land close (see the test). So: the same
// logic, the same inputs, the same targets — but not WHOOP's exact weights,
// and the screen says so.
//
// HONESTY RULES, same as everywhere else in this app:
//   * a contributor with no measured days is ABSENT and scores nothing — it is
//     never filled with a population value;
//   * the age is reported with the number of days behind it; WHOOP uses six
//     months, and before that many days exist the label says how many do;
//   * nothing unlocks before 21 scored days in the last 31 (WHOOP's gate);
//   * the models behind the slopes are adult cohorts. WHOOP refuses the
//     feature under 18 for that reason; this app computes it and the screen
//     carries that caveat instead.
//
// Pure: no Flutter, no database. The loader (healthspan_load.dart) reads the
// days; this file only does the arithmetic.

import 'dart:math' as math;

/// The nine contributors, in WHOOP's grouping: sleep, activity, fitness.
enum HsKey {
  sleepHours,
  consistency,
  steps,
  zone13,
  zone45,
  strength,
  vo2max,
  restingHr,
  leanMass,
}

/// One day's inputs, as read off the stored day. Null = not measured that
/// day (never zero). [strengthMin] is a sum, so a day with no strength session
/// is a measured 0 — but only on a day the band scored at all.
class HsDay {
  final String date; // YYYY-MM-DD, local
  final double? tstMin;
  final double? onsetSec; // signed seconds either side of 04:00, unwrapped
  final double? midsleepSec;
  final double? steps;
  final double? rhr;
  final double? zone13Min;
  final double? zone45Min;
  final double strengthMin;

  const HsDay(
    this.date, {
    this.tstMin,
    this.onsetSec,
    this.midsleepSec,
    this.steps,
    this.rhr,
    this.zone13Min,
    this.zone45Min,
    this.strengthMin = 0,
  });

  /// A day the band judged: a night or a resting heart rate. The same thing
  /// WHOOP counts as "a recovery" for the unlock.
  bool get scored => tstMin != null || rhr != null;
}

/// One contributor's read-out: the window value, its target and the years it
/// adds (positive) or takes off (negative). [value] null = absent, years 0.
class HsContributor {
  final HsKey key;
  final double? value;
  final double target;
  final double years;

  /// Days of evidence behind [value] — 0 for an absent one, 1 for a typed
  /// value (VO2max, lean mass).
  final int days;

  const HsContributor(this.key, this.value, this.target, this.years, this.days);

  bool get absent => value == null;
}

class HealthspanResult {
  final int chronoAge;

  /// Null until unlocked.
  final double? whoopAge;

  /// -1..3, null until unlocked.
  final double? pace;
  final List<HsContributor> contributors;

  /// Scored days in the long window, and the window's span in calendar days.
  final int scoredDays;
  final int spanDays;

  /// Scored days in the last 31 — the unlock counter.
  final int recentScored;
  final bool unlocked;

  const HealthspanResult({
    required this.chronoAge,
    required this.whoopAge,
    required this.pace,
    required this.contributors,
    required this.scoredDays,
    required this.spanDays,
    required this.recentScored,
    required this.unlocked,
  });

  /// WHOOP Age minus calendar age, in years.
  double? get delta => whoopAge == null ? null : whoopAge! - chronoAge;
}

/// The targets, WHOOP's published ones. Steps, VO2max and lean mass move with
/// age in WHOOP's table; the published anchors are "younger adult" and "60+"
/// for steps and age 30 for VO2max, so between them this is a straight line.
class HsTargets {
  static const sleepLoH = 7.0, sleepHiH = 9.0;
  static const consistencyPct = 70.0;
  static const zone13MinWk = 100.0;
  static const zone45MinWk = 10.0;
  static const strengthMinWk = 40.0;

  // ponytail: WHOOP publishes 8,000 under 60 and 5,600 for older adults; the
  // age the step falls at is not published, so it falls at 60 (Paluch 2022
  // splits its cohorts there).
  static double steps(int age) => age >= 60 ? 5600 : 8000;

  /// 44 (men) / 38 (women) at 30, falling about 1 % a year after 30 — the
  /// population decline, so the target asks the same relative fitness of a
  /// 50-year-old as of a 30-year-old. Not raised above the anchor for the
  /// young: the anchor is already "supports independent living later".
  static double vo2max(int age, String sex) {
    final base = sex == 'f' ? 38.0 : 44.0;
    return age <= 30 ? base : base * (1 - 0.01 * (age - 30)).clamp(0.5, 1.0);
  }

  static double restingHr(String sex) => sex == 'f' ? 64 : 60;
  static double leanPct(String sex) => sex == 'f' ? 67 : 80;
}

/// Years for a contributor are 10 · ln(HR) · [shrink]. The nine inputs
/// overlap (resting HR and VO2max both read cardiovascular fitness; steps and
/// zone minutes both read movement), and WHOOP's structural model prices that
/// overlap out of each one. Its weights are not published; 0.6 is the single
/// scalar that lands the white paper's two worked examples (Table 2) within a
/// year — see test/healthspan_test.dart. Fitted, named, and the only one.
const double kHsShrink = 0.6;

/// ln(hazard ratio) for one contributor at [value], against its target for
/// this [age] and [sex]. Positive = older. Each slope cites the study it is
/// read off; each is clipped at the range that study covered, so a wild
/// input cannot buy or cost unlimited years.
double hsLogHazard(HsKey key, double value, {required int age, required String sex}) {
  switch (key) {
    case HsKey.sleepHours:
      // Cappuccio 2010 (16 cohorts): short sleep HR 1.12, long sleep 1.30
      // against 7-8 h. Per hour short of 7, and per hour past 9.
      if (value < HsTargets.sleepLoH) {
        return 0.12 * (HsTargets.sleepLoH - value).clamp(0, 3);
      }
      if (value > HsTargets.sleepHiH) {
        return 0.13 * (value - HsTargets.sleepHiH).clamp(0, 2);
      }
      return 0;
    case HsKey.consistency:
      // Windred 2024 (UK Biobank, Sleep Regularity Index): the least regular
      // quintile carried HR 1.53 against the most regular, about 45 index
      // points apart — 0.01 per point. Above 70 the benefit keeps going,
      // smaller, to 90.
      if (value < HsTargets.consistencyPct) {
        return 0.01 * (HsTargets.consistencyPct - value).clamp(0, 40);
      }
      return -0.004 * (value - HsTargets.consistencyPct).clamp(0, 20);
    case HsKey.steps:
      // Paluch 2022 (Lancet Public Health, 15 cohorts): under 60, risk keeps
      // falling to 8-10k; lowest vs that: HR about 0.55 over ~4,500 steps.
      // 0.0001 per step short; over it the fall goes on to 10k (ln 0.5/0.6
      // across 2,000 steps), so 0.00006 per step over, capped at 3,000.
      final t = HsTargets.steps(age);
      if (value < t) return 0.0001 * (t - value).clamp(0, 5000);
      return -0.00006 * (value - t).clamp(0, 3000);
    case HsKey.zone13:
      // Ekelund 2019 (BMJ, accelerometer cohorts): moderate activity, highest
      // vs lowest quartile HR about 0.6, and the fall continues past the
      // guideline minimum — 0.003 per minute short, 0.002 per minute over.
      if (value < HsTargets.zone13MinWk) {
        return 0.003 * (HsTargets.zone13MinWk - value).clamp(0, 100);
      }
      return -0.002 * (value - HsTargets.zone13MinWk).clamp(0, 200);
    case HsKey.zone45:
      // Stamatakis 2022 (Nature Medicine, VILPA): a few vigorous minutes a
      // day, HR about 0.6 in non-exercisers; here a short, steep slope to the
      // 10-minute target and a shallow one beyond it.
      if (value < HsTargets.zone45MinWk) {
        return 0.015 * (HsTargets.zone45MinWk - value).clamp(0, 10);
      }
      return -0.006 * (value - HsTargets.zone45MinWk).clamp(0, 30);
    case HsKey.strength:
      // Momma 2022 (BJSM meta-analysis): 30-60 min/week of muscle
      // strengthening, HR 0.83; the benefit flattens and reverses past
      // ~130 min, so the bonus is capped at 80 over the target.
      if (value < HsTargets.strengthMinWk) {
        return 0.0045 * (HsTargets.strengthMinWk - value).clamp(0, 40);
      }
      return -0.0015 * (value - HsTargets.strengthMinWk).clamp(0, 80);
    case HsKey.vo2max:
      // Mandsager 2018 (JAMA Netw Open, 122,007 patients): each MET
      // (3.5 ml/kg/min) about 12 % lower mortality, no upper limit observed
      // — 0.035 per unit short, 0.04 per unit over (the curve is steeper
      // through the fit range than below it), both capped.
      final t = HsTargets.vo2max(age, sex);
      if (value < t) return 0.035 * (t - value).clamp(0, 15);
      return -0.04 * (value - t).clamp(0, 10);
    case HsKey.restingHr:
      // Zhang 2016 (CMAJ meta-analysis): 9 % per 10 bpm of resting heart
      // rate — 0.009 per bpm over the target, 0.007 under it.
      final t = HsTargets.restingHr(sex);
      if (value > t) return 0.009 * (value - t).clamp(0, 30);
      return -0.007 * (t - value).clamp(0, 15);
    case HsKey.leanMass:
      // Srikanthan 2014 (Am J Med, NHANES III): highest vs lowest muscle
      // mass quartile, about 20 % lower mortality — 0.02 per point of lean
      // mass short of the target, 0.015 over it.
      final t = HsTargets.leanPct(sex);
      if (value < t) return 0.02 * (t - value).clamp(0, 15);
      return -0.015 * (value - t).clamp(0, 8);
  }
}

/// Years a contributor adds, after the overlap shrink. Rounded to a tenth so
/// the nine lines on screen add up to the headline.
double hsYears(HsKey key, double value, {required int age, required String sex}) =>
    (10 * kHsShrink * hsLogHazard(key, value, age: age, sex: sex) * 10).round() /
    10;

/// WHOOP's unlock: 21 recoveries in 31 days.
const int kHsUnlockDays = 21, kHsUnlockWindow = 31;

/// WHOOP Age looks at six months; Pace of Aging at the last 30 days.
const int kHsLongWindow = 182, kHsPaceWindow = 30;

/// The window averages for one span of days. Null where nothing in the span
/// measured that input.
class HsWindow {
  final double? sleepHours;
  final double? consistency;
  final double? steps;
  final double? zone13Wk;
  final double? zone45Wk;
  final double? strengthWk;
  final double? rhr;
  final int scored;
  final int span;
  final int sleepDays, consistencyPairs, stepDays, zoneDays, rhrDays;

  const HsWindow({
    this.sleepHours,
    this.consistency,
    this.steps,
    this.zone13Wk,
    this.zone45Wk,
    this.strengthWk,
    this.rhr,
    this.scored = 0,
    this.span = 0,
    this.sleepDays = 0,
    this.consistencyPairs = 0,
    this.stepDays = 0,
    this.zoneDays = 0,
    this.rhrDays = 0,
  });
}

/// Averages over [days] (any order; sorted here). [span] is the calendar
/// stretch from the first scored day to [today], so weekly rates are per
/// calendar week, not per worn week — a band worn three days in seven did
/// three days of strength, not seven.
HsWindow hsWindow(List<HsDay> days, DateTime today) {
  final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
  final scored = sorted.where((d) => d.scored).toList();
  if (scored.isEmpty) return const HsWindow();
  final first = DateTime.parse(scored.first.date);
  final span = DateTime(today.year, today.month, today.day)
          .difference(DateTime(first.year, first.month, first.day))
          .inDays +
      1;
  double? mean(Iterable<double> xs) {
    final list = xs.toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b) / list.length;
  }

  final tst = [for (final d in sorted) if (d.tstMin != null) d.tstMin!];
  final st = [for (final d in sorted) if (d.steps != null) d.steps!];
  final rh = [for (final d in sorted) if (d.rhr != null) d.rhr!];
  final z13 = [for (final d in sorted) if (d.zone13Min != null) d.zone13Min!];
  final z45 = [for (final d in sorted) if (d.zone45Min != null) d.zone45Min!];

  // Consistency: consecutive nights only — a night after a gap says nothing
  // about regularity, it says the band was off.
  final pairs = <double>[];
  for (var i = 1; i < sorted.length; i++) {
    final a = sorted[i - 1], b = sorted[i];
    if (a.onsetSec == null ||
        a.midsleepSec == null ||
        b.onsetSec == null ||
        b.midsleepSec == null) {
      continue;
    }
    final gap = DateTime.parse(b.date).difference(DateTime.parse(a.date)).inDays;
    if (gap != 1) continue;
    pairs.add(hsNightConsistency(
      a.onsetSec! - b.onsetSec!,
      a.midsleepSec! - b.midsleepSec!,
    ));
  }

  final strength = sorted.fold<double>(0, (s, d) => s + d.strengthMin);
  return HsWindow(
    sleepHours: mean(tst)?.let((m) => m / 60),
    consistency: mean(pairs),
    steps: mean(st),
    zone13Wk: mean(z13)?.let((m) => m * 7),
    zone45Wk: mean(z45)?.let((m) => m * 7),
    strengthWk: strength * 7 / span,
    rhr: mean(rh),
    scored: scored.length,
    span: span,
    sleepDays: tst.length,
    consistencyPairs: pairs.length,
    stepDays: st.length,
    zoneDays: math.max(z13.length, z45.length),
    rhrDays: rh.length,
  );
}

/// How alike two consecutive nights are, 0-100, from the shift in sleep onset
/// and mid-sleep. 100 at no shift, 0 at three hours — an hour's drift reads
/// 67, which is where WHOOP's own consistency sits for an ordinary sleeper.
// ponytail: WHOOP's consistency compares each night with the previous four;
// this compares with the previous one. Same scale, less smoothing.
double hsNightConsistency(double dOnsetSec, double dMidSec) {
  final driftMin = (dOnsetSec.abs() + dMidSec.abs()) / 2 / 60;
  return (100 * (1 - driftMin / 180)).clamp(0, 100).toDouble();
}

/// The whole read-out. [vo2max] and [leanPct] are typed or estimated once,
/// not windowed. [today] is the local date the windows end on.
HealthspanResult computeHealthspan({
  required List<HsDay> days,
  required int age,
  required String sex,
  required DateTime today,
  double? vo2max,
  double? leanPct,
}) {
  final t0 = DateTime(today.year, today.month, today.day);
  bool within(HsDay d, int n) =>
      t0.difference(DateTime.parse(d.date)).inDays < n;
  final long = days.where((d) => within(d, kHsLongWindow)).toList();
  final recent = days.where((d) => within(d, kHsUnlockWindow)).toList();
  final recentScored = recent.where((d) => d.scored).length;
  final unlocked = recentScored >= kHsUnlockDays;

  final w = hsWindow(long, today);
  final w30 = hsWindow(days.where((d) => within(d, kHsPaceWindow)).toList(), today);

  HsContributor c(HsKey k, double? v, double target, int evidence) =>
      HsContributor(
        k,
        v,
        target,
        v == null ? 0 : hsYears(k, v, age: age, sex: sex),
        v == null ? 0 : evidence,
      );
  final contributors = [
    c(HsKey.sleepHours, w.sleepHours, HsTargets.sleepLoH, w.sleepDays),
    c(HsKey.consistency, w.consistency, HsTargets.consistencyPct,
        w.consistencyPairs),
    c(HsKey.steps, w.steps, HsTargets.steps(age), w.stepDays),
    c(HsKey.zone13, w.zone13Wk, HsTargets.zone13MinWk, w.zoneDays),
    c(HsKey.zone45, w.zone45Wk, HsTargets.zone45MinWk, w.zoneDays),
    c(HsKey.strength, w.scored == 0 ? null : w.strengthWk,
        HsTargets.strengthMinWk, w.scored),
    c(HsKey.vo2max, vo2max, HsTargets.vo2max(age, sex), 1),
    c(HsKey.restingHr, w.rhr, HsTargets.restingHr(sex), w.rhrDays),
    c(HsKey.leanMass, leanPct, HsTargets.leanPct(sex), 1),
  ];

  double sum(List<HsContributor> cs) =>
      cs.fold<double>(0, (s, x) => s + x.years);
  final deltaLong = sum(contributors);

  // The 30-day read-out, same contributors; typed values cancel out.
  double? pace;
  if (unlocked) {
    final c30 = [
      c(HsKey.sleepHours, w30.sleepHours, HsTargets.sleepLoH, 1),
      c(HsKey.consistency, w30.consistency, HsTargets.consistencyPct, 1),
      c(HsKey.steps, w30.steps, HsTargets.steps(age), 1),
      c(HsKey.zone13, w30.zone13Wk, HsTargets.zone13MinWk, 1),
      c(HsKey.zone45, w30.zone45Wk, HsTargets.zone45MinWk, 1),
      c(HsKey.strength, w30.scored == 0 ? null : w30.strengthWk,
          HsTargets.strengthMinWk, 1),
      c(HsKey.restingHr, w30.rhr, HsTargets.restingHr(sex), 1),
    ];
    // Only contributors measured in BOTH windows take part, so a month that
    // happened to carry no zone minutes does not read as "aging slower".
    final measured = {for (final x in contributors) if (!x.absent) x.key};
    final d30 = sum([for (final x in c30) if (measured.contains(x.key)) x]);
    final dLong = sum([
      for (final x in contributors)
        if (c30.any((y) => y.key == x.key && !y.absent)) x
    ]);
    // If the last 30 days' habits held for the next six months, WHOOP Age
    // would move from age + dLong to age + 0.5 + d30 over half a year:
    // pace = (0.5 + d30 - dLong) / 0.5.
    final raw = (1 + 2 * (d30 - dLong)).clamp(-1.0, 3.0).toDouble();
    pace = (raw * 10).round() / 10;
  }

  return HealthspanResult(
    chronoAge: age,
    whoopAge: unlocked ? ((age + deltaLong) * 10).round() / 10 : null,
    pace: pace,
    contributors: contributors,
    scoredDays: w.scored,
    spanDays: w.span,
    recentScored: recentScored,
    unlocked: unlocked,
  );
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
