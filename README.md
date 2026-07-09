# godopty

**A Godot-based Rust multi-PTY emulator** — a desktop application for creating, expanding, and orchestrating terminal sessions in a fluid, grid-based GUI.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Godot 4.3+ Frontend (Phase 2–3)                            │
│  ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌───────────────┐    │
│  │ Terminal │ │ Terminal │ │ File-Tree │ │ Task Ledger   │    │
│  │  Pane   │ │  Pane   │ │  Viewer   │ │               │    │
│  └────┬────┘ └────┬────┘ └──────────┘ └───────────────┘    │
│       │           │                                         │
│  ┌────┴───────────┴────────────────────────────────────┐    │
│  │  Nested SplitContainer + Drag-and-Drop              │    │
│  └─────────────────────────┬───────────────────────────┘    │
│                            │                                │
│  ┌─────────────────────────┴───────────────────────────┐    │
│  │  gdext Bridge (rust → Godot character grid arrays)   │    │
│  └─────────────────────────┬───────────────────────────┘    │
└────────────────────────────┼────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────┐
│  Rust Backend (godopty-core)                                 │
│  ┌─────────────────────────┴───────────────────────────┐    │
│  │  WorkspaceEngine — tokio::sync::broadcast pub-sub    │    │
│  │  Concept registry (regex triggers → labelled actions) │    │
│  └──────────┬──────────────────────┬───────────────────┘    │
│             │                      │                        │
│  ┌──────────┴──────────┐  ┌───────┴───────────────────┐    │
│  │  pty.rs              │  │  parser.rs                │    │
│  │  portable-pty spawn  │  │  vte ANSI state machine   │    │
│  │  dedicated I/O thread│  │  extracts visible lines   │    │
│  │  cross-platform      │  │                            │    │
│  └──────────────────────┘  └────────────────────────────┘    │
│                                                              │
│  Future: SQLite + FTS5 memory backend                        │
└──────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| PTY library | `portable-pty` | Cross-platform (Linux `/dev/ptmx` + Windows ConPTY) with a single API |
| ANSI parsing | `vte` crate | Fastest Rust ANSI state machine; used by Alacritty |
| Async runtime | `tokio` | Mature, full-featured; native `broadcast` channel for 1:N pub-sub |
| I/O threading | Dedicated `std::thread` per PTY | Predictable blocking reads; bridges to tokio via `mpsc` |
| Pub-sub | `tokio::sync::broadcast(1024)` | 1:N fan-out, lagged-receiver protection, self-reaction prevention |
| Grid rendering | `alacritty_terminal` | Full DEC STD 070 grid state machine; pass arrays to Godot `_draw()` |
| Godot bridge | `gdext 0.5` | Native GDExtension for Godot 4.7 |
| Rust edition | 2024 | Requires Rust ≥ 1.85 |

---

## Project Structure

```
godopty/
├── Cargo.toml                  # Workspace root
├── README.md
├── AGENTS.md                   # AI agent onboarding guide
├── LICENSE                     # Apache 2.0
├── .gitignore
├── crates/
│   ├── godopty-core/           # Library crate
│   │   ├── README.md
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs          # Module map + data-flow diagram
│   │       ├── types.rs        # Concept, Event, Action, TerminalConfig
│   │       ├── concept.rs      # Regex matching + label routing (pure fns)
│   │       ├── engine.rs       # WorkspaceEngine + SpawnedTerminal
│   │       ├── pty.rs          # portable-pty spawn + dedicated I/O thread
│   │       ├── parser.rs       # vte Perform → plain-text lines
│   │       └── term.rs         # alacritty_terminal grid + CellInfo
│   ├── godopty-cli/            # CLI demos
│   │   ├── README.md
│   │   ├── Cargo.toml
│   │   └── src/main.rs         # 3 demo modes (mock, --pty, --term)
│   └── godopty-gdext/          # Godot 4 GDExtension
│       ├── README.md
│       ├── Cargo.toml
│       └── src/lib.rs          # GodoptyTerminal GodotClass
└── godot/                      # Godot 4.7 project
    ├── project.godot
    ├── godopty.gdextension
    └── scenes/
        ├── main.tscn
        ├── workspace.gd        # Root controller, layout, settings, sidebar
        ├── terminal_pane.gd    # Terminal renderer (Control-based)
        └── focus_manager.gd    # Autoload: Alt+Arrow pane navigation
```

---

## Development Setup

### Prerequisites

- **Rust** ≥ 1.85 (tested on 1.96.0)
- **Linux** (primary target) or **Windows 11** (ConPTY supported via `portable-pty`)
- **Godot 4.4+** (tested on 4.7) with GDExtension support

### Quick Start

```bash
# Clone and build
git clone <repo-url> godopty
cd godopty

# Build everything
cargo build

# Run tests (23 unit tests)
cargo test -p godopty-core

# Run checks
cargo check
```

### Run the Demos

```bash
# Mock terminal demo (validates pub-sub engine)
cargo run --bin godopty-cli

# Real-PTY demo (requires Linux or Windows 11)
cargo run --bin godopty-cli -- --pty

# Terminal grid demo (validates alacritty_terminal ANSI + color processing)
cargo run --bin godopty-cli -- --term

# Build the GDExtension
cargo build -p godopty-gdext

# Open in Godot editor
cd godot && godot -e

# Verbose logging
RUST_LOG=debug cargo run --bin godopty-cli
```

**Mock demo output:**
```
[Pane 1] Broadcasting event: "port_conflict"
[Pane 2] Received topic 'port_conflict'. Would execute: echo '[Auto] Port conflict...'
[Pane 1] Broadcasting event: "crash_detected"
[Pane 3] Received topic 'crash_detected'. Would execute: echo '[Auto] Restart attempt...'
```

**Real-PTY demo output:**
```
>>> Injecting: echo 'ERROR: Address 8080 already in use'
[Pane 1] PTY: ERROR: Address 8080 already in use
[Pane 1] Broadcasting event: "port_conflict"
[Pane 2] Received topic 'port_conflict'. Injecting: echo '[Auto] Port conflict...'
[Pane 2] PTY: [Auto] Port conflict detected — consider lsof -i
```

---

## Concept System

Concepts are the core orchestration primitive — a regex trigger paired with labelled actions:

```rust
Concept {
    name: "port_conflict",
    trigger_regex: Regex::new(r"(?i)address.*already.*in\s*use").unwrap(),
    destinations: vec![Action {
        command_template: "echo '[Auto] Port conflict detected — consider lsof -i'",
        target_label: "observer",   // only delivered to terminals with this label
    }],
}
```

**How it works:**
1. PTY output bytes stream through the `vte` parser
2. The parser strips ANSI escape sequences and extracts visible text lines
3. Each line is tested against every registered concept's `trigger_regex`
4. On match, an `Event` is broadcast on the `tokio::sync::broadcast` channel
5. Every terminal task receives the event, checks its labels against each action's `target_label`
6. Matching terminals inject the `command_template` into their PTY's stdin

Self-reaction loops are prevented: a terminal ignores events where `source_pane == my_id`.

---

## Implementation Phases

### ✅ Phase 1 — Headless Rust Prototype (COMPLETE)

- [x] Rust workspace with `godopty-core` lib + `godopty-cli` binary
- [x] Cross-platform PTY spawning via `portable-pty` with dedicated I/O threads
- [x] ANSI escape sequence stripping via `vte` state machine
- [x] `WorkspaceEngine` with `tokio::sync::broadcast` pub-sub
- [x] Concept registry: regex triggers → label-gated action routing
- [x] Mock terminal demo validating 3-terminal fan-out routing
- [x] Real-PTY demo validating end-to-end pipeline (bash → vte → regex → broadcast → cross-PTY injection)

### ✅ Phase 2a — Headless Terminal Grid (COMPLETE)

- [x] `alacritty_terminal` integration for full DEC STD 070 grid emulation
- [x] `TermGrid` wrapper with grid export as `Vec<Vec<CellInfo>>`
- [x] Color conversion: Named, Indexed (256-color), and True Color → RGB
- [x] `SpawnedTerminal` with `Arc<Mutex<TermGrid>>` for Godot polling
- [x] `--term` CLI demo validating ANSI color processing
- [x] Full inline documentation on all source files

### ✅ Phase 2b — Godot + gdext Bridge (COMPLETE)

- [x] `godopty-gdext` crate (cdylib, gdext 0.5, Godot 4.7)
- [x] `GodoptyTerminal` GodotClass: `start_shell()`, `send_input()`, `get_grid_rows()`
- [x] Global tokio runtime (`LazyLock`) shared across all terminal nodes
- [x] GDScript `terminal_pane.gd`: `_draw()` renderer + `_input()` keyboard forwarding
- [x] Cell cache with dirty-check for efficient redraws
- [x] Edge cases documented: double start, spawn failure, empty grid, lock contention

### 🔜 Phase 3 — Spatial Layout & SQLite

- [ ] Nested `SplitContainer` logic
- [ ] Drag-and-drop pane swapping
- [ ] Label/Tag UI for terminals
- [ ] Code Viewer panes (`CodeEdit` node)
- [ ] Task Ledger pane
- [ ] SQLite + FTS5 async logging backend
- [ ] Session history persistence between restarts
- [ ] `SIGWINCH` handling (Godot resize → PTY resize signal)

---

## Roadmap

Features planned for future phases, roughly prioritized:

### Layout & UX
- [ ] **Drag-to-resize tile edges** — grab grid lines to resize panes (needs sub-grid positioning, deferred until pane type rewrite)
- [ ] **Standalone mode** — test and fix canvas resizing outside the embedded editor
- [ ] **Tab/workspace switching** — multiple named workspaces per session
- [ ] **ESC to dismiss settings panel** — `gui_input` on the settings panel background is not receiving key events; the ESC handler is wired but never fires
- [ ] **Title bar right-click menu** — split/close/move options

### Pane Types
- [ ] **File tree viewer** — Godot `Tree` node populated via `DirAccess` API
- [ ] **Code viewer pane** — Godot `CodeEdit` node for read-only file display
- [ ] **Task ledger** — persistent to-do list per workspace
- [ ] **Pane type registry** — unified interface for adding custom pane types
- [x] ~~**Consolidate terminal renderers**~~ — removed unused `terminal.gd` (Node2D) variant; `terminal_pane.gd` (Control) is the sole renderer

### Terminal Engine
- [ ] **Search** — Ctrl+F regex search across scrollback using alacritty_terminal
- [ ] **Damage tracking** — only redraw changed grid lines (optimization)
- [x] ~~**Optimize grid data transfer**~~ — added `generation` counter to TermGrid; GDScript skips `get_grid_rows()` when unchanged, avoiding per-frame Dictionary allocations
- [x] ~~**Deduplicate engine spawn functions**~~ — extracted shared `run_terminal_task()` helper; `spawn_pty_terminal` and `spawn_terminal_with_grid` are now thin wrappers
- [ ] **PtyHandle.resize wired to SIGWINCH** — shell reflows on pane resize
- [ ] **Configurable color palettes** — load xterm color schemes

### Memory & Persistence
- [ ] **SQLite + FTS5 history backend** — infinite scrollback with full-text search
- [ ] **Session auto-save** — restore all PTY sessions on relaunch
- [ ] **Concept persistence** — saved regex triggers survive restarts

### Polish
- [ ] ~~**Configurable font selection**~~ — added font file picker with `_add_file_picker()` reusable helper
- [ ] ~~**Title bar vertical centering**~~ — added `vertical_alignment = VERTICAL_ALIGNMENT_CENTER` to title label
- [ ] ~~**Notification/warning system**~~ — added `ToastManager` autoload with info/warn/error levels, queued display, and extensible data model
- [ ] **Drag-and-drop file paths** — drop a file on terminal to insert its path

### User Settings
- [x] ~~**Cursor blink speed**~~ — added `cursor_blink_speed` setting (0.1–2.0 s, persisted to settings.json)
- [x] ~~**Scroll wheel sensitivity**~~ — added `scroll_lines` setting (1–10, persisted to settings.json)
- [x] ~~**Default terminal dimensions**~~ — added `default_rows`/`default_cols` settings (10–100 × 40–200)
- [x] ~~**Cursor thickness**~~ — added `beam_width`/`underline_height` settings (1–8 px each)
- [x] ~~**UI theme colors**~~ — added 7 ColorPicker controls for wrapper, title bar, sidebar, focus, selection, and scrollback colors

### Repository
- [ ] **CONTRIBUTING.md** — setup instructions, PR process, and code style guide for contributors
- [ ] **`.github/` directory** — issue templates (bug report, feature request) and pull request template

---

## Technical Hurdles & Mitigations

### Cross-Platform PTY
- `portable-pty` provides a uniform API over POSIX `/dev/ptmx` and Windows ConPTY
- Process-killing must be abstracted: Unix uses POSIX signals, Windows uses `TerminateProcess`
- Environment variable setup differs per platform

### SIGWINCH (Window Resize)
- Godot `SplitContainer` resize → GDScript signal
- Pass new `(rows, cols)` through `gdext` to Rust
- Forward `PtySize` to `portable-pty` master → OS sends `SIGWINCH` to child process
- `alacritty_terminal` reflows the grid

### gdext + tokio Bridge
- Godot runs its own main loop on the main thread
- A global tokio runtime is started at extension init
- PTY threads push grid snapshots into a `Mutex<Vec<(TerminalId, GridData)>>`
- Godot's `_process()` drains the queue and updates `_draw()`
- This avoids blocking the Godot render thread

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions, code style, and the pull request process.

## License

This project is licensed under the Apache License, Version 2.0 — see [LICENSE](LICENSE) for details.
