// Small pieces every Study screen uses: an RTL Arabic text block, an answer
// option row, and the "why" explanation card. Arabic is laid out RTL inside
// an LTR app, so each Arabic block declares its own direction rather than
// hoping the ambient one is right.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui2.dart';

/// An Arabic paragraph: right-to-left, right-aligned, in [style].
class ArText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;
  const ArText(this.text, {super.key, required this.style, this.maxLines});

  @override
  Widget build(BuildContext c) => Directionality(
        textDirection: TextDirection.rtl,
        child: Text(
          text,
          style: style,
          textAlign: TextAlign.right,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
        ),
      );
}

/// One multiple-choice option. Before an answer it is a plain card; after,
/// the correct one is green and a wrong pick is red, and the rest fade.
class OptionRow extends StatelessWidget {
  final String letter;
  final String text;
  final bool chosen;
  final bool correct;
  final bool revealed;
  final VoidCallback? onTap;

  const OptionRow({
    super.key,
    required this.letter,
    required this.text,
    required this.chosen,
    required this.correct,
    required this.revealed,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Color? tint;
    IconData? mark;
    if (revealed && correct) {
      tint = C.green;
      mark = LucideIcons.check;
    } else if (revealed && chosen) {
      tint = C.red;
      mark = LucideIcons.x;
    }
    final ink = tint == null
        ? (revealed ? p.ink3 : p.ink)
        : p.on(tint);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x2),
      child: Surface(
        onTap: revealed ? null : onTap,
        elevation: 0,
        color: tint == null ? p.card2 : Color.alphaBlend(p.wash(tint), p.card2),
        pad: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: S.x6,
              child: Text(letter,
                  style: F.head.copyWith(color: ink)),
            ),
            Expanded(
              child: Text(text, style: F.body.copyWith(color: ink)),
            ),
            if (mark != null) ...[
              const SizedBox(width: S.x2),
              Icon(mark, size: 18, color: ink),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Arabic explanation shown once an answer is revealed.
class WhyCard extends StatelessWidget {
  final bool correct;
  final String whyAr;
  const WhyCard({super.key, required this.correct, required this.whyAr});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final tint = correct ? C.green : C.orange;
    return Surface(
      elevation: 0,
      color: Color.alphaBlend(p.wash(tint), p.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArText(correct ? 'صح. ليه؟' : 'مش صح. الشرح:',
              style: F.head.copyWith(color: p.on(tint))),
          const SizedBox(height: S.x2),
          ArText(whyAr, style: F.body.copyWith(color: p.ink)),
        ],
      ),
    );
  }
}

/// A/B/C/D for an option index.
String optionLetter(int i) => String.fromCharCode(65 + i);
