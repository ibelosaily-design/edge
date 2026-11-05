// SLEEP FRONT — the top of the Sleep tab, in the shape WHOOP's Sleep page
// has: one ring, four lines under it, then the night itself (the heart-rate
// trace with the stage bars under it), then one card per line, then the
// week as columns.
//
// Where this differs from WHOOP's page, it differs on purpose:
//   * the ring carries the hours slept against the need, not only the
//     percentage — the percentage is a ratio of two numbers, and the two
//     numbers are what you act on;
//   * every line says WHY its figure is what it is in one short sub-line;
//   * a stage bar carries the night's own uncertainty: the staged minutes are
//     an estimate with a width (`stageIntervals`), and the width is drawn;
//   * the need is this user's learned need, and until that exists the ring
//     reads against the age-band guideline — labelled as the guideline, never
//     presented as a measurement.
//
// Everything drawn here comes off [SleepData]; nothing is computed for the
// first time on this screen except ratios of its own fields.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;

import '../../l10n/app_localizations.dart';
import '../ui2.dart';
import 'home_screen.dart' show clockOfTs, hm, weekdayShortName;
import 'sleep_detail.dart';

/// The three-step verdict WHOOP's lines carry: poor / sufficient / optimal.
enum SleepBand { poor, fair, optimal }

Color bandColor(P p, SleepBand b) => switch (b) {
      SleepBand.poor => p.on(C.orange),
      SleepBand.fair => p.ink3,
      SleepBand.optimal => p.on(C.green),
    };

/// WHOOP's own cut-offs where it publishes them (performance 85 / 70,
/// consistency 80 / 60, efficiency 90 / 85); the restorative share is this
/// app's (deep + REM of sleep: 45 / 35, the middle of the adult ranges).
SleepBand bandOfPerformance(double frac) =>
    frac >= .85 ? SleepBand.optimal : (frac >= .70 ? SleepBand.fair : SleepBand.poor);
SleepBand bandOfConsistency(num sri) =>
    sri >= 80 ? SleepBand.optimal : (sri >= 60 ? SleepBand.fair : SleepBand.poor);
SleepBand bandOfEfficiency(double frac) =>
    frac >= .90 ? SleepBand.optimal : (frac >= .85 ? SleepBand.fair : SleepBand.poor);
SleepBand bandOfRestorative(double frac) =>
    frac >= .45 ? SleepBand.optimal : (frac >= .35 ? SleepBand.fair : SleepBand.poor);

/// The sleep guideline for an age band, minutes — the National Sleep
/// Foundation's recommended range, read at its lower bound plus half an hour
/// so it sits inside the band rather than on its edge: 14-17 → 8:30, 18-64 →
/// 7:30, 65+ → 7:30. A guideline, not a need; the screen names it as one.
int? guidelineSleepMin(int? age) {
  if (age == null) return null;
  if (age < 18) return 8 * 60 + 30;
  return 7 * 60 + 30;
}

/// The typical adult share of each stage, as a fraction of time asleep
/// (awake: of time in bed). Population ranges from the sleep-medicine
/// literature, drawn as the hatched band under each bar.
(double, double) typicalStageShare(SleepStage s) => switch (s) {
      SleepStage.awake => (0, .10),
      SleepStage.light => (.45, .60),
      SleepStage.deep => (.15, .25),
      SleepStage.rem => (.20, .25),
    };

/// What the ring reads against: the learned need when there is one, else
/// the age guideline, else nothing.
({int min, bool learned})? sleepTarget(SleepData d) {
  final need = d.isLatestNight ? d.need.value : null;
  if (need != null && need > 0) return (min: need.round(), learned: true);
  final g = guidelineSleepMin(d.age);
  if (g != null) return (min: g, learned: false);
  return null;
}

class SleepFront extends StatelessWidget {
  final SleepData data;
  const SleepFront(this.data, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = data;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _RingCard(d),
      const SizedBox(height: S.x5),
      Padding(
        padding: const EdgeInsetsDirectional.only(start: S.x1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l?.sleepFrontLastNight ?? 'Last night',
              style: F.t2.copyWith(color: p.ink)),
          Text(
            d.tstHistory.isEmpty
                ? (l?.sleepFrontFirstNight ??
                    'First night — nothing to compare it with yet')
                : (l?.sleepFrontVsNights(d.tstHistory.length) ??
                    'Against your last ${d.tstHistory.length} nights'),
            style: F.cap.copyWith(color: p.ink3),
          ),
        ]),
      ),
      const SizedBox(height: S.x3),
      _NightCard(d),
      const SizedBox(height: S.x3),
      _HoursCard(d),
      const SizedBox(height: S.x3),
      _EfficiencyCard(d),
      if (d.trend.isNotEmpty) ...[
        const SizedBox(height: S.x5),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: S.x1),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l?.sleepFrontTrends ?? 'This week',
                style: F.t2.copyWith(color: p.ink)),
            Text(l?.sleepFrontTrendsSub ?? 'Tap a column to open that night',
                style: F.cap.copyWith(color: p.ink3)),
          ]),
        ),
        const SizedBox(height: S.x3),
        _TrendsCard(d),
      ],
    ]);
  }
}

// ── 1 · the ring and the four lines ────────────────────────────────────────

class _RingCard extends StatelessWidget {
  final SleepData d;
  const _RingCard(this.d);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final n = d.night;
    final tst = (n['duration_min'] as num?)?.toDouble();
    final target = sleepTarget(d);
    final perf = (tst == null || target == null) ? null : tst / target.min;
    final eff = (n['efficiency'] as num?)?.toDouble();
    final inBed = (n['in_bed_min'] as num?)?.toDouble();
    final awake = (n['awake_min'] as num?)?.toDouble();
    final deep = (n['deep_min'] as num?)?.toDouble();
    final rem = (n['rem_min'] as num?)?.toDouble();
    final restorative =
        (tst == null || tst <= 0 || deep == null) ? null : (deep + (rem ?? 0)) / tst;
    final sri = d.regularity.value;
    final sriNights = d.regularity.needMoreNights;

    final ringColor = perf == null
        ? p.ink3
        : bandColor(p, bandOfPerformance(perf));
    final rows = <Widget>[
      _Line(
        icon: LucideIcons.clock3,
        name: l?.sleepFrontHoursVsNeed ?? 'Hours vs need',
        sub: perf == null
            ? (tst == null
                ? (l?.sleepFrontNoNight ?? 'No night scored')
                : (l?.sleepFrontNoTarget ??
                    'Set your age in Profile for a target'))
            : tst! >= target!.min
                ? (l?.sleepFrontMetTarget ?? 'Need met')
                : (target.learned
                    ? (l?.sleepFrontShortOfNeed(hm(target.min - tst)) ??
                        '${hm(target.min - tst)} short of your need')
                    : (l?.sleepFrontShortOfGuideline(hm(target.min - tst)) ??
                        '${hm(target.min - tst)} short of the guideline for your age')),
        band: perf == null ? null : bandOfPerformance(perf),
        value: perf == null ? null : _pct(perf),
      ),
      _Line(
        icon: LucideIcons.calendarCheck,
        name: l?.sleepFrontConsistency ?? 'Sleep consistency',
        sub: sri == null
            ? (l?.sleepFrontConsistencyHow ?? 'How alike your bed and wake times are')
            : (l?.sleepFrontConsistencyOf ?? 'Bed and wake times, night to night'),
        band: sri == null ? null : bandOfConsistency(sri),
        value: sri == null ? null : '${sri.round()}%',
        pending: sri == null && sriNights != null
            ? (l?.sleepFrontNightsLeft(sriNights) ?? '$sriNights nights to go')
            : null,
      ),
      _Line(
        icon: LucideIcons.bedDouble,
        name: l?.sleepFrontEfficiency ?? 'Sleep efficiency',
        sub: (awake != null && inBed != null)
            ? (l?.sleepFrontAwakeOfBed(hm(awake), hm(inBed)) ??
                '${hm(awake)} awake of ${hm(inBed)} in bed')
            : (l?.sleepFrontEfficiencyHow ?? 'Time asleep of time in bed'),
        band: eff == null ? null : bandOfEfficiency(eff),
        value: eff == null ? null : _pct(eff),
      ),
      _Line(
        icon: LucideIcons.sparkles,
        name: l?.sleepFrontRestorative ?? 'Restorative sleep',
        sub: l?.sleepFrontRestorativeHow ?? 'Deep and REM, of all sleep',
        band: restorative == null ? null : bandOfRestorative(restorative),
        value: restorative == null ? null : _pct(restorative),
      ),
    ];

    return Surface(
      child: Column(children: [
        _Ring(
          frac: perf,
          color: ringColor,
          label: l?.sleepFrontPerformance ?? 'Sleep performance',
          big: perf == null ? '—' : _pct(perf),
          under: tst == null
              ? ''
              : target == null
                  ? hm(tst)
                  : '${hm(tst)} / ${hm(target.min)}',
          underNote: target != null && !target.learned
              ? (l?.sleepFrontGuidelineNote ?? 'age guideline, not yet your need')
              : null,
          band: perf == null ? null : bandOfPerformance(perf),
        ),
        const SizedBox(height: S.x2),
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) Divider(color: p.line, height: 1),
          r,
        ],
        const SizedBox(height: S.x3),
        _Legend(),
      ]),
    );
  }
}

String _pct(double frac) => '${(frac * 100).round()}%';

class _Ring extends StatelessWidget {
  final double? frac;
  final Color color;
  final String label, big, under;
  final String? underNote;
  final SleepBand? band;
  const _Ring({
    required this.frac,
    required this.color,
    required this.label,
    required this.big,
    required this.under,
    this.underNote,
    this.band,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final side = bigText(c) ? 200.0 : 236.0;
    return SizedBox(
      width: side,
      height: side,
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _RingPainter(
              frac: (frac ?? 0).clamp(0.0, 1.0).toDouble(),
              color: color,
              track: p.track,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(S.x8),
          // Scaled down as one block when large text outgrows the ring, so
          // the figure, its label and the hours never spill over the arc.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: side - 2 * S.x8,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(big,
                    textAlign: TextAlign.center,
                    style: F.n64.copyWith(color: p.ink)),
                Text(label,
                    textAlign: TextAlign.center,
                    style: F.cap.copyWith(color: p.ink2)),
                if (under.isNotEmpty) ...[
                  const SizedBox(height: S.x1),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(under,
                        textAlign: TextAlign.center,
                        style: F.n17.copyWith(color: p.on(C.domSleep))),
                  ),
                ],
                if (underNote != null)
                  Text(underNote!,
                      textAlign: TextAlign.center,
                      style: F.over.copyWith(color: p.ink3)),
                if (band != null) ...[
                  const SizedBox(height: S.x2),
                  _Seg3(band!, compact: true),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double frac;
  final Color color, track;
  const _RingPainter({required this.frac, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * .06;
    final r = size.shortestSide / 2 - stroke;
    final centre = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(centre, r, paint..color = track);
    if (frac > 0) {
      canvas.drawArc(Rect.fromCircle(center: centre, radius: r), -math.pi / 2,
          2 * math.pi * frac, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.frac != frac || o.color != color || o.track != track;
}

/// The three-step indicator: one lit segment for the band.
class _Seg3 extends StatelessWidget {
  final SleepBand band;
  final bool compact;
  const _Seg3(this.band, {this.compact = false});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final w = compact ? S.x5 : S.x6;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final b in SleepBand.values) ...[
        if (b != SleepBand.poor) const SizedBox(width: 3),
        Container(
          width: w,
          height: S.x1,
          decoration: BoxDecoration(
            color: b == band ? bandColor(p, b) : p.track,
            borderRadius: R.rPill,
          ),
        ),
      ],
    ]);
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String name, sub;
  final SleepBand? band;
  final String? value, pending;
  const _Line({
    required this.icon,
    required this.name,
    required this.sub,
    required this.band,
    required this.value,
    this.pending,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
        Text(sub, style: F.over.copyWith(color: p.ink3)),
      ],
    );
    final right = value != null
        ? Text(value!, style: F.n24.copyWith(color: p.ink))
        : Text(pending ?? '—', style: F.cap.copyWith(color: p.ink3));
    final seg = band == null ? _Seg3Empty() : _Seg3(band!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: bigText(c)
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: p.ink2),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: S.x2),
                    Wrap(
                      spacing: S.x3,
                      runSpacing: S.x1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [seg, right],
                    ),
                  ],
                ),
              ),
            ])
          : Row(children: [
              Icon(icon, size: 20, color: p.ink2),
              const SizedBox(width: S.x3),
              Expanded(child: title),
              const SizedBox(width: S.x3),
              seg,
              const SizedBox(width: S.x3),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: S.x12),
                child: Align(
                    alignment: AlignmentDirectional.centerEnd, child: right),
              ),
            ]),
    );
  }
}

class _Seg3Empty extends StatelessWidget {
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        Container(
          width: S.x6,
          height: S.x1,
          decoration: BoxDecoration(color: p.track, borderRadius: R.rPill),
        ),
      ],
    ]);
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    Widget item(SleepBand b, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: S.x4,
            height: S.x1,
            decoration: BoxDecoration(color: bandColor(p, b), borderRadius: R.rPill),
          ),
          const SizedBox(width: S.x2),
          Text(t, style: F.cap.copyWith(color: p.ink2)),
        ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: S.x5,
        runSpacing: S.x1,
        children: [
          item(SleepBand.poor, l?.sleepFrontBandPoor ?? 'Poor'),
          item(SleepBand.fair, l?.sleepFrontBandFair ?? 'Sufficient'),
          item(SleepBand.optimal, l?.sleepFrontBandOptimal ?? 'Optimal'),
        ],
      ),
    );
  }
}

// ── 2 · the night: heart rate over it, stages under it ─────────────────────

class _NightCard extends StatelessWidget {
  final SleepData d;
  const _NightCard(this.d);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final n = d.night;
    final tst = (n['duration_min'] as num?)?.toDouble();
    final inBed = (n['in_bed_min'] as num?)?.toDouble();
    final onset = (n['onset_ts'] as num?)?.round();
    final wake = (n['wake_ts'] as num?)?.round();
    final hr = _stamped(d.timeline['hr']);
    final cols = Hypnogram.cols(p);
    final ranges = n['sleep_source'] == 'vendor_staged' ? null : sleepStageRanges(n);
    final deep = (n['deep_min'] as num?)?.toDouble();
    final rem = (n['rem_min'] as num?)?.toDouble();
    final light = (n['light_min'] as num?)?.toDouble();
    final awake = (n['awake_min'] as num?)?.toDouble();
    final restorative = deep == null ? null : deep + (rem ?? 0);

    Widget stage(SleepStage s, double? min, double? of, (int, int)? range) {
      if (min == null || of == null || of <= 0) return const SizedBox.shrink();
      final frac = (min / of).clamp(0.0, 1.0).toDouble();
      final (tLo, tHi) = typicalStageShare(s);
      return Padding(
        padding: const EdgeInsets.only(top: S.x3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: S.x4,
              height: S.x4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cols[s]!, width: 2),
              ),
            ),
            const SizedBox(width: S.x2),
            Expanded(
              flex: 3,
              child: Text(s.label(l),
                  style: F.body.copyWith(color: p.ink)),
            ),
            const SizedBox(width: S.x2),
            Flexible(
              flex: 2,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: S.x3,
                children: [
                  Text(_pct(frac),
                      style: F.cap.copyWith(
                          color: cols[s]!, fontWeight: FontWeight.w700)),
                  Text(
                    range == null ? hm(min) : '≈${hm(min)}',
                    style: F.n17.copyWith(color: p.ink),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: S.x2),
          SizedBox(
            height: S.x4,
            child: CustomPaint(
              painter: _StageBarPainter(
                frac: frac,
                color: cols[s]!,
                hatch: p.line,
                base: p.card2,
                marker: p.ink3,
                typicalLo: tLo,
                typicalHi: tHi,
                rangeLo: range == null ? null : (range.$1 / 60 / of).clamp(0.0, 1.0).toDouble(),
                rangeHi: range == null ? null : (range.$2 / 60 / of).clamp(0.0, 1.0).toDouble(),
                rtl: Directionality.of(c) == TextDirection.rtl,
              ),
            ),
          ),
          if (range != null)
            Padding(
              padding: const EdgeInsets.only(top: S.x1),
              child: Text(
                l?.sleepFrontStageRange('${hm(range.$1 / 60)}–${hm(range.$2 / 60)}') ??
                    'Likely ${hm(range.$1 / 60)}–${hm(range.$2 / 60)}',
                style: F.over.copyWith(color: p.ink3),
              ),
            ),
        ]),
      );
    }

    (int, int)? secs(ana.StageInterval? i) {
      if (i == null) return null;
      final lo = i.loSec.round(), hi = i.hiSec.round();
      return lo <= hi ? (lo, hi) : null;
    }

    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(l?.sleepFrontHoursOfSleep ?? 'Hours of sleep',
                style: F.head.copyWith(color: p.ink)),
          ),
          const SizedBox(width: S.x3),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(hm(tst),
                  textAlign: TextAlign.end,
                  style: F.n34.copyWith(color: p.ink)),
              if (onset != null && wake != null)
                Text(
                  l?.sleepFrontFromTo(clockOfTs(onset), clockOfTs(wake)) ??
                      '${clockOfTs(onset)} to ${clockOfTs(wake)}',
                  textAlign: TextAlign.end,
                  style: F.cap.copyWith(color: p.ink3),
                ),
            ]),
          ),
        ]),
        if (hr.length >= 2 && onset != null && wake != null && wake > onset) ...[
          const SizedBox(height: S.x3),
          SizedBox(
            height: bigText(c) ? 120 : 150,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: CustomPaint(
                painter: _NightHrPainter(
                  points: hr,
                  t0: onset,
                  t1: wake,
                  line: p.on(C.domSleep),
                  fill: p.wash(C.domSleep),
                  grid: p.line,
                  ink: p.ink3,
                  labelStyle: F.over.copyWith(color: p.ink3),
                  startLabel: clockOfTs(onset),
                  endLabel: clockOfTs(wake),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: S.x3),
        Divider(color: p.line, height: 1),
        const SizedBox(height: S.x2),
        Row(children: [
          Container(
            width: S.x4,
            height: S.x3,
            decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(l?.sleepFrontTypicalRange ?? 'Typical adult range',
                style: F.over.copyWith(color: p.ink3)),
          ),
          if (inBed != null) ...[
            const SizedBox(width: S.x2),
            Flexible(
              child: Text(l?.sleepFrontInBed(hm(inBed)) ?? 'In bed ${hm(inBed)}',
                  textAlign: TextAlign.end,
                  style: F.over.copyWith(color: p.ink3)),
            ),
          ],
        ]),
        stage(SleepStage.awake, awake, inBed, null),
        stage(SleepStage.light, light, tst, secs(ranges?.light)),
        stage(SleepStage.deep, deep, tst, secs(ranges?.deep)),
        if (rem != null) stage(SleepStage.rem, rem, tst, secs(ranges?.rem)),
        if (restorative != null && tst != null && tst > 0) ...[
          const SizedBox(height: S.x3),
          Divider(color: p.line, height: 1),
          const SizedBox(height: S.x3),
          Row(children: [
            Container(
              width: S.x3,
              height: S.x3,
              decoration: BoxDecoration(
                borderRadius: R.rSm,
                gradient: LinearGradient(
                  colors: [cols[SleepStage.deep]!, cols[SleepStage.rem]!],
                ),
              ),
            ),
            const SizedBox(width: S.x2),
            Expanded(
              flex: 3,
              child: Text(l?.sleepFrontRestorative ?? 'Restorative sleep',
                  style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: S.x2),
            Flexible(
              flex: 2,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: S.x3,
                children: [
                  Text(_pct(restorative / tst), style: F.cap.copyWith(color: p.ink3)),
                  Text(hm(restorative), style: F.n24.copyWith(color: p.ink)),
                ],
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

List<(int, double)> _stamped(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is Map && e['v'] is num && e['t'] is num)
        ((e['t'] as num).round(), (e['v'] as num).toDouble()),
  ];
}

/// Heart rate across the night: the trace, a soft fill under it, light
/// gridlines at round values, dashed edges at onset and wake, and the two
/// clock labels. Time runs left to right whatever the text direction — the
/// caller wraps this in LTR.
class _NightHrPainter extends CustomPainter {
  final List<(int, double)> points;
  final int t0, t1;
  final Color line, fill, grid, ink;
  final TextStyle labelStyle;
  final String startLabel, endLabel;
  const _NightHrPainter({
    required this.points,
    required this.t0,
    required this.t1,
    required this.line,
    required this.fill,
    required this.grid,
    required this.ink,
    required this.labelStyle,
    required this.startLabel,
    required this.endLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const axisW = 28.0, labelH = 18.0, pad = 6.0;
    final plot = Rect.fromLTWH(axisW, pad, size.width - axisW - pad, size.height - labelH - pad);
    final inWin = [for (final p in points) if (p.$1 >= t0 && p.$1 <= t1) p];
    if (inWin.length < 2) return;
    var lo = inWin.map((e) => e.$2).reduce(math.min);
    var hi = inWin.map((e) => e.$2).reduce(math.max);
    // Round the axis out to tens with a little headroom.
    lo = (lo / 10).floor() * 10.0 - 10;
    hi = (hi / 10).ceil() * 10.0 + 10;
    if (hi - lo < 30) hi = lo + 30;
    double x(int t) => plot.left + plot.width * (t - t0) / (t1 - t0);
    double y(double v) => plot.bottom - plot.height * (v - lo) / (hi - lo);

    final gridPaint = Paint()..color = grid..strokeWidth = 1;
    final step = (hi - lo) / 20 > 5 ? 20.0 : 10.0;
    for (var v = lo + step; v < hi; v += step) {
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: v.round().toString(), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y(v) - tp.height / 2));
    }

    final path = Path()..moveTo(x(inWin.first.$1), y(inWin.first.$2));
    for (final (t, v) in inWin.skip(1)) {
      path.lineTo(x(t), y(v));
    }
    final area = Path.from(path)
      ..lineTo(x(inWin.last.$1), plot.bottom)
      ..lineTo(x(inWin.first.$1), plot.bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );

    // Dashed edges.
    final dash = Paint()..color = ink..strokeWidth = 1;
    for (final edge in [plot.left, plot.right]) {
      for (var yy = plot.top; yy < plot.bottom; yy += 6) {
        canvas.drawLine(Offset(edge, yy), Offset(edge, math.min(yy + 3, plot.bottom)), dash);
      }
    }
    final s = TextPainter(
      text: TextSpan(text: startLabel, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    s.paint(canvas, Offset(plot.left, size.height - s.height));
    final e = TextPainter(
      text: TextSpan(text: endLabel, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    e.paint(canvas, Offset(plot.right - e.width, size.height - e.height));
  }

  @override
  bool shouldRepaint(_NightHrPainter o) =>
      o.points != points || o.t0 != t0 || o.t1 != t1 || o.line != line;
}

/// A stage bar: hatched track, the stage's share filled from the start side,
/// the night's own likely range as a lighter band over the fill edge, and the
/// typical population range as two dashed ticks.
class _StageBarPainter extends CustomPainter {
  final double frac;
  final Color color, hatch, base, marker;
  final double typicalLo, typicalHi;
  final double? rangeLo, rangeHi;
  final bool rtl;
  const _StageBarPainter({
    required this.frac,
    required this.color,
    required this.hatch,
    required this.base,
    required this.marker,
    required this.typicalLo,
    required this.typicalHi,
    required this.rangeLo,
    required this.rangeHi,
    required this.rtl,
  });

  double _x(double f, Size s) => rtl ? s.width * (1 - f) : s.width * f;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(R.sm));
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final hp = Paint()..color = hatch..strokeWidth = 1.5;
    for (var x = -size.height; x < size.width + size.height; x += 7) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), hp);
    }
    // The fill, from the start side.
    final a = _x(0, size), b = _x(frac, size);
    canvas.drawRect(Rect.fromLTRB(math.min(a, b), 0, math.max(a, b), size.height),
        Paint()..color = color);
    // The night's own range, as a translucent band around the fill edge.
    if (rangeLo != null && rangeHi != null && rangeHi! > rangeLo!) {
      final ra = _x(rangeLo!, size), rb = _x(rangeHi!, size);
      canvas.drawRect(Rect.fromLTRB(math.min(ra, rb), 0, math.max(ra, rb), size.height),
          Paint()..color = color.withValues(alpha: .35));
    }
    canvas.restore();
    // Typical range ticks, outside the clip so they can overhang.
    final mp = Paint()..color = marker..strokeWidth = 1.5;
    for (final f in [typicalLo, typicalHi]) {
      final x = _x(f, size);
      for (var yy = -2.0; yy < size.height + 2; yy += 4) {
        canvas.drawLine(Offset(x, yy), Offset(x, math.min(yy + 2, size.height + 2)), mp);
      }
    }
  }

  @override
  bool shouldRepaint(_StageBarPainter o) =>
      o.frac != frac ||
      o.color != color ||
      o.rangeLo != rangeLo ||
      o.rangeHi != rangeHi ||
      o.rtl != rtl;
}

// ── 3 · hours against the need ─────────────────────────────────────────────

class _HoursCard extends StatelessWidget {
  final SleepData d;
  const _HoursCard(this.d);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final n = d.night;
    final tst = (n['duration_min'] as num?)?.toDouble();
    final target = sleepTarget(d);
    if (tst == null || target == null) return const SizedBox.shrink();
    final frac = (tst / target.min).clamp(0.0, 1.0).toDouble();
    final debt = d.isLatestNight ? d.debt.value : null;
    final guideline = guidelineSleepMin(d.age);
    final gap = target.min - tst;
    final wake = (n['wake_ts'] as num?)?.round();
    // The bedtime that closes the gap: the night's own wake time, the target
    // earlier. Only when there is a gap and a wake time to count back from.
    String? bedtimeHint;
    if (gap > 0 && wake != null) {
      final bed = wake - (target.min * 60).round();
      bedtimeHint = clockOfTs(bed);
    }

    Widget bar(double f, Color col, {bool outline = false}) => Container(
          height: S.x8,
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: f,
            child: Container(
              decoration: BoxDecoration(
                color: outline ? null : col,
                border: outline ? Border.all(color: p.line) : null,
                borderRadius: R.rMd,
              ),
            ),
          ),
        );
    Widget lab(String t, String v) => Row(children: [
          Expanded(child: Text(t, style: F.cap.copyWith(color: p.ink2))),
          const SizedBox(width: S.x2),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.end,
                style: F.n17.copyWith(color: p.ink)),
          ),
        ]);

    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(l?.sleepFrontHoursVsNeed ?? 'Hours vs need',
                style: F.head.copyWith(color: p.ink)),
          ),
          const SizedBox(width: S.x3),
          Flexible(
            child: Text(_pct(tst / target.min),
                textAlign: TextAlign.end,
                style: F.n34.copyWith(color: p.ink)),
          ),
        ]),
        const SizedBox(height: S.x4),
        lab(l?.sleepFrontHoursOfSleep ?? 'Hours of sleep', hm(tst)),
        const SizedBox(height: S.x2),
        bar(frac, p.on(C.domSleep)),
        const SizedBox(height: S.x2),
        bar(1, p.card2, outline: true),
        const SizedBox(height: S.x2),
        lab(
          target.learned
              ? (l?.sleepFrontYourNeed ?? 'Your sleep need')
              : (l?.sleepFrontGuidelineForAge ?? 'Guideline for your age'),
          hm(target.min),
        ),
        const SizedBox(height: S.x3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
          child: Column(children: [
            if (guideline != null)
              _Part(l?.sleepFrontGuidelineForAge ?? 'Guideline for your age',
                  hm(guideline), p.ink3),
            if (target.learned)
              _Part(l?.sleepFrontLearnedNeed ?? 'Learned from your nights',
                  hm(target.min), p.on(C.domSleep)),
            if (debt != null)
              _Part(l?.sleepFrontDebt ?? 'Sleep debt carried', hm(debt),
                  p.on(C.orange)),
          ]),
        ),
        if (gap > 0) ...[
          const SizedBox(height: S.x3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
            decoration: BoxDecoration(
              color: p.wash(C.domSleep),
              borderRadius: R.rMd,
            ),
            child: Text(
              bedtimeHint == null
                  ? (l?.sleepFrontGapOnly(hm(gap)) ?? '${hm(gap)} short.')
                  : (l?.sleepFrontGapHint(hm(gap), bedtimeHint, clockOfTs(wake)) ??
                      '${hm(gap)} short. Asleep by $bedtimeHint, up at ${clockOfTs(wake)} as usual, closes it.'),
              style: F.cap.copyWith(color: p.on(C.domSleep)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Part extends StatelessWidget {
  final String name, value;
  final Color color;
  const _Part(this.name, this.value, this.color);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x1),
      child: Row(children: [
        Container(
          width: S.x2,
          height: S.x2,
          decoration: BoxDecoration(color: color, borderRadius: R.rSm),
        ),
        const SizedBox(width: S.x2),
        Expanded(child: Text(name, style: F.cap.copyWith(color: p.ink2))),
        const SizedBox(width: S.x2),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end, style: F.n17.copyWith(color: p.ink)),
        ),
      ]),
    );
  }
}

// ── 4 · efficiency: asleep and awake across the window ─────────────────────

class _EfficiencyCard extends StatelessWidget {
  final SleepData d;
  const _EfficiencyCard(this.d);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final n = d.night;
    final eff = (n['efficiency'] as num?)?.toDouble();
    final tst = (n['duration_min'] as num?)?.toDouble();
    final awake = (n['awake_min'] as num?)?.toDouble();
    if (eff == null) return const SizedBox.shrink();
    final stages = d.stages;
    final cols = Hypnogram.cols(p);

    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(l?.sleepFrontEfficiency ?? 'Sleep efficiency',
                style: F.head.copyWith(color: p.ink)),
          ),
          const SizedBox(width: S.x3),
          Flexible(
            child: Text(_pct(eff),
                textAlign: TextAlign.end,
                style: F.n34.copyWith(color: p.ink)),
          ),
        ]),
        const SizedBox(height: S.x4),
        Row(children: [
          Expanded(
            child: Text(l?.sleepFrontAsleep ?? 'Asleep',
                style: F.cap.copyWith(color: p.ink2)),
          ),
          const SizedBox(width: S.x2),
          Flexible(
            child: Text(hm(tst),
                textAlign: TextAlign.end, style: F.n17.copyWith(color: p.ink)),
          ),
        ]),
        if (stages.isNotEmpty) ...[
          const SizedBox(height: S.x2),
          SizedBox(
            height: S.x8,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: CustomPaint(
                painter: _AsleepAwakePainter(
                  stages: stages,
                  asleep: p.on(C.domSleep),
                  awake: cols[SleepStage.awake]!,
                  hole: p.card2,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: S.x2),
        Row(children: [
          Expanded(
            child: Text(l?.sleepFrontAwake ?? 'Awake',
                style: F.cap.copyWith(color: p.ink2)),
          ),
          const SizedBox(width: S.x2),
          Flexible(
            child: Text(awake == null ? '—' : hm(awake),
                textAlign: TextAlign.end, style: F.n17.copyWith(color: p.ink)),
          ),
        ]),
        const SizedBox(height: S.x3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
          child: Column(children: [
            _Fact(
              l?.sleepFrontAwakenings ?? 'Times awake (at least)',
              d.awakenings == null ? '—' : d.awakenings!.round().toString(),
            ),
            _Fact(
              l?.sleepFrontLongestStretch ?? 'Longest unbroken sleep',
              d.longestSleepMin == null ? '—' : hm(d.longestSleepMin),
            ),
            _Fact(
              l?.sleepFrontLatency ?? 'Time to fall asleep',
              d.solMin == null ? '—' : hm(d.solMin),
              note: d.solMin == null
                  ? (l?.sleepFrontLatencyNote ?? 'counted only from a bedtime you set')
                  : null,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  final String name, value;
  final String? note;
  const _Fact(this.name, this.value, {this.note});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x1),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: F.cap.copyWith(color: p.ink2)),
            if (note != null) Text(note!, style: F.over.copyWith(color: p.ink3)),
          ]),
        ),
        const SizedBox(width: S.x3),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end, style: F.n17.copyWith(color: p.ink)),
        ),
      ]),
    );
  }
}

/// The in-bed window as asleep (any stage) and awake runs, one block per
/// column of the resampled hypnogram. An unknown column is a hole.
class _AsleepAwakePainter extends CustomPainter {
  final List<SleepStage?> stages;
  final Color asleep, awake, hole;
  const _AsleepAwakePainter({
    required this.stages,
    required this.asleep,
    required this.awake,
    required this.hole,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (stages.isEmpty) return;
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(R.sm));
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(Offset.zero & size, Paint()..color = hole);
    final w = size.width / stages.length;
    var i = 0;
    while (i < stages.length) {
      final s = stages[i];
      var j = i;
      while (j < stages.length && stages[j] == s) {
        j++;
      }
      if (s != null) {
        final isAwake = s == SleepStage.awake;
        final r = Rect.fromLTRB(i * w, isAwake ? size.height * .15 : 0, j * w,
            isAwake ? size.height * .85 : size.height);
        canvas.drawRect(r, Paint()..color = isAwake ? awake : asleep);
      }
      i = j;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AsleepAwakePainter o) => o.stages != stages;
}

// ── 5 · the week as columns ────────────────────────────────────────────────

class _TrendsCard extends StatelessWidget {
  final SleepData d;
  const _TrendsCard(this.d);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final cols = Hypnogram.cols(p);
    final target = sleepTarget(d);
    final week = d.trend;
    final selected = d.day;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _TrendBlock(
          title: l?.sleepFrontHoursOfSleep ?? 'Hours of sleep',
          days: week,
          selected: selected,
          series: [
            (
              [for (final t in week) t.tstMin == null ? null : t.tstMin! / 60],
              p.on(C.domSleep)
            ),
          ],
          max: 10,
          reference: target == null ? null : target.min / 60,
          referenceLabel: target == null
              ? null
              : (target.learned
                  ? (l?.sleepFrontYourNeed ?? 'Your sleep need')
                  : (l?.sleepFrontGuidelineForAge ?? 'Guideline for your age')),
          format: (v) => hm(v * 60),
        ),
        const SizedBox(height: S.x5),
        _TrendBlock(
          title: l?.sleepFrontRestorativeHours ?? 'Restorative sleep',
          days: week,
          selected: selected,
          series: [
            ([for (final t in week) t.remMin == null ? null : t.remMin! / 60], cols[SleepStage.rem]!),
            ([for (final t in week) t.deepMin == null ? null : t.deepMin! / 60], cols[SleepStage.deep]!),
          ],
          max: 5,
          format: (v) => hm(v * 60),
          legend: [
            (SleepStage.deep.label(l), cols[SleepStage.deep]!),
            (SleepStage.rem.label(l), cols[SleepStage.rem]!),
          ],
        ),
        const SizedBox(height: S.x5),
        _TrendBlock(
          title: l?.sleepFrontEfficiency ?? 'Sleep efficiency',
          days: week,
          selected: selected,
          series: [
            ([for (final t in week) t.effPct], p.on(C.domSleep)),
          ],
          max: 100,
          format: (v) => '${v.round()}%',
        ),
      ]),
    );
  }
}

class _TrendBlock extends StatelessWidget {
  final String title;
  final List<SleepTrendDay> days;
  final String? selected;

  /// Stacked bottom-up in list order.
  final List<(List<double?>, Color)> series;
  final double max;
  final double? reference;
  final String? referenceLabel;
  final String Function(double) format;
  final List<(String, Color)> legend;
  const _TrendBlock({
    required this.title,
    required this.days,
    required this.selected,
    required this.series,
    required this.max,
    required this.format,
    this.reference,
    this.referenceLabel,
    this.legend = const [],
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final h = bigText(c) ? 110.0 : 140.0;
    // The top of the axis: the larger of [max] and anything drawn.
    var top = max;
    for (var i = 0; i < days.length; i++) {
      var sum = 0.0;
      for (final (vals, _) in series) {
        sum += vals[i] ?? 0;
      }
      if (sum > top) top = sum;
    }
    if (reference != null && reference! > top) top = reference!;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: S.x3,
        runSpacing: S.x1,
        children: [
          Text(title, style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
          for (final (name, col) in legend)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: S.x2,
                height: S.x2,
                decoration: BoxDecoration(color: col, borderRadius: R.rSm),
              ),
              const SizedBox(width: S.x1),
              Text(name, style: F.over.copyWith(color: p.ink3)),
            ]),
        ],
      ),
      if (reference != null && referenceLabel != null)
        Row(children: [
          Container(width: S.x4, height: 1, color: p.ink3),
          const SizedBox(width: S.x2),
          Flexible(
            child: Text('$referenceLabel · ${format(reference!)}',
                style: F.over.copyWith(color: p.ink3)),
          ),
        ]),
      const SizedBox(height: S.x3),
      // Time runs left to right whatever the text direction, as on the
      // heart-rate trace above; the labels inside stay in the reader's.
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: _TrendColumn(
                day: days[i],
                values: [for (final (vals, col) in series) (vals[i], col)],
                top: top,
                height: h,
                reference: reference,
                selected: days[i].date == selected,
                format: format,
                weekday: weekdayShortName(
                    DateTime.parse(days[i].date).weekday, l),
                dayNum: DateTime.parse(days[i].date).day.toString(),
              ),
            ),
        ]),
      ),
    ]);
  }
}

class _TrendColumn extends StatelessWidget {
  final SleepTrendDay day;
  final List<(double?, Color)> values;
  final double top, height;
  final double? reference;
  final bool selected;
  final String Function(double) format;
  final String weekday, dayNum;
  const _TrendColumn({
    required this.day,
    required this.values,
    required this.top,
    required this.height,
    required this.reference,
    required this.selected,
    required this.format,
    required this.weekday,
    required this.dayNum,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final total = values.fold<double>(0, (s, v) => s + (v.$1 ?? 0));
    final any = values.any((v) => v.$1 != null);
    final labelStyle = F.over.copyWith(color: selected ? p.ink : p.ink3);
    // Seven columns across a phone leave no room for 44 pt targets, so the
    // columns read and are not tapped; the day stepper above walks nights.
    return Semantics(
      label: '$weekday $dayNum, ${any ? format(total) : '—'}',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? p.card2 : null,
          borderRadius: R.rMd,
        ),
        padding: const EdgeInsets.symmetric(vertical: S.x1),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (any)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(format(total),
                  style: F.over.copyWith(
                      color: selected ? p.on(C.domSleep) : p.ink3)),
            ),
          const SizedBox(height: 2),
          SizedBox(
            height: height,
            child: Stack(alignment: Alignment.bottomCenter, children: [
              if (reference != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: height * (reference! / top).clamp(0.0, 1.0),
                  child: Container(height: 1, color: p.ink3),
                ),
              Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                // Stacked top-down, so the LAST series is at the bottom.
                for (final (v, col) in values.reversed)
                  if (v != null)
                    Container(
                      width: S.x3,
                      height: height * (v / top).clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        color: col,
                        borderRadius: R.rSm,
                      ),
                    ),
              ]),
            ]),
          ),
          const SizedBox(height: S.x1),
          FittedBox(fit: BoxFit.scaleDown, child: Text(dayNum, style: labelStyle)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(weekday, style: labelStyle)),
        ]),
      ),
    );
  }
}
