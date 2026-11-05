// STRAIN FRONT — the top of the Activity tab, in the shape WHOOP's Strain
// page has: the day's strain as a ring on the 0-21 scale with the target
// range drawn on the ring, the day's activities under it, then time in
// zones and the two movement figures (steps, calories).
//
// Everything here is read, not computed: the strain and zones off the day's
// strain bundle (the same read DayStrainDetail does), the target off today's
// cross-day coach block, steps and calories off `getToday`, the activities
// off the sessions table. An absence is written, never filled.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/decimal_text.dart';
import '../../models/metric.dart';
import '../screens/home_screen.dart' show go, hm, metricOf, repoOf, thousands;
import '../screens/metric_detail.dart' show MetricDetail;
import '../ui2.dart';
import 'catalogue.dart';
import 'day_strain.dart';
import 'zones.dart' show ZonesDetail;

/// One of today's sessions, as the list prints it.
class StrainSession {
  final String type;
  final String? title;
  final int startTs;
  final double? durationMin, strain, avgHr;
  const StrainSession({
    required this.type,
    this.title,
    required this.startTs,
    this.durationMin,
    this.strain,
    this.avgHr,
  });
}

class StrainFrontData {
  final DayStrainData day;

  /// `{value, low, high, estimated}` off today's coach block, or null.
  final Map<String, dynamic>? target;
  final Metric steps, calories;
  final int stepGoal;
  final List<StrainSession> sessions;

  const StrainFrontData({
    this.day = const DayStrainData(),
    this.target,
    this.steps = Metric.empty,
    this.calories = Metric.empty,
    this.stepGoal = kDefaultStepGoal,
    this.sessions = const [],
  });

  static Future<StrainFrontData> load(LocalRepository repo) async {
    final label = todayLabel();
    final day = await DayStrainData.load(repo, forDay: label);
    final today = await repo.getToday();
    final daily = today['daily'];
    Object? d(String k) => daily is Map ? daily[k] : null;
    final coach = today['coach'];
    final target = coach is Map && coach['strain_target'] is Map
        ? (coach['strain_target'] as Map).cast<String, dynamic>()
        : null;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final rows = await repo.getSessions(
      from: midnight.millisecondsSinceEpoch ~/ 1000,
      to: now.millisecondsSinceEpoch ~/ 1000,
    );
    return StrainFrontData(
      day: day,
      target: target,
      steps: metricOf(d('steps')),
      calories: metricOf(d('calories')),
      stepGoal: (today['step_goal'] as num?)?.toInt() ?? kDefaultStepGoal,
      sessions: [
        for (final r in rows)
          if (r['start_ts'] is num)
            StrainSession(
              type: (r['type'] as String?) ?? 'other',
              title: r['title'] as String?,
              startTs: (r['start_ts'] as num).toInt(),
              durationMin: (r['duration_min'] as num?)?.toDouble(),
              strain: (r['strain'] as num?)?.toDouble(),
              avgHr: (r['avg_hr'] as num?)?.toDouble(),
            ),
      ],
    );
  }
}

/// Reads on open and again when a sync or a derive lands, like the tabs do.
class StrainFrontLoader extends StatefulWidget {
  final VoidCallback? onStart;
  const StrainFrontLoader({super.key, this.onStart});

  @override
  State<StrainFrontLoader> createState() => _StrainFrontLoaderState();
}

class _StrainFrontLoaderState extends State<StrainFrontLoader>
    with RevisionReload {
  StrainFrontData? _d;

  @override
  bool get revisionReloads => true;

  @override
  void reload() => _load();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      final d = await StrainFrontData.load(repo);
      if (mounted) setState(() => _d = d);
    } catch (_) {
      // A read that failed leaves the last good front, or nothing.
    }
  }

  @override
  Widget build(BuildContext c) {
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    return StrainFront(d, onStart: widget.onStart);
  }
}

class StrainFront extends StatelessWidget {
  final StrainFrontData data;
  final VoidCallback? onStart;
  const StrainFront(this.data, {super.key, this.onStart});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = data;
    final zones = d.day.zoneMin;
    final zoneTotal = zones?.fold<int>(0, (a, b) => a + b) ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _RingCard(d),
      const SizedBox(height: S.x3),
      _MoveRow(d),
      if (d.sessions.isNotEmpty) ...[
        const SizedBox(height: S.x5),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: S.x1),
          child: Text(l?.strainFrontToday ?? "Today's activities",
              style: F.t2.copyWith(color: p.ink)),
        ),
        const SizedBox(height: S.x3),
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x1),
          child: Column(children: [
            for (final (i, s) in d.sessions.indexed) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              _SessionRow(s),
            ],
          ]),
        ),
      ],
      if (zones != null && zoneTotal > 0) ...[
        const SizedBox(height: S.x5),
        Section(
          l?.dayStrainTimeInZonesSection ?? 'Time in zones',
          Surface(
            child: ZoneRows(
              [for (final v in zones) v.toDouble()],
              lowerBpm: d.day.zoneLowerBpm,
              footnote: zonesWhy(d.day.zoneSource, d.day.zoneMaxHr, l),
            ),
          ),
          action: l?.dayStrainHowSet ?? 'How these are set',
          onAction: () => go(c, const ZonesDetail()),
        ),
      ],
    ]);
  }
}

class _RingCard extends StatelessWidget {
  final StrainFrontData d;
  const _RingCard(this.d);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final strain = d.day.strain;
    final t = d.target;
    final lo = (t?['low'] as num?)?.toDouble();
    final hi = (t?['high'] as num?)?.toDouble();
    final side = bigText(c) ? 200.0 : 236.0;
    final color = p.on(C.purple);
    String? targetLine;
    if (lo != null && hi != null) {
      final met = strain != null && strain >= lo;
      final over = strain != null && strain > hi;
      targetLine = over
          ? (l?.strainFrontOverTarget(displayFixed(hi, 1)) ??
              'Past the ${displayFixed(hi, 1)} your recovery suggested')
          : met
              ? (l?.strainFrontInTarget ?? 'Inside your target for today')
              : (l?.strainFrontTarget(displayFixed(lo, 1), displayFixed(hi, 1)) ??
                  'Target ${displayFixed(lo, 1)}–${displayFixed(hi, 1)} from your recovery');
    }
    return Surface(
      onTap: () => go(c, const DayStrainDetail()),
      child: Column(children: [
        SizedBox(
          width: side,
          height: side,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _StrainRingPainter(
                  frac: strain == null ? 0 : (strain / 21).clamp(0.0, 1.0).toDouble(),
                  bandLo: lo == null ? null : (lo / 21).clamp(0.0, 1.0).toDouble(),
                  bandHi: hi == null ? null : (hi / 21).clamp(0.0, 1.0).toDouble(),
                  color: color,
                  band: p.wash(C.purple, strength: 2),
                  track: p.track,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(S.x8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: side - 2 * S.x8,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      strain == null ? '—' : displayFixed(strain, 1),
                      textAlign: TextAlign.center,
                      style: F.n64.copyWith(color: strain == null ? p.ink3 : p.ink),
                    ),
                    Text(l?.strainFrontDayStrain ?? 'Day strain',
                        textAlign: TextAlign.center,
                        style: F.cap.copyWith(color: p.ink2)),
                    if (strain == null && d.day.note != null)
                      Text(d.day.note!,
                          textAlign: TextAlign.center,
                          style: F.over.copyWith(color: p.ink3)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: S.x2),
        if (targetLine != null)
          Text(targetLine,
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink2))
        else
          Text(l?.strainFrontNoTarget ?? 'A target appears once recovery is scored',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink3)),
        if (t?['estimated'] == true)
          Text(l?.wearableEstimated ?? 'Estimated',
              style: F.over.copyWith(color: p.ink3)),
      ]),
    );
  }
}

/// The 0-21 ring: the track, the target band drawn under the arc, the arc.
class _StrainRingPainter extends CustomPainter {
  final double frac;
  final double? bandLo, bandHi;
  final Color color, band, track;
  const _StrainRingPainter({
    required this.frac,
    required this.bandLo,
    required this.bandHi,
    required this.color,
    required this.band,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * .06;
    final r = size.shortestSide / 2 - stroke;
    final centre = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: centre, radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(centre, r, paint..color = track);
    if (bandLo != null && bandHi != null && bandHi! > bandLo!) {
      canvas.drawArc(rect, -math.pi / 2 + 2 * math.pi * bandLo!,
          2 * math.pi * (bandHi! - bandLo!), false, paint..color = band);
    }
    if (frac > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * frac, false,
          paint
            ..color = color
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_StrainRingPainter o) =>
      o.frac != frac || o.bandLo != bandLo || o.bandHi != bandHi || o.color != color;
}

/// Steps and calories, side by side, each a door.
class _MoveRow extends StatelessWidget {
  final StrainFrontData d;
  const _MoveRow(this.d);

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final steps = d.steps.value;
    final cal = d.calories.value;
    final tiles = [
      _MoveTile(
        icon: LucideIcons.footprints,
        color: C.green,
        name: l?.homeSteps ?? 'Steps',
        value: steps == null ? '—' : thousands(steps),
        sub: steps == null
            ? (l?.strainFrontNotYet ?? 'Not measured yet')
            : (l?.strainFrontOfGoal(thousands(d.stepGoal)) ?? 'of ${thousands(d.stepGoal)}'),
        frac: steps == null ? null : (steps / d.stepGoal).clamp(0.0, 1.0).toDouble(),
        onTap: () => go(c, const MetricDetail('steps')),
      ),
      _MoveTile(
        icon: LucideIcons.flame,
        color: C.orange,
        name: l?.workoutCaloriesStatLabel ?? 'Calories',
        value: cal == null ? '—' : thousands(cal),
        sub: cal == null
            ? (l?.strainFrontNotYet ?? 'Not measured yet')
            : (l?.strainFrontActiveKcal ?? 'active, kcal'),
        onTap: () => go(c, const MetricDetail('calories')),
      ),
    ];
    if (bigText(c)) {
      return Column(children: [
        for (final (i, t) in tiles.indexed) ...[
          if (i > 0) const SizedBox(height: S.x3),
          t,
        ],
      ]);
    }
    return Row(children: [
      for (final (i, t) in tiles.indexed) ...[
        if (i > 0) const SizedBox(width: S.x3),
        Expanded(child: t),
      ],
    ]);
  }
}

class _MoveTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name, value, sub;
  final double? frac;
  final VoidCallback onTap;
  const _MoveTile({
    required this.icon,
    required this.color,
    required this.name,
    required this.value,
    required this.sub,
    required this.onTap,
    this.frac,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: p.on(color)),
          const SizedBox(width: S.x2),
          Expanded(child: Text(name, style: F.cap.copyWith(color: p.ink2))),
        ]),
        const SizedBox(height: S.x2),
        Text(value, style: F.n24.copyWith(color: p.ink)),
        const SizedBox(height: S.x1),
        Text(sub, style: F.over.copyWith(color: p.ink3)),
        if (frac != null) ...[
          const SizedBox(height: S.x2),
          ClipRRect(
            borderRadius: R.rPill,
            child: LinearProgressIndicator(
              value: frac,
              minHeight: S.x1,
              backgroundColor: p.track,
              color: p.on(color),
            ),
          ),
        ],
      ]),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final StrainSession s;
  const _SessionRow(this.s);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final a = activityByName(s.type);
    final name = s.title ?? a?.displayName(c) ?? s.type;
    final when = TimeOfDay.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch(s.startTs * 1000))
        .format(c);
    final parts = <String>[
      when,
      if (s.durationMin != null) hm(s.durationMin),
      if (s.avgHr != null) '${s.avgHr!.round()} bpm',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Icon(a?.icon ?? LucideIcons.activity, size: 20, color: p.on(C.purple)),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            Text(parts.join(' · '), style: F.over.copyWith(color: p.ink3)),
          ]),
        ),
        const SizedBox(width: S.x3),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(s.strain == null ? '—' : displayFixed(s.strain!, 1),
              style: F.n17.copyWith(color: p.ink)),
          Text(l?.homeRingStrain ?? 'Strain', style: F.over.copyWith(color: p.ink3)),
        ]),
      ]),
    );
  }
}
