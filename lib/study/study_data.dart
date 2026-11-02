// The Study pack: SAT vocabulary, bilingual stories and reading passages,
// bundled as assets (assets/study/*.json) and parsed once per process.
//
// Pure data. Nothing here knows about progress, scheduling or the UI — those
// live in study_progress.dart and the screens. Loaded lazily on first use so
// the four health tabs never pay for ~550 KB of JSON they do not read.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class StudyWord {
  final String id;
  final String word;
  final String pos;
  final String ipa;
  final String ar;
  final String def;
  final List<String> syn;
  final List<String> ant;
  final String? other;
  final String ex;
  final List<String> decks;

  const StudyWord({
    required this.id,
    required this.word,
    required this.pos,
    required this.ipa,
    required this.ar,
    required this.def,
    required this.syn,
    required this.ant,
    required this.other,
    required this.ex,
    required this.decks,
  });

  static StudyWord fromJson(Map<String, dynamic> j) => StudyWord(
        id: j['id'] as String,
        word: j['w'] as String? ?? j['id'] as String,
        pos: j['pos'] as String? ?? '',
        ipa: j['ipa'] as String? ?? '',
        ar: j['ar'] as String? ?? '',
        def: j['def'] as String? ?? '',
        syn: _strings(j['syn']),
        ant: _strings(j['ant']),
        other: j['other'] as String?,
        ex: j['ex'] as String? ?? '',
        decks: _strings(j['decks']),
      );
}

class StudyPassage {
  final String id;

  /// Question-type code (wic, tsp, ctc, cid, coet, coeq, inf, bnd, fss, trn,
  /// rsy). [StudyPack.typeNames] maps it to a label.
  final String type;
  final String passage;
  final String q;
  final List<String> options;
  final int answer;
  final String whyAr;
  final String trAr;

  const StudyPassage({
    required this.id,
    required this.type,
    required this.passage,
    required this.q,
    required this.options,
    required this.answer,
    required this.whyAr,
    required this.trAr,
  });

  static StudyPassage fromJson(Map<String, dynamic> j) => StudyPassage(
        id: j['id'] as String,
        type: j['type'] as String? ?? '',
        passage: j['passage'] as String? ?? '',
        q: j['q'] as String? ?? '',
        options: _strings(j['options']),
        answer: (j['answer'] as num?)?.toInt() ?? 0,
        whyAr: j['why_ar'] as String? ?? '',
        trAr: j['tr_ar'] as String? ?? '',
      );
}

class StorySentence {
  final String en;
  final String ar;
  const StorySentence(this.en, this.ar);
}

class StoryTarget {
  final String word;
  final String form;
  final int sentence;
  final String meaningAr;
  const StoryTarget(this.word, this.form, this.sentence, this.meaningAr);
}

class StoryQuestion {
  final String q;
  final List<String> options;
  final int answer;
  final String whyAr;
  const StoryQuestion(this.q, this.options, this.answer, this.whyAr);
}

class StudyStory {
  final String id;
  final String title;
  final String titleAr;
  final String topic;
  final List<String> newWords;
  final List<StorySentence> sentences;
  final List<StoryTarget> targets;
  final List<StoryQuestion> questions;

  const StudyStory({
    required this.id,
    required this.title,
    required this.titleAr,
    required this.topic,
    required this.newWords,
    required this.sentences,
    required this.targets,
    required this.questions,
  });

  static StudyStory fromJson(Map<String, dynamic> j) => StudyStory(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        titleAr: j['title_ar'] as String? ?? '',
        topic: j['topic'] as String? ?? '',
        newWords: _strings(j['new']),
        sentences: [
          for (final s in (j['sentences'] as List? ?? const []))
            StorySentence(
              (s as Map)['en'] as String? ?? '',
              s['ar'] as String? ?? '',
            ),
        ],
        targets: [
          for (final t in (j['targets'] as List? ?? const []))
            StoryTarget(
              (t as Map)['word'] as String? ?? '',
              t['form'] as String? ?? t['word'] as String? ?? '',
              (t['sentence'] as num?)?.toInt() ?? -1,
              t['meaning_ar'] as String? ?? '',
            ),
        ],
        questions: [
          for (final q in (j['questions'] as List? ?? const []))
            StoryQuestion(
              (q as Map)['q'] as String? ?? '',
              _strings(q['options']),
              (q['answer'] as num?)?.toInt() ?? 0,
              q['why_ar'] as String? ?? '',
            ),
        ],
      );
}

List<String> _strings(Object? v) =>
    v is List ? [for (final x in v) x.toString()] : const [];

class StudyPack {
  final List<StudyWord> words;
  final List<StudyStory> stories;
  final List<StudyPassage> passages;

  /// type code → (en, ar) label.
  final Map<String, ({String en, String ar})> typeNames;

  const StudyPack({
    required this.words,
    required this.stories,
    required this.passages,
    required this.typeNames,
  });

  StudyWord? word(String id) {
    for (final w in words) {
      if (w.id == id) return w;
    }
    return null;
  }

  static Future<StudyPack>? _loading;

  /// Parsed once; later callers get the same future.
  static Future<StudyPack> load() => _loading ??= _load();

  static Future<StudyPack> _load() async {
    final wj = jsonDecode(await rootBundle.loadString('assets/study/words.json'))
        as Map<String, dynamic>;
    final sj = jsonDecode(await rootBundle.loadString('assets/study/stories.json'))
        as List;
    final rj = jsonDecode(await rootBundle.loadString('assets/study/reading.json'))
        as Map<String, dynamic>;
    final types = <String, ({String en, String ar})>{};
    for (final e in ((rj['types'] as Map?) ?? const {}).entries) {
      final v = e.value as Map;
      types[e.key as String] = (
        en: v['en'] as String? ?? e.key as String,
        ar: v['ar'] as String? ?? '',
      );
    }
    return StudyPack(
      words: [
        for (final w in (wj['words'] as List))
          StudyWord.fromJson(w as Map<String, dynamic>),
      ],
      stories: [
        for (final s in sj) StudyStory.fromJson(s as Map<String, dynamic>),
      ],
      passages: [
        for (final b in ((rj['built'] as List?) ?? const []))
          StudyPassage.fromJson(b as Map<String, dynamic>),
      ],
      typeNames: types,
    );
  }
}
