// Healthspan — reading the nine inputs off what the app already stores.
//
// Everything here is a read of a series, a session list or a day the band
// scored; nothing is computed for the first time. The one slow read is the
// day's zone minutes, which live inside each day's bundle, so those are
// cached per day (days lock about 48 h after wake, so a cached day is only
// re-read while it is still that fresh).

import 'dart:convert';

import '../data/day_label.dart';
import '../data/local_repository.dart';
import '../state/prefs.dart';
import '../ui2/activity/catalogue.dart' show activityLibrary;
import 'healthspan.dart';

/// Profile keys the Healthspan screen writes. VO2max typed from another app
/// (WHOOP shows one weekly) or a lab; body fat from a scale or a caliper.
const kProfileVo2maxKey = 'vo2max_manual';
const kProfileBodyFatKey = 'body_fat_pct';

/// The activity names WHOOP counts as strength-based: this app's own
/// Strength group, by name.
final Set<String> kStrengthTypes = {
  for (final g in activityLibrary)
    if (g.name == 'Strength')
      for (final a in g.items) a.name.toLowerCase(),
};

bool isStrengthType(String? type) =>
    type != null && kStrengthTypes.contains(type.toLowerCase().replaceAll('_', ' '));

/// What the screen needs, read in one pass.
class HealthspanInputs {
  final List<HsDay> days;
  final int? age;
  final String? sex;
  final double? vo2max;

  /// Where [vo2max] came from: 'typed', 'session' or null.
  final String? vo2maxSource;
  final double? leanPct;

  const HealthspanInputs({
    required this.days,
    this.age,
    this.sex,
    this.vo2max,
    this.vo2maxSource,
    this.leanPct,
  });

  bool get profileComplete => age != null && (sex == 'm' || sex == 'f');

  HealthspanResult? compute(DateTime today) => !profileComplete
      ? null
      : computeHealthspan(
          days: days,
          age: age!,
          sex: sex!,
          today: today,
          vo2max: vo2max,
          leanPct: leanPct,
        );
}

/// Zone minutes per day, cached: {date: [z13, z45]}.
class _ZoneCache {
  static const key = 'healthspan.zones';

  static Map<String, List<double>> read() {
    try {
      final raw = jsonDecode(Prefs.getString(key, '{}'));
      if (raw is! Map) return {};
      return {
        for (final e in raw.entries)
          if (e.value is List && (e.value as List).length == 2)
            e.key.toString(): [
              ((e.value as List)[0] as num).toDouble(),
              ((e.value as List)[1] as num).toDouble(),
            ],
      };
    } catch (_) {
      return {};
    }
  }

  static void write(Map<String, List<double>> m) =>
      Prefs.setString(key, jsonEncode(m));
}

Future<HealthspanInputs> loadHealthspan(
  LocalRepository repo, {
  required Map<String, dynamic> profile,
  DateTime? now,
}) async {
  final today = now ?? DateTime.now();
  final t0 = DateTime(today.year, today.month, today.day);
  final from = t0.subtract(const Duration(days: kHsLongWindow));

  // One slot per date: the series come back as {t, v} at local noon.
  final byDate = <String, Map<String, double>>{};
  Future<void> series(String metric, String field) async {
    final chart = await repo.getChart(metric);
    for (final p in (chart['points'] as List? ?? const [])) {
      if (p is! Map || p['t'] is! num || p['v'] is! num) continue;
      final t = DateTime.fromMillisecondsSinceEpoch((p['t'] as num).toInt() * 1000);
      if (t.isBefore(from)) continue;
      final date = dayLabelOf(t);
      (byDate[date] ??= {})[field] = (p['v'] as num).toDouble();
    }
  }

  await series('sleep', 'tst');
  await series('resting_hr', 'rhr');
  await series('steps', 'steps');
  await series('sleep_onset_sec', 'onset');
  await series('midsleep_sec', 'mid');

  // Strength minutes per day, and the newest session VO2max estimate.
  final sessions = await repo.getSessions(
    from: from.millisecondsSinceEpoch ~/ 1000,
    to: today.millisecondsSinceEpoch ~/ 1000,
  );
  final strength = <String, double>{};
  double? sessionVo2;
  for (final s in sessions) {
    final start = (s['start_ts'] as num?)?.toInt();
    if (start == null) continue;
    final date = dayLabelOf(DateTime.fromMillisecondsSinceEpoch(start * 1000));
    final v = (s['vo2max_estimate'] as num?)?.toDouble();
    if (v != null && sessionVo2 == null) sessionVo2 = v; // newest first
    if (!isStrengthType(s['type'] as String?)) continue;
    final min = (s['duration_min'] as num?)?.toDouble() ?? 0;
    strength[date] = (strength[date] ?? 0) + min;
  }

  // Zone minutes: cached, except the last two days, which may still move.
  final cache = _ZoneCache.read();
  final fresh = {dayLabelOf(t0), dayLabelOf(t0.subtract(const Duration(days: 1)))};
  var cacheDirty = false;
  for (final date in byDate.keys) {
    if (cache.containsKey(date) && !fresh.contains(date)) continue;
    final strain = await repo.getDayStrain(date);
    final z = strain['zones'];
    if (z is! Map) continue;
    double? zone(int i) => (z['z$i'] as num?)?.toDouble();
    final zs = [for (var i = 1; i <= 5; i++) zone(i)];
    if (zs.every((v) => v == null)) continue;
    cache[date] = [
      (zs[0] ?? 0) + (zs[1] ?? 0) + (zs[2] ?? 0),
      (zs[3] ?? 0) + (zs[4] ?? 0),
    ];
    cacheDirty = true;
  }
  // Drop cached days that fell out of the window.
  final before = cache.length;
  cache.removeWhere((date, _) => DateTime.parse(date).isBefore(from));
  if (cacheDirty || cache.length != before) _ZoneCache.write(cache);

  final days = [
    for (final e in byDate.entries)
      HsDay(
        e.key,
        tstMin: e.value['tst'],
        onsetSec: e.value['onset'],
        midsleepSec: e.value['mid'],
        steps: e.value['steps'],
        rhr: e.value['rhr'],
        zone13Min: cache[e.key]?[0],
        zone45Min: cache[e.key]?[1],
        strengthMin: strength[e.key] ?? 0,
      ),
  ];

  final typedVo2 = (profile[kProfileVo2maxKey] as num?)?.toDouble();
  final fat = (profile[kProfileBodyFatKey] as num?)?.toDouble();
  final sex = (profile['sex'] as String?)?.toLowerCase();
  return HealthspanInputs(
    days: days,
    age: (profile['age'] as num?)?.round(),
    sex: sex,
    vo2max: typedVo2 ?? sessionVo2,
    vo2maxSource: typedVo2 != null ? 'typed' : (sessionVo2 != null ? 'session' : null),
    leanPct: fat == null ? null : (100 - fat).clamp(0, 100).toDouble(),
  );
}
