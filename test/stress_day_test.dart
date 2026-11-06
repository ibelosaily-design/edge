// The Stress Monitor's arithmetic (compute/stress_day.dart): the scale, the
// bands, what is excluded, and when it abstains.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/stress_day.dart';

void main() {
  const h = 60.0, r = 60.0; // resting HR, nightly RMSSD

  group('stressScore', () {
    test('at rest reads near zero; well below rest clamps to zero', () {
      expect(stressScore(hr: 60, hrv: 60, hrBase: h, hrvBase: r), 0);
      expect(stressScore(hr: 50, hrv: 90, hrBase: h, hrvBase: r), 0);
    });

    test('worked minutes land in the bands the header promises', () {
      // calm desk minute: +8 % HR, −17 % HRV → low
      final calm = stressScore(hr: 65, hrv: 50, hrBase: h, hrvBase: r);
      expect(calm, closeTo(0.6, 0.1));
      expect(stressBand(calm), 'low');
      // alert work: +25 %, −42 % → medium
      final alert = stressScore(hr: 75, hrv: 35, hrBase: h, hrvBase: r);
      expect(alert, closeTo(1.7, 0.1));
      expect(stressBand(alert), 'medium');
      // argument: +50 %, −67 % → high
      final hot = stressScore(hr: 90, hrv: 20, hrBase: h, hrvBase: r);
      expect(hot, closeTo(2.9, 0.1));
      expect(stressBand(hot), 'high');
    });

    test('saturates at 3 and never above', () {
      expect(stressScore(hr: 150, hrv: 5, hrBase: h, hrvBase: r), 3);
    });

    test('a bad baseline gives nothing rather than a division', () {
      expect(stressScore(hr: 70, hrv: 40, hrBase: 0, hrvBase: r), 0);
    });
  });

  group('stressBaseline', () {
    test('needs the minimum nights, takes the median of the last 14', () {
      expect(stressBaseline([60, 61, 62]), isNull);
      expect(stressBaseline([60, 61, 62, 63]), 61.5);
      final many = [for (var i = 0; i < 30; i++) 40.0 + i]; // oldest first
      // last 14 are 56..69 → median 62.5
      expect(stressBaseline(many), 62.5);
    });
  });

  group('stressDay', () {
    final rhr = List.filled(7, h);
    final rmssd = List.filled(7, r);
    const day0 = 1_700_000_100; // on a five-minute bucket edge (% 300 == 0)
    List<TimePoint> line(int from, int n, double Function(int) v) =>
        [for (var i = 0; i < n; i++) (t: from + i * 60, v: v(i))];

    test('abstains without a baseline and says how many nights it has', () {
      final (d, why) = stressDay(
        hrv: line(day0, 10, (_) => 50),
        hr: line(day0, 10, (_) => 70),
        activity: const [],
        exclude: const [],
        rhrNights: const [60, 61],
        rmssdNights: rmssd,
      );
      expect(d, isNull);
      expect(why!.note, 'need_baseline');
      expect(why.have, 2);
      expect(why.need, kStressMinBaselineNights);
    });

    test('scores still minutes, drops moving and exerting ones, counts them',
        () {
      final hrv = line(day0, 30, (_) => 40); // −33 %
      final hr = line(day0, 30, (i) => i < 10 ? 70 : (i < 20 ? 100 : 70));
      // Minutes 20..29 fall in a moving bucket.
      final activity = <TimePoint>[
        (t: day0 + 20 * 60, v: 0.8),
        (t: day0 + 25 * 60, v: 0.8),
      ];
      final (d, why) = stressDay(
        hrv: hrv,
        hr: hr,
        activity: activity,
        exclude: const [],
        rhrNights: rhr,
        rmssdNights: rmssd,
      );
      expect(why, isNull);
      expect(d!.points.length, 10, reason: 'minutes 0–9 only');
      expect(d.activeMin, 20, reason: '10 at 100 bpm (≥1.6×60), 10 moving');
      expect(d.mean, closeTo(stressScore(hr: 70, hrv: 40, hrBase: h, hrvBase: r), 1e-9));
      expect(d.latest.t, day0 + 9 * 60);
      expect(d.scoredMin, 10);
      expect(d.nights, 7);
    });

    test('sleep, naps and workouts are not stress minutes', () {
      final hrv = line(day0, 20, (_) => 30);
      final hr = line(day0, 20, (_) => 80);
      final (d, _) = stressDay(
        hrv: hrv,
        hr: hr,
        activity: const [],
        exclude: [(day0, day0 + 10 * 60)],
        rhrNights: rhr,
        rmssdNights: rmssd,
      );
      expect(d!.points.first.t, day0 + 10 * 60);
      expect(d.points.length, 10);
      expect(d.activeMin, 0, reason: 'an excluded span is not activity');
    });

    test('an HRV sample with no heart-rate minute near it is skipped', () {
      final (d, why) = stressDay(
        hrv: line(day0, 12, (_) => 40),
        hr: [(t: day0 + 3600, v: 70)],
        activity: const [],
        exclude: const [],
        rhrNights: rhr,
        rmssdNights: rmssd,
      );
      expect(d, isNull);
      expect(why!.note, 'no_still');
    });

    test('stressSleep scores only the night, with no movement gate', () {
      final hrv = line(day0, 60, (_) => 55);
      final hr = line(day0, 60, (i) => i < 30 ? 62 : 100);
      final night = (day0, day0 + 30 * 60);
      final n = stressSleep(
          hrv: hrv, hr: hr, sleep: night, rhrNights: rhr, rmssdNights: rmssd)!;
      expect(n.points.length, 30);
      expect(n.points.last.t, day0 + 29 * 60);
      expect(n.activeMin, 0);
      // 100 bpm at minute 30+ is outside the window, so it is not here —
      // but inside the window an exertion-level minute would still count.
      final n2 = stressSleep(
          hrv: hrv,
          hr: hr,
          sleep: (day0, day0 + 60 * 60),
          rhrNights: rhr,
          rmssdNights: rmssd)!;
      expect(n2.points.length, 60);
      expect(stressSleep(
              hrv: hrv, hr: hr, sleep: night, rhrNights: const [60], rmssdNights: rmssd),
          isNull);
    });

    test('band minutes weight each point by its gap, capped at five minutes',
        () {
      // Three points: 0 min (low), 2 min (high), 60 min later (medium).
      final hrv = <TimePoint>[
        (t: day0, v: 60), // 0
        (t: day0 + 120, v: 15), // high
        (t: day0 + 3720, v: 40), // medium-ish with hr 78
      ];
      final hr = <TimePoint>[
        (t: day0, v: 60),
        (t: day0 + 120, v: 95),
        (t: day0 + 3720, v: 78),
      ];
      final (d, _) = stressDay(
        hrv: hrv,
        hr: hr,
        activity: const [],
        exclude: const [],
        rhrNights: rhr,
        rmssdNights: rmssd,
      );
      expect(d!.lowMin, 2); // gap to the next point
      expect(d.highMin, 5); // 60 min gap, capped
      expect(d.midMin, 1); // last point, one minute
      expect(d.peak.t, day0 + 120);
    });
  });
}
