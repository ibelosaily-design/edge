// Food-log CSV import: header-driven column discovery across the vendors,
// null-not-zero nutrients, meal mapping that invents nothing, rejection by
// line, the daily-summary refusal, and ids that make a re-import replace.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/import/nutrition_csv_import.dart';

const _cronometer = '''Day,Time,Group,Food Name,Amount,Energy (kcal),Alcohol (g),Caffeine (mg),Water (g),Carbs (g),Fiber (g),Starch (g),Sugars (g),Added Sugars (g),Net Carbs (g),Fat (g),Monounsaturated (g),Polyunsaturated (g),Omega-3 (g),Saturated (g),Trans-Fats (g),Cholesterol (mg),Protein (g),Calcium (mg),Iron (mg),Sodium (mg)
2026-11-03,08:15 AM,Breakfast,"Oats, rolled",80.00 g,303.2,0,0,8.1,54.8,8.2,,0.8,,46.6,5.5,1.7,2.0,0.1,1.0,0,0,10.7,43.2,3.6,4.8
2026-11-03,01:40 PM,Lunch,Chicken breast,150.00 g,247.5,,,,,0,,,,,5.4,,,,1.5,,,46.2,,,111
2026-11-03,04:00 PM,Pre-workout,Banana,1.00 medium,105.0,,,,27.0,3.1,,14.4,,,0.4,,,,0.1,,,1.3,5.9,0.3,1.2
2026-11-03,,Snacks,Almonds,,,,,,,,,,,,,,,,,,,,,,
not-a-date,09:00 AM,Dinner,Rice,100 g,130,,,,28,,,,,,0.3,,,,,,,2.7,,,
2026-11-04,07:30 PM,Dinner,,100 g,130,,,,28,,,,,,0.3,,,,,,,2.7,,,
''';

const _loseIt = '''Date,Name,Type,Quantity,Units,Calories,Fat (g),Protein (g),Carbohydrates (g),Saturated Fat (g),Sugars (g),Fiber (g),Cholesterol (mg),Sodium (mg)
11/3/2026,Greek yogurt,Breakfast,1,cup,150,4,20,8,2.5,6,0,15,80
''';

const _summary = '''Date,Energy (kcal),Protein (g),Carbs (g),Fat (g),Completed
2026-11-03,2140,131,240,70,true
''';

void main() {
  test('Cronometer servings: columns found by name, nulls kept, meals mapped',
      () {
    final p = parseNutritionCsv(_cronometer);
    expect(p.source, 'Cronometer');
    expect(p.entries.length, 4);
    expect(p.rejected.map((r) => r.line), [6, 7]);
    expect(p.rejected.first.reason, contains('not a date'));
    expect(p.rejected.last.reason, 'no food name');

    final oats = p.entries[0];
    expect(oats.date, '2026-11-03');
    expect(oats.meal, 'breakfast');
    expect(oats.label, 'Oats, rolled');
    expect(oats.quantity, 80);
    expect(oats.unit, 'g');
    expect(oats.kcal, closeTo(303.2, 1e-9));
    expect(oats.carbsG, closeTo(54.8, 1e-9));
    expect(oats.fibreG, closeTo(8.2, 1e-9));
    expect(oats.sugarG, closeTo(0.8, 1e-9));
    expect(oats.fatG, closeTo(5.5, 1e-9), reason: 'Fat (g), not the mono/poly columns');
    expect(oats.satFatG, closeTo(1.0, 1e-9));
    expect(oats.proteinG, closeTo(10.7, 1e-9));
    expect(oats.calciumMg, closeTo(43.2, 1e-9));
    expect(oats.ironMg, closeTo(3.6, 1e-9));
    expect(oats.sodiumMg, closeTo(4.8, 1e-9));
    expect(oats.atTs, DateTime(2026, 11, 3, 8, 15).millisecondsSinceEpoch ~/ 1000);
    expect(oats.note, 'from Cronometer');

    final chicken = p.entries[1];
    expect(chicken.carbsG, isNull, reason: 'an empty cell is absent, not 0');
    expect(chicken.fibreG, 0, reason: 'a written 0 is 0');
    expect(chicken.atTs, DateTime(2026, 11, 3, 13, 40).millisecondsSinceEpoch ~/ 1000);

    final banana = p.entries[2];
    expect(banana.meal, 'snack', reason: 'an unknown group is a snack…');
    expect(banana.note, 'from Cronometer · Pre-workout',
        reason: '…with the original name kept');
    expect(banana.quantity, 1);
    expect(banana.unit, 'medium');

    final almonds = p.entries[3];
    expect(almonds.kcal, isNull);
    expect(almonds.isBareOccasion, isTrue);
    expect(almonds.atTs, isNull);
    expect(almonds.quantity, isNull);
  });

  test('Lose It: US dates, Type as meal, Units column', () {
    final p = parseNutritionCsv(_loseIt);
    expect(p.source, 'Lose It');
    final y = p.entries.single;
    expect(y.date, '2026-11-03');
    expect(y.meal, 'breakfast');
    expect(y.quantity, 1);
    expect(y.unit, 'cup');
    expect(y.kcal, 150);
    expect(y.carbsG, 8, reason: '"Carbohydrates (g)" is carbs');
    expect(y.satFatG, 2.5);
    expect(y.fatG, 4);
  });

  test('a daily summary is refused with the fix named', () {
    expect(
        () => parseNutritionCsv(_summary),
        throwsA(isA<NutritionCsvFormatException>().having(
            (e) => e.message, 'message', contains('Servings'))));
  });

  test('a file with no date column is not a food log', () {
    expect(() => parseNutritionCsv('Food Name,Calories\nRice,130\n'),
        throwsA(isA<NutritionCsvFormatException>()));
    expect(() => parseNutritionCsv(''),
        throwsA(isA<NutritionCsvFormatException>()));
  });

  test('ids are stable, so a second import replaces rather than doubles', () {
    final a = parseNutritionCsv(_cronometer).entries.map((e) => e.id).toList();
    final b = parseNutritionCsv(_cronometer).entries.map((e) => e.id).toList();
    expect(a, b);
    expect(a.toSet().length, a.length, reason: 'distinct rows, distinct ids');
    expect(a.first, startsWith('imp:'));
  });

  test('mealOf', () {
    expect(mealOf('Breakfast'), 'breakfast');
    expect(mealOf('SNACKS'), 'snack');
    expect(mealOf('Supper'), 'dinner');
    expect(mealOf('Pre-workout'), isNull);
  });
}
