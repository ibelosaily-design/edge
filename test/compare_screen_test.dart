// Compare: the overlay and the pair sentences from day-keyed series, and the
// honest absences (too few shared days, fewer than two signals).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/compare_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart' show buildTheme;

CompareData _data(int days) {
  final s = <String, Map<String, double>>{'readiness': {}, 'resting_hr': {}, 'sleep': {}};
  for (var i = 0; i < days; i++) {
    final d = DateTime(2026, 9, 1 + i);
    final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    s['sleep']![k] = 360.0 + (i % 7) * 15;
    s['readiness']![k] = 40.0 + (i % 7) * 7;
    s['resting_hr']![k] = 68.0 - (i % 7) * 1.5;
  }
  return CompareData(s);
}

void main() {
  test('dayMapOf keys by local day label', () {
    final m = dayMapOf([(t: DateTime(2026, 9, 3, 12).millisecondsSinceEpoch ~/ 1000, v: 5.0)]);
    expect(m, {'2026-09-03': 5.0});
  });

  test('daysIn takes the last N labels across every series', () {
    final d = _data(40);
    expect(d.daysIn(7).length, 7);
    expect(d.daysIn(7).last, '2026-10-10');
    expect(d.daysIn(0).length, 40);
    expect(d.available, ['readiness', 'sleep', 'resting_hr']);
  });

  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: SingleChildScrollView(child: w)),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('three signals over 90 days: every pair gets a sentence',
      (tester) async {
    await pump(tester, CompareBody(_data(40), keys: const ['readiness', 'sleep', 'resting_hr'], window: 2));
    expect(find.textContaining('tends to rise'), findsWidgets);
    expect(find.textContaining('tends to fall'), findsWidgets);
    expect(find.textContaining('40 days'), findsNWidgets(3));
    expect(find.text('—'), findsNothing);
  });

  testWidgets('seven days: no number, the shortfall explained', (tester) async {
    await pump(tester, CompareBody(_data(40), keys: const ['readiness', 'sleep'], window: 0));
    expect(find.textContaining('Fewer than 10 days'), findsOneWidget);
    expect(find.textContaining('tends to'), findsNothing);
  });

  testWidgets('one signal: asked to pick a second', (tester) async {
    await pump(tester, CompareBody(_data(40), keys: const ['readiness'], window: 2));
    expect(find.text('Pick two signals'), findsOneWidget);
  });

  testWidgets('moves-with lists the links for one metric', (tester) async {
    await pump(tester, MovesWithList(_data(40), 'readiness', windowDays: 90));
    expect(find.text('Time asleep'), findsOneWidget);
    expect(find.textContaining('same way'), findsOneWidget);
    expect(find.textContaining('opposite way'), findsOneWidget);
  });
}
