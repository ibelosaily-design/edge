// HEALTHSPAN — body age and pace of aging, from the nine habits WHOOP's
// Healthspan feature scores, worked out on this phone.
//
// The screen reads inside-out, the way WHOOP's own page is meant to be read:
// the age first, then the pace, then the nine lines that made them — each
// with its value, its target and the years it added or took off, so the
// headline is never a number the user cannot take apart.
//
// Two of the nine are typed, not measured (VO2max from another app or a lab,
// lean mass from a body-fat reading), and their rows are the way in.
//
// What this screen does NOT do: show a number before 21 scored days exist
// (WHOOP's gate, kept), fill an unmeasured habit with a population value, or
// hide that the models behind it are adult cohorts. See compute/healthspan.dart
// for the arithmetic and its sources.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../compute/healthspan.dart';
import '../../compute/healthspan_load.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'home_screen.dart' show go, repoOf, thousands;
import 'metric_detail.dart' show detailScaffold;

/// What the screen shows, read once. [result] is null when the profile has no
/// age or sex yet.
class HealthspanView {
  final HealthspanResult? result;
  final bool profileComplete;
  final String? vo2maxSource;

  const HealthspanView({
    this.result,
    this.profileComplete = true,
    this.vo2maxSource,
  });

  static Future<HealthspanView> load(BuildContext c) async {
    final repo = repoOf(c);
    if (repo == null) return const HealthspanView(profileComplete: false);
    final profile = await repo.getProfile();
    final inputs = await loadHealthspan(repo, profile: profile);
    return HealthspanView(
      result: inputs.compute(DateTime.now()),
      profileComplete: inputs.profileComplete,
      vo2maxSource: inputs.vo2maxSource,
    );
  }
}

String _tenths(double v) => v.toStringAsFixed(1);

/// "+1.2 y" / "−0.8 y" / on target. Shared by the rows and the door.
String yearsLabel(AppLocalizations? l, double years) {
  if (years > 0) return l?.healthspanYearsPlus(_tenths(years)) ?? '+${_tenths(years)} y';
  if (years < 0) return l?.healthspanYearsMinus(_tenths(-years)) ?? '−${_tenths(-years)} y';
  return l?.healthspanYearsZero ?? 'On target';
}

Color yearsColor(double years) =>
    years > 0 ? C.orange : (years < 0 ? C.green : C.blue);

/// One line on the pace, by WHOOP's bands: under 0 reversing, 0-1 slowing,
/// 1 steady, over 1 faster.
String paceLine(AppLocalizations? l, double pace) {
  if (pace < 0) return l?.healthspanPaceReversing ?? 'Reversing — this month is taking years off';
  if (pace < 1) return l?.healthspanPaceSlowing ?? 'Slowing — aging slower than the calendar';
  if (pace == 1) return l?.healthspanPaceSteady ?? 'Steady — aging at calendar speed';
  return l?.healthspanPaceFaster ?? 'Faster — this month is adding years';
}

String contributorName(AppLocalizations? l, HsKey k) => switch (k) {
      HsKey.sleepHours => l?.healthspanSleepHours ?? 'Hours of sleep',
      HsKey.consistency => l?.healthspanConsistency ?? 'Sleep consistency',
      HsKey.steps => l?.healthspanSteps ?? 'Daily steps',
      HsKey.zone13 => l?.healthspanZone13 ?? 'Heart rate zones 1–3',
      HsKey.zone45 => l?.healthspanZone45 ?? 'Heart rate zones 4–5',
      HsKey.strength => l?.healthspanStrength ?? 'Strength training',
      HsKey.vo2max => l?.healthspanVo2max ?? 'VO₂ max',
      HsKey.restingHr => l?.healthspanRestingHr ?? 'Resting heart rate',
      HsKey.leanMass => l?.healthspanLeanMass ?? 'Lean body mass',
    };

IconData contributorIcon(HsKey k) => switch (k) {
      HsKey.sleepHours => LucideIcons.moon,
      HsKey.consistency => LucideIcons.calendarCheck,
      HsKey.steps => LucideIcons.footprints,
      HsKey.zone13 => LucideIcons.activity,
      HsKey.zone45 => LucideIcons.zap,
      HsKey.strength => LucideIcons.dumbbell,
      HsKey.vo2max => LucideIcons.wind,
      HsKey.restingHr => LucideIcons.heartPulse,
      HsKey.leanMass => LucideIcons.scale,
    };

/// The value as the row prints it, in the unit the target is in.
String contributorValue(AppLocalizations? l, HsContributor c) {
  final v = c.value;
  if (v == null) return '';
  return switch (c.key) {
    HsKey.sleepHours => l?.healthspanHoursValue(_tenths(v)) ?? '${_tenths(v)} h',
    HsKey.consistency => '${v.round()}%',
    HsKey.steps => thousands(v),
    HsKey.zone13 || HsKey.zone45 || HsKey.strength =>
      l?.healthspanPerWeek(v.round()) ?? '${v.round()} min/week',
    HsKey.vo2max => _tenths(v),
    HsKey.restingHr => l?.healthspanBpm(v.round()) ?? '${v.round()} bpm',
    HsKey.leanMass => '${v.round()}%',
  };
}

String contributorTarget(AppLocalizations? l, HsContributor c) {
  final t = c.target;
  final String shown = switch (c.key) {
    HsKey.sleepHours => l?.healthspanTargetRange(
            HsTargets.sleepLoH.round().toString(),
            HsTargets.sleepHiH.round().toString()) ??
        '${HsTargets.sleepLoH.round()}–${HsTargets.sleepHiH.round()} h',
    HsKey.consistency || HsKey.leanMass => '${t.round()}%',
    HsKey.steps => thousands(t),
    HsKey.zone13 || HsKey.zone45 || HsKey.strength =>
      l?.healthspanPerWeek(t.round()) ?? '${t.round()} min/week',
    HsKey.vo2max => _tenths(t),
    HsKey.restingHr => l?.healthspanBpm(t.round()) ?? '${t.round()} bpm',
  };
  final word = c.key == HsKey.restingHr
      ? (l?.healthspanTargetUnder(shown) ?? 'Under $shown')
      : (l?.healthspanTarget(shown) ?? 'Target $shown');
  return word;
}

class HealthspanScreen extends StatefulWidget {
  /// Preloaded, for the gallery. Null means read the repo on open.
  final HealthspanView? data;
  const HealthspanScreen({super.key, this.data});

  @override
  State<HealthspanScreen> createState() => _HealthspanScreenState();
}

class _HealthspanScreenState extends State<HealthspanScreen> {
  HealthspanView? _v;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _v = widget.data;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final v = await HealthspanView.load(context);
      if (mounted) setState(() => (_v = v, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A typed value: VO2max or body fat. Cleared with an empty field.
  Future<void> _enter(BuildContext c, HsKey key) async {
    final l = AppLocalizations.of(c);
    final isVo2 = key == HsKey.vo2max;
    final app = c.read<AppState>();
    final profileKey = isVo2 ? kProfileVo2maxKey : kProfileBodyFatKey;
    final current = (app.user?[profileKey] as num?)?.toDouble();
    var text = current == null ? '' : _tenths(current);
    final ok = await showDialog<bool>(
      context: c,
      builder: (dc) => AlertDialog(
        title: Text(isVo2
            ? (l?.healthspanEnterVo2Title ?? 'VO₂ max')
            : (l?.healthspanEnterFatTitle ?? 'Body fat')),
        content: TextFormField(
          initialValue: text,
          autofocus: true,
          onChanged: (s) => text = s,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: isVo2 ? 'ml/kg/min' : '%',
            helperText: isVo2
                ? (l?.healthspanEnterVo2Hint ??
                    'From the WHOOP app, a watch or a lab test')
                : (l?.healthspanEnterFatHint ??
                    'From a scale or a caliper; lean mass is the rest'),
            helperMaxLines: 3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dc, false),
            child: Text(l?.actionCancel ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dc, true),
            child: Text(l?.actionSave ?? 'Save'),
          ),
        ],
      ),
    );
    if (ok != true || !c.mounted) return;
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    // A typo trap, not a model: VO2max 10-100, body fat 2-70.
    final plausible = v == null ||
        (isVo2 ? (v >= 10 && v <= 100) : (v >= 2 && v <= 70));
    if (!plausible) return;
    await app.updateProfile({profileKey: v});
    if (!mounted) return;
    setState(() => _loading = true);
    _load();
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final v = _v;
    return detailScaffold(c, l?.healthspanTitle ?? 'Healthspan', [
      if (_loading && v == null) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else
        HealthspanBody(
          v ?? const HealthspanView(profileComplete: false),
          onEnter: (k) => _enter(c, k),
        ),
    ]);
  }
}

/// The screen's content, handed its view — the age, the pace, the nine
/// lines and the method note. Pure, so the gallery can sweep it.
class HealthspanBody extends StatelessWidget {
  final HealthspanView view;
  final void Function(HsKey key)? onEnter;
  const HealthspanBody(this.view, {super.key, this.onEnter});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final v = view;
    final r = v.result;
    if (!v.profileComplete || r == null) {
      return StatusCard(
        l?.healthspanNeedProfileTitle ?? 'Needs your age and sex',
        l?.healthspanNeedProfile ??
            'Add them in Profile; every target here depends on them.',
        icon: LucideIcons.userRound,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(r),
        if (r.unlocked) ...[
          const SizedBox(height: S.x3),
          _PaceCard(r),
        ],
        if (r.chronoAge < 18) ...[
          const SizedBox(height: S.x3),
          Surface(
            color: p.wash(C.yellow),
            child: Text(
              l?.healthspanAdultNote ??
                  'The studies behind this are adult cohorts, which is why '
                      'WHOOP keeps it off under 18. Under 18, read it as a '
                      'habits score, not a biological age.',
              style: F.cap.copyWith(color: p.on(C.yellow)),
            ),
          ),
        ],
        for (final (title, keys) in [
          (l?.healthspanGroupSleep ?? 'Sleep', [HsKey.sleepHours, HsKey.consistency]),
          (
            l?.healthspanGroupActivity ?? 'Activity',
            [HsKey.steps, HsKey.zone13, HsKey.zone45, HsKey.strength]
          ),
          (
            l?.healthspanGroupFitness ?? 'Fitness',
            [HsKey.vo2max, HsKey.restingHr, HsKey.leanMass]
          ),
        ])
          Section(
            title,
            Surface(
              pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x1),
              child: Column(children: [
                for (final (i, k) in keys.indexed) ...[
                  if (i > 0) Divider(color: p.line, height: 1),
                  _ContributorRow(
                    r.contributors.firstWhere((x) => x.key == k),
                    vo2maxSource: v.vo2maxSource,
                    onTap: onEnter != null &&
                            (k == HsKey.vo2max || k == HsKey.leanMass)
                        ? () => onEnter!(k)
                        : null,
                  ),
                ],
              ]),
            ),
          ),
        Section(
          l?.healthspanMethodTitle ?? 'How this is worked out',
          Surface(
            child: Text(
              l?.healthspanMethod ??
                  'Each habit is compared with a public-health target. The '
                      'gap becomes a mortality risk from the studies that link '
                      'that habit to lifespan, and the risk becomes years: '
                      'risk doubles about every eight to ten years of adult '
                      'life, so a risk ratio is an age offset. The nine '
                      'offsets are added to your age; pace compares the last '
                      '30 days with your long average. The framework, inputs '
                      'and targets are the ones WHOOP publishes for its '
                      'Healthspan feature. The exact weights are not '
                      'published, so this app\'s come from the cited studies '
                      'and will not match WHOOP\'s number to the decimal.',
              style: F.cap.copyWith(color: p.ink2),
            ),
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final HealthspanResult r;
  const _Hero(this.r);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final age = r.whoopAge;
    if (age == null) {
      final frac = (r.recentScored / kHsUnlockDays).clamp(0.0, 1.0).toDouble();
      return Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l?.healthspanBodyAge ?? 'Body age',
                style: F.cap.copyWith(color: p.ink3)),
            const SizedBox(height: S.x2),
            Text(
              l?.healthspanLockedTitle ?? 'Unlocks after 21 scored days in 31',
              style: F.head.copyWith(color: p.ink),
            ),
            const SizedBox(height: S.x3),
            ClipRRect(
              borderRadius: R.rPill,
              child: LinearProgressIndicator(
                value: frac,
                minHeight: S.x1,
                backgroundColor: p.track,
                color: p.on(C.indigo),
              ),
            ),
            const SizedBox(height: S.x1),
            Text(
              l?.healthspanLockedProgress(r.recentScored, kHsUnlockDays) ??
                  '${r.recentScored} of $kHsUnlockDays in the last 31 days',
              style: F.cap.copyWith(color: p.ink3),
            ),
          ],
        ),
      );
    }
    final delta = r.delta!;
    final line = delta.abs() < 0.05
        ? (l?.healthspanOnPace ?? 'Same as your age')
        : delta < 0
            ? (l?.healthspanYounger(_tenths(-delta)) ??
                '${_tenths(-delta)} years younger than ${r.chronoAge}')
            : (l?.healthspanOlder(_tenths(delta)) ??
                '${_tenths(delta)} years older than ${r.chronoAge}');
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l?.healthspanBodyAge ?? 'Body age',
              style: F.cap.copyWith(color: p.ink3)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(_tenths(age),
                      style: F.n64.copyWith(color: p.on(yearsColor(delta)))),
                ),
              ),
              const SizedBox(width: S.x2),
              Text(l?.healthspanYears ?? 'years',
                  style: F.body.copyWith(color: p.ink2)),
            ],
          ),
          Text(line, style: F.body.copyWith(color: p.ink)),
          const SizedBox(height: S.x2),
          Text(
            l?.healthspanBasedOn(r.scoredDays, kHsLongWindow) ??
                'From ${r.scoredDays} scored days; fills out at $kHsLongWindow',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }
}

class _PaceCard extends StatelessWidget {
  final HealthspanResult r;
  const _PaceCard(this.r);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final pace = r.pace;
    if (pace == null) return const SizedBox.shrink();
    final color = pace < 1 ? C.green : (pace == 1 ? C.blue : C.orange);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l?.healthspanPace ?? 'Pace of aging',
              style: F.cap.copyWith(color: p.ink3)),
          Text('${_tenths(pace)}x',
              style: F.t1.copyWith(color: p.on(color))),
          const SizedBox(height: S.x1),
          Text(paceLine(l, pace), style: F.body.copyWith(color: p.ink)),
          const SizedBox(height: S.x1),
          Text(
            l?.healthspanPaceWhy(r.spanDays) ??
                'The last 30 days against your ${r.spanDays}-day average',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }
}

class _ContributorRow extends StatelessWidget {
  final HsContributor c;
  final String? vo2maxSource;
  final VoidCallback? onTap;
  const _ContributorRow(this.c, {this.vo2maxSource, this.onTap});

  @override
  Widget build(BuildContext ctx) {
    final p = P.of(ctx);
    final l = AppLocalizations.of(ctx);
    final name = contributorName(l, c.key);
    final value = contributorValue(l, c);
    final sub = c.absent
        ? (onTap != null
            ? (l?.healthspanAddValue ?? 'Tap to enter')
            : (l?.healthspanAbsent ?? 'Not measured yet'))
        : [
            contributorTarget(l, c),
            if (c.key == HsKey.vo2max && vo2maxSource == 'session')
              l?.healthspanVo2FromSession ?? 'from your runs',
            if (c.key == HsKey.vo2max && vo2maxSource == 'typed')
              l?.healthspanVo2Typed ?? 'typed in',
          ].join(' · ');
    final pill = c.absent
        ? Text('—', style: F.body.copyWith(color: p.ink3))
        : Pill(yearsLabel(l, c.years), yearsColor(c.years));
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: F.body.copyWith(color: p.ink)),
        Text(sub, style: F.over.copyWith(color: p.ink3)),
      ],
    );
    final amount = Text(
      value,
      style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
    );
    return Pressable(
      onTap: onTap,
      semanticLabel: '$name, $value, ${c.absent ? sub : yearsLabel(l, c.years)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: bigText(ctx)
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(contributorIcon(c.key), size: 18, color: p.on(C.indigo)),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: S.x1),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: S.x3,
                          runSpacing: S.x1,
                          children: [amount, pill],
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Icon(contributorIcon(c.key), size: 18, color: p.on(C.indigo)),
                  const SizedBox(width: S.x3),
                  Expanded(child: title),
                  const SizedBox(width: S.x2),
                  amount,
                  const SizedBox(width: S.x3),
                  pill,
                ],
              ),
      ),
    );
  }
}

/// The door on the Health tab: the age and the pace, or how far the unlock
/// has got. Reads on its own, so Health's load is untouched.
class HealthspanDoor extends StatefulWidget {
  /// Preloaded, for the gallery.
  final HealthspanView? data;
  const HealthspanDoor({super.key, this.data});

  @override
  State<HealthspanDoor> createState() => _HealthspanDoorState();
}

class _HealthspanDoorState extends State<HealthspanDoor> {
  HealthspanView? _v;

  @override
  void initState() {
    super.initState();
    _v = widget.data;
    if (_v == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final v = await HealthspanView.load(context);
      if (mounted) setState(() => _v = v);
    } catch (_) {/* the door still opens */}
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final r = _v?.result;
    final String sub;
    if (_v == null) {
      sub = '';
    } else if (r == null) {
      sub = l?.healthspanNeedProfileTitle ?? 'Needs your age and sex';
    } else if (!r.unlocked) {
      sub = l?.healthspanLockedProgress(r.recentScored, kHsUnlockDays) ??
          '${r.recentScored} of $kHsUnlockDays in the last 31 days';
    } else {
      sub = '${_tenths(r.whoopAge!)} · ${_tenths(r.pace!)}x';
    }
    return Surface(
      onTap: () => go(c, const HealthspanScreen()),
      child: Row(children: [
        Icon(LucideIcons.hourglass, size: 20, color: p.on(C.indigo)),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l?.healthspanDoorTitle ?? 'Body age and pace of aging',
                  style: F.body.copyWith(color: p.ink)),
              if (sub.isNotEmpty)
                Text(sub, style: F.cap.copyWith(color: p.ink3)),
            ],
          ),
        ),
        Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
      ]),
    );
  }
}
