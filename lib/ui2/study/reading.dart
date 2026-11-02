// Reading & Writing passages: the list (grouped by question type, done ones
// ticked) and one passage with its four options and Arabic explanation.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../study/study_data.dart';
import '../../study/study_progress.dart';
import '../screens/metric_detail.dart' show detailScaffold;
import '../ui2.dart';
import 'study_shared.dart';

class PassageListScreen extends StatefulWidget {
  final StudyPack pack;
  const PassageListScreen({super.key, required this.pack});

  @override
  State<PassageListScreen> createState() => _PassageListScreenState();
}

class _PassageListScreenState extends State<PassageListScreen> {
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final prog = StudyProgress.load();
    final byType = <String, List<StudyPassage>>{};
    for (final b in widget.pack.passages) {
      byType.putIfAbsent(b.type, () => []).add(b);
    }
    final solved = prog.passages.length;
    final right = widget.pack.passages
        .where((b) => prog.passages[b.id] == b.answer)
        .length;
    return detailScaffold(
      c,
      'قطع القراءة · Reading',
      sub: '$solved / ${widget.pack.passages.length} solved · $right correct',
      [
        for (final e in byType.entries) ...[
          Section(
            widget.pack.typeNames[e.key]?.en ?? e.key,
            Column(children: [
              for (final b in e.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.x2),
                  child: Surface(
                    elevation: 0,
                    color: p.card2,
                    pad: const EdgeInsets.symmetric(
                        horizontal: S.x3, vertical: S.x3),
                    onTap: () async {
                      await Navigator.of(c).push(MaterialPageRoute(
                        builder: (_) =>
                            PassageScreen(pack: widget.pack, passage: b),
                      ));
                      if (mounted) setState(() {});
                    },
                    child: Row(children: [
                      Icon(
                        prog.passages.containsKey(b.id)
                            ? (prog.passages[b.id] == b.answer
                                ? LucideIcons.circleCheck
                                : LucideIcons.circleX)
                            : LucideIcons.circle,
                        size: 18,
                        color: prog.passages.containsKey(b.id)
                            ? p.on(prog.passages[b.id] == b.answer
                                ? C.green
                                : C.red)
                            : p.ink3,
                      ),
                      const SizedBox(width: S.x3),
                      Expanded(
                        child: Text(
                          b.passage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: F.body.copyWith(color: p.ink),
                        ),
                      ),
                      const SizedBox(width: S.x2),
                      Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
                    ]),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: S.x1, bottom: S.x2),
            child: ArText(widget.pack.typeNames[e.key]?.ar ?? '',
                style: F.cap.copyWith(color: p.ink3)),
          ),
        ],
      ],
    );
  }
}

class PassageScreen extends StatefulWidget {
  final StudyPack pack;
  final StudyPassage passage;
  const PassageScreen({super.key, required this.pack, required this.passage});

  @override
  State<PassageScreen> createState() => _PassageScreenState();
}

class _PassageScreenState extends State<PassageScreen> {
  int? _chosen;
  bool _showTr = false;

  @override
  void initState() {
    super.initState();
    _chosen = StudyProgress.load().passages[widget.passage.id];
  }

  void _pick(int i) {
    final b = widget.passage;
    StudyProgress.load().answerPassage(b.id, i, correct: i == b.answer);
    setState(() => _chosen = i);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final b = widget.passage;
    final type = widget.pack.typeNames[b.type];
    final revealed = _chosen != null;
    return detailScaffold(
      c,
      type?.en ?? 'Passage',
      sub: type?.ar ?? '',
      [
        const SizedBox(height: S.x2),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(b.passage,
                  style: F.body.copyWith(color: p.ink, height: 1.6)),
              if (b.q.isNotEmpty) ...[
                const SizedBox(height: S.x4),
                Text(b.q, style: F.head.copyWith(color: p.ink)),
              ],
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        for (var i = 0; i < b.options.length; i++)
          OptionRow(
            letter: optionLetter(i),
            text: b.options[i],
            chosen: _chosen == i,
            correct: b.answer == i,
            revealed: revealed,
            onTap: () => _pick(i),
          ),
        if (revealed) ...[
          const SizedBox(height: S.x2),
          WhyCard(correct: _chosen == b.answer, whyAr: b.whyAr),
        ],
        if (b.trAr.isNotEmpty) ...[
          const SizedBox(height: S.x4),
          BigButton(_showTr ? 'إخفاء الترجمة' : 'الترجمة بالعربي',
              icon: LucideIcons.languages,
              color: C.blue,
              soft: true,
              onTap: () => setState(() => _showTr = !_showTr)),
          if (_showTr) ...[
            const SizedBox(height: S.x3),
            Surface(
              elevation: 0,
              color: p.card2,
              child: ArText(b.trAr,
                  style: F.body.copyWith(color: p.ink2, height: 1.7)),
            ),
          ],
        ],
      ],
    );
  }
}
