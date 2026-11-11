// compute/correlate.dart: Pearson over paired days, the gates that keep a
// coin-flip from becoming a number, and the overlay scaling.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/correlate.dart';

Map<String, double> _days(List<double> v, {int from = 1}) => {
      for (var i = 0; i < v.length; i++)
        '2026-09-${(from + i).toString().padLeft(2, '0')}': v[i],
    };

void main() {
  group('pearson', () {
    test('perfect lines read ±1; a flat side or too few pairs read null', () {
      final x = [for (var i = 0; i < 12; i++) i.toDouble()];
      expect(pearson(x, x), closeTo(1, 1e-12));
      expect(pearson(x, [for (final v in x) 100 - v]), closeTo(-1, 1e-12));
      expect(pearson(x, List.filled(12, 3.0)), isNull);
      expect(pearson(x.sublist(0, 9), x.sublist(0, 9)), isNull,
          reason: 'under kCorrMinDays');
    });
  });

  group('correlate / pairs', () {
    test('joins by day label and counts only the shared days', () {
      final a = _days([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final b = _days([2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28],
          from: 3);
      final c = correlate('a', a, 'b', b)!;
      expect(c.n, 10, reason: 'days 3..12');
      expect(c.r, closeTo(1, 1e-12));
      expect(c.strength, 'strong');
      expect(c.positive, isTrue);
    });

    test('correlatePairs lists every pair strongest first', () {
      final x = [for (var i = 0; i < 20; i++) i.toDouble()];
      final s = {
        'a': _days(x),
        'b': _days([for (final v in x) 50 - v]),
        'c': _days([for (var i = 0; i < 20; i++) (i % 3).toDouble()]),
      };
      final pairs = correlatePairs(['a', 'b', 'c'], s);
      expect(pairs.first.a, 'a');
      expect(pairs.first.b, 'b');
      expect(pairs.first.r, closeTo(-1, 1e-12));
      expect(pairs.length, 3);
      expect(pairs.last.r.abs(), lessThanOrEqualTo(pairs[1].r.abs()));
    });

    test('correlatesOf keeps |r| ≥ 0.30 only, at most six, strongest first',
        () {
      final x = [for (var i = 0; i < 30; i++) i.toDouble()];
      final s = <String, Map<String, double>>{'k': _days(x)};
      for (var j = 0; j < 8; j++) {
        s['o$j'] = _days([for (final v in x) v * (j + 1) + (j.isEven ? 0 : 1)]);
      }
      s['flat'] = _days(List.filled(30, 7.0));
      s['noise'] = _days([for (var i = 0; i < 30; i++) (i * 7 % 5).toDouble()]);
      final out = correlatesOf('k', s);
      expect(out.length, 6);
      expect(out.every((c) => c.r.abs() >= kCorrMinAbs), isTrue);
      expect(out.any((c) => c.b == 'flat'), isFalse);
      expect(out.any((c) => c.b == 'k'), isFalse);
    });
  });

  group('normalizeOverlay', () {
    test('scales each series to 0..1 inside the window, null where absent',
        () {
      final days = ['2026-09-01', '2026-09-02', '2026-09-03', '2026-09-04'];
      final out = normalizeOverlay({
        'a': {'2026-09-01': 10, '2026-09-02': 20, '2026-09-04': 30},
        'flat': {'2026-09-01': 5, '2026-09-03': 5},
      }, days);
      expect(out['a'], [0.0, 0.5, null, 1.0]);
      expect(out['flat'], [0.5, null, 0.5, null]);
    });
  });

  test('corrStrength bands', () {
    expect(corrStrength(0.1), 'weak');
    expect(corrStrength(-0.45), 'moderate');
    expect(corrStrength(0.75), 'strong');
  });
}
