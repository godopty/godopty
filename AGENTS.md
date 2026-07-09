# godopty — Agent Guide

Rust + Godot 4.7 multi-PTY terminal emulator with a tiling grid GUI.

## Project

- **Stack**: Rust (edition 2024) backend + Godot 4.7 GDScript frontend via gdext 0.5
- **Entry point**: `godot/scenes/main.tscn` → `workspace.gd` (root Control node)
- **License**: Apache 2.0 (see `LICENSE`)

## Commands

```bash
# Build the GDExtension shared library
cargo build -p godopty-gdext

# Run all Rust unit tests
cargo test -p godopty-core

# Type-check Rust only (fast, no codegen)
cargo check

# CLI demos (no Godot needed)
cargo run --bin godopty-cli              # mock pub-sub
cargo run --bin godopty-cli -- --pty     # real PTY
cargo run --bin godopty-cli -- --term    # alacritty_terminal grid

# Open in Godot editor (after building gdext)
cd godot && godot -e
```

## Architecture

### Rust crates (`crates/`)

| Crate | Role |
|---|---|
| `godopty-core` | Library: PTY spawning, ANSI parsing (vte), alacritty_terminal grid, concept/pub-sub engine |
| `godopty-cli` | CLI binary: three demo modes (mock, `--pty`, `--term`) |
| `godopty-gdext` | GDExtension cdylib: `GodoptyTerminal` GodotClass bridging Rust ↔ GDScript |

Key modules in `godopty-core`:
- `pty.rs` — portable-pty spawn + dedicated I/O thread
- `parser.rs` — vte ANSI state machine, extracts visible lines
- `term.rs` — alacritty_terminal grid + CellInfo
- `engine.rs` — WorkspaceEngine with tokio broadcast pub-sub
- `concept.rs` — regex-trigger → labelled-action routing
- `types.rs` — Concept, Event, Action, TerminalConfig structs
- `color.rs` — ANSI color mapping: named, indexed (256-color), true-color → RGB

### Godot scenes (`godot/scenes/`)

| File | Role |
|---|---|
| `workspace.gd` | **Root controller**: tile grid, layout, sidebar, palette, global settings panel, keyboard shortcuts |
| `terminal_pane.gd` | **Active renderer** (Control-based): inherits from Control, draws cells via `_draw()`, handles input, selection, scrollback |
| `focus_manager.gd` | Autoload singleton: Alt+Arrow geographic pane navigation |
| `main.tscn` | Scene entry point |

### Data flow

```
Shell → PTY I/O thread → vte parser → alacritty_terminal grid
  → Arc<Mutex<TermGrid>> → GodoptyTerminal (gdext) → GDScript _draw()
```

## Conventions

### GDScript
- **Indentation**: tabs
- **Private members**: underscore prefix (`_cell_w`, `_settings_panel`)
- **Config vars**: `_cfg_` prefix (`_cfg_cursor_shape`)
- **Export pattern**: `@export var` for properties settable from Inspector or externally
- **Settings pipeline**: `_cfg_*` → `_save_settings()` → `user://settings.json`. To add a new setting: (1) add `_cfg_` var, (2) add UI control, (3) add one line to `_apply_settings_to()`. `_build_wrapper()` calls it automatically — no other wiring needed.
- **Layout persistence**: `user://layout.json`
- **Terminal spawning**: `_build_wrapper()` is the sole entry point; all paths go through it
- **Layout Constraints**: The tiling grid relies on Godot `Control` nodes. Prefer using Godot's built-in Size Flags (Expand/Fill) inside containers (`HBoxContainer`/`VBoxContainer`) over manual pixel math. When manual math is absolutely required (like terminal cell reflows), hook into `_notification(NOTIFICATION_RESIZED)`.
- **Pub-Sub Bridge**: To handle `WorkspaceEngine` events (like regex concept triggers) in Godot, GDScript must poll the Rust backend in `_process()` or rely on Rust calling `call_deferred("emit_signal", ...)`.

### Rust
- **Edition**: 2024 (requires Rust ≥ 1.85)
- **Format**: standard `rustfmt`
- **Async runtime**: `tokio` (global `LazyLock` runtime in gdext)
- **Grid sharing**: `Arc<Mutex<TermGrid>>` — lock briefly, clone the grid, release
- **Thread Safety**: Godot's SceneTree is strictly single-threaded. NEVER call Godot methods, mutate nodes, or emit signals directly from background `tokio` threads. Instead, queue the state changes for GDScript to poll, or use Godot's thread-safe `call_deferred()`.
- **Lifecycle & Teardown**: When a `GodoptyTerminal` is destroyed (e.g., `queue_free()` in Godot), the Rust side MUST ensure the spawned shell and background `tokio` tasks are cleanly terminated (via the `Drop` trait) to prevent zombie processes or memory leaks.

### Commits
- **Format**: [Conventional Commits](https://www.conventionalcommits.org/) — `feat(scope):`, `fix(scope):`, `chore(scope):`
- Scopes: `settings`, `terminal`, `layout`, `sidebar`, `gdext`, `core`, `cli`

### Pitfalls
- **`alacritty_terminal` display_iter**: returns **negative** line numbers for scrollback history rows. Never cast directly to `usize` — it wraps to a huge value. Always add the grid's `display_offset()` to normalize: `let line = (indexed.point.line.0 + offset) as usize`.
- **Godot typed Arrays**: `Array[T]` won't accept plain `Array`. If you type a parameter, check all call sites use matching types (`var x: Array[Control] = []`).
- **GDExtension rebuilds**: After changing `#[func]` signatures or adding methods, rebuild with `cargo build -p godopty-gdext` and restart Godot.
- **GDScript default params**: Evaluated at definition time, not call time. `func f(x := some_var)` captures the value of `some_var` when the script loads. Use `func f(x := -1)` and check `if x < 0: x = some_var` inside the body for runtime-evaluated defaults.
- **`extends Node` won't render `Control` children**: Only `Control` nodes can render child `Control`s (Labels, Buttons, etc.). If you add a Label to a plain `Node`, it's invisible. Use `extends Control` for UI containers and set `z_index` for layering.
- **Rendering Performance**: GDScript `_draw` is slow when calling `draw_rect`/`draw_string` character-by-character. Avoid generating heavy data structures (like `Dictionary`) per-cell across the FFI boundary. Prefer packing data into flat arrays (`PackedByteArray`, `PackedInt32Array`) in Rust, and batch rendering operations line-by-line in Godot.
- **Resize Rate Limiting**: Firing SIGWINCH heavily on every frame during window drag will overwhelm the child PTY process. Always debounce or rate-limit terminal `_on_resize` events before passing them to the backend.

## Notes

- The ESC key handler on the settings panel exists but `gui_input` never receives the event (see README roadmap).
- `terminal_pane.gd` is the sole renderer (Control-based); the legacy Node2D `terminal.gd` was removed.
- Font-size changes now auto-recalculate cell metrics via a setter on `font_size` — no need to recreate terminals.
- The global tokio runtime is initialized once at GDExtension init and shared across all GodoptyTerminal nodes.
