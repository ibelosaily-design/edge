// MUSCULAR LOAD — what a strength session asked of the muscles, from the sets
// that were logged, on a 0–21 scale like strain's. WHOOP's Strength Trainer
// reports the same quantity under the same name; its formula is not public,
// so this one is written down here and shown with the number as an estimate.
//
// Heart rate under-reads lifting: a heavy set of five barely moves it, so a
// strength session scored on TRIMP alone looks like a walk. This number is the
// other half, and it is kept APART from strain — shown beside it, never added
// into it — so the day's strain stays the one the pipeline measured.
//
// THE ARITHMETIC. For each set with a rep count:
//   load  = external kg + (body-weight exercise ? kBodyweightShare × body kg : 0)
//   work  = load × reps × effort,  effort = 1 + (RPE − 7) / 10 when an RPE was
//           logged (RPE 9 → 1.2, RPE 5 → 0.8), else 1
// Relative volume RV = Σ work / body kg — tonnage in units of the body that
// moved it, so a 60 kg and a 90 kg lifter doing the same relative session
// score alike. Then
//   muscular load = 21 · (1 − exp(−RV / kMuscularScale))
// kMuscularScale 91 puts RV 100 (about seven tonnes for a 70 kg person — a
// hard full session) at 14.0, RV 30 (a short accessory session) at 5.9, and
// RV 200 at 18.7. The curve saturates like strain's, so doubling the tonnage
// never doubles the number.
//
// WHAT IS LEFT OUT, and said so: a set with no load on a non-bodyweight lift
// (nobody recorded the kilos — counted in [MuscularLoad.unloadedSets], not in
// the number); a session with no body weight in the profile (RV needs it;
// null, never a default body). Isometric holds count their seconds as reps
// at a tenth — ten seconds of plank as one rep of bodyweight — stated in
// [kHoldSecPerRep].

import 'dart:math' as math;

/// Fraction of body mass a bodyweight movement lifts, as one constant: a
/// push-up loads ~64 % of body weight on the hands (Suprak 2011), a pull-up
/// 100 %, an air squat ~85 %. Two-thirds stands for the family.
///
/// ponytail: one share for every bodyweight exercise. A per-exercise table
/// (push-up 0.64, pull-up 1.0, dip 1.0, squat 0.85 …) is the obvious upgrade
/// and changes a session's number by a few tenths at most.
const double kBodyweightShare = 0.65;

/// Relative volume at which the scale reaches 21 · (1 − 1/e) ≈ 13.3.
const double kMuscularScale = 91;

/// Seconds of an isometric hold that count as one rep.
const int kHoldSecPerRep = 10;

/// One logged set, as this module needs it. [bodyweight] is the exercise's
/// own flag (ExerciseDef.bodyweight), not a property of the set.
class LoadSet {
  final int reps;
  final double? loadKg;
  final int? rpe;
  final int? holdSec;
  final bool bodyweight;
  const LoadSet({
    required this.reps,
    this.loadKg,
    this.rpe,
    this.holdSec,
    required this.bodyweight,
  });
}

class MuscularLoad {
  /// 0–21.
  final double value;

  /// Σ work, kg.
  final double tonnageKg;

  /// Σ work / body kg.
  final double relativeVolume;

  /// Sets that counted.
  final int sets;

  /// Non-bodyweight sets logged without a load — not in the number.
  final int unloadedSets;

  const MuscularLoad({
    required this.value,
    required this.tonnageKg,
    required this.relativeVolume,
    required this.sets,
    required this.unloadedSets,
  });
}

/// The effort multiplier for a logged RPE (1 when none).
double rpeEffort(int? rpe) =>
    rpe == null ? 1 : (1 + (rpe.clamp(1, 10) - 7) / 10);

/// The session's muscular load, or null when [bodyKg] is unknown or no set
/// could be counted.
MuscularLoad? muscularLoad(List<LoadSet> sets, {required double? bodyKg}) {
  if (bodyKg == null || bodyKg <= 0) return null;
  var work = 0.0;
  var counted = 0, unloaded = 0;
  for (final s in sets) {
    var reps = s.reps;
    if (reps <= 0 && (s.holdSec ?? 0) > 0) reps = s.holdSec! ~/ kHoldSecPerRep;
    if (reps <= 0) continue;
    final ext = s.loadKg ?? 0;
    if (!s.bodyweight && s.loadKg == null) {
      unloaded++;
      continue;
    }
    final load = ext + (s.bodyweight ? kBodyweightShare * bodyKg : 0);
    if (load <= 0) continue;
    work += load * reps * rpeEffort(s.rpe);
    counted++;
  }
  if (counted == 0) return null;
  final rv = work / bodyKg;
  return MuscularLoad(
    value: 21 * (1 - math.exp(-rv / kMuscularScale)),
    tonnageKg: work,
    relativeVolume: rv,
    sets: counted,
    unloadedSets: unloaded,
  );
}
