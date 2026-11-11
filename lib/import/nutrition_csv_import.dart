// Import a food log another app exported — Cronometer "Servings",
// MacroFactor, MyFitnessPal's food diary, Lose It — as eating occasions.
//
// HEADER-DRIVEN, NOT VENDOR-DRIVEN. The vendors rename columns between
// versions, so this reads the header once and finds, by name, a day column,
// an optional time and meal column, a food name, an optional amount, and
// whichever nutrient columns it recognises (energy, protein, carbs, fat,
// fibre, sugars, saturated fat, sodium, iron, calcium). A file with a day
// and a food name is a food log; a file with a day and energy but NO food
// name is a daily summary (Cronometer's "Daily Nutrition"), which this
// refuses with a sentence saying which export to take instead — one row per
// day cannot become occasions without inventing meals.
//
// NULL IS NOT ZERO, as everywhere in nutrition_store.dart: a nutrient column
// the file lacks is simply absent on every entry, and an empty cell is
// absent on that row. A row with no readable day, or no food name, is
// REJECTED and reported by line number — never clamped or guessed.
//
// A meal the app does not know ("Pre-workout", "Supplements") lands as a
// snack with the original name kept in the entry's note, so nothing is lost
// and nothing is fabricated as a breakfast.
//
// IDEMPOTENT. The entry id is a hash of (source, day, time, food, amount,
// energy), so importing the same file twice REPLACES the rows it wrote the
// first time instead of doubling the day.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;

import '../data/db.dart';
import '../data/nutrition_store.dart';
import 'journal_csv_import.dart' show RejectedRow, parseCsv;

class NutritionCsvFormatException implements Exception {
  const NutritionCsvFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

@immutable
class NutritionCsvParse {
  const NutritionCsvParse(this.entries, this.rejected, this.source);
  final List<FoodEntry> entries;
  final List<RejectedRow> rejected;

  /// The app the header looked like, for the note and the report.
  final String source;
}

class NutritionImportResult {
  const NutritionImportResult(this.imported, this.rejected, this.source);
  final int imported;
  final List<RejectedRow> rejected;
  final String source;
}

/// Column roles found in a header; -1 = absent.
class _Cols {
  int day = -1, time = -1, meal = -1, name = -1, amount = -1, unit = -1;
  final nutrients = <String, int>{};
}

String _norm(String h) => h.trim().toLowerCase().replaceAll('_', ' ');

/// Which role a header cell plays, by name.
_Cols _mapHeader(List<String> header) {
  final c = _Cols();
  for (var i = 0; i < header.length; i++) {
    final h = _norm(header[i]);
    if (h.isEmpty) continue;
    if (c.day < 0 && (h == 'day' || h == 'date' || h.startsWith('date '))) {
      c.day = i;
    } else if (c.time < 0 && h == 'time') {
      c.time = i;
    } else if (c.meal < 0 &&
        (h == 'group' || h == 'meal' || h == 'meal type' || h == 'type')) {
      c.meal = i;
    } else if (c.name < 0 &&
        (h == 'food name' || h == 'food' || h == 'name' || h == 'item')) {
      c.name = i;
    } else if (c.amount < 0 &&
        (h == 'amount' || h == 'serving size' || h == 'quantity' ||
            h == 'serving')) {
      c.amount = i;
    } else if (c.unit < 0 && (h == 'units' || h == 'unit')) {
      c.unit = i;
    } else {
      final k = _nutrientKey(h);
      if (k != null && !c.nutrients.containsKey(k)) c.nutrients[k] = i;
    }
  }
  return c;
}

/// Our nutrient key for a header, or null when it is not one we store.
String? _nutrientKey(String h) {
  bool has(String s) => h.contains(s);
  if (has('saturated') && !has('mono') && !has('poly')) return 'sat_fat';
  if (has('energy') || has('calories') || h == 'kcal') return 'kcal';
  if (has('protein')) return 'protein';
  if (has('net carb')) return null;
  if (has('carb')) return 'carbs';
  if (has('fiber') || has('fibre')) return 'fibre';
  if (has('added sugar')) return null;
  if (has('sugar')) return 'sugar';
  if (has('sodium')) return 'sodium';
  if (has('calcium')) return 'calcium';
  if (has('iron') && !has('environ')) return 'iron';
  if (h == 'fat' || h.startsWith('fat (') || h == 'fat (g)' || h == 'total fat') {
    return 'fat';
  }
  if (has('fat') && !has('mono') && !has('poly') && !has('trans') && !has('omega')) {
    return 'fat';
  }
  return null;
}

String _sourceOf(List<String> header) {
  final h = header.map(_norm).toSet();
  if (h.contains('group') && h.contains('food name')) return 'Cronometer';
  if (h.contains('meal type') || (h.contains('meal') && h.contains('food name'))) {
    return 'food diary';
  }
  if (h.contains('type') && h.contains('name') && h.contains('units')) {
    return 'Lose It';
  }
  return 'food log';
}

/// `YYYY-MM-DD` from the day cell: ISO as written, or a `M/D/YYYY`.
String? _day(String s) {
  final t = s.trim();
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
  if (iso != null) return _valid(iso[1]!, iso[2]!, iso[3]!);
  final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(t);
  if (us != null) {
    return _valid(us[3]!, us[1]!.padLeft(2, '0'), us[2]!.padLeft(2, '0'));
  }
  return null;
}

String? _valid(String y, String m, String d) {
  final yy = int.tryParse(y), mm = int.tryParse(m), dd = int.tryParse(d);
  if (yy == null || mm == null || dd == null) return null;
  if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
  final dt = DateTime(yy, mm, dd);
  if (dt.month != mm || dt.day != dd) return null;
  return '$y-$m-$d';
}

double? _num(String s) {
  final t = s.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  final m = RegExp(r'^-?\d+(\.\d+)?').firstMatch(t);
  return m == null ? null : double.tryParse(m[0]!);
}

/// "100.00 g" → (100, 'g'); "1 cup" → (1, 'cup'); "2" → (2, null).
(double?, String?) _amount(String s) {
  final t = s.trim();
  if (t.isEmpty) return (null, null);
  final m = RegExp(r'^(-?\d+(?:\.\d+)?)\s*(.*)$').firstMatch(t);
  if (m == null) return (null, null);
  final u = m[2]!.trim();
  return (double.tryParse(m[1]!), u.isEmpty ? null : u);
}

/// Our four meals from the vendor's group name; null for one we do not know.
String? mealOf(String s) {
  final t = _norm(s);
  if (t.startsWith('breakfast')) return 'breakfast';
  if (t.startsWith('lunch')) return 'lunch';
  if (t.startsWith('dinner') || t.startsWith('supper')) return 'dinner';
  if (t.startsWith('snack')) return 'snack';
  return null;
}

/// Parse a food-log CSV. Throws [NutritionCsvFormatException] when the header
/// is not a food log at all (then the caller tries the next importer); rows
/// that fail inside a recognised file are returned as [NutritionCsvParse.rejected].
NutritionCsvParse parseNutritionCsv(String text) {
  final records = parseCsv(text);
  if (records.isEmpty) {
    throw const NutritionCsvFormatException('Empty file.');
  }
  final header = records.first;
  final c = _mapHeader(header);
  if (c.day < 0) {
    throw const NutritionCsvFormatException('No day or date column.');
  }
  if (c.name < 0) {
    if (c.nutrients.containsKey('kcal')) {
      throw const NutritionCsvFormatException(
          'This is a daily summary (one row per day, no foods). Export the '
          'food diary or "Servings" instead — one row per food.');
    }
    throw const NutritionCsvFormatException('No food name column.');
  }
  final source = _sourceOf(header);
  final entries = <FoodEntry>[];
  final rejected = <RejectedRow>[];
  for (var i = 1; i < records.length; i++) {
    final r = records[i];
    final line = i + 1;
    String cell(int idx) => idx >= 0 && idx < r.length ? r[idx] : '';
    if (r.every((x) => x.trim().isEmpty)) continue;
    final day = _day(cell(c.day));
    if (day == null) {
      rejected.add(RejectedRow(line, 'day "${cell(c.day)}" is not a date'));
      continue;
    }
    final label = cell(c.name).trim();
    if (label.isEmpty) {
      rejected.add(RejectedRow(line, 'no food name'));
      continue;
    }
    final rawMeal = cell(c.meal).trim();
    final meal = mealOf(rawMeal) ?? 'snack';
    final noteParts = <String>[
      'from $source',
      if (rawMeal.isNotEmpty && mealOf(rawMeal) == null) rawMeal,
    ];
    final (qty, unitFromAmount) = _amount(cell(c.amount));
    final unit = cell(c.unit).trim().isNotEmpty
        ? cell(c.unit).trim()
        : (unitFromAmount ?? 'g');
    double? n(String k) =>
        c.nutrients.containsKey(k) ? _num(cell(c.nutrients[k]!)) : null;
    int? atTs;
    final time = cell(c.time).trim();
    final tm = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(time);
    if (tm != null) {
      final hh = int.parse(tm[1]!), mi = int.parse(tm[2]!);
      final pm = time.toLowerCase().contains('pm') && hh < 12;
      final am = time.toLowerCase().contains('am') && hh == 12;
      final parts = day.split('-').map(int.parse).toList();
      atTs = DateTime(parts[0], parts[1], parts[2], pm ? hh + 12 : (am ? 0 : hh), mi)
              .millisecondsSinceEpoch ~/
          1000;
    }
    final kcal = n('kcal');
    final id = 'imp:${_hash('$source|$day|$time|$label|${cell(c.amount)}|$kcal')}';
    entries.add(FoodEntry(
      id: id,
      date: day,
      meal: meal,
      label: label,
      atTs: atTs,
      quantity: qty,
      unit: unit,
      kcal: kcal,
      proteinG: n('protein'),
      carbsG: n('carbs'),
      fatG: n('fat'),
      fibreG: n('fibre'),
      sugarG: n('sugar'),
      satFatG: n('sat_fat'),
      sodiumMg: n('sodium'),
      ironMg: n('iron'),
      calciumMg: n('calcium'),
      note: noteParts.join(' · '),
    ));
  }
  return NutritionCsvParse(entries, rejected, source);
}

/// FNV-1a, hex — stable across runs, no crypto needed for an id.
String _hash(String s) {
  var h = 0x811C9DC5;
  for (final c in utf8.encode(s)) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// Read [path], parse it, and write the accepted rows. Same-id rows from an
/// earlier import of the same file are replaced, not doubled.
Future<NutritionImportResult> importNutritionCsvFile(String path) async {
  final text = utf8.decode(await File(path).readAsBytes());
  final parsed = parseNutritionCsv(text);
  final db = await LocalDb.instance;
  for (final e in parsed.entries) {
    await NutritionDb.put(db, e);
  }
  return NutritionImportResult(
      parsed.entries.length, parsed.rejected, parsed.source);
}
