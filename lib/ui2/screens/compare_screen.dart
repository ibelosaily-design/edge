// COMPARE — two to four of this person's daily series on one axis, and how
// each pair moves together.
//
// Every series is min–max scaled inside the window so different units share
// a chart (the legend prints each series' real range, so the scaling hides
// nothing). Under the chart, every pair gets its Pearson r over the days both
// have a value, the day count, a strength word and one plain sentence: "when
// sleep rises, resting HR tends to fall". It is an association in one
// person's own history — the sentence says "tends to", the day count is
// always beside the number, and under ten paired days there is no number
// (compute/correlate.dart).
//
// Two doors in: the Health tab (pick your own metrics) and a metric screen's
// "moves with" list (which opens this with that pair chosen).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../compute/correlate.dart';
import '../../data/day_label.dart' show dayLabelOf;
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/display_text.dart' show uiText;
import '../ui2.dart';
import 'home_screen.dart' show go, pointsOf, repoOf;
import 'metric_detail.dart' show detailLinkRow, detailScaffold, specOf;

/// The daily series offered for comparison: the catalogue's daily metrics,
/// minus the suppressed and the research-only ones.
const List<String> kCompareKeys = [
  'readiness',
  'sleep',
  'efficiency',
  'deep',
  'rem',
  'hrv',
  'resting_hr',
  'resp_rate',
  'skin_temp',
  'spo2',
  'strain',
  'steps',
  'calories',
  'active_min',
  'nap_min',
  'stress',
];

/// Window lengths in days; 0 = all history.
const List<int> kCompareWindows = [7, 30, 90, 182, 365, 0];

/// Day-keyed values for one series.
Map<String, double> dayMapOf(Iterable<({int t, double v})> points) => {
      for (final p in points)
        dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)): p.v,
    };

class CompareData {
  /// Every offered series that has at least one point, day-keyed.
  final Map<String, Map<String, double>> series;
  const CompareData(this.series);

  static Future<CompareData> load(LocalRepository repo,
      {List<String> keys = kCompareKeys}) async {
    final out = <String, Map<String, double>>{};
    for (final k in keys) {
      final spec = specOf(k);
      if (spec.suppress != null) continue;
      try {
        final m = dayMapOf(pointsOf(await repo.getChart(spec.chartKey)));
        if (m.isNotEmpty) out[k] = m;
      } catch (_) {
        // A series the repository cannot serve is simply not offered.
      }
    }
    return CompareData(out);
  }

  /// Keys with any data, in catalogue order.
  List<String> get available =>
      [for (final k in kCompareKeys) if (series.containsKey(k)) k];

  /// The last [days] day labels present in any series (0 = all), sorted.
  List<String> daysIn(int days) {
    final all = <String>{for (final m in series.values) ...m.keys}.toList()
      ..sort();
    if (days <= 0 || all.length <= days) return all;
    return all.sublist(all.length - days);
  }

  /// The series restricted to [days].
  Map<String, Map<String, double>> within(List<String> days) {
    final set = days.toSet();
    return {
      for (final e in series.entries)
        e.key: {
          for (final d in e.value.entries)
            if (set.contains(d.key)) d.key: d.value,
        },
    };
  }
}

/// The sentence for one pair, in the reader's language.
String correlationSentence(
    BuildContext c, Correlation x, AppLocalizations? l) {
  final a = uiText(c, specOf(x.a).title), b = uiText(c, specOf(x.b).title);
  final strength = switch (x.strength) {
    'strong' => l?.compareStrong ?? 'strong',
    'moderate' => l?.compareModerate ?? 'moderate',
    _ => l?.compareWeak ?? 'weak',
  };
  return x.positive
      ? (l?.compareRiseTogether(a, b, strength) ??
          'When $a rises, $b tends to rise too — a $strength link.')
      : (l?.compareRiseFall(a, b, strength) ??
          'When $a rises, $b tends to fall — a $strength link.');
}

class CompareScreen extends StatefulWidget {
  /// Preselected keys (2–4); a metric screen's door passes its pair.
  final List<String> initial;

  /// Preloaded, for the gallery; null reads the repository.
  final CompareData? data;
  const CompareScreen({super.key, this.initial = const [], this.data});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  CompareData? _d;
  late List<String> _keys = [...widget.initial];
  int _win = 2; // 90 days

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
      final d = await CompareData.load(repo);
      if (!mounted) return;
      setState(() {
        _d = d;
        if (_keys.isEmpty) {
          _keys = [
            for (final k in const ['readiness', 'sleep', 'resting_hr'])
              if (d.series.containsKey(k)) k,
          ];
        }
      });
    } catch (_) {
      if (mounted) setState(() => _d = const CompareData({}));
    }
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final d = _d;
    return detailScaffold(
      c,
      l?.compareTitle ?? 'Compare',
      [
        if (d != null)
          CompareBody(
            d,
            keys: _keys,
            window: _win,
            onKeys: (k) => setState(() => _keys = k),
            onWindow: (i) => setState(() => _win = i),
          ),
      ],
      sub: l?.compareSub ?? 'Two to four of your own signals, side by side',
    );
  }
}

/// The screen's content; the gallery sweeps it with fixed state.
class CompareBody extends StatelessWidget {
  final CompareData data;
  final List<String> keys;
  final int window;
  final ValueChanged<List<String>>? onKeys;
  final ValueChanged<int>? onWindow;
  const CompareBody(this.data,
      {super.key,
      required this.keys,
      required this.window,
      this.onKeys,
      this.onWindow});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final days = data.daysIn(kCompareWindows[window.clamp(0, 5)]);
    final chosen = [for (final k in keys) if (data.series.containsKey(k)) k];
    final within = data.within(days);
    final norm = normalizeOverlay(
        {for (final k in chosen) k: within[k]!}, days);
    final pairs = correlatePairs(chosen, within);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Chips: the chosen, each removable; an add chip while under four.
      Wrap(spacing: S.x2, runSpacing: S.x2, children: [
        for (final k in chosen)
          _Chip(
            label: uiText(c, specOf(k).title),
            color: specOf(k).color,
            onRemove: chosen.length > 2 && onKeys != null
                ? () => onKeys!([for (final x in chosen) if (x != k) x])
                : null,
          ),
        if (chosen.length < 4 && onKeys != null)
          _AddChip(onTap: () => _pick(c, chosen)),
      ]),
      const SizedBox(height: S.x3),
      SubTabs(
        [
          l?.compareWindow7 ?? '7d',
          l?.compareWindow30 ?? '30d',
          l?.compareWindow90 ?? '90d',
          l?.compareWindow182 ?? '6m',
          l?.compareWindowYear ?? '1y',
          l?.compareWindowAll ?? 'All',
        ],
        window.clamp(0, 5),
        (i) => onWindow?.call(i),
        color: C.purple,
      ),
      const SizedBox(height: S.x3),
      if (chosen.length < 2)
        StatusCard(
          l?.compareNeedTwoTitle ?? 'Pick two signals',
          l?.compareNeedTwoBody ??
              'Add a second signal above to see how the two move together.',
          icon: LucideIcons.gitCompare,
        )
      else ...[
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 160,
              child: CustomPaint(
                painter: OverlayPainter(
                  [for (final k in chosen) norm[k]!],
                  [for (final k in chosen) p.on(specOf(k).color)],
                  p,
                ),
              ),
            ),
            const SizedBox(height: S.x2),
            // The two ends of the axis; at large text they stack rather than
            // squeeze.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: S.x3,
              children: [
                Text(days.isEmpty ? '' : days.first,
                    style: F.over.copyWith(color: p.ink3)),
                Text(days.isEmpty ? '' : days.last,
                    style: F.over.copyWith(color: p.ink3)),
              ],
            ),
            const SizedBox(height: S.x3),
            // The real range of each series — the scaling hides nothing.
            for (final k in chosen) _RangeLine(k, within[k]!, days),
          ]),
        ),
        const SizedBox(height: S.x3),
        Section(
          l?.comparePairsSection ?? 'How they move together',
          Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (pairs.isEmpty)
                Text(
                  l?.compareTooFewDays(kCorrMinDays) ??
                      'Fewer than $kCorrMinDays days with both signals in '
                          'this window. Widen it, or wear the band longer.',
                  style: F.body.copyWith(color: p.ink2),
                )
              else
                for (final (i, x) in pairs.indexed) ...[
                  if (i > 0) ...[
                    const SizedBox(height: S.x2),
                    Divider(color: p.line, height: 1),
                    const SizedBox(height: S.x2),
                  ],
                  _PairRow(x),
                ],
              const SizedBox(height: S.x3),
              Text(
                l?.compareCaveat ??
                    'A link in your own history, not a cause: it says the two '
                        'moved together on these days, nothing about why.',
                style: F.over.copyWith(color: p.ink3),
              ),
            ]),
          ),
        ),
      ],
    ]);
  }

  Future<void> _pick(BuildContext c, List<String> chosen) async {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final options = [for (final k in data.available) if (!chosen.contains(k)) k];
    final picked = await showModalBottomSheet<String>(
      context: c,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (sc) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.all(S.x4),
            child: Text(l?.compareAddSignal ?? 'Add a signal',
                style: F.head.copyWith(color: p.ink)),
          ),
          for (final k in options)
            Pressable(
              semanticLabel: uiText(sc, specOf(k).title),
              onTap: () => Navigator.of(sc).pop(k),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: S.x4, vertical: S.x3),
                child: Row(children: [
                  Icon(specOf(k).icon, size: 18, color: p.on(specOf(k).color)),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(uiText(sc, specOf(k).title),
                        style: F.body.copyWith(color: p.ink)),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: S.x4),
        ]),
      ),
    );
    if (picked != null) onKeys?.call([...chosen, picked]);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onRemove;
  const _Chip({required this.label, required this.color, this.onRemove});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
      decoration: BoxDecoration(color: p.wash(color), borderRadius: R.rPill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: S.x2,
          height: S.x2,
          decoration: BoxDecoration(color: p.on(color), shape: BoxShape.circle),
        ),
        const SizedBox(width: S.x2),
        Text(label, style: F.cap.copyWith(color: p.ink)),
        if (onRemove != null) ...[
          const SizedBox(width: S.x2),
          Icon(LucideIcons.x, size: 14, color: p.ink3),
        ],
      ]),
    );
    return onRemove == null
        ? chip
        : Pressable(semanticLabel: label, onTap: onRemove, child: chip);
  }
}

class _AddChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddChip({required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return Pressable(
      semanticLabel: l?.compareAddSignal ?? 'Add a signal',
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
        decoration: BoxDecoration(
            border: Border.all(color: p.line), borderRadius: R.rPill),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.plus, size: 14, color: p.ink2),
          const SizedBox(width: S.x1),
          Text(l?.compareAdd ?? 'Add', style: F.cap.copyWith(color: p.ink2)),
        ]),
      ),
    );
  }
}

class _RangeLine extends StatelessWidget {
  final String k;
  final Map<String, double> m;
  final List<String> days;
  const _RangeLine(this.k, this.m, this.days);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final spec = specOf(k);
    double? lo, hi;
    var n = 0;
    for (final d in days) {
      final v = m[d];
      if (v == null) continue;
      n++;
      lo = lo == null ? v : (v < lo ? v : lo);
      hi = hi == null ? v : (v > hi ? v : hi);
    }
    String f(double v) => v == v.roundToDouble()
        ? '${v.round()}'
        : v.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(top: S.x1),
      child: Row(children: [
        Container(
          width: S.x2,
          height: S.x2,
          decoration:
              BoxDecoration(color: p.on(spec.color), shape: BoxShape.circle),
        ),
        const SizedBox(width: S.x2),
        Flexible(
          flex: 3,
          child: Text(uiText(c, spec.title),
              style: F.cap.copyWith(color: p.ink2)),
        ),
        const SizedBox(width: S.x2),
        Flexible(
          flex: 2,
          child: Text(
            lo == null || hi == null
                ? (l?.compareNoDays ?? 'no days')
                : '${f(lo)}–${f(hi)} ${spec.unit} · $n',
            style: F.cap.copyWith(color: p.ink3),
            textAlign: TextAlign.end,
          ),
        ),
      ]),
    );
  }
}

class _PairRow extends StatelessWidget {
  final Correlation x;
  const _PairRow(this.x);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final col = x.r.abs() < kCorrModerate
        ? p.ink3
        : p.on(x.positive ? C.green : C.orange);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Text(correlationSentence(c, x, l),
              style: F.body.copyWith(color: p.ink)),
        ),
        const SizedBox(width: S.x3),
        Flexible(
          child: Text(
              'r ${x.r >= 0 ? '+' : '−'}${x.r.abs().toStringAsFixed(2)}',
              style: F.n17.copyWith(color: col)),
        ),
      ]),
      const SizedBox(height: S.x1),
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: R.rPill,
            child: SizedBox(
              height: S.x1,
              child: CustomPaint(painter: _RBar(x.r, col, p.track)),
            ),
          ),
        ),
        const SizedBox(width: S.x3),
        Flexible(
          child: Text(l?.compareDays(x.n) ?? '${x.n} days',
              style: F.over.copyWith(color: p.ink3)),
        ),
      ]),
    ]);
  }
}

/// A centred bar: |r| to the right for a positive link, to the left for a
/// negative one.
class _RBar extends CustomPainter {
  final double r;
  final Color col, track;
  const _RBar(this.r, this.col, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final mid = size.width / 2;
    final w = mid * r.abs().clamp(0.0, 1.0);
    final rect = r >= 0
        ? Rect.fromLTWH(mid, 0, w, size.height)
        : Rect.fromLTWH(mid - w, 0, w, size.height);
    canvas.drawRect(rect, Paint()..color = col);
  }

  @override
  bool shouldRepaint(_RBar o) => o.r != r || o.col != col;
}

/// Up to four normalised lines over the same day axis; a null breaks a line.
class OverlayPainter extends CustomPainter {
  final List<List<double?>> lines;
  final List<Color> colors;
  final P p;
  const OverlayPainter(this.lines, this.colors, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = size.height - f * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 0; i < lines.length; i++) {
      final d = lines[i];
      if (d.length < 2) continue;
      final paint = Paint()
        ..color = colors[i]
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var pen = false;
      for (var j = 0; j < d.length; j++) {
        final v = d[j];
        if (v == null) {
          pen = false;
          continue;
        }
        final x = j / (d.length - 1) * size.width;
        final y = size.height - v.clamp(0.0, 1.0) * size.height;
        if (pen) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          pen = true;
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(OverlayPainter o) => o.lines != lines;
}

/// "Moves with" — the top links for one metric, as rows that open Compare
/// on that pair. Reads the whole catalogue once when the door is opened,
/// never on the metric screen's own load.
class MovesWithLoader extends StatefulWidget {
  final String metricKey;
  final int windowDays;
  const MovesWithLoader(this.metricKey, {super.key, required this.windowDays});

  @override
  State<MovesWithLoader> createState() => _MovesWithLoaderState();
}

class _MovesWithLoaderState extends State<MovesWithLoader> {
  CompareData? _d;
  bool _open = false, _loading = false;

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) return;
    setState(() => _loading = true);
    try {
      final d = await CompareData.load(repo);
      if (mounted) setState(() => _d = d);
    } catch (_) {
      if (mounted) setState(() => _d = const CompareData({}));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    if (!_open) {
      return detailLinkRow(
        c,
        LucideIcons.gitCompare,
        l?.compareMovesWithTitle ?? 'Moves with',
        l?.compareMovesWithSub ?? 'Which of your other signals track this one',
        () {
          setState(() => _open = true);
          _load();
        },
      );
    }
    final d = _d;
    if (_loading || d == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return MovesWithList(d, widget.metricKey, windowDays: widget.windowDays);
  }
}

class MovesWithList extends StatelessWidget {
  final CompareData data;
  final String metricKey;
  final int windowDays;
  const MovesWithList(this.data, this.metricKey,
      {super.key, required this.windowDays});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final days = data.daysIn(windowDays);
    final links = correlatesOf(metricKey, data.within(days));
    return Section(
      l?.compareMovesWithTitle ?? 'Moves with',
      Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
        child: links.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x2),
                child: Text(
                  l?.compareNoLinks(kCorrMinDays) ??
                      'No clear link yet in this window — a link needs '
                          '$kCorrMinDays shared days and a steady pattern.',
                  style: F.body.copyWith(color: p.ink2),
                ),
              )
            : Column(children: [
                for (final (i, x) in links.indexed) ...[
                  if (i > 0) Divider(color: p.line, height: 1),
                  Pressable(
                    semanticLabel: correlationSentence(c, x, l),
                    onTap: () => go(c,
                        CompareScreen(initial: [metricKey, x.b], data: data)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.x3),
                      child: Row(children: [
                        Icon(specOf(x.b).icon,
                            size: 18, color: p.on(specOf(x.b).color)),
                        const SizedBox(width: S.x3),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(uiText(c, specOf(x.b).title),
                                    style: F.body.copyWith(color: p.ink)),
                                Text(
                                  '${x.positive ? (l?.compareSameWay ?? 'same way') : (l?.compareOppositeWay ?? 'opposite way')} · '
                                  '${l?.compareDays(x.n) ?? '${x.n} days'}',
                                  style: F.over.copyWith(color: p.ink3),
                                ),
                              ]),
                        ),
                        Flexible(
                          child: Text(
                              'r ${x.r >= 0 ? '+' : '−'}${x.r.abs().toStringAsFixed(2)}',
                              style: F.n17.copyWith(color: p.ink2)),
                        ),
                        const SizedBox(width: S.x2),
                        Icon(LucideIcons.chevronRight, size: 15, color: p.ink3),
                      ]),
                    ),
                  ),
                ],
              ]),
      ),
    );
  }
}
