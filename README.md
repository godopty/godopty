# godopty

**A Godot-based Rust multi-PTY emulator** — a desktop application for creating, expanding, and orchestrating terminal sessions in a fluid, grid-based GUI.

## Core Philosophy

Godopty occupies the middle ground between rigid, GPU-accelerated terminals and feature-heavy, web-based terminals. It combines the speed of native systems programming with the rendering flexibility of a game engine.

- **Reactive Automation**: Rather than acting as a passive text pipe, the terminal reads its own output. The built-in pub-sub engine detects matched patterns and automatically executes fixes, restarts, or notifications in adjacent panes.
- **Unrestricted Aesthetics**: Built on Godot, the UI is hardware-accelerated. It supports fluid animations, instant theming, and rich UI overlays without the memory overhead of an embedded browser.
- **Zero-Friction Tiling**: Managing multiple panes relies on a native graphical grid and drag-and-drop mechanics, bypassing the need to memorize complex keyboard multiplexer bindings.
- **Open Source and Local**: The application is fully open source. There is no telemetry, no mandatory login, and complete control over local data.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Godot 4.3+ Frontend                                        │
│  ┌──────────┐ ┌──────────┐ ┌───────────┐ ┌───────────────┐  │
│  │ Terminal │ │ Terminal │ │ File-Tree │ │ Task Ledger   │  │
│  │  Pane    │ │  Pane    │ │  Viewer   │ │               │  │
│  └────┬─────┘ └────┬─────┘ └───────────┘ └───────────────┘  │
│       │            │                                        │
│  ┌────┴────────────┴─────────────────────────────────────┐  │
│  │  Nested SplitContainer + Drag-and-Drop                │  │
│  └─────────────────────────┬─────────────────────────────┘  │
│                            │                                │
│  ┌─────────────────────────┴─────────────────────────────┐  │
│  │  gdext Bridge (FFI partial damage tracking + arrays)  │  │
│  └─────────────────────────┬─────────────────────────────┘  │
└────────────────────────────┼────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────┐
│  Rust Backend (godopty-core)                                │
│  ┌─────────────────────────┴─────────────────────────────┐  │
│  │  WorkspaceEngine — tokio::sync::broadcast pub-sub     │  │
│  │  Concept registry (regex triggers → labelled actions) │  │
│  └──────────┬──────────────────────┬─────────────────────┘  │
│             │                      │                        │
│  ┌──────────┴───────────┐  ┌───────┴─────────────────────┐  │
│  │  pty.rs              │  │  parser.rs                  │  │
│  │  portable-pty spawn  │  │  vte ANSI state machine     │  │
│  │  dedicated I/O thread│  │  extracts visible lines     │  │
│  │  cross-platform      │  │                             │  │
│  └──────────────────────┘  └─────────────────────────────┘  │
│                                                             │
│  Future: SQLite + FTS5 memory backend                       │
└─────────────────────────────────────────────────────────────┘
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
        ├── autoloads/
        │   ├── base_persistence_manager.gd  # Shared JSON I/O base class
        │   ├── settings_manager.gd
        │   ├── profile_manager.gd
        │   ├── concept_manager.gd
        │   ├── layout_manager.gd
        │   ├── focus_manager.gd
        │   ├── toast_manager.gd
        │   └── shortcut_manager.gd
        ├── terminal/
        │   ├── workspace.gd    # Root controller
        │   ├── terminal_pane.gd
        │   └── terminal_manager.gd
        ├── ui/
        │   ├── sidebar.gd
        │   ├── settings_panel.gd
        │   ├── toast_overlay.gd
        │   └── icons.gd
        └── panes/
            ├── code_viewer.gd
            ├── file_tree.gd
            └── observer_pane.gd

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
# Mock terminal demo (demonstrates pub-sub engine)
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

**Security Warning:** The Concept Engine is designed to execute commands automatically based on terminal output. Do not bind destructive or high-privilege actions (like `rm` or `sudo`) to easily spoofable regex triggers. An attacker could intentionally print matching text to trick your terminal into executing the action payload.

## Use Cases

The Concept Engine allows developers to automate repetitive workflows based on standard shell output.

- **Auto-Restarting Watchers**: Detect a segmentation fault or panic string in a backend server pane, and automatically inject a restart command into an adjacent management pane.
- **Port Conflict Resolution**: Detect an "Address already in use" error and immediately run an `lsof` or `kill` command to clear the bound port.
- **AI Observer**: Pipe error blocks (such as a Python traceback or Rust compiler error) to a local language model, displaying a plain-English explanation and a proposed fix in a secondary pane.
- **Automated Documentation**: Match specific compiler error codes and automatically open the relevant local or web documentation in an adjacent window.

---

## Implementation Phases

### ✅ Phase 1 — Headless Rust Prototype (COMPLETE)

- [x] Rust workspace with `godopty-core` lib + `godopty-cli` binary
- [x] Cross-platform PTY spawning via `portable-pty` with dedicated I/O threads
- [x] ANSI escape sequence stripping via `vte` state machine
- [x] `WorkspaceEngine` with `tokio::sync::broadcast` pub-sub
- [x] Concept registry: regex triggers → label-gated action routing
- [x] Mock terminal demo demonstrating 3-terminal fan-out routing
- [x] Real-PTY demo demonstrating end-to-end pipeline (bash → vte → regex → broadcast → cross-PTY injection)

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

### ✅ Phase 2c — User Experience & Customization (COMPLETE)

- [x] Configurable cursor blink speed (0.1–2.0 s)
- [x] Configurable scroll wheel sensitivity (1–10 lines)
- [x] Configurable default terminal dimensions (10–100 × 40–200)
- [x] Named layout profiles — save/restore workspace configurations via sidebar (`user://profiles.json`)
- [x] Centralized icon system (`icons.gd`) — single source of truth for all UI glyphs
- [x] Concept persistence — regex triggers + actions saved to `user://concepts.json` via `ConceptManager` autoload
- [x] Standardized persistence pattern — all managers (`SettingsManager`, `ProfileManager`, `ConceptManager`, `LayoutManager`) follow autoload + JSON + signal convention
- [x] Configurable cursor thickness (beam width 1–8 px, underline height 1–8 px)
- [x] Configurable UI theme colors (7 ColorPicker controls)
- [x] Configurable font selection (file picker with `_add_file_picker()` reusable helper)
- [x] Title bar vertical centering (label + right-aligned buttons with toggle arrows)
- [x] Global settings panel with instant-apply, debounce, and Reset-to-defaults
- [x] Settings persistence (auto-save/load to `user://settings.json`)
- [x] Toast notification system (`ToastManager` autoload, replace-on-new, 3 levels)

### 🔜 Phase 3 — Spatial Layout & SQLite

- [ ] Nested `SplitContainer` logic
- [ ] Drag-and-drop pane swapping
- [ ] Label/Tag UI for terminals
- [ ] Code Viewer panes (`CodeEdit` node)
- [ ] Task Ledger pane
- [ ] SQLite + FTS5 async logging backend
- [ ] Session history persistence between restarts
- [ ] `SIGWINCH` handling (Godot resize → PTY resize signal)
- [ ] **Concept Manager UI** — add/edit/remove regex-triggered concepts and action targets through the settings panel

### Phase 4 — Reactive UX & Visual Scripting

- [ ] **Visual Concept Graph** — Allow users to build concept automations visually using Godot's GraphEdit nodes, connecting regex matchers to output filters and action triggers without writing JSON.
- [ ] **Interactive Output** — Convert specific text patterns (such as file paths and line numbers) into clickable UI elements that open integrated viewers or external editors.
- [ ] **Dynamic Shaders** — Expose Godot's shading language to the terminal background, enabling CRT effects, glassmorphism, or state-based visual feedback.
- [ ] **Reactive Environments** — Link terminal events to global UI state, such as shifting the application tint to red upon detecting a panic, or emitting subtle particle effects on successful test suites.
- [ ] **Variable Substitution (CLI AI)** — Add `{payload}` string interpolation to the Concept Engine's action templates. Allows passing extracted tokens from one pane into another's shell (e.g., injecting an error string into an ephemeral `ollama run` command).
- [ ] **Persistent REPL Injection** — Support routing event payloads directly into the `stdin` of a running script, enabling persistent context-aware agents in adjacent panes.
- [ ] **Native AI Observer Pane** — Build a dedicated Godot pane that subscribes directly to the `WorkspaceEngine`. By bypassing shell escaping entirely, it safely catches multi-line tracebacks in-memory, queries an LLM API natively, and renders the explanation via a Markdown `RichTextLabel`.

---

## Roadmap

Features planned for future phases, roughly prioritized:

### Layout & UX
- [ ] **Drag-to-resize tile edges** — grab grid lines to resize panes (needs sub-grid positioning, deferred until pane type rewrite)
- [ ] **Standalone mode** — test and fix canvas resizing outside the embedded editor
- [ ] **Tab/workspace switching** — multiple named workspaces per session
- [ ] **Title bar right-click menu** — split/close/move options
- [ ] **Drag-and-drop file paths** — drop a file on terminal to insert its path
- [x] ~~**Wrapped text selection**~~ — replace rectangular (block) selection with standard terminal wrapped/flow selection for correct copy/paste

### Pane Types
- [ ] **File tree viewer** — Godot `Tree` node populated via `DirAccess` API
- [ ] **Code viewer pane** — Godot `CodeEdit` node for read-only file display
- [ ] **Task ledger** — persistent to-do list per workspace
- [ ] **Pane type registry** — unified interface for adding custom pane types
- [x] ~~**Consolidate terminal renderers**~~ — removed unused `terminal.gd` (Node2D) variant; `terminal_pane.gd` (Control) is the sole renderer

### Terminal Engine
- [ ] **Search** — Ctrl+F regex search across scrollback using alacritty_terminal
- [x] ~~**Damage tracking**~~ — implemented FFI partial cell updates via `Term::damage()`, cutting typical FFI array allocations from 1,920 down to ~5 cells.
- [x] ~~**Optimize grid data transfer**~~ — replaced per-cell Dictionary format with flat packed arrays (chars/fg/bg/attrs); generation counter skips idle frames
- [x] ~~**Deduplicate engine spawn functions**~~ — extracted shared `run_terminal_task()` helper; `spawn_pty_terminal` and `spawn_terminal_with_grid` are now thin wrappers
- [x] ~~**PtyHandle.resize wired to SIGWINCH**~~ — fully wired since P0 audit (35370dc); debounced in _on_resize()
- [x] ~~**Configurable color palettes**~~ — added scheme file picker with sample solarized-dark; per-terminal runtime palette
- [ ] **GPU-accelerated rendering** — rasterize grid to a single texture in Rust (fontdue), replace 1,920 per-frame draw calls with one draw_texture (~2.5× faster)

### Memory & Persistence
- [ ] **SQLite + FTS5 history backend** — infinite scrollback with full-text search
- [ ] **Session auto-save** — restore all PTY sessions on relaunch
- [ ] **Concept persistence** — saved regex triggers survive restarts

### Security
- [ ] **Workspace Trust** — warn the user before spawning a PTY if a loaded `layout.json` sets `shell_command` to anything other than a standard system shell (e.g., `/bin/bash`). Protects against "Malicious Workspace" layout files executing arbitrary code.
- [ ] **UI Thread DoS Mitigation** — implement a frame-rate cap on grid synchronization to prevent a flooded PTY (e.g., `cat /dev/urandom`) from spamming GDScript's `_draw` cycle and freezing the Godot main thread.
- [ ] **Godot Export Security** — ensure production Godot export templates strictly disable debugging and console output to prevent leaking internal node trees.
- [ ] **FFI Fuzz Testing** — implement Rust tests pumping garbage binary data into `TermGrid::feed()` to ensure `alacritty_terminal` and `LineParser` handle panics safely without crashing the Godot runtime.

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

## Distribution

Standalone binaries (no Godot install required) are published on [GitHub Releases](https://github.com/you/godopty/releases) for Linux, macOS, and Windows.

| Platform | Package |
|---|---|
| **Arch Linux / CachyOS / Manjaro** | `yay -S godopty-bin` ([AUR](https://aur.archlinux.org/packages/godopty-bin)) |
| **Any Linux** | Download `godopty-linux-x86_64` from the [latest release](https://github.com/you/godopty/releases/latest) |
| **macOS** | Download `godopty-macos-arm64.zip`, unzip, right-click → Open (unsigned) |
| **Windows** | Download `godopty-windows-x86_64.exe` |

The in-app update checker notifies direct-download users when a new release is available. Package-managed installs (AUR, apt, dnf) skip the check —
updates arrive through the package manager.

## Roadmap

| Item | Status |
|---|---|
| AUR package (`godopty-bin`) | Done |
| Standalone export (Linux/macOS/Windows) | Done |
| In-app update checker | Done |
| Flatpak (Flathub) | Planned |
| `.deb` package (PPA) | Planned |
| `.rpm` package (COPR) | Planned |
| macOS code signing + notarization | Planned |
| Windows code signing | Planned |
| Auto-update (download + replace binary) | Planned |


## License

This project is licensed under the Apache License, Version 2.0 — see [LICENSE](LICENSE) for details.
