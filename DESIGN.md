# Elosaily Strap — design notes

Direction: a watch dial, not a dashboard. Dark by default, ivory type, one
champagne-gold accent for the things that matter, serif hero numerals.

| Token | Dark | Light |
|---|---|---|
| bg | `#0D0E11` | `#F6F2EA` (ivory paper) |
| card / card2 | `#17181D` / `#1F2127` | `#FFFDF9` / `#EFEAE0` |
| line | `#2B2E36` | `#E2DCD0` |
| ink / ink2 / ink3 | `#F2EDE3` / `#B9B2A5` / `#8E887C` | `#1A1A1C` / `#5C5850` / `#6B665C` |

Accents (pigments in `lib/ui2/theme.dart` → `C`): racing green `#3C9D66`
(ready), champagne gold `#CDAA4F` (strain / signature), midnight navy
`#4A5C9E` (sleep), slate blue `#4F74A8` (health), oxblood `#B33A3A`
(rest / alerts), bronze `#C98A3A` (food), deep teal `#2F8C86` (mind),
plum `#7A5AA6` (move).

Type: body stays Manrope; hero numerals (`F.n48`, `F.n34`) are Cormorant
Garamond with lining + tabular figures (bundled, subset to Latin + digits,
OFL — `assets/fonts/CormorantGaramond/OFL.txt`).

Icon: gold band ring open at 12 with an ivory index, serif "E" on ink.
Sources in the design folder of the chat session; outputs in
`assets/images/icon.png`, `assets/launcher/icon_adaptive.png` and the
Android `mipmap-*` / `drawable-*` folders (written directly, not via
`flutter_launcher_icons`, so the iOS project is untouched).

All inks and accents were checked against `test/ui2_contrast_test.dart`'s
rules (AA 4.5:1 on every surface; raw green must still fail on white so the
solver has teeth) before being committed.
