// Study audio: bundled clips for word pronunciation (normal and slow), the
// example sentence, and stories and passages read aloud — sentence by
// sentence, from the Kalimat SAT pack (Kokoro TTS, voice in index.json).
//
// Each entry in assets/study/audio/index.json names a sprite file and the
// start/end seconds of the clip inside it. Nothing is fetched; a word or
// passage without an entry simply has no play button.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:just_audio/just_audio.dart';

typedef AudioClip = ({String file, double start, double end});

class StudyAudio {
  static const _dir = 'assets/study/audio';

  final Map<String, AudioClip> _word, _slow, _ex;
  final Map<String, List<AudioClip>> _story, _passage;

  StudyAudio._(this._word, this._slow, this._ex, this._story, this._passage);

  static Future<StudyAudio?>? _loading;
  static AudioPlayer? _player;

  /// The index, loaded once. Null when the pack ships without audio.
  static Future<StudyAudio?> load() => _loading ??= _load();

  static Future<StudyAudio?> _load() async {
    try {
      final j = jsonDecode(await rootBundle.loadString('$_dir/index.json'))
          as Map<String, dynamic>;
      return StudyAudio._(
        _clips(j['words']),
        _clips(j['slow']),
        _clips(j['ex']),
        _sentences(j['stories']),
        _sentences(j['passages']),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, AudioClip> _clips(Object? m) => {
        if (m is Map)
          for (final e in m.entries)
            if (e.value case [final String f, final num a, final num b])
              e.key as String: (file: f, start: a.toDouble(), end: b.toDouble()),
      };

  static Map<String, List<AudioClip>> _sentences(Object? m) => {
        if (m is Map)
          for (final e in m.entries)
            if (e.value case {'f': final String f, 's': final List s})
              e.key as String: [
                for (final x in s)
                  if (x case [final num a, final num b])
                    (file: f, start: a.toDouble(), end: b.toDouble()),
              ],
      };

  AudioClip? word(String w) => _word[w];
  AudioClip? slow(String w) => _slow[w];
  AudioClip? example(String w) => _ex[w];

  /// One clip per sentence, in reading order; empty when not recorded.
  List<AudioClip> story(String id) => _story[id] ?? const [];
  List<AudioClip> passage(String id) => _passage[id] ?? const [];

  static Duration _at(double s) => Duration(milliseconds: (s * 1000).round());

  /// Play one clip, cutting off whatever was playing.
  static Future<void> play(AudioClip c) => playAll([c]);

  /// Play clips back to back (a story or passage, sentence after sentence).
  static Future<void> playAll(List<AudioClip> clips) async {
    if (clips.isEmpty) return;
    try {
      final p = _player ??= AudioPlayer();
      await p.stop();
      await p.setAudioSources([
        for (final c in clips)
          ClippingAudioSource(
            child: AudioSource.asset('$_dir/${c.file}'),
            start: _at(c.start),
            end: _at(c.end),
          ),
      ]);
      await p.play();
    } catch (_) {
      // A clip that cannot play is not worth an error dialog in a drill.
    }
  }

  static Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
