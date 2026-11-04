# Provenance / مصدر الكود

This fork is built on top of **OpenStrap Edge**, verified against the original
upstream repositories (not mirrors or third-party forks) on 2026-11-02.

| Package | Upstream | Commit pinned at fork time | Date |
|---|---|---|---|
| App (this repo) | https://github.com/OpenStrap/edge | `871d3267a0d2eca90341347300626d4a669ff6f6` (v0.11.3+78) | 2026-11-02 |
| openstrap_protocol | https://github.com/OpenStrap/protocol | `b4fde6ab5589e53154b808f8b2bbb4d01d9c15b5` | 2026-10-31 |
| openstrap_analytics | https://github.com/OpenStrap/analytics | `3a7ca34d30233ff11e6c2877083f319a907ccb31` | 2026-11-01 |

Verification notes:
- Upstream org `OpenStrap` is the one referenced by Hackaday (2026-07-15) and
  Adafruit coverage, and by the project's own README/Discord/Reddit links.
- `protocol` and `analytics` are pinned by commit SHA inside `pubspec.yaml`
  (upstream policy, kept as-is). Bump deliberately, never to a floating branch.
- License: **AGPL-3.0** (all three packages). Our changes stay AGPL-3.0. If the
  APK is ever shared with anyone outside personal use, the modified source must
  be shared too. "OpenStrap" name/logo are trademarked (see TRADEMARKS.md);
  our build uses its own name.
- Not affiliated with WHOOP. Reads data from a band you own, over Bluetooth
  services the band exposes. Metrics are research-based approximations, not
  WHOOP's algorithms and not medical-grade.

Rules for this fork:
1. Keep upstream pullable: changes live on branch `elosaily`; `main` tracks
   upstream `OpenStrap/edge` untouched.
2. Record every upstream re-sync here (new SHAs + date).
3. Never switch the band back and forth with the official WHOOP app once in
   use (a firmware push from there can change the records this app decodes).

## Study audio (assets/study/audio)

Copied byte-for-byte from the owner's Kalimat SAT artifact
(claude.ai/artifact/MRuVxo3PzsjqMynNVX56zK, version 1793045414-24f8) on
2026-11-04: 120 MP3 sprites plus index.json, each file matched against the
artifact's published SHA-256 before it was committed. Generated with Kokoro
TTS (Apache-2.0), voice af_heart. The text they read (words, stories,
passages) is the same pack already in assets/study/, unchanged
(words/stories/reading SHA-256 identical to the earlier import).
