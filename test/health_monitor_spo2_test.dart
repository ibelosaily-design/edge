// The Health Monitor's SpO₂ card has three honest states and no fourth: the
// band's own nightly byte (labelled reported, not measured), WHOOP's imported
// value for the SAME night, or the refusal with its reason. An older imported
// point is another night and must not pose as this one's vital.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart' show dayLabelOf;
import 'package:openstrap_edge/ui2/screens/health_monitor.dart';
import 'package:openstrap_edge/ui2/screens/health_screen.dart'
    show HealthData;
import 'package:openstrap_edge/ui2/ui2.dart' show buildTheme;

int _noon(DateTime d) =>
    DateTime(d.year, d.month, d.day, 12).millisecondsSinceEpoch ~/ 1000;

HealthData _data({
  Map<String, Object?>? band,
  List<({int t, double v})> imported = const [],
  required String night,
}) =>
    HealthData(
      today: {
        'status': {'today_day': night, 'overnight_day': night},
        if (band != null) 'spo2_band': band,
      },
      charts: {'spo2': imported},
    );

VitalRead _spo2(HealthData d) =>
    vitalReads(d, null).singleWhere((r) => r.key == 'spo2');

void main() {
  final today = DateTime(2026, 11, 5);
  final night = dayLabelOf(today);
  final yesterday = DateTime(2026, 11, 4);

  test('band byte present: its value, reported status, caveat, no detail', () {
    final r = _spo2(_data(
        night: night, band: {'value': 96, 'min': 93, 'n': 84}));
    expect(r.value, '96');
    expect(r.unit, '%');
    expect(r.status, VitalStatus.reported);
    expect(r.refusal, isNull);
    expect(r.note, contains('as sent'));
    expect(r.opens, isFalse,
        reason: 'the detail screen charts the IMPORTED series only');
  });

  test('no band byte, WHOOP import for this night: its value, labelled', () {
    final r = _spo2(_data(
        night: night, imported: [(t: _noon(today), v: 95.0)]));
    expect(r.value, '95');
    expect(r.status, VitalStatus.reported);
    expect(r.note, contains('export'));
    expect(r.opens, isTrue);
  });

  test('band byte wins over the import, and the card then opens the import',
      () {
    final r = _spo2(_data(
      night: night,
      band: {'value': 96},
      imported: [(t: _noon(today), v: 95.0)],
    ));
    expect(r.value, '96');
    expect(r.opens, isTrue);
  });

  test('an older imported point is another night: the refusal stands', () {
    final r = _spo2(_data(
        night: night, imported: [(t: _noon(yesterday), v: 95.0)]));
    expect(r.value, '');
    expect(r.status, VitalStatus.absent);
    expect(r.refusal, isNotNull);
    expect(r.opens, isFalse);
  });

  test('nothing: refusal, not computed, no value', () {
    final r = _spo2(_data(night: night));
    expect(r.value, '');
    expect(r.status, VitalStatus.absent);
    expect(r.refusal, contains('one signal'));
  });

  test('importedSpo2For matches on the local day label, newest first', () {
    final pts = [
      (t: _noon(yesterday), v: 94.0),
      (t: _noon(today), v: 95.0),
    ];
    expect(importedSpo2For(pts, night), 95);
    expect(importedSpo2For(pts, dayLabelOf(yesterday)), 94);
    expect(importedSpo2For(pts, '2026-11-03'), isNull);
    expect(importedSpo2For(pts, null), isNull);
  });

  testWidgets('the grid renders the reported card with its pill and caveat',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: HealthMonitorGrid(
              _data(night: night, band: {'value': 96, 'min': 93, 'n': 84})),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('96'), findsOneWidget);
    expect(find.text('Reported, not measured here'), findsOneWidget);
    expect(find.textContaining('encoding'), findsOneWidget);
    expect(find.textContaining('Not computed'), findsNothing);
  });
}
