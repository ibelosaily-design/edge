// Muscular load (compute/muscular_load.dart): the stated arithmetic, what is
// counted, what is left out and said so.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/muscular_load.dart';

void main() {
  const body = 70.0;
  LoadSet set(int reps, double? kg, {int? rpe, bool bw = false, int? hold}) =>
      LoadSet(reps: reps, loadKg: kg, rpe: rpe, bodyweight: bw, holdSec: hold);

  test('no body weight → null, never a default body', () {
    expect(muscularLoad([set(5, 80)], bodyKg: null), isNull);
    expect(muscularLoad([set(5, 80)], bodyKg: 0), isNull);
  });

  test('tonnage and relative volume are load × reps over body weight', () {
    final ml = muscularLoad([for (var i = 0; i < 5; i++) set(5, 80)],
        bodyKg: body)!;
    expect(ml.tonnageKg, 2000);
    expect(ml.relativeVolume, closeTo(2000 / 70, 1e-9));
    expect(ml.sets, 5);
    expect(ml.unloadedSets, 0);
  });

  test('the scale anchors: RV 100 ≈ 14, RV 30 ≈ 5.9, never reaches 21', () {
    MuscularLoad at(double rv) =>
        muscularLoad([set(1, rv * body)], bodyKg: body)!;
    expect(at(100).value, closeTo(14.0, 0.1));
    expect(at(30).value, closeTo(5.9, 0.1));
    expect(at(200).value, closeTo(18.7, 0.1));
    // Saturates: RV 500 is a fraction under the ceiling (exp(−500/91)).
    expect(at(500).value, lessThan(21));
    expect(at(500).value, greaterThan(20.8));
  });

  test('a bodyweight set counts about two-thirds of the body; a loaded one adds',
      () {
    final pullUps = muscularLoad([set(10, null, bw: true)], bodyKg: body)!;
    expect(pullUps.tonnageKg, closeTo(10 * kBodyweightShare * body, 1e-9));
    final weighted = muscularLoad([set(10, 10, bw: true)], bodyKg: body)!;
    expect(weighted.tonnageKg, closeTo(10 * (10 + kBodyweightShare * body), 1e-9));
  });

  test('an unloaded set on a loaded lift is left out and counted', () {
    final ml = muscularLoad([set(5, 80), set(5, null)], bodyKg: body)!;
    expect(ml.sets, 1);
    expect(ml.unloadedSets, 1);
    expect(ml.tonnageKg, 400);
    expect(muscularLoad([set(5, null)], bodyKg: body), isNull);
  });

  test('RPE scales the set: 9 → ×1.2, 7 → ×1, 5 → ×0.8, none → ×1', () {
    expect(rpeEffort(9), closeTo(1.2, 1e-9));
    expect(rpeEffort(7), 1);
    expect(rpeEffort(5), closeTo(0.8, 1e-9));
    expect(rpeEffort(null), 1);
    final hard = muscularLoad([set(5, 80, rpe: 9)], bodyKg: body)!;
    expect(hard.tonnageKg, closeTo(480, 1e-9));
  });

  test('a hold counts ten seconds as a rep', () {
    final plank = muscularLoad([set(0, null, bw: true, hold: 60)], bodyKg: body)!;
    expect(plank.tonnageKg, closeTo(6 * kBodyweightShare * body, 1e-9));
    expect(muscularLoad([set(0, null, bw: true, hold: 5)], bodyKg: body), isNull);
  });
}
