// One lift over time, from the set log: sessions grouped and ordered, the
// top set and Epley estimate per session, bodyweight sessions without a bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/activity/exercise_progress.dart';
import 'package:openstrap_edge/ui2/ui2.dart' show buildTheme;

Map<String, Object?> _row(String s, int seq, int? reps, double? kg, int at) => {
      'session_id': s,
      'exercise_key': 'bench_press',
      'seq': seq,
      'reps': reps,
      'load_kg': kg,
      'at_ts': at,
    };

void main() {
  test('sessions are grouped, oldest first, with top set and volume', () {
    final out = exerciseSessionsFrom([
      _row('b', 0, 8, 62.5, 2000),
      _row('b', 1, 5, 70, 2100),
      _row('a', 0, 8, 60, 1000),
      _row('a', 1, 8, 60, 1100),
      _row('a', 2, 10, null, 1200), // a bodyweight finisher: no load
    ]);
    expect(out.length, 2);
    expect(out.first.sessionId, 'a');
    expect(out.first.sets, 3);
    expect(out.first.reps, 26);
    expect(out.first.top!.loadKg, 60);
    expect(out.first.volumeKg, 960);
    expect(out.first.e1rm, closeTo(60 * (1 + 8 / 30), 1e-9));
    expect(out.last.top!.loadKg, 70);
    expect(out.last.top!.reps, 5);
    expect(out.last.at, DateTime.fromMillisecondsSinceEpoch(2100 * 1000));
  });

  test('a session with no loaded set has no top set and no estimate', () {
    final out = exerciseSessionsFrom([_row('a', 0, 12, null, 1000)]);
    expect(out.single.top, isNull);
    expect(out.single.e1rm, isNull);
    expect(out.single.volumeKg, isNull);
    expect(out.single.reps, 12);
  });

  testWidgets('the body renders a record, a single session, and none',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Future<void> pump(List<ExerciseSession> s) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
            body: SingleChildScrollView(
                child: ExerciseProgressBody('bench_press', s))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    final two = exerciseSessionsFrom([
      _row('a', 0, 8, 60, DateTime(2026, 9, 1).millisecondsSinceEpoch ~/ 1000),
      _row('b', 0, 8, 65, DateTime(2026, 9, 8).millisecondsSinceEpoch ~/ 1000),
    ]);
    await pump(two);
    expect(find.text('65 kg × 8'), findsWidgets);
    expect(find.textContaining('1RM estimate per session'), findsOneWidget);

    await pump([two.first]);
    expect(find.textContaining('1RM estimate per session'), findsNothing,
        reason: 'no line through one point');

    await pump(const []);
    expect(find.text('Not logged yet'), findsOneWidget);
  });
}
