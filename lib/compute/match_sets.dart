// Heart rate per set of a match, from the session's per-minute HR curve and
// the elapsed second each set was closed at.
//
// The curve is one slot per minute, null where the band recorded nothing, so
// "peak" here is the highest MINUTE average, not the highest beat, and the
// summary says so. A set with no recorded minute gets no figure at all —
// absent, never zero.

/// One set's heart rate: the mean of its recorded minutes and the highest of
/// them, in bpm. Both null when the set has no recorded minute.
typedef SetHr = ({int? avg, int? peak});

/// [hrPerMin] — slot i covers elapsed seconds [60·i, 60·i + 60).
/// [setEndsSec] — the elapsed second each CLOSED set ended at, ascending.
/// [sets] — how many sets the score holds: either one per closed set, or one
/// more when a set was still in progress at the finish (it ends at
/// [totalSec]).
///
/// Returns null when the ends cannot be matched to the score (a session
/// recorded before set ends were stamped), so the screen shows the score
/// without inventing where each set began.
List<SetHr>? setHeartRates(
  List<double?> hrPerMin,
  List<int> setEndsSec,
  int sets,
  int totalSec,
) {
  if (sets == 0) return const [];
  final ends = [...setEndsSec];
  if (ends.length == sets - 1) {
    ends.add(totalSec);
  } else if (ends.length != sets) {
    return null;
  }
  for (var i = 1; i < ends.length; i++) {
    if (ends[i] < ends[i - 1]) return null;
  }
  final out = <SetHr>[];
  var start = 0;
  for (final end in ends) {
    final vals = <double>[];
    for (var m = 0; m < hrPerMin.length; m++) {
      final t = m * 60;
      if (t < start || t >= end) continue;
      final v = hrPerMin[m];
      if (v != null && v > 0) vals.add(v);
    }
    if (vals.isEmpty) {
      out.add((avg: null, peak: null));
    } else {
      final sum = vals.reduce((a, b) => a + b);
      final peak = vals.reduce((a, b) => a > b ? a : b);
      out.add((avg: (sum / vals.length).round(), peak: peak.round()));
    }
    start = end;
  }
  return out;
}
