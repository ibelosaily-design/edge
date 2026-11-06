// STRESS MONITOR — the Health tab's card and its screen, in the shape WHOOP's
// Stress Monitor has: today's 0–3 line across the day with the three bands
// behind it, the latest reading with its time, and the day's summary (average,
// minutes high, the peak). The arithmetic is compute/stress_day.dart; this
// file only reads series the day already stores and paints them.
//
// Honesty: no baseline → the card counts the nights it still needs, the same
// bar the Health Monitor uses. No still minute with both signals → it says so.
// The latest reading carries its clock time, because the line is only as
// current as the day's last derive pass — this is a re-read of stored minutes,
// not a live feed.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../compute/stress_day.dart';
import '../../data/day_label.dart'
    show dayLabelOf, localDayEndSec, localDayStartSec, todayLabel;
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/decimal_text.dart';
import '../../state/clock_format.dart' show formatClockOf;
import '../ui2.dart';
import 'calm_breathing.dart' show CalmBreathing;
import 'home_screen.dart' show go, pointsOf, repoOf;
import 'metric_detail.dart' show detailScaffold;
import '../profile/devices.dart' show formatDayTime;

/// Everything the card and the screen draw, loaded once from the repository.
class StressMonitorData {
  final String date;
  final int dayStart, dayEnd; // local day, epoch seconds
  final StressDay? day;
  final StressAbsent? absent;

  /// The same scale over the night that ended on this day, or null.
  final StressDay? sleep;

  const StressMonitorData({
    required this.date,
    required this.dayStart,
    required this.dayEnd,
    this.day,
    this.absent,
    this.sleep,
  });

  static Future<StressMonitorData> load(LocalRepository repo,
      {String? date}) async {
    final d = date ?? todayLabel();
    final heart = await repo.getDayHeart(d);
    // The displayed day is the bundle's: a partial today can fall back to
    // the last complete day, and the axis must follow it.
    final shown = heart['date']?.toString() ?? d;
    final dayStart = localDayStartSec(shown) ?? 0;
    final dayEnd = localDayEndSec(shown) ?? dayStart + 86400;

    List<TimePoint> line(Object? l) => [
          for (final e in (l is List ? l : const []))
            if (e is Map && e['t'] is num && e['v'] is num)
              (t: (e['t'] as num).round(), v: (e['v'] as num).toDouble()),
        ];
    final exclude = <(int, int)>[];
    (int, int)? night;
    for (final s in (heart['sleep'] is List ? heart['sleep'] as List : const [])) {
      if (s is Map && s['onset_ts'] is num && s['wake_ts'] is num) {
        night = ((s['onset_ts'] as num).toInt(), (s['wake_ts'] as num).toInt());
        exclude.add(night);
      }
    }
    for (final n in (heart['naps'] is List ? heart['naps'] as List : const [])) {
      if (n is Map && n['start'] is num && n['end'] is num) {
        exclude.add(((n['start'] as num).toInt(), (n['end'] as num).toInt()));
      }
    }
    for (final w in (heart['sessions'] is List ? heart['sessions'] as List : const [])) {
      if (w is Map && w['start_ts'] is num && w['duration_min'] is num) {
        final s = (w['start_ts'] as num).toInt();
        exclude.add((s, s + (w['duration_min'] as num).toInt() * 60));
      }
    }
    // Nightly baselines: the stored trend, nights strictly before the shown
    // day, oldest first.
    List<double> nights(Object? chart) => [
          for (final p in pointsOf(chart))
            if (dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000))
                    .compareTo(shown) <
                0)
              p.v,
        ];
    final rhr = nights(await repo.getChart('resting_hr'));
    final rmssd = nights(await repo.getChart('hrv'));

    final hrvLine = line(heart['hrv']), hrLine = line(heart['hr']);
    final (day, absent) = stressDay(
      hrv: hrvLine,
      hr: hrLine,
      activity: line(heart['activity']),
      exclude: exclude,
      rhrNights: rhr,
      rmssdNights: rmssd,
    );
    final sleep = night == null
        ? null
        : stressSleep(
            hrv: hrvLine,
            hr: hrLine,
            sleep: night,
            rhrNights: rhr,
            rmssdNights: rmssd,
          );
    return StressMonitorData(
      date: shown,
      dayStart: dayStart,
      dayEnd: dayEnd,
      day: day,
      absent: absent,
      sleep: sleep,
    );
  }
}

/// Loads on open and on every data revision; renders the card.
class StressMonitorLoader extends StatefulWidget {
  const StressMonitorLoader({super.key});

  @override
  State<StressMonitorLoader> createState() => _StressMonitorLoaderState();
}

class _StressMonitorLoaderState extends State<StressMonitorLoader>
    with RevisionReload {
  StressMonitorData? _d;

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
      final d = await StressMonitorData.load(repo);
      if (mounted) setState(() => _d = d);
    } catch (_) {
      // The card stays absent; nothing to say that the data did not.
    }
  }

  @override
  Widget build(BuildContext c) =>
      _d == null ? const SizedBox.shrink() : StressMonitorCard(_d!);
}

String stressBandWord(String band, AppLocalizations? l) => switch (band) {
      'low' => l?.stressBandLow ?? 'Calm',
      'medium' => l?.stressBandMedium ?? 'Alert',
      _ => l?.stressBandHigh ?? 'High',
    };

Color stressBandColor(String band) => switch (band) {
      'low' => C.green,
      'medium' => C.orange,
      _ => C.red,
    };

class StressMonitorCard extends StatelessWidget {
  final StressMonitorData data;
  const StressMonitorCard(this.data, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = data.day;
    return Surface(
      onTap: () => go(c, StressMonitorScreen(data: data)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.brain, size: 16, color: p.on(C.purple)),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(l?.stressMonitorTitle ?? 'Stress Monitor',
                style: F.cap.copyWith(color: p.ink2)),
          ),
          Icon(LucideIcons.chevronRight, size: 15, color: p.ink3),
        ]),
        const SizedBox(height: S.x3),
        if (d == null)
          _Absent(data.absent)
        else ...[
          _Latest(d, big: false),
          const SizedBox(height: S.x3),
          SizedBox(
            height: 72,
            child: CustomPaint(
              painter: StressLinePainter(d.points, data.dayStart, data.dayEnd, p),
            ),
          ),
          const SizedBox(height: S.x3),
          _Summary(d),
        ],
      ]),
    );
  }
}

class _Absent extends StatelessWidget {
  final StressAbsent? why;
  const _Absent(this.why);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final w = why;
    if (w != null && w.note == 'need_baseline') {
      final left = w.need - w.have;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          l?.stressNeedNights(left) ??
              'Wear the band to sleep $left more nights to learn your usual.',
          style: F.body.copyWith(color: p.ink2),
        ),
        const SizedBox(height: S.x2),
        Row(children: [
          for (var i = 0; i < w.need; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: S.x1,
                decoration: BoxDecoration(
                  color: i < w.have ? p.on(C.purple) : p.track,
                  borderRadius: R.rPill,
                ),
              ),
            ),
          ],
        ]),
      ]);
    }
    return Text(
      l?.stressNoStill ??
          'No still minute with both a heart-rate and an HRV reading yet today.',
      style: F.body.copyWith(color: p.ink2),
    );
  }
}

class _Latest extends StatelessWidget {
  final StressDay d;
  final bool big;
  const _Latest(this.d, {required this.big});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final band = stressBand(d.latest.v);
    // A line served from an earlier day (today not derived yet) says which
    // day it is: "at 22:10" alone would read as tonight.
    final latest = DateTime.fromMillisecondsSinceEpoch(d.latest.t * 1000);
    final at = dayLabelOf(latest) == todayLabel()
        ? formatClockOf(latest)
        : formatDayTime(latest, l);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(displayFixed(d.latest.v, 1),
          style: (big ? F.n64 : F.n34).copyWith(color: p.ink)),
      const SizedBox(width: S.x2),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: S.x1),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: S.x2,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: S.x2, vertical: 2),
                decoration: BoxDecoration(
                    color: p.wash(stressBandColor(band)), borderRadius: R.rPill),
                child: Text(stressBandWord(band, l),
                    style: F.over.copyWith(color: p.on(stressBandColor(band)))),
              ),
              Text(l?.stressLatestAt(at) ?? 'at $at',
                  style: F.cap.copyWith(color: p.ink3)),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _Summary extends StatelessWidget {
  final StressDay d;
  const _Summary(this.d);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final peakAt = formatClockOf(
        DateTime.fromMillisecondsSinceEpoch(d.peak.t * 1000));
    return Wrap(spacing: S.x4, runSpacing: S.x1, children: [
      Text(l?.stressDayAverage(displayFixed(d.mean, 1)) ??
              'Day average ${displayFixed(d.mean, 1)}',
          style: F.cap.copyWith(color: p.ink2)),
      Text(l?.stressHighMinutes(d.highMin) ?? '${d.highMin} min high',
          style: F.cap.copyWith(color: p.ink2)),
      Text(l?.stressPeakAt(displayFixed(d.peak.v, 1), peakAt) ??
              'Peak ${displayFixed(d.peak.v, 1)} at $peakAt',
          style: F.cap.copyWith(color: p.ink2)),
    ]);
  }
}

/// The 0–3 line over the local day, the three bands washed behind it. A gap
/// of more than fifteen minutes between points breaks the line: nothing is
/// drawn across minutes that were asleep, moving or unmeasured.
class StressLinePainter extends CustomPainter {
  final List<StressPoint> points;
  final int dayStart, dayEnd;
  final P p;
  final bool axis;
  const StressLinePainter(this.points, this.dayStart, this.dayEnd, this.p,
      {this.axis = false});

  static const int gapSec = 15 * 60;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (dayEnd - dayStart).toDouble();
    if (span <= 0) return;
    final labelH = axis ? 14.0 : 0.0;
    final h = size.height - labelH;
    double x(int t) => (t - dayStart) / span * size.width;
    double y(double v) => h - (v / 3).clamp(0.0, 1.0) * h;

    // Bands, bottom up: low / medium / high.
    for (final (lo, hi, col) in [
      (0.0, kStressLowHi, C.green),
      (kStressLowHi, kStressMidHi, C.orange),
      (kStressMidHi, 3.0, C.red),
    ]) {
      canvas.drawRect(
        Rect.fromLTRB(0, y(hi), size.width, y(lo)),
        Paint()..color = p.wash(col, strength: .5),
      );
    }
    // Hour ticks on the screen's chart.
    if (axis) {
      final tick = Paint()
        ..color = p.line
        ..strokeWidth = 1;
      for (final hour in const [6, 12, 18]) {
        final t = dayStart + hour * 3600;
        if (t <= dayStart || t >= dayEnd) continue;
        canvas.drawLine(Offset(x(t), 0), Offset(x(t), h), tick);
        final tp = TextPainter(
          text: TextSpan(
              text: formatClockOf(
                  DateTime.fromMillisecondsSinceEpoch(t * 1000)),
              style: F.over.copyWith(color: p.ink3)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x(t) - tp.width / 2, h + 1));
      }
    }
    if (points.isEmpty) return;
    final line = Paint()
      ..color = p.ink
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    StressPoint? prev;
    for (final pt in points) {
      final o = Offset(x(pt.t), y(pt.v));
      if (prev == null || pt.t - prev.t > gapSec) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
      prev = pt;
    }
    canvas.drawPath(path, line);
    // The latest reading, as a dot.
    final last = points.last;
    canvas.drawCircle(Offset(x(last.t), y(last.v)), 3.5, Paint()..color = p.ink);
  }

  @override
  bool shouldRepaint(StressLinePainter o) =>
      o.points != points || o.dayStart != dayStart || o.dayEnd != dayEnd;
}

class StressMonitorScreen extends StatefulWidget {
  /// Preloaded, for the card's tap and the gallery. Null reads the repo.
  final StressMonitorData? data;
  const StressMonitorScreen({super.key, this.data});

  @override
  State<StressMonitorScreen> createState() => _StressMonitorScreenState();
}

class _StressMonitorScreenState extends State<StressMonitorScreen>
    with RevisionReload {
  StressMonitorData? _d;

  @override
  bool get revisionReloads => true;

  @override
  void reload() => _load();

  @override
  void initState() {
    super.initState();
    _d = widget.data;
    if (_d == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      final d = await StressMonitorData.load(repo);
      if (mounted) setState(() => _d = d);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final d = _d;
    return detailScaffold(
      c,
      l?.stressMonitorTitle ?? 'Stress Monitor',
      [if (d != null) StressMonitorBody(d)],
      sub: l?.stressMonitorSub ?? 'Heart rate and HRV against your usual',
    );
  }
}

/// The screen's content, a plain widget so the gallery can sweep it.
class StressMonitorBody extends StatelessWidget {
  final StressMonitorData data;
  const StressMonitorBody(this.data, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = data.day;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (d == null)
            _Absent(data.absent)
          else ...[
            _Latest(d, big: true),
            const SizedBox(height: S.x4),
            SizedBox(
              height: 160,
              child: CustomPaint(
                painter: StressLinePainter(
                    d.points, data.dayStart, data.dayEnd, p,
                    axis: true),
              ),
            ),
            const SizedBox(height: S.x2),
            _Legend(),
          ],
        ]),
      ),
      if (d != null) ...[
        const SizedBox(height: S.x3),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _Tile(l?.stressDayAverageLabel ?? 'Day average',
                displayFixed(d.mean, 1), stressBandWord(stressBand(d.mean), l)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: _Tile(l?.stressHighLabel ?? 'Time high', '${d.highMin}',
                l?.stressMinutes ?? 'min'),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: _Tile(l?.stressActiveLabel ?? 'Moving', '${d.activeMin}',
                l?.stressMinutesLeftOut ?? 'min left out'),
          ),
        ]),
      ],
      // The night, on the same scale, when it was scored. Shown apart from
      // the day because WHOOP reports it apart: how settled the sleep was.
      if (data.sleep case final n?) ...[
        const SizedBox(height: S.x3),
        Surface(
          child: Row(children: [
            Icon(LucideIcons.moon, size: 16, color: p.on(C.indigo)),
            const SizedBox(width: S.x3),
            Expanded(
              child: Text(l?.stressSleepLabel ?? 'Sleep stress',
                  style: F.body.copyWith(color: p.ink)),
            ),
            Text(displayFixed(n.mean, 1), style: F.n24.copyWith(color: p.ink)),
            const SizedBox(width: S.x2),
            Text(stressBandWord(stressBand(n.mean), l),
                style: F.cap.copyWith(color: p.on(stressBandColor(stressBand(n.mean))))),
          ]),
        ),
      ],
      if (d != null) ...[
        const SizedBox(height: S.x3),
        Surface(
          color: p.card2,
          child: Text(
            l?.stressMethod(d.hrBase.round(), d.hrvBase.round(), d.nights) ??
                'Each still, awake minute is scored by how far your heart rate '
                    'sits above your typical resting rate (${d.hrBase.round()} '
                    'bpm) and how far your HRV sits below your recent nights '
                    '(${d.hrvBase.round()} ms), over ${d.nights} nights. '
                    'Minutes asleep, napping, in a workout or moving are left '
                    'out. 0–1 calm, 1–2 alert, 2–3 high.',
            style: F.cap.copyWith(color: p.ink2),
          ),
        ),
      ],
      const SizedBox(height: S.x3),
      Surface(
        onTap: () => go(c, const CalmBreathing()),
        child: Row(children: [
          Icon(LucideIcons.wind, size: 18, color: p.on(C.teal)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l?.stressBreatheTitle ?? 'Breathe',
                  style: F.body.copyWith(color: p.ink)),
              Text(
                l?.stressBreatheSub ??
                    'A few minutes of slow breathing, with the effect shown after.',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ]),
          ),
          Icon(LucideIcons.chevronRight, size: 15, color: p.ink3),
        ]),
      ),
    ]);
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return Wrap(spacing: S.x4, runSpacing: S.x1, children: [
      for (final (band, range) in [
        ('low', '0–1'),
        ('medium', '1–2'),
        ('high', '2–3'),
      ])
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: S.x2,
            height: S.x2,
            decoration: BoxDecoration(
                color: p.on(stressBandColor(band)), shape: BoxShape.circle),
          ),
          const SizedBox(width: S.x1),
          Text('$range ${stressBandWord(band, l)}',
              style: F.over.copyWith(color: p.ink3)),
        ]),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final String label, value, sub;
  const _Tile(this.label, this.value, this.sub);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      pad: const EdgeInsets.all(S.x3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x1),
        Text(value, style: F.n24.copyWith(color: p.ink)),
        Text(sub, style: F.cap.copyWith(color: p.ink2)),
      ]),
    );
  }
}
