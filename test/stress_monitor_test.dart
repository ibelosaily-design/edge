// The Stress Monitor's loader reads only what the day already stores, and
// the card says one of three honest things: the line, the nights it still
// needs, or that no still minute carried both signals.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/stress_day.dart';
import 'package:openstrap_edge/data/day_label.dart' show dayLabelOf;
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/ui2/screens/stress_monitor.dart';
import 'package:openstrap_edge/ui2/ui2.dart' show buildTheme;

final _day = DateTime(2026, 11, 5);
final _label = dayLabelOf(_day);
int _at(int h, [int m = 0]) =>
    DateTime(2026, 11, 5, h, m).millisecondsSinceEpoch ~/ 1000;
int _noonOf(int daysBack) =>
    DateTime(2026, 11, 5 - daysBack, 12).millisecondsSinceEpoch ~/ 1000;

class _Repo extends LocalRepository {
  final int nights;
  final bool withMinutes;
  _Repo({this.nights = 7, this.withMinutes = true});

  @override
  Future<Map<String, dynamic>> getDayHeart(String date) async => {
        'date': _label,
        'hr': [
          if (withMinutes)
            for (var m = 0; m < 120; m += 1)
              {'t': _at(9) + m * 60, 'v': m < 60 ? 68 : 90},
        ],
        'hrv': [
          if (withMinutes)
            for (var m = 0; m < 120; m += 2)
              {'t': _at(9) + m * 60, 'v': m < 60 ? 48.0 : 22.0},
        ],
        'activity': const [],
        'sleep': [
          {'onset_ts': _at(0, 30), 'wake_ts': _at(7)},
        ],
        'naps': const [],
        // A workout 10:30–10:50 — those minutes must not be scored.
        'sessions': [
          {'start_ts': _at(10, 30), 'duration_min': 20},
        ],
      };

  @override
  Future<Map<String, dynamic>> getChart(String metric,
      {int? from, int? to, Set<String> signals = const {}}) async {
    final v = metric == 'resting_hr' ? 60.0 : 60.0;
    return {
      'points': [
        for (var i = 1; i <= nights; i++) {'t': _noonOf(i), 'v': v},
        // Today's own night is not a baseline night for today.
        {'t': _noonOf(0), 'v': 999.0},
      ],
    };
  }
}

void main() {
  test('loads the day: sleep and the workout are left out, the rest scored',
      () async {
    final d = await StressMonitorData.load(_Repo(), date: _label);
    expect(d.absent, isNull);
    final day = d.day!;
    expect(day.nights, 7);
    expect(day.hrBase, 60, reason: "today's 999 is not a prior night");
    // 09:00–11:00 every 2 min = 60 HRV samples, minus the ten inside the
    // workout (10:30–10:50 → 10:30, 10:32 … 10:48).
    expect(day.points.length, 50);
    expect(day.points.first.t, _at(9));
    expect(stressBand(day.points.first.v), 'low');
    expect(stressBand(day.latest.v), 'high');
    expect(day.highMin, greaterThan(0));
    expect(d.dayStart, _day.millisecondsSinceEpoch ~/ 1000);
  });

  test('too few nights: no day, the shortfall counted', () async {
    final d = await StressMonitorData.load(_Repo(nights: 2), date: _label);
    expect(d.day, isNull);
    expect(d.absent!.note, 'need_baseline');
    expect(d.absent!.have, 2);
  });

  test('no minutes: no day, no_still', () async {
    final d =
        await StressMonitorData.load(_Repo(withMinutes: false), date: _label);
    expect(d.day, isNull);
    expect(d.absent!.note, 'no_still');
  });

  testWidgets('the card renders each state in words, never a dash',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Future<void> pump(StressMonitorData d) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
            body: SingleChildScrollView(
                child: Column(children: [
          StressMonitorCard(d),
          StressMonitorBody(d),
        ]))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsNothing);
    }

    await pump(await StressMonitorData.load(_Repo(), date: _label));
    expect(find.textContaining('Day average'), findsWidgets);
    expect(find.text('High'), findsWidgets);
    expect(find.textContaining('Breathe'), findsOneWidget);

    await pump(await StressMonitorData.load(_Repo(nights: 1), date: _label));
    expect(find.textContaining('3 more nights'), findsWidgets);

    await pump(
        await StressMonitorData.load(_Repo(withMinutes: false), date: _label));
    expect(find.textContaining('No still minute'), findsWidgets);
  });
}
