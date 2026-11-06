// Home's start row: the two activity doors follow what this person recently
// did, fall back to the two sports the build is for, and never repeat.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/home_start.dart';
import 'package:openstrap_edge/ui2/ui2.dart' show buildTheme;

void main() {
  test('defaults to Tennis and Swimming with no history', () {
    final a = homeStartActivities(const []);
    expect([for (final x in a) x.name], ['Tennis', 'Swimming']);
  });

  test('recent sessions lead, deduped, unknown types skipped, then defaults',
      () {
    final a = homeStartActivities(
        const ['weight_training', 'weight_training', 'not_a_type', null]);
    expect([for (final x in a) x.name], ['Weight training', 'Tennis']);
    final b = homeStartActivities(const ['running', 'cycling', 'tennis']);
    expect([for (final x in b) x.name], ['Running', 'Cycling']);
  });

  testWidgets('four doors render, each tappable by its label', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: HomeStartRow(activities: homeStartActivities(const [])),
      ),
    ));
    await tester.pumpAndSettle();
    for (final label in ['Start', 'Tennis', 'Swimming', 'Breathe']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}
