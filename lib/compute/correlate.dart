// CORRELATE — how two of this person's own daily series move together, and
// nothing more than that.
//
// Pearson r over the days both series have a value, inside one window. The
// number is an ASSOCIATION in one person's history: it does not say which
// moved the other, and with a few dozen days it moves a lot between weeks, so
// every surface prints the day count beside it and words the link as "tends
// to", never "causes". Below kCorrMinDays paired days there is no number at
// all — a correlation over nine points is a coin that remembers.
//
// Pure. Series come in as day-keyed maps (local day label → value), which is
// how the chart read seam already delivers them (one point per local day, at
// local noon); the join is by that label, so a day missing on either side is
// simply not a pair.

import 'dart:math' as math;

/// Fewest paired days before r is reported.
const int kCorrMinDays = 10;

/// |r| at or above which a link is worth listing.
const double kCorrMinAbs = 0.30;

/// Band edges for the strength word.
const double kCorrModerate = 0.30, kCorrStrong = 0.60;

class Correlation {
  final String a, b;
  final double r;
  final int n;
  const Correlation(this.a, this.b, this.r, this.n);

  /// 'weak' | 'moderate' | 'strong' by |r|.
  String get strength => corrStrength(r);
  bool get positive => r > 0;
}

String corrStrength(double r) {
  final a = r.abs();
  return a >= kCorrStrong ? 'strong' : (a >= kCorrModerate ? 'moderate' : 'weak');
}

/// Pearson r of two equal-length lists, or null when fewer than
/// [kCorrMinDays] pairs or either side has no variance.
double? pearson(List<double> x, List<double> y) {
  final n = math.min(x.length, y.length);
  if (n < kCorrMinDays) return null;
  var sx = 0.0, sy = 0.0;
  for (var i = 0; i < n; i++) {
    sx += x[i];
    sy += y[i];
  }
  final mx = sx / n, my = sy / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = x[i] - mx, dy = y[i] - my;
    sxy += dx * dy;
    sxx += dx * dx;
    syy += dy * dy;
  }
  if (sxx <= 0 || syy <= 0) return null;
  return (sxy / math.sqrt(sxx * syy)).clamp(-1.0, 1.0);
}

/// The days both series carry, as aligned value lists (same order).
(List<double>, List<double>) pairedDays(
    Map<String, double> a, Map<String, double> b) {
  final xs = <double>[], ys = <double>[];
  final days = a.keys.toList()..sort();
  for (final d in days) {
    final y = b[d];
    if (y != null) {
      xs.add(a[d]!);
      ys.add(y);
    }
  }
  return (xs, ys);
}

/// r between two day-keyed series, or null under the gates.
Correlation? correlate(
    String ka, Map<String, double> a, String kb, Map<String, double> b) {
  final (xs, ys) = pairedDays(a, b);
  final r = pearson(xs, ys);
  return r == null ? null : Correlation(ka, kb, r, xs.length);
}

/// Every pair among [keys] that clears the gates, strongest first.
List<Correlation> correlatePairs(
    List<String> keys, Map<String, Map<String, double>> series) {
  final out = <Correlation>[];
  for (var i = 0; i < keys.length; i++) {
    for (var j = i + 1; j < keys.length; j++) {
      final a = series[keys[i]], b = series[keys[j]];
      if (a == null || b == null) continue;
      final c = correlate(keys[i], a, keys[j], b);
      if (c != null) out.add(c);
    }
  }
  out.sort((x, y) => y.r.abs().compareTo(x.r.abs()));
  return out;
}

/// What moves with [key]: the other series whose |r| clears [kCorrMinAbs],
/// strongest first, at most [limit].
List<Correlation> correlatesOf(
  String key,
  Map<String, Map<String, double>> series, {
  int limit = 6,
  double minAbs = kCorrMinAbs,
}) {
  final a = series[key];
  if (a == null) return const [];
  final out = <Correlation>[];
  for (final e in series.entries) {
    if (e.key == key) continue;
    final c = correlate(key, a, e.key, e.value);
    if (c != null && c.r.abs() >= minAbs) out.add(c);
  }
  out.sort((x, y) => y.r.abs().compareTo(x.r.abs()));
  return out.take(limit).toList();
}

/// Each series min–max scaled to 0..1 over the days in [days], for an
/// overlay where different units share one axis. A flat series scales to
/// 0.5. Days a series lacks are null.
Map<String, List<double?>> normalizeOverlay(
    Map<String, Map<String, double>> series, List<String> days) {
  final out = <String, List<double?>>{};
  for (final e in series.entries) {
    double? lo, hi;
    for (final d in days) {
      final v = e.value[d];
      if (v == null) continue;
      lo = lo == null ? v : math.min(lo, v);
      hi = hi == null ? v : math.max(hi, v);
    }
    out[e.key] = [
      for (final d in days)
        if (e.value[d] case final v?)
          (lo == null || hi == null || hi == lo) ? 0.5 : (v - lo) / (hi - lo)
        else
          null,
    ];
  }
  return out;
}
