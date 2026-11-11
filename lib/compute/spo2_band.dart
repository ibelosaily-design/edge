// What the band itself reports about blood oxygen over one night.
//
// WHOOP 5.0 (gen5) writes an SpO2 estimate/status byte once a second
// (`Sample.spo2Cand`, the protocol's `spo2CandidateRaw`). The protocol package
// has established the byte's FAMILY — zero outside band-declared sleep, a
// small fraction of sleep seconds carrying a value clustered at 95-99, bit 7
// behaving like a flag — but NOT its encoding, and refuses to publish a
// percentage from it. This module does not either: it summarises the bytes
// the band wrote, and every surface of the result says "as the band reports
// it", never "measured". Our own optical path cannot measure SpO2 at all (the
// red and IR ADCs are one signal; see `kSpo2Refusal`), so this is the only
// band-side SpO2 the app has, and it is kept apart from WHOOP's own nightly
// value carried in from a "My Data" export (metric_series `spo2`).
//
// Independent corroboration (2026-11-11): the NOOP Android line and its Rust
// core (tanarchytan/noop, tanarchytan/whoop-rs — PolyForm Noncommercial; no
// code is taken, the byte offset and gate are protocol facts) read the SAME
// byte (their frame-82 = this inner-74) as "the strap's own computed SpO2",
// keep it only in 70..100, drop bit-7 bytes as saturation sentinels and
// sub-70 bytes as diagnostic codes, take the in-bed median per night, and
// report it "cross-checked against the band's own readings". This module's
// gate now matches that reading exactly. What is still not done: a check of
// the number against the WHOOP app on THIS wearer's nights, so every surface
// keeps the band-reported label until that comparison is in hand.
//
// Honesty gates — any one of them failing yields null, never a shape of nulls:
//   * a second's byte of 0 is "no sample", not 0 %;
//   * a byte with bit 7 set is a sentinel: counted ([Spo2BandNight.flaggedN])
//     and dropped, never read as a value with the bit stripped;
//   * a byte below [kSpo2BandLo] is a status code we cannot read — counted
//     ([Spo2BandNight.unreadN]) and dropped;
//   * fewer than [kSpo2BandMinSamples] kept samples is no night.
//
// Pure: a list of per-second bytes in, a summary out. The engine stores the
// block ONLY when this returns non-null, so a gen4 day, an imported day and a
// gen5 day drained before the column existed carry no `spo2_band` key at all
// (the WHOOP freeze golden pins that).

/// Lowest byte read as a value (below it, a diagnostic code).
const int kSpo2BandLo = 70;

/// Highest byte read as a value; above it (bit 7) a sentinel.
const int kSpo2BandHi = 100;

/// Kept samples a night needs before it is summarised at all. The byte fires
/// on a small fraction of sleep seconds, so a 7 h night yields dozens to a
/// few hundred; ten is enough to make the median mean something and little
/// enough that a short night still reports.
const int kSpo2BandMinSamples = 10;

/// Written into the block so a reader (and a future self) sees what this is.
const String kSpo2BandNote =
    'band_reported: gen5 SpO2 byte (inner 74), read as a percent in '
    '$kSpo2BandLo-$kSpo2BandHi; bit-7 sentinels and sub-$kSpo2BandLo codes '
    'dropped (gate matches whoop-rs v18; not yet checked against WHOOP on '
    'this wearer)';

/// One night's band-reported SpO2 summary. [median] and [min] are over the
/// kept stripped bytes, in whatever unit the band uses (observed to behave
/// like a percentage; not asserted to be one).
class Spo2BandNight {
  final int median;
  final int min;

  /// Kept samples.
  final int n;

  /// Nonzero samples with bit 7 set — sentinels, dropped.
  final int flaggedN;

  /// Nonzero samples below the readable range — codes, dropped.
  final int unreadN;

  const Spo2BandNight({
    required this.median,
    required this.min,
    required this.n,
    required this.flaggedN,
    required this.unreadN,
  });

  Map<String, Object?> toJson() => {
        'value': median,
        'min': min,
        'n': n,
        'flagged_n': flaggedN,
        'unread_n': unreadN,
        'note': kSpo2BandNote,
      };
}

/// Summarise one night's per-second band SpO2 bytes ([Substrate.spo2Cand],
/// -1 or 0 where absent). Null when the night has fewer than
/// [kSpo2BandMinSamples] readable samples.
Spo2BandNight? spo2BandNight(List<int> bytes) {
  final kept = <int>[];
  var flagged = 0, unread = 0;
  for (final b in bytes) {
    if (b <= 0) continue;
    if ((b & 0x80) != 0) {
      flagged++;
      continue;
    }
    if (b < kSpo2BandLo || b > kSpo2BandHi) {
      unread++;
      continue;
    }
    kept.add(b);
  }
  if (kept.length < kSpo2BandMinSamples) return null;
  kept.sort();
  final mid = kept.length ~/ 2;
  final median =
      kept.length.isOdd ? kept[mid] : (kept[mid - 1] + kept[mid] + 1) ~/ 2;
  return Spo2BandNight(
    median: median,
    min: kept.first,
    n: kept.length,
    flaggedN: flagged,
    unreadN: unread,
  );
}
