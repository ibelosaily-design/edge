// HOME · START — four doors under the rings, the way WHOOP's home opens with
// a "start" strip: begin a session, the two activities this person actually
// does, and a breathing sitting. Doors only: no number, no observation, so
// they stay on the right side of Home's law (home_screen.dart header).
//
// The two activity doors are the two most recent band sessions, deduped; a
// first week with none shows Tennis and Swimming — the sports this build was
// made for — so the row is never empty.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../activity/catalogue.dart';
import '../activity/picker.dart' show ActivityPicker;
import '../activity/setup.dart' show ActivitySetup;
import '../ui2.dart';
import 'calm_breathing.dart' show CalmBreathing;
import 'home_screen.dart' show go, repoOf;
import '../activity/live.dart' show SetHistory;
import 'workout_screen.dart' show activityHost, loadSetHistory;

/// The two activities the row offers beside the picker and breathing.
List<Activity> homeStartActivities(List<String?> recentTypes) {
  final out = <Activity>[];
  for (final t in recentTypes) {
    final a = activityByName(t);
    if (a != null && !out.any((x) => x.name == a.name)) out.add(a);
    if (out.length == 2) break;
  }
  for (final name in const ['Tennis', 'Swimming']) {
    if (out.length == 2) break;
    final a = activityByName(name);
    if (a != null && !out.any((x) => x.name == a.name)) out.add(a);
  }
  return out;
}

class HomeStartLoader extends StatefulWidget {
  const HomeStartLoader({super.key});

  @override
  State<HomeStartLoader> createState() => _HomeStartLoaderState();
}

class _HomeStartLoaderState extends State<HomeStartLoader> {
  List<Activity> _recent = homeStartActivities(const []);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day - 60)
              .millisecondsSinceEpoch ~/
          1000;
      final rows = await repo.getSessions(
          from: from, to: now.millisecondsSinceEpoch ~/ 1000);
      // Newest first; the band's own sessions only (imports live elsewhere).
      final types = [for (final r in rows.reversed) r['type']?.toString()];
      final recent = homeStartActivities(types);
      if (mounted) setState(() => _recent = recent);
    } catch (_) {
      // The defaults stand.
    }
  }

  @override
  Widget build(BuildContext c) => HomeStartRow(activities: _recent);
}

class HomeStartRow extends StatelessWidget {
  final List<Activity> activities;
  const HomeStartRow({super.key, required this.activities});

  Future<void> _openPicker(BuildContext c) async {
    final repo = repoOf(c);
    double? weight;
    var history = const <String, SetHistory>{};
    if (repo != null) {
      try {
        weight = (await repo.getProfile())['weight_kg'] as double?;
        history = await loadSetHistory();
      } catch (_) {}
    }
    if (!c.mounted) return;
    final app = c.read<AppState>();
    go(
        c,
        ActivityPicker(
            weightKg: weight,
            host: activityHost(app, history: history),
            recent: activities));
  }

  Future<void> _openSetup(BuildContext c, Activity a) async {
    final repo = repoOf(c);
    double? weight;
    if (repo != null) {
      try {
        weight = (await repo.getProfile())['weight_kg'] as double?;
      } catch (_) {}
    }
    if (!c.mounted) return;
    final app = c.read<AppState>();
    go(c, ActivitySetup(a, weightKg: weight, host: activityHost(app)));
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final doors = <_Door>[
      _Door(LucideIcons.play, C.purple, l?.homeStartSession ?? 'Start',
          () => _openPicker(c)),
      for (final a in activities.take(2))
        _Door(a.icon, a.color, activityLabel(a, l), () => _openSetup(c, a)),
      _Door(LucideIcons.wind, C.teal, l?.homeStartBreathe ?? 'Breathe',
          () => go(c, const CalmBreathing())),
    ];
    if (bigText(c)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, d) in doors.indexed) ...[
          if (i > 0) const SizedBox(height: S.x2),
          _DoorTile(d, wide: true),
        ],
      ]);
    }
    return Row(children: [
      for (final (i, d) in doors.indexed) ...[
        if (i > 0) const SizedBox(width: S.x2),
        Expanded(child: _DoorTile(d, wide: false)),
      ],
    ]);
  }
}

/// The activity's display name in this locale, falling back to its own.
String activityLabel(Activity a, AppLocalizations? l) => switch (a.name) {
      'Tennis' => l?.homeStartTennis ?? a.name,
      'Swimming' => l?.homeStartSwimming ?? a.name,
      'Weight training' => l?.homeStartStrength ?? a.name,
      'Running' => l?.homeStartRunning ?? a.name,
      'Walking' => l?.homeStartWalking ?? a.name,
      'Cycling' => l?.homeStartCycling ?? a.name,
      _ => a.name,
    };

class _Door {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _Door(this.icon, this.color, this.label, this.onTap);
}

class _DoorTile extends StatelessWidget {
  final _Door d;
  final bool wide;
  const _DoorTile(this.d, {required this.wide});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      semanticLabel: d.label,
      onTap: d.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
        decoration: BoxDecoration(color: p.card, borderRadius: R.rMd),
        child: wide
            ? Row(children: [
                Icon(d.icon, size: 18, color: p.on(d.color)),
                const SizedBox(width: S.x3),
                Expanded(
                    child: Text(d.label, style: F.body.copyWith(color: p.ink))),
                Icon(LucideIcons.chevronRight, size: 15, color: p.ink3),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(d.icon, size: 20, color: p.on(d.color)),
                const SizedBox(height: S.x2),
                Text(
                  d.label,
                  style: F.over.copyWith(color: p.ink2),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
      ),
    );
  }
}
