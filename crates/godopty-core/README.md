# godopty-core

Library crate for the godopty multi-PTY emulator. This is the engine — all terminal lifecycle, ANSI parsing, concept matching, and grid management live here.

## Module Layout

| Module | Purpose | Key Types |
|--------|---------|-----------|
| [`types`](src/types.rs) | Data vocabulary shared across all modules | `Concept`, `Event`, `Action`, `TerminalConfig` |
| [`concept`](src/concept.rs) | Pure functions for regex matching and command routing | `match_and_broadcast()`, `matching_commands()` |
| [`engine`](src/engine.rs) | Runtime orchestrator; spawns terminal tasks on tokio | `WorkspaceEngine`, `PtyTerminalHandle` |
| [`pty`](src/pty.rs) | Cross-platform PTY lifecycle via `portable-pty` | `PtyHandle` |
| [`parser`](src/parser.rs) | Strips ANSI escape sequences; extracts plain-text lines | `LineParser` |
| [`term`](src/term.rs) | Full terminal grid via `alacritty_terminal` | `TermGrid`, `CellInfo` |
| [`color`](src/color.rs) | ANSI color mapping — named, indexed, true-color → RGB | `color_to_rgb()` |

## Why Flat?

All modules are single files in `src/`. When a module grows beyond ~200 lines or needs helper files, it will be promoted to `src/<name>/mod.rs`. This keeps navigation simple during prototyping while leaving room for future nesting.

## Key Dependencies

| Crate | Version | Role |
|-------|---------|------|
| `portable-pty` | 0.9 | Cross-platform PTY (Linux `/dev/ptmx`, Windows ConPTY) |
| `vte` | 0.15 | ANSI/VT100 escape sequence parser |
| `alacritty_terminal` | 0.26 | Full terminal grid emulator (Phase 2a+) |
| `tokio` | 1.52 | Async runtime + broadcast channel |
| `regex` | 1.12 | Concept trigger patterns |
