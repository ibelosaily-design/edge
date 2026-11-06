// Strength routines: presets that resolve, and the user's own recent sessions
// turned into an exercise order — newest first, duplicates collapsed, no
// sets, reps or loads attached.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/routines.dart';
import 'package:openstrap_edge/ui2/activity/setup.dart';
import 'package:openstrap_edge/ui2/ui2.dart' show buildTheme;

Map<String, Object?> _row(String session, String key, int seq, int at) =>
    {'session_id': session, 'exercise_key': key, 'seq': seq, 'at_ts': at};

void main() {
  test('every preset lift exists in the catalogue', () {
    for (final r in kPresetRoutines) {
      expect(r.isPreset, isTrue);
      for (final k in r.exerciseKeys) {
        expect(exerciseByKey(k), isNotNull, reason: '${r.id}: $k');
      }
    }
    expect(routineName(kPresetRoutines.first, null), 'Push');
  });

  test('recent sessions become routines, newest first, in set order', () {
    final rows = [
      _row('s1', 'bench_press', 0, 1000),
      _row('s1', 'bench_press', 1, 1100),
      _row('s1', 'overhead_press', 2, 1200),
      _row('s2', 'back_squat', 0, 5000),
      _row('s2', 'deadlift', 1, 5100),
      // Same order as s1, later: collapses into one routine.
      _row('s3', 'bench_press', 0, 9000),
      _row('s3', 'overhead_press', 1, 9100),
    ];
    final out = recentRoutinesFrom(rows);
    expect(out.length, 2);
    expect(out.first.id, 'session:s3');
    expect(out.first.exerciseKeys, ['bench_press', 'overhead_press']);
    expect(out.first.lastDone,
        DateTime.fromMillisecondsSinceEpoch(9100 * 1000));
    expect(out.last.exerciseKeys, ['back_squat', 'deadlift']);
    expect(out.first.isPreset, isFalse);
    expect(routineName(out.first, null), 'Last time');
  });

  test('limit, empty input, and rows with no session are handled', () {
    expect(recentRoutinesFrom(const []), isEmpty);
    expect(recentRoutinesFrom([_row('', 'bench_press', 0, 1)]), isEmpty);
    final many = [
      for (var i = 0; i < 6; i++) _row('s$i', 'lift_$i', 0, 1000 + i),
    ];
    expect(recentRoutinesFrom(many, limit: 3).length, 3);
    expect(recentRoutinesFrom(many, limit: 3).first.exerciseKeys, ['lift_5']);
  });

  test('a subtitle names the lifts in order', () {
    expect(routineExercises(kPresetRoutines[1], 'en'),
        'Pull-up · Barbell row · Lat pulldown · Barbell curl');
  });

  testWidgets('the strength setup offers the routines; a run gets none',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Future<void> pump(String activity) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: ActivitySetup(activityByName(activity)!, weightKg: 72.4),
      ));
      await tester.pumpAndSettle();
    }

    await pump('weight_training');
    expect(find.text('Routine'), findsOneWidget);
    expect(find.text('Pick as you go'), findsOneWidget);
    for (final name in ['Push', 'Pull', 'Legs', 'Full body']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    await tester.tap(find.text('Legs'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await pump('running');
    expect(find.text('Routine'), findsNothing);
  });
}
