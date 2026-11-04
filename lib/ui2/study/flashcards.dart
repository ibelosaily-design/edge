// Vocabulary flashcards. One word per card: tap to flip, then "عارفها" or
// "مش عارفها". Answers feed the Leitner boxes in StudyProgress.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../study/study_data.dart';
import '../../study/study_progress.dart';
import '../screens/metric_detail.dart' show detailScaffold;
import '../ui2.dart';
import '../../study/study_audio.dart';
import 'study_shared.dart';

class FlashcardsScreen extends StatefulWidget {
  final StudyPack pack;
  final List<String> ids;
  final String title;
  const FlashcardsScreen(
      {super.key, required this.pack, required this.ids, required this.title});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  // Leaving the screen ends whatever it was reading aloud.
  @override
  void dispose() {
    StudyAudio.stop();
    super.dispose();
  }

  int _i = 0;
  bool _flipped = false;
  int _ok = 0;
  int _missed = 0;

  StudyWord? get _word =>
      _i < widget.ids.length ? widget.pack.word(widget.ids[_i]) : null;

  void _answer(bool correct) {
    final w = _word;
    if (w == null) return;
    StudyProgress.load().answerWord(w.id, correct: correct);
    setState(() {
      if (correct) {
        _ok += 1;
      } else {
        _missed += 1;
      }
      _i += 1;
      _flipped = false;
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final w = _word;
    final total = widget.ids.length;
    if (w == null) {
      return detailScaffold(c, widget.title, [
        const SizedBox(height: S.x8),
        Surface(
          child: Column(children: [
            Icon(LucideIcons.badgeCheck, size: 40, color: p.on(C.green)),
            const SizedBox(height: S.x3),
            Text('$_ok / $total', style: F.n48.copyWith(color: p.ink)),
            const SizedBox(height: S.x2),
            ArText(
              total == 0
                  ? 'مفيش كلمات مستحقة النهارده. ارجع بكرة.'
                  : 'خلصت الجلسة. $_missed كلمة هترجعلك بكرة.',
              style: F.body.copyWith(color: p.ink2),
            ),
            const SizedBox(height: S.x4),
            BigButton('رجوع', color: C.yellow, onTap: () => Navigator.of(c).maybePop()),
          ]),
        ),
      ]);
    }
    final state = StudyProgress.load().words[w.id];
    return detailScaffold(
      c,
      widget.title,
      sub: '${_i + 1} / $total',
      [
        const SizedBox(height: S.x2),
        _progress(p, _i / total),
        const SizedBox(height: S.x4),
        Surface(
          onTap: () => setState(() => _flipped = !_flipped),
          semanticLabel: _flipped ? 'Hide meaning' : 'Show meaning',
          pad: const EdgeInsets.all(S.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Pill(w.pos.isEmpty ? 'word' : w.pos, C.yellow),
                const Spacer(),
                if (state != null)
                  Pill('box ${state.box + 1}', state.known ? C.green : C.blue),
              ]),
              const SizedBox(height: S.x6),
              Text(w.word,
                  textAlign: TextAlign.center,
                  style: F.n48.copyWith(color: p.ink)),
              if (w.ipa.isNotEmpty) ...[
                const SizedBox(height: S.x2),
                Text(w.ipa,
                    textAlign: TextAlign.center,
                    style: F.cap.copyWith(color: p.ink3)),
              ],
              const SizedBox(height: S.x3),
              ListenRow([
                ('اسمع', (a) => [?a.word(w.word)]),
                ('ببطء', (a) => [?a.slow(w.word)]),
              ]),
              const SizedBox(height: S.x6),
              if (!_flipped)
                Text('Tap to reveal · اضغط للمعنى',
                    textAlign: TextAlign.center,
                    style: F.cap.copyWith(color: p.ink3))
              else ...[
                ArText(w.ar, style: F.t2.copyWith(color: p.on(C.yellow))),
                const SizedBox(height: S.x3),
                Text(w.def, style: F.body.copyWith(color: p.ink)),
                if (w.ex.isNotEmpty) ...[
                  const SizedBox(height: S.x3),
                  Text('“${w.ex}”',
                      style: F.body.copyWith(
                          color: p.ink2, fontStyle: FontStyle.italic)),
                  const SizedBox(height: S.x2),
                  ListenRow([
                    ('المثال', (a) => [?a.example(w.word)]),
                  ], alignment: WrapAlignment.start),
                ],
                if (w.syn.isNotEmpty || w.ant.isNotEmpty) ...[
                  const SizedBox(height: S.x4),
                  Wrap(spacing: S.x2, runSpacing: S.x2, children: [
                    for (final s in w.syn) Pill('= $s', C.green),
                    for (final a in w.ant) Pill('≠ $a', C.red),
                  ]),
                ],
                if (w.other != null && w.other!.isNotEmpty) ...[
                  const SizedBox(height: S.x3),
                  Text(w.other!, style: F.cap.copyWith(color: p.ink3)),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        if (_flipped) ...[
          AskTutorButton(prompt: tutorWordPrompt(w.word, w.def, w.ex)),
          const SizedBox(height: S.x2),
        ],
        if (_flipped)
          Row(children: [
            Expanded(
              child: BigButton('مش عارفها',
                  icon: LucideIcons.rotateCcw,
                  color: C.red,
                  soft: true,
                  onTap: () => _answer(false)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: BigButton('عارفها',
                  icon: LucideIcons.check,
                  color: C.green,
                  onTap: () => _answer(true)),
            ),
          ])
        else
          BigButton('اعرض المعنى',
              icon: LucideIcons.eye,
              color: C.yellow,
              soft: true,
              onTap: () => setState(() => _flipped = true)),
      ],
    );
  }

  Widget _progress(P p, double t) => ClipRRect(
        borderRadius: R.rPill,
        child: SizedBox(
          height: 6,
          child: LinearProgressIndicator(
            value: t.clamp(0.0, 1.0).toDouble(),
            backgroundColor: p.track,
            color: p.fill(C.yellow),
          ),
        ),
      );
}
