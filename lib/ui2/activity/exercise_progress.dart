// EXERCISE PROGRESS — one lift over time, from this user's own set log: the
// top set and the Epley 1RM estimate per session as bars, the latest and best
// in words, and the sessions listed. Read-only, derived on open from
// `strength_set` (nothing stored), the second half of the Strength Trainer
// plan item beside routines.
//
// Honesty: every 1RM here is an ESTIMATE and says so; a bodyweight session
// with no load has no bar (an absence, not a zero); a lift logged once has
// no trend to speak of and the screen shows the one session rather than a
// line through one point.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../charts.dart';
import '../onboarding/profile_setup.dart' show formatDay;
import '../screens/metric_detail.dart' show detailScaffold;
import '../ui2.dart';
import 'catalogue.dart' show exerciseByKey;
import 'summary.dart' show LoggedSet, oneRepMax;

/// One session's summary for a lift.
class ExerciseSession {
  final String sessionId;
  final DateTime at;
  final int sets, reps;
  final LoggedSet? top; // heaviest set with a load
  final double? volumeKg; // Σ load × reps over loaded sets
  const ExerciseSession({
    required this.sessionId,
    required this.at,
    required this.sets,
    required this.reps,
    this.top,
    this.volumeKg,
  });

  double? get e1rm => oneRepMax(top);
}

/// Group `strength_set` rows of one exercise by session, oldest first.
List<ExerciseSession> exerciseSessionsFrom(List<Map<String, Object?>> rows) {
  final by = <String, List<Map<String, Object?>>>{};
  for (final r in rows) {
    final id = r['session_id'];
    if (id is String && id.isNotEmpty) (by[id] ??= []).add(r);
  }
  final out = <ExerciseSession>[];
  for (final e in by.entries) {
    var sets = 0, reps = 0, at = 0;
    LoggedSet? top;
    double? vol;
    for (final r in e.value) {
      final n = (r['reps'] as num?)?.toInt() ?? 0;
      final kg = (r['load_kg'] as num?)?.toDouble();
      final t = (r['at_ts'] as num?)?.toInt() ?? 0;
      if (t > at) at = t;
      sets++;
      reps += n;
      if (kg != null) {
        vol = (vol ?? 0) + kg * n;
        if (top == null ||
            kg > top.loadKg! ||
            (kg == top.loadKg && n > top.reps)) {
          top = LoggedSet(e.key, n,
              loadKg: kg,
              rpe: (r['rpe'] as num?)?.toInt(),
              at: DateTime.fromMillisecondsSinceEpoch(t * 1000));
        }
      }
    }
    out.add(ExerciseSession(
      sessionId: e.key,
      at: DateTime.fromMillisecondsSinceEpoch(at * 1000),
      sets: sets,
      reps: reps,
      top: top,
      volumeKg: vol,
    ));
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

class ExerciseProgressScreen extends StatefulWidget {
  final String exerciseKey;

  /// Preloaded sessions (gallery); null reads the database.
  final List<ExerciseSession>? sessions;
  const ExerciseProgressScreen(this.exerciseKey, {super.key, this.sessions});

  @override
  State<ExerciseProgressScreen> createState() => _ExerciseProgressScreenState();
}

class _ExerciseProgressScreenState extends State<ExerciseProgressScreen> {
  List<ExerciseSession>? _s;

  @override
  void initState() {
    super.initState();
    _s = widget.sessions;
    if (_s == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final rows = await LocalDb.recentSetsFor(widget.exerciseKey, limit: 600);
      if (mounted) setState(() => _s = exerciseSessionsFrom(rows));
    } catch (_) {
      if (mounted) setState(() => _s = const []);
    }
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final lang = Localizations.localeOf(c).languageCode;
    final name = exerciseByKey(widget.exerciseKey)?.labelFor(lang) ??
        widget.exerciseKey;
    return detailScaffold(
      c,
      name,
      [if (_s != null) ExerciseProgressBody(widget.exerciseKey, _s!)],
      sub: l?.exerciseProgressSub ?? 'Your own sets, session by session',
    );
  }
}

class ExerciseProgressBody extends StatelessWidget {
  final String exerciseKey;
  final List<ExerciseSession> sessions;
  const ExerciseProgressBody(this.exerciseKey, this.sessions, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    if (sessions.isEmpty) {
      return StatusCard(
        l?.exerciseProgressNoneTitle ?? 'Not logged yet',
        l?.exerciseProgressNoneBody ??
            'The first session you log here starts the record.',
        icon: LucideIcons.dumbbell,
      );
    }
    final loaded = [for (final s in sessions) if (s.e1rm != null) s];
    final best = loaded.isEmpty
        ? null
        : loaded.reduce((a, b) => (b.e1rm! > a.e1rm!) ? b : a);
    final latest = sessions.last;
    final e1 = [for (final s in sessions) s.e1rm];
    final maxE = loaded.isEmpty
        ? 0.0
        : loaded.map((s) => s.e1rm!).reduce((a, b) => a > b ? a : b);
    final axis = AxisSpec(
        min: 0, max: maxE <= 0 ? 1 : maxE * 1.1, format: (v) => '${v.round()}');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: _Stat(
                l?.exerciseProgressLatest ?? 'Latest',
                latest.top == null
                    ? (l?.exerciseProgressBodyweight ?? 'Bodyweight')
                    : '${_kg(latest.top!.loadKg!)} × ${latest.top!.reps}',
                formatDay(latest.at, l),
              ),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: _Stat(
                l?.exerciseProgressBest ?? 'Best 1RM estimate',
                best == null ? (l?.exerciseProgressNoLoad ?? 'No load logged') : '${best.e1rm!.round()} kg',
                best == null ? '' : formatDay(best.at, l),
              ),
            ),
          ]),
          if (loaded.length >= 2) ...[
            const SizedBox(height: S.x4),
            Text(l?.exerciseProgressChartTitle ?? '1RM estimate per session',
                style: F.cap.copyWith(color: p.ink2)),
            const SizedBox(height: S.x2),
            SizedBox(
              height: 120,
              child: CustomPaint(
                painter: Bars(e1, p.on(C.purple),
                    axis: axis, highlight: e1.length - 1),
              ),
            ),
            const SizedBox(height: S.x1),
            Row(children: [
              Text(formatDay(sessions.first.at, l),
                  style: F.over.copyWith(color: p.ink3)),
              const Spacer(),
              Text(formatDay(sessions.last.at, l),
                  style: F.over.copyWith(color: p.ink3)),
            ]),
          ],
          const SizedBox(height: S.x3),
          Text(
            l?.exerciseProgressEpley ??
                'Epley: load × (1 + reps ÷ 30), from the heaviest set of each '
                    'session. An estimate, never a lift you did.',
            style: F.over.copyWith(color: p.ink3),
          ),
        ]),
      ),
      const SizedBox(height: S.x3),
      Section(
        l?.exerciseProgressSessions ?? 'Sessions',
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(children: [
            for (final (i, s) in sessions.reversed.indexed) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x3),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(formatDay(s.at, l),
                              style: F.body.copyWith(color: p.ink)),
                          Text(
                            l?.exerciseProgressSetsReps(s.sets, s.reps) ??
                                '${s.sets} sets · ${s.reps} reps',
                            style: F.over.copyWith(color: p.ink3),
                          ),
                        ]),
                  ),
                  if (s.top != null)
                    Text('${_kg(s.top!.loadKg!)} × ${s.top!.reps}',
                        style: F.n17.copyWith(color: p.ink)),
                ]),
              ),
            ],
          ]),
        ),
      ),
    ]);
  }

  static String _kg(double v) =>
      v == v.roundToDouble() ? '${v.round()} kg' : '${v.toStringAsFixed(1)} kg';
}

class _Stat extends StatelessWidget {
  final String label, value, sub;
  const _Stat(this.label, this.value, this.sub);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: F.over.copyWith(color: p.ink3)),
      const SizedBox(height: S.x1),
      Text(value, style: F.n24.copyWith(color: p.ink)),
      if (sub.isNotEmpty) Text(sub, style: F.cap.copyWith(color: p.ink2)),
    ]);
  }
}
