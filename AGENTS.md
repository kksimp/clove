# AGENTS.md — Clove

Clove is an archiver with its own context-mixing compressor, written 100% in AIL
(https://github.com/kksimp/ail). Source files are `.ail`; the toolchain is the `ail` CLI
from the AIL repository (`ail check`, `ail fmt`, `ail test`, `ail build`).

- Builds and tests run on the designer's machines (Mac, ail-linux, ail-win), never in a cloud container.
- Keep the codec (`cm/cm.ail`) integer-only so every machine produces identical bytes.
- Any change to the model or coder changes the format: bump the magic in `clove.ail` and note it in README.md.
- Run `tools/check.sh` (check, fmt, tests; AIL pinned in `.ail-version`) before pushing.
