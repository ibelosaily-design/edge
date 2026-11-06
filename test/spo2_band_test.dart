// The band-reported SpO2 summary (compute/spo2_band.dart) and its gates. The
// byte's encoding is not pinned, so every test here is about what the module
// refuses or counts, not about what a percentage means.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derive_prepare.dart';
import 'package:openstrap_edge/compute/spo2_band.dart';
import 'package:openstrap_edge/compute/substrate.dart';

void main() {
  group('spo2BandNight', () {
    test('an empty or all-absent night is null, not a shape of nulls', () {
      expect(spo2BandNight(const []), isNull);
      expect(spo2BandNight(List.filled(3600, -1)), isNull);
      expect(spo2BandNight(List.filled(3600, 0)), isNull);
    });

    test('fewer than kSpo2BandMinSamples readable samples is no night', () {
      final bytes = List.filled(3600, 0)
        ..setRange(0, kSpo2BandMinSamples - 1,
            List.filled(kSpo2BandMinSamples - 1, 96));
      expect(spo2BandNight(bytes), isNull);
      bytes[kSpo2BandMinSamples - 1] = 96;
      expect(spo2BandNight(bytes)?.n, kSpo2BandMinSamples);
    });

    test('median and min over the kept bytes; absent seconds ignored', () {
      final bytes = <int>[
        ...List.filled(500, 0),
        97, 96, 98, 95, 99, 96, 97, 94, 96, 97, 98, // 11 values
        ...List.filled(500, -1),
      ];
      final n = spo2BandNight(bytes)!;
      expect(n.n, 11);
      expect(n.median, 97);
      expect(n.min, 94);
      expect(n.flaggedN, 0);
      expect(n.unreadN, 0);
    });

    test('even count rounds the median half up', () {
      final n = spo2BandNight([96, 96, 96, 96, 96, 97, 97, 97, 97, 97])!;
      expect(n.median, 97);
    });

    test('bit 7 is stripped and counted, never read as part of the number',
        () {
      final bytes = [for (var i = 0; i < 12; i++) 128 + 96, 95];
      final n = spo2BandNight(bytes)!;
      expect(n.n, 13);
      expect(n.median, 96);
      expect(n.flaggedN, 12);
      expect(n.min, 95);
    });

    test('a stripped value outside the readable range is dropped and counted',
        () {
      final bytes = [
        ...List.filled(12, 96),
        1, 2, 3, 127, 79, 101, // status codes, not saturations
      ];
      final n = spo2BandNight(bytes)!;
      expect(n.n, 12);
      expect(n.unreadN, 6);
      expect(n.median, 96);
      expect(spo2BandNight([...List.filled(20, 5), 96]), isNull,
          reason: 'codes alone never make a night');
    });

    test('toJson carries the caveat and no key the UI could read as measured',
        () {
      final j = spo2BandNight(List.filled(10, 96))!.toJson();
      expect(j['value'], 96);
      expect(j['note'], kSpo2BandNote);
      expect(j.keys, isNot(contains('tier')));
      expect(j.keys, isNot(contains('confidence')));
    });
  });

  group('Substrate.spo2Cand (decoded rows → substrate → isolate)', () {
    Map<String, Object?> row(int ts, Object? cand) => {
          'counter': ts, 'rec_ts': ts, 'hr': 60, 'ax': 0.1, 'ay': 0.2,
          'az': 0.95, 'device_family': 'gen5', 'device_id': 'd',
          'spo2_cand': cand,
        };

    test('NULL is -1 (absent); a stored byte comes through as written', () {
      final sub = substrateFromDecodedPage(
          [row(1000, 96), row(1001, null), row(1002, 128 + 97)], const []);
      expect(sub.spo2Cand, [96, -1, 225]);
      expect(sub.spo2CandSlice(1, 3), [-1, 225]);
    });

    test('a beat-only second keeps alignment with -1', () {
      final sub = substrateFromDecodedPage([row(1000, 96), row(1002, 97)],
          [{'rec_ts': 1001, 'rr_ms': 900}]);
      expect(sub.tsSec, [1000, 1001, 1002]);
      expect(sub.spo2Cand, [96, -1, 97]);
    });

    test('slice() and sliceIdx() both carry it', () {
      final sub = substrateFromDecodedPage(
          [for (var t = 1000; t < 1010; t++) row(t, t < 1005 ? 96 : 97)],
          const []);
      expect(sub.sliceIdx(3, 7).spo2Cand, [96, 96, 97, 97]);
      expect(sub.slice(1003, 1007).spo2Cand, [96, 96, 97, 97]);
    });

    test('round-trips through JSON; a legacy payload is all -1', () {
      final sub =
          substrateFromDecodedPage([row(1000, 96), row(1001, 97)], const []);
      expect(Substrate.fromJson(sub.toJson()).spo2Cand, [96, 97]);
      final m = sub.toJson()..remove('spo2_cand');
      expect(Substrate.fromJson(m).spo2CandSlice(0, 2), [-1, -1]);
    });

    test('a gen4 page (no column) yields no night', () {
      final sub = substrateFromDecodedPage(
          [for (var t = 1000; t < 1100; t++) row(t, null)], const []);
      expect(spo2BandNight(sub.spo2Cand), isNull);
    });
  });
}
