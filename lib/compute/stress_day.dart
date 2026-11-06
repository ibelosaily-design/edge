// STRESS MONITOR — a day's physiological activation on WHOOP's 0–3 scale, from
// the two signals WHOOP names for it (heart rate up against your typical
// resting rate, HRV down against your own recent nights) over the still,
// awake minutes of the day. Activity is left out, as WHOOP leaves it out: a
// raised heart rate while walking is exertion, not stress.
//
// Computed at the READ seam from series the engine already stores for every
// day (`series.hrv_day`, `series.hr_curve`, `activity_curve`, the sleep
// window, naps and workouts) plus the trailing nightly baselines. Nothing new
// is written, so no derived row moves and the WHOOP freeze golden is
// untouched; the cost is a few hundred points of arithmetic per open.
//
// THE SCALE. For one minute with heart rate h and five-minute RMSSD r:
//   a = clamp((h − H) / H, −0.2, 1)   how far the heart is above your typical
//                                      resting rate H (a little below counts)
//   b = clamp(1 − r / R, −0.5, 1)      how far HRV is below your recent nightly
//                                      RMSSD R (well above pulls the score down)
//   score = 3 · clamp(((a + b) / 2) / kStressSaturation, 0, 1)
// With kStressSaturation 0.6 the scale reads 3 when the heart sits 60 % above
// resting AND HRV is 60 % below the nightly value at once — the arousal of a
// hard argument or the minutes before a race — and reads about 0.6 for a calm
// desk minute (+8 % HR, −17 % HRV) and about 1.7 for alert work (+25 %, −40 %).
// WHOOP's own bands: 0–1 low, 1–2 alert, 2–3 high. The constants are this
// file's and are stated in the method text; WHOOP's are not public.
//
// WHAT IS NOT A STRESS MINUTE. A minute inside the night, a nap or a logged or
// detected workout; a minute whose five-minute movement bucket shows the wrist
// moving more than kStressMoveFrac of the time; a minute whose heart rate is
// at or above kStressActiveHrRatio × resting (exertion the accelerometer may
// have missed — cycling, a cold pool); a minute with no heart-rate sample
// within kStressPairWindowSec of the HRV sample. Each is dropped, and the
// count of dropped-for-activity minutes is reported so the screen can say how
// much of the day was movement rather than silence.
//
// WHEN THERE IS NO ANSWER. Fewer than kStressMinBaselineNights nights of
// resting HR or RMSSD → null with a need_baseline note (the screen counts the
// nights). No still minute with both signals → null with a no_still note.
// Never a default baseline, never a population figure.

import 'dart:math' as math;

/// Nights of resting HR and RMSSD the baselines are taken over (median).
const int kStressBaselineNights = 14;

/// Fewest nights before a score is shown at all.
const int kStressMinBaselineNights = 4;

/// The mean of the two normalised deviations at which the scale reads 3.
const double kStressSaturation = 0.6;

/// A five-minute bucket moving more than this fraction of its seconds is
/// activity, not a stress minute.
const double kStressMoveFrac = 0.3;

/// Heart rate at or above this multiple of resting is exertion.
const double kStressActiveHrRatio = 1.6;

/// An HRV sample needs a heart-rate sample within this many seconds.
const int kStressPairWindowSec = 90;

/// A point's weight in minutes is the gap to the next point, capped here.
const int kStressMaxPointSec = 300;

/// Band edges on the 0–3 scale.
const double kStressLowHi = 1.0, kStressMidHi = 2.0;

typedef TimePoint = ({int t, double v});

class StressPoint {
  final int t; // epoch seconds
  final double v; // 0..3
  const StressPoint(this.t, this.v);
}

/// One day's stress line and its summary. [points] are time-ordered.
class StressDay {
  final List<StressPoint> points;
  final double mean;
  final StressPoint peak;
  final StressPoint latest;

  /// Minutes the day spent in each band, weighted by each point's gap.
  final int lowMin, midMin, highMin;

  /// HRV minutes dropped for movement or an exertion-level heart rate.
  final int activeMin;

  final double hrBase, hrvBase;
  final int nights;

  const StressDay({
    required this.points,
    required this.mean,
    required this.peak,
    required this.latest,
    required this.lowMin,
    required this.midMin,
    required this.highMin,
    required this.activeMin,
    required this.hrBase,
    required this.hrvBase,
    required this.nights,
  });

  int get scoredMin => lowMin + midMin + highMin;
}

/// Why there is no [StressDay]: `need_baseline` with the nights counted, or
/// `no_still` when the baselines exist but no still minute carried both
/// signals.
class StressAbsent {
  final String note;
  final int have, need;
  const StressAbsent(this.note, {this.have = 0, this.need = 0});
}

/// The score for one still minute. Pure; see the file header for the scale.
double stressScore({
  required double hr,
  required double hrv,
  required double hrBase,
  required double hrvBase,
}) {
  if (hrBase <= 0 || hrvBase <= 0) return 0;
  final a = ((hr - hrBase) / hrBase).clamp(-0.2, 1.0);
  final b = (1 - hrv / hrvBase).clamp(-0.5, 1.0);
  return 3 * (((a + b) / 2) / kStressSaturation).clamp(0.0, 1.0);
}

/// 'low' | 'medium' | 'high' on WHOOP's bands.
String stressBand(double v) =>
    v < kStressLowHi ? 'low' : (v < kStressMidHi ? 'medium' : 'high');

/// Median of the trailing nightly values, or null under the minimum.
double? stressBaseline(List<double> nights) {
  if (nights.length < kStressMinBaselineNights) return null;
  final s = [...nights.skip(math.max(0, nights.length - kStressBaselineNights))]
    ..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Build the day. [hrv] is the all-day RMSSD line ({t sec, v ms}), [hr] the
/// minute heart-rate curve, [activity] the five-minute moving fraction, and
/// [exclude] the spans (sleep, naps, workouts) that are not stress minutes.
/// [rhrNights] / [rmssdNights] are the trailing nightly values, oldest first.
(StressDay?, StressAbsent?) stressDay({
  required List<TimePoint> hrv,
  required List<TimePoint> hr,
  required List<TimePoint> activity,
  required List<(int, int)> exclude,
  required List<double> rhrNights,
  required List<double> rmssdNights,
}) {
  final hrBase = stressBaseline(rhrNights);
  final hrvBase = stressBaseline(rmssdNights);
  if (hrBase == null || hrvBase == null) {
    return (
      null,
      StressAbsent('need_baseline',
          have: math.min(rhrNights.length, rmssdNights.length),
          need: kStressMinBaselineNights),
    );
  }
  final day = _score(
    hrv: hrv,
    hr: hr,
    activity: activity,
    keep: (t) => !exclude.any((s) => t >= s.$1 && t < s.$2),
    gateActivity: true,
    hrBase: hrBase,
    hrvBase: hrvBase,
    nights: math.min(rhrNights.length, rmssdNights.length),
  );
  return day == null ? (null, const StressAbsent('no_still')) : (day, null);
}

/// The same scale over the night [sleep] (onset, wake), no movement gate: the
/// body is still, and what the line shows is how settled the night was.
/// Null without baselines or without a minute inside the window.
StressDay? stressSleep({
  required List<TimePoint> hrv,
  required List<TimePoint> hr,
  required (int, int) sleep,
  required List<double> rhrNights,
  required List<double> rmssdNights,
}) {
  final hrBase = stressBaseline(rhrNights);
  final hrvBase = stressBaseline(rmssdNights);
  if (hrBase == null || hrvBase == null) return null;
  return _score(
    hrv: hrv,
    hr: hr,
    activity: const [],
    keep: (t) => t >= sleep.$1 && t < sleep.$2,
    gateActivity: false,
    hrBase: hrBase,
    hrvBase: hrvBase,
    nights: math.min(rhrNights.length, rmssdNights.length),
  );
}

StressDay? _score({
  required List<TimePoint> hrv,
  required List<TimePoint> hr,
  required List<TimePoint> activity,
  required bool Function(int t) keep,
  required bool gateActivity,
  required double hrBase,
  required double hrvBase,
  required int nights,
}) {
  if (hrv.isEmpty || hr.isEmpty) return null;

  final hrSorted = [...hr]..sort((x, y) => x.t.compareTo(y.t));
  final moveAt = <int, double>{
    for (final a in activity) a.t - a.t % kStressMaxPointSec: a.v,
  };

  final out = <StressPoint>[];
  var active = 0;
  var hi = 0;
  for (final p in [...hrv]..sort((x, y) => x.t.compareTo(y.t))) {
    if (p.v <= 0 || !keep(p.t)) continue;
    // Nearest heart-rate minute.
    while (hi + 1 < hrSorted.length && hrSorted[hi + 1].t <= p.t) {
      hi++;
    }
    TimePoint? near;
    for (final cand in [hrSorted[hi], if (hi + 1 < hrSorted.length) hrSorted[hi + 1]]) {
      if ((cand.t - p.t).abs() <= kStressPairWindowSec &&
          (near == null || (cand.t - p.t).abs() < (near.t - p.t).abs())) {
        near = cand;
      }
    }
    if (near == null || near.v <= 0) continue;
    final moving = moveAt[p.t - p.t % kStressMaxPointSec];
    if (gateActivity &&
        ((moving != null && moving > kStressMoveFrac) ||
            near.v >= kStressActiveHrRatio * hrBase)) {
      active++;
      continue;
    }
    out.add(StressPoint(
        p.t, stressScore(hr: near.v, hrv: p.v, hrBase: hrBase, hrvBase: hrvBase)));
  }
  if (out.isEmpty) return null;

  var low = 0.0, mid = 0.0, high = 0.0, sum = 0.0, wsum = 0.0;
  var peak = out.first;
  for (var i = 0; i < out.length; i++) {
    final w = (i + 1 < out.length
            ? math.min(out[i + 1].t - out[i].t, kStressMaxPointSec)
            : 60) /
        60.0;
    final v = out[i].v;
    switch (stressBand(v)) {
      case 'low':
        low += w;
      case 'medium':
        mid += w;
      default:
        high += w;
    }
    sum += v * w;
    wsum += w;
    if (v > peak.v) peak = out[i];
  }
  return StressDay(
    points: out,
    mean: sum / wsum,
    peak: peak,
    latest: out.last,
    lowMin: low.round(),
    midMin: mid.round(),
    highMin: high.round(),
    activeMin: active,
    hrBase: hrBase,
    hrvBase: hrvBase,
    nights: nights.clamp(0, kStressBaselineNights),
  );
}
