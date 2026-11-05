// HEALTH MONITOR — the Health tab's top, in the shape WHOOP's Health Monitor
// has: one card per vital with the night's value and where it sits against
// the user's own range, and a banner counting the nights until the ranges
// exist.
//
// The range verdict is the pipeline's own (`baselines` block: in_normal_range
// / z / n_valid); this card never draws a second one. Under kUsualMinDays
// nights a vital is calibrating and says how many nights are left. SpO₂ is
// listed and refused with the pipeline's reason: the band's red and infrared
// channels arrive as one signal and this app does not invent a saturation
// from it.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/decimal_text.dart';
import '../ui2.dart';
import 'health_screen.dart' show HealthData;
import 'home_screen.dart' show go;
import 'metric_detail.dart' show MetricDetail;

enum VitalStatus { calibrating, inside, above, below, absent }

/// One vital's read-out, resolved from the day's envelopes.
class VitalRead {
  final String key; // MetricDetail key
  final IconData icon;
  final Color color;
  final String name;
  final String value; // '' when absent
  final String unit;
  final VitalStatus status;
  final int nightsLeft; // while calibrating
  final String? refusal; // a vital this app does not compute, and why

  const VitalRead({
    required this.key,
    required this.icon,
    required this.color,
    required this.name,
    required this.value,
    required this.unit,
    required this.status,
    this.nightsLeft = 0,
    this.refusal,
  });
}

/// The status of a vital from its pipeline baseline block. Calibrating until
/// the block has [kUsualMinDays] valid nights; then the block's own verdict.
(VitalStatus, int) vitalStatusOf(Object? block, {required bool hasValue}) {
  if (!hasValue) return (VitalStatus.absent, 0);
  if (block is! Map) return (VitalStatus.calibrating, kUsualMinDays);
  final n = (block['n_valid'] as num?)?.toInt() ?? 0;
  if (n < kUsualMinDays) return (VitalStatus.calibrating, kUsualMinDays - n);
  final inRange = block['in_normal_range'];
  final z = (block['z'] as num?)?.toDouble();
  if (inRange == true) return (VitalStatus.inside, 0);
  if (inRange == false && z != null) {
    return (z > 0 ? VitalStatus.above : VitalStatus.below, 0);
  }
  return (VitalStatus.calibrating, 0);
}

List<VitalRead> vitalReads(HealthData d, AppLocalizations? l) {
  final b = d.baselines;
  Object? block(String k) => b?[k];

  final resp = d.resp.value;
  final rhr = d.daily('resting_hr').value;
  final hrv = d.hrv.value;
  final temp = d.today['skin_temp'];
  final tempDevC = temp is Map ? (temp['dev_c'] as num?)?.toDouble() : null;
  final tempZ = temp is Map ? (temp['value'] as num?)?.toDouble() : null;

  final (rs, rn) = vitalStatusOf(block('resp'), hasValue: resp != null);
  final (hs, hn) = vitalStatusOf(block('resting_hr'), hasValue: rhr != null);
  final (vs, vn) = vitalStatusOf(block('hrv'), hasValue: hrv != null);
  final (ts, tn) = vitalStatusOf(block('skin_temp'),
      hasValue: tempDevC != null || tempZ != null);

  return [
    VitalRead(
      key: 'resp_rate',
      icon: LucideIcons.wind,
      color: C.teal,
      name: l?.healthRowRespRate ?? 'Respiratory rate',
      value: resp == null ? '' : displayFixed(resp, 1),
      unit: l?.healthMonitorBrMin ?? 'br/min',
      status: rs,
      nightsLeft: rn,
    ),
    VitalRead(
      key: 'spo2',
      icon: LucideIcons.droplet,
      color: C.blue,
      name: l?.healthMonitorSpo2 ?? 'Blood oxygen (SpO₂)',
      value: '',
      unit: '%',
      status: VitalStatus.absent,
      refusal: l?.healthMonitorSpo2Refused ??
          'Not computed here: the band sends its red and infrared light as '
              'one signal, and a saturation needs the two apart.',
    ),
    VitalRead(
      key: 'resting_hr',
      icon: LucideIcons.heart,
      color: C.red,
      name: l?.healthRowRestingHr ?? 'Resting heart rate',
      value: rhr == null ? '' : rhr.round().toString(),
      unit: 'bpm',
      status: hs,
      nightsLeft: hn,
    ),
    VitalRead(
      key: 'hrv',
      icon: LucideIcons.activity,
      color: C.green,
      name: l?.healthRowHrv ?? 'HRV',
      value: hrv == null ? '' : hrv.round().toString(),
      unit: 'ms',
      status: vs,
      nightsLeft: vn,
    ),
    VitalRead(
      key: 'skin_temp',
      icon: LucideIcons.thermometer,
      color: C.orange,
      name: l?.healthMonitorSkinTemp ?? 'Skin temperature (from your usual)',
      value: tempDevC != null
          ? '${tempDevC < 0 ? '−' : '+'}${displayFixed(tempDevC.abs(), 1)}'
          : (tempZ != null && ts != VitalStatus.calibrating
              ? '${tempZ < 0 ? '−' : '+'}${displayFixed(tempZ.abs(), 1)}'
              : ''),
      unit: tempDevC != null ? '°C' : (tempZ != null ? 'SD' : ''),
      status: ts,
      nightsLeft: tn,
    ),
  ];
}

class HealthMonitorGrid extends StatelessWidget {
  final HealthData data;
  const HealthMonitorGrid(this.data, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final reads = vitalReads(data, l);
    final calibrating = [
      for (final r in reads)
        if (r.status == VitalStatus.calibrating) r.nightsLeft
    ];
    final nightsLeft = calibrating.isEmpty ? 0 : calibrating.reduce((a, b) => a > b ? a : b);
    final cards = [for (final r in reads) _VitalCard(r)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (nightsLeft > 0) ...[
        Surface(
          color: p.wash(C.purple),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              l?.healthMonitorCalibrate(nightsLeft) ??
                  'Wear the band to sleep $nightsLeft more nights to set your ranges.',
              style: F.body.copyWith(color: p.on(C.purple)),
            ),
            const SizedBox(height: S.x2),
            Row(children: [
              for (var i = 0; i < kUsualMinDays; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: S.x1,
                    decoration: BoxDecoration(
                      color: i < kUsualMinDays - nightsLeft ? p.on(C.purple) : p.track,
                      borderRadius: R.rPill,
                    ),
                  ),
                ),
              ],
            ]),
          ]),
        ),
        const SizedBox(height: S.x3),
      ],
      if (bigText(c))
        for (final (i, w) in cards.indexed) ...[
          if (i > 0) const SizedBox(height: S.x3),
          w,
        ]
      else
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: S.x3),
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: cards[i]),
            const SizedBox(width: S.x3),
            Expanded(
              child: i + 1 < cards.length ? cards[i + 1] : const SizedBox.shrink(),
            ),
          ]),
        ],
    ]);
  }
}

class _VitalCard extends StatelessWidget {
  final VitalRead r;
  const _VitalCard(this.r);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final (String word, Color col) = switch (r.status) {
      VitalStatus.calibrating => (
          l?.healthMonitorCalibrating ?? 'Setting your range',
          p.ink3
        ),
      VitalStatus.inside => (l?.healthMonitorInside ?? 'In your range', p.on(C.green)),
      VitalStatus.above => (l?.healthMonitorAbove ?? 'Above your range', p.on(C.orange)),
      VitalStatus.below => (l?.healthMonitorBelow ?? 'Below your range', p.on(C.orange)),
      VitalStatus.absent => (
          r.refusal == null
              ? (l?.healthMonitorNotMeasured ?? 'Not measured')
              : (l?.healthMonitorNotComputed ?? 'Not computed'),
          p.ink3
        ),
    };
    return Surface(
      onTap: r.refusal == null ? () => go(c, MetricDetail(r.key)) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(r.icon, size: 16, color: p.on(r.color)),
          const SizedBox(width: S.x2),
          Expanded(child: Text(r.name, style: F.cap.copyWith(color: p.ink2))),
        ]),
        const SizedBox(height: S.x3),
        if (r.value.isNotEmpty)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: S.x1,
            children: [
              Text(r.value, style: F.n34.copyWith(color: p.ink)),
              Text(r.unit, style: F.cap.copyWith(color: p.ink3)),
            ],
          )
        else
          Text('—', style: F.n34.copyWith(color: p.ink3)),
        if (r.refusal != null) ...[
          const SizedBox(height: S.x2),
          Text(r.refusal!, style: F.over.copyWith(color: p.ink3)),
        ],
        const SizedBox(height: S.x3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rPill),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: S.x2,
              height: S.x2,
              decoration: BoxDecoration(color: col, shape: BoxShape.circle),
            ),
            const SizedBox(width: S.x2),
            Flexible(
              child: Text(
                r.status == VitalStatus.calibrating && r.nightsLeft > 0
                    ? (l?.healthMonitorNightsLeft(r.nightsLeft) ??
                        '$word · ${r.nightsLeft} nights')
                    : word,
                style: F.over.copyWith(color: p.ink2),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
