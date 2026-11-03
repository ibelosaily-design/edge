import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/match_sets.dart';

void main() {
  // Six minutes: two closed sets of three minutes each.
  final hr = <double?>[120, 140, 160, 130, null, 150];

  test('each closed set gets its own minutes', () {
    final r = setHeartRates(hr, [180, 360], 2, 360)!;
    expect(r, hasLength(2));
    expect(r[0], (avg: 140, peak: 160));
    // The null minute is skipped, not averaged in as zero.
    expect(r[1], (avg: 140, peak: 150));
  });

  test('a set still in progress at the finish ends at the session end', () {
    final r = setHeartRates(hr, [180], 2, 360)!;
    expect(r[1], (avg: 140, peak: 150));
  });

  test('a set with no recorded minute has no figure', () {
    final r = setHeartRates(<double?>[null, null, 150], [120], 2, 180)!;
    expect(r[0], (avg: null, peak: null));
    expect(r[1], (avg: 150, peak: 150));
  });

  test('ends that do not match the score give nothing rather than a guess', () {
    expect(setHeartRates(hr, const [], 3, 360), isNull);
    expect(setHeartRates(hr, [300, 120], 2, 360), isNull);
  });

  test('no sets, no rows', () {
    expect(setHeartRates(hr, const [], 0, 360), isEmpty);
  });
}
