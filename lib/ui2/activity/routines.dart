// STRENGTH ROUTINES — a list of exercises to open a strength session with,
// so the first set is not preceded by picking five lifts one by one. Two
// kinds: the lifts this person did last time (their own recent sessions, read
// from the set log), and four plain presets built from the hand-written core
// of the catalogue. A routine is an ORDER OF EXERCISES and nothing else — no
// sets, reps or loads are prescribed; the live screen seeds each lift from
// what the user did last time, as it always has.

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import 'catalogue.dart' show exerciseByKey;

class StrengthRoutine {
  /// Stable id: `preset:<name>` or `session:<session_id>`.
  final String id;
  final List<String> exerciseKeys;

  /// The session this routine repeats, when it is one of the user's own.
  final DateTime? lastDone;

  const StrengthRoutine(this.id, this.exerciseKeys, {this.lastDone});

  bool get isPreset => id.startsWith('preset:');
  String get presetName => isPreset ? id.substring('preset:'.length) : '';
}

/// Four presets from the core catalogue; every key resolves.
const List<StrengthRoutine> kPresetRoutines = [
  StrengthRoutine('preset:push', [
    'bench_press',
    'incline_db_press',
    'overhead_press',
    'cable_fly',
    'triceps_pushdown',
  ]),
  StrengthRoutine('preset:pull', [
    'pull_up',
    'barbell_row',
    'lat_pulldown',
    'barbell_curl',
  ]),
  StrengthRoutine('preset:legs', [
    'back_squat',
    'romanian_deadlift',
    'leg_press',
    'hip_thrust',
    'plank',
  ]),
  StrengthRoutine('preset:full', [
    'back_squat',
    'bench_press',
    'barbell_row',
    'overhead_press',
    'plank',
  ]),
];

String routineName(StrengthRoutine r, AppLocalizations? l) =>
    switch (r.presetName) {
      'push' => l?.routinePush ?? 'Push',
      'pull' => l?.routinePull ?? 'Pull',
      'legs' => l?.routineLegs ?? 'Legs',
      'full' => l?.routineFullBody ?? 'Full body',
      _ => l?.routineLastTime ?? 'Last time',
    };

/// The user's own recent sessions as routines, newest first, identical
/// exercise orders collapsed into one, at most [limit]. [rows] are
/// `strength_set` rows (session_id, exercise_key, seq, at_ts), any order.
List<StrengthRoutine> recentRoutinesFrom(List<Map<String, Object?>> rows,
    {int limit = 3}) {
  final bySession = <String, List<Map<String, Object?>>>{};
  for (final r in rows) {
    final id = r['session_id'];
    if (id is! String || id.isEmpty) continue;
    (bySession[id] ??= []).add(r);
  }
  final sessions = <({String id, List<String> keys, int at})>[];
  for (final e in bySession.entries) {
    e.value.sort((a, b) =>
        ((a['seq'] as num?) ?? 0).compareTo((b['seq'] as num?) ?? 0));
    final keys = <String>[];
    var at = 0;
    for (final r in e.value) {
      final k = r['exercise_key'];
      if (k is String && k.isNotEmpty && !keys.contains(k)) keys.add(k);
      final t = (r['at_ts'] as num?)?.toInt() ?? 0;
      if (t > at) at = t;
    }
    if (keys.isNotEmpty) sessions.add((id: e.key, keys: keys, at: at));
  }
  sessions.sort((a, b) => b.at.compareTo(a.at));
  final out = <StrengthRoutine>[];
  for (final s in sessions) {
    if (out.any((r) => _sameOrder(r.exerciseKeys, s.keys))) continue;
    out.add(StrengthRoutine('session:${s.id}', s.keys,
        lastDone:
            s.at > 0 ? DateTime.fromMillisecondsSinceEpoch(s.at * 1000) : null));
    if (out.length == limit) break;
  }
  return out;
}

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The exercise names of a routine, in this locale, joined for a subtitle.
String routineExercises(StrengthRoutine r, String lang) => [
      for (final k in r.exerciseKeys) exerciseByKey(k)?.labelFor(lang) ?? k,
    ].join(' · ');

/// The user's recent routines from the database; empty when it has none or
/// cannot be read (a preview with no database).
Future<List<StrengthRoutine>> loadRecentRoutines({int sessions = 12}) async {
  try {
    final rows = await LocalDb.recentStrengthSessionSets(sessions: sessions);
    return recentRoutinesFrom(rows);
  } catch (_) {
    return const [];
  }
}
