// Bilingual stories: each one introduces a handful of SAT words in context.
// The reader shows the English with the target words marked, the Arabic
// under each sentence on demand, then the comprehension questions.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../study/study_data.dart';
import '../../study/study_progress.dart';
import '../screens/metric_detail.dart' show detailScaffold;
import '../ui2.dart';
import 'study_shared.dart';

class StoryListScreen extends StatefulWidget {
  final StudyPack pack;
  const StoryListScreen({super.key, required this.pack});

  @override
  State<StoryListScreen> createState() => _StoryListScreenState();
}

class _StoryListScreenState extends State<StoryListScreen> {
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final read = StudyProgress.load().storiesRead;
    return detailScaffold(
      c,
      'قصص · Stories',
      sub: '${read.length} / ${widget.pack.stories.length} read',
      [
        const SizedBox(height: S.x2),
        for (final s in widget.pack.stories)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x2),
            child: Surface(
              elevation: 0,
              color: p.card2,
              pad: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
              onTap: () async {
                await Navigator.of(c).push(MaterialPageRoute(
                  builder: (_) => StoryScreen(pack: widget.pack, story: s),
                ));
                if (mounted) setState(() {});
              },
              child: Row(children: [
                Icon(
                  read.contains(s.id)
                      ? LucideIcons.circleCheck
                      : LucideIcons.bookOpen,
                  size: 18,
                  color: read.contains(s.id) ? p.on(C.green) : p.ink3,
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title, style: F.head.copyWith(color: p.ink)),
                      const SizedBox(height: 2),
                      Text(
                        '${s.titleAr} · ${s.newWords.length} new words',
                        style: F.cap.copyWith(color: p.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
              ]),
            ),
          ),
      ],
    );
  }
}

class StoryScreen extends StatefulWidget {
  final StudyPack pack;
  final StudyStory story;
  const StoryScreen({super.key, required this.pack, required this.story});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  bool _showAr = false;
  final Map<int, int> _chosen = {};

  StudyStory get s => widget.story;

  void _pick(int qi, int oi) {
    if (_chosen.containsKey(qi)) return;
    setState(() => _chosen[qi] = oi);
    if (_chosen.length == s.questions.length) {
      StudyProgress.load().finishStory(s.id);
    }
  }

  /// The sentence with every target form in bold accent.
  TextSpan _marked(BuildContext c, String en, P p) {
    final forms = {
      for (final t in s.targets)
        if (t.form.isNotEmpty) t.form.toLowerCase(),
    };
    if (forms.isEmpty) {
      return TextSpan(text: en, style: F.body.copyWith(color: p.ink, height: 1.6));
    }
    final re = RegExp(
      r'\b(' + forms.map(RegExp.escape).join('|') + r')\b',
      caseSensitive: false,
    );
    final base = F.body.copyWith(color: p.ink, height: 1.6);
    final hi = base.copyWith(
        color: p.on(C.yellow), fontWeight: FontWeight.w700);
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in re.allMatches(en)) {
      if (m.start > last) {
        spans.add(TextSpan(text: en.substring(last, m.start), style: base));
      }
      spans.add(TextSpan(text: m.group(0), style: hi));
      last = m.end;
    }
    if (last < en.length) {
      spans.add(TextSpan(text: en.substring(last), style: base));
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final done = _chosen.length == s.questions.length && s.questions.isNotEmpty;
    return detailScaffold(
      c,
      s.title,
      sub: s.titleAr,
      [
        const SizedBox(height: S.x2),
        if (s.targets.isNotEmpty)
          Wrap(spacing: S.x2, runSpacing: S.x2, children: [
            for (final t in s.targets) Pill(t.word, C.yellow),
          ]),
        const SizedBox(height: S.x4),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final sent in s.sentences) ...[
                Text.rich(_marked(c, sent.en, p)),
                if (_showAr && sent.ar.isNotEmpty) ...[
                  const SizedBox(height: S.x1),
                  ArText(sent.ar,
                      style: F.cap.copyWith(color: p.ink2, height: 1.6)),
                ],
                const SizedBox(height: S.x3),
              ],
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        BigButton(_showAr ? 'إخفاء الترجمة' : 'الترجمة تحت كل جملة',
            icon: LucideIcons.languages,
            color: C.blue,
            soft: true,
            onTap: () => setState(() => _showAr = !_showAr)),
        if (s.targets.isNotEmpty)
          Section(
            'الكلمات · Words',
            Column(children: [
              for (final t in s.targets)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.x2),
                  child: Surface(
                    elevation: 0,
                    color: p.card2,
                    pad: const EdgeInsets.symmetric(
                        horizontal: S.x3, vertical: S.x3),
                    child: Row(children: [
                      Text(t.word, style: F.head.copyWith(color: p.ink)),
                      const SizedBox(width: S.x3),
                      Expanded(
                        child: ArText(t.meaningAr,
                            style: F.body.copyWith(color: p.ink2)),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        if (s.questions.isNotEmpty)
          Section(
            'أسئلة · Questions',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var qi = 0; qi < s.questions.length; qi++) ...[
                  Text('${qi + 1}. ${s.questions[qi].q}',
                      style: F.head.copyWith(color: p.ink)),
                  const SizedBox(height: S.x2),
                  for (var oi = 0; oi < s.questions[qi].options.length; oi++)
                    OptionRow(
                      letter: optionLetter(oi),
                      text: s.questions[qi].options[oi],
                      chosen: _chosen[qi] == oi,
                      correct: s.questions[qi].answer == oi,
                      revealed: _chosen.containsKey(qi),
                      onTap: () => _pick(qi, oi),
                    ),
                  if (_chosen.containsKey(qi)) ...[
                    WhyCard(
                      correct: _chosen[qi] == s.questions[qi].answer,
                      whyAr: s.questions[qi].whyAr,
                    ),
                  ],
                  const SizedBox(height: S.x5),
                ],
              ],
            ),
          ),
        if (done)
          Surface(
            elevation: 0,
            color: Color.alphaBlend(p.wash(C.green), p.card),
            child: Row(children: [
              Icon(LucideIcons.badgeCheck, color: p.on(C.green)),
              const SizedBox(width: S.x3),
              Expanded(
                child: ArText('خلصت القصة. الكلمات دي هتظهرلك في الفلاش كاردز.',
                    style: F.body.copyWith(color: p.ink)),
              ),
            ]),
          ),
      ],
    );
  }
}
