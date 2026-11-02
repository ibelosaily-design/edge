// The Study tab. Today's plan (due + new words, one passage, one story), the
// streak, and the three decks. Everything it shows comes from the bundled
// pack and the local progress blob; nothing is fetched.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../study/study_data.dart';
import '../../study/study_progress.dart';
import '../profile/profile.dart' show ProfileAvatar;
import '../screens/home_screen.dart' show pad;
import '../ui2.dart';
import 'flashcards.dart';
import 'reading.dart';
import 'stories.dart';
import 'study_shared.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late final Future<StudyPack> _pack = StudyPack.load();

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return FutureBuilder<StudyPack>(
      future: _pack,
      builder: (c, snap) {
        final pack = snap.data;
        return ListView(padding: pad, children: [
          ScreenTitle('Study',
              trailing: const ProfileAvatar(accent: C.yellow)),
          if (pack == null)
            Padding(
              padding: const EdgeInsets.only(top: S.x8),
              child: snap.hasError
                  ? Text('Study pack failed to load: ${snap.error}',
                      style: F.body.copyWith(color: p.on(C.red)))
                  : const Center(child: CircularProgressIndicator()),
            )
          else
            ..._body(c, p, pack),
        ]);
      },
    );
  }

  List<Widget> _body(BuildContext c, P p, StudyPack pack) {
    final prog = StudyProgress.load();
    final ids = [for (final w in pack.words) w.id];
    final due = prog.dueToday(ids);
    final fresh = prog.newToday(ids);
    final session = [...due, ...fresh];
    final today = prog.today();
    final streak = prog.streak();
    final known = prog.knownCount();
    final solved = prog.passages.length;
    final nextPassage = pack.passages
        .where((b) => !prog.passages.containsKey(b.id))
        .firstOrNull;
    final nextStory =
        pack.stories.where((s) => !prog.storiesRead.contains(s.id)).firstOrNull;

    return [
      // ── today ──
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              ArText('خطة النهارده', style: F.head.copyWith(color: p.ink)),
              const Spacer(),
              Pill(streak > 0 ? '$streak day streak' : 'start today',
                  streak > 0 ? C.yellow : C.blue,
                  icon: LucideIcons.flame),
            ]),
            const SizedBox(height: S.x4),
            Row(children: [
              _stat(p, '${due.length}', 'review', 'مراجعة'),
              _stat(p, '${fresh.length}', 'new', 'جديدة'),
              _stat(p, '${today.words}', 'done today', 'خلصت'),
            ]),
            const SizedBox(height: S.x4),
            BigButton(
              session.isEmpty
                  ? 'خلصت كلمات النهارده'
                  : 'ابدأ الكلمات (${session.length})',
              icon: LucideIcons.layers,
              color: C.yellow,
              onTap: session.isEmpty
                  ? null
                  : () => _push(FlashcardsScreen(
                        pack: pack,
                        ids: session,
                        title: 'كلمات النهارده',
                      )),
            ),
            if (nextPassage != null) ...[
              const SizedBox(height: S.x2),
              BigButton(
                'قطعة قراءة: ${pack.typeNames[nextPassage.type]?.en ?? ''}',
                icon: LucideIcons.bookOpenText,
                color: C.blue,
                soft: true,
                onTap: () =>
                    _push(PassageScreen(pack: pack, passage: nextPassage)),
              ),
            ],
            if (nextStory != null) ...[
              const SizedBox(height: S.x2),
              BigButton(
                'قصة: ${nextStory.title}',
                icon: LucideIcons.bookOpen,
                color: C.teal,
                soft: true,
                onTap: () => _push(StoryScreen(pack: pack, story: nextStory)),
              ),
            ],
          ],
        ),
      ),
      // ── decks ──
      Section(
        'Decks · المكتبة',
        Column(children: [
          _deck(
            p,
            icon: LucideIcons.layers,
            color: C.yellow,
            title: 'Words · كلمات',
            sub: '$known known of ${pack.words.length}',
            onTap: () => _push(FlashcardsScreen(
              pack: pack,
              ids: _reviewAll(pack, prog),
              title: 'كل الكلمات',
            )),
          ),
          _deck(
            p,
            icon: LucideIcons.bookOpenText,
            color: C.blue,
            title: 'Reading · قطع القراءة',
            sub: '$solved of ${pack.passages.length} solved',
            onTap: () => _push(PassageListScreen(pack: pack)),
          ),
          _deck(
            p,
            icon: LucideIcons.bookOpen,
            color: C.teal,
            title: 'Stories · قصص',
            sub: '${prog.storiesRead.length} of ${pack.stories.length} read',
            onTap: () => _push(StoryListScreen(pack: pack)),
          ),
        ]),
      ),
      const SizedBox(height: S.x3),
      ArText(
        'الأرقام والمدرب الذكي هيربطوا جاهزيتك بمذاكرتك بعد ما الجهاز يتربط.',
        style: F.cap.copyWith(color: p.ink3),
      ),
    ];
  }

  /// Everything seen but not yet known, oldest-due first, then unseen words:
  /// the "just keep going" deck for a long session.
  List<String> _reviewAll(StudyPack pack, StudyProgress prog) {
    final seen = <String>[];
    final unseen = <String>[];
    for (final w in pack.words) {
      final s = prog.words[w.id];
      if (s == null) {
        unseen.add(w.id);
      } else if (!s.known) {
        seen.add(w.id);
      }
    }
    seen.sort((a, b) => prog.words[a]!.due.compareTo(prog.words[b]!.due));
    return [...seen, ...unseen].take(50).toList();
  }

  Widget _stat(P p, String n, String en, String ar) => Expanded(
        child: Column(children: [
          Text(n, style: F.n34.copyWith(color: p.ink)),
          const SizedBox(height: 2),
          Text('$en · $ar',
              style: F.cap.copyWith(color: p.ink3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      );

  Widget _deck(
    P p, {
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: S.x2),
        child: Surface(
          onTap: onTap,
          pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          child: Row(children: [
            Container(
              width: S.x10,
              height: S.x10,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.wash(color),
                borderRadius: R.rMd,
              ),
              child: Icon(icon, size: 20, color: p.on(color)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: F.head.copyWith(color: p.ink)),
                  const SizedBox(height: 2),
                  Text(sub, style: F.cap.copyWith(color: p.ink3)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
          ]),
        ),
      );
}
