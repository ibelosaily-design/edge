// Study progress: a small Leitner scheduler for vocabulary, plus which
// passages and stories are done and a per-day tally. Persisted as one JSON
// string in Prefs (`study.progress.v1`), read synchronously like every other
// UI preference. Day keys are local day labels (data/day_label.dart) — never
// UTC substrings.

import 'dart:convert';
import 'dart:math' as math;

import '../data/day_label.dart';
import '../state/prefs.dart';

/// Leitner boxes 0..4 and the days until the next review for each.
const _intervals = [0, 1, 3, 7, 14];

class WordState {
  int box;
  String due; // day label, '' = due now
  int seen;
  int ok;
  WordState({this.box = 0, this.due = '', this.seen = 0, this.ok = 0});

  Map<String, dynamic> toJson() => {'b': box, 'd': due, 's': seen, 'o': ok};
  static WordState fromJson(Map<String, dynamic> j) => WordState(
        box: (j['b'] as num?)?.toInt() ?? 0,
        due: j['d'] as String? ?? '',
        seen: (j['s'] as num?)?.toInt() ?? 0,
        ok: (j['o'] as num?)?.toInt() ?? 0,
      );

  /// Box 3+ means the word has survived a week — "known".
  bool get known => box >= 3;
}

class DayTally {
  int words;
  int passages;
  int stories;
  int minutes;
  DayTally({this.words = 0, this.passages = 0, this.stories = 0, this.minutes = 0});

  Map<String, dynamic> toJson() =>
      {'w': words, 'p': passages, 's': stories, 'm': minutes};
  static DayTally fromJson(Map<String, dynamic> j) => DayTally(
        words: (j['w'] as num?)?.toInt() ?? 0,
        passages: (j['p'] as num?)?.toInt() ?? 0,
        stories: (j['s'] as num?)?.toInt() ?? 0,
        minutes: (j['m'] as num?)?.toInt() ?? 0,
      );

  bool get any => words > 0 || passages > 0 || stories > 0;
}

class StudyProgress {
  static const key = 'study.progress.v1';

  /// New words introduced per day on top of what is due.
  static const newPerDay = 20;

  final Map<String, WordState> words;

  /// passage id → chosen option index (the first attempt is what counts).
  final Map<String, int> passages;
  final Set<String> storiesRead;
  final Map<String, DayTally> days;

  StudyProgress._(this.words, this.passages, this.storiesRead, this.days);

  static StudyProgress? _cached;

  static StudyProgress load() {
    final c = _cached;
    if (c != null) return c;
    final raw = Prefs.getString(key, '');
    if (raw.isEmpty) {
      return _cached = StudyProgress._({}, {}, {}, {});
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return _cached = StudyProgress._(
        {
          for (final e in ((j['words'] as Map?) ?? const {}).entries)
            e.key as String:
                WordState.fromJson((e.value as Map).cast<String, dynamic>()),
        },
        {
          for (final e in ((j['passages'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num).toInt(),
        },
        {for (final s in ((j['stories'] as List?) ?? const [])) s as String},
        {
          for (final e in ((j['days'] as Map?) ?? const {}).entries)
            e.key as String:
                DayTally.fromJson((e.value as Map).cast<String, dynamic>()),
        },
      );
    } catch (_) {
      // A corrupt blob is not worth a crash on the Study tab; start over.
      return _cached = StudyProgress._({}, {}, {}, {});
    }
  }

  void save() {
    Prefs.setString(
      key,
      jsonEncode({
        'v': 1,
        'words': {for (final e in words.entries) e.key: e.value.toJson()},
        'passages': passages,
        'stories': storiesRead.toList(),
        'days': {for (final e in days.entries) e.key: e.value.toJson()},
      }),
    );
  }

  DayTally today() => days.putIfAbsent(todayLabel(), DayTally.new);

  // ── vocabulary ──────────────────────────────────────────────────────────

  bool isDue(String id, String day) {
    final s = words[id];
    if (s == null) return false;
    return s.due.isEmpty || s.due.compareTo(day) <= 0;
  }

  /// Words to review today: everything whose box interval has elapsed.
  List<String> dueToday(Iterable<String> allIds) {
    final day = todayLabel();
    return [for (final id in allIds) if (isDue(id, day)) id];
  }

  /// Unseen words, in pack order, up to [newPerDay] minus what today already
  /// introduced — so a long session does not drain the whole deck in a day.
  List<String> newToday(Iterable<String> allIds) {
    final left = newPerDay - math.min(today().words, newPerDay);
    if (left <= 0) return const [];
    final out = <String>[];
    for (final id in allIds) {
      if (!words.containsKey(id)) {
        out.add(id);
        if (out.length >= left) break;
      }
    }
    return out;
  }

  /// Record one flashcard answer. Correct moves the word up a box (max 4) and
  /// schedules it `interval` days out; wrong drops it to box 0, due tomorrow.
  void answerWord(String id, {required bool correct}) {
    final s = words.putIfAbsent(id, WordState.new);
    s.seen += 1;
    if (correct) {
      s.ok += 1;
      s.box = math.min(s.box + 1, _intervals.length - 1);
    } else {
      s.box = 0;
    }
    final days = correct ? _intervals[s.box] : 1;
    s.due = dayLabelOf(DateTime.now().add(Duration(days: days)));
    today().words += 1;
    save();
  }

  int knownCount() => words.values.where((w) => w.known).length;

  // ── passages ────────────────────────────────────────────────────────────

  void answerPassage(String id, int chosen, {required bool correct}) {
    if (passages.containsKey(id)) return; // first attempt counts
    passages[id] = chosen;
    today().passages += 1;
    save();
  }

  // ── stories ─────────────────────────────────────────────────────────────

  void finishStory(String id) {
    if (storiesRead.add(id)) {
      today().stories += 1;
      save();
    }
  }

  // ── streak ──────────────────────────────────────────────────────────────

  /// Consecutive days, ending today or yesterday, with any study activity.
  int streak() {
    var n = 0;
    var d = DateTime.now();
    var label = dayLabelOf(d);
    if (!(days[label]?.any ?? false)) {
      d = d.subtract(const Duration(days: 1));
      label = dayLabelOf(d);
    }
    while (days[label]?.any ?? false) {
      n += 1;
      d = d.subtract(const Duration(days: 1));
      label = dayLabelOf(d);
    }
    return n;
  }
}
