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
# Copy to the Godot project for local development
cp target/debug/libgodopty_gdext.so godot/bin/libgodopty_gdext.linux.x86_64.so

# Run all Rust tests (57 across core, gdext, cli)
cargo test --workspace

# Type-check Rust only (fast, no codegen)
cargo check

# Run all GDScript tests (59 unit + integration, headless)
godot --headless --path godot --import
godot --headless --path godot -s addons/gut/gut_cmdln.gd -d -gdir=res://tests/unit -gdir=res://tests/integration

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

```
scenes/
├── autoloads/
│   ├── base_persistence_manager.gd  # Shared JSON I/O base for persistence managers
│   ├── settings_manager.gd          # user://settings.json, settings_changed signal
│   ├── profile_manager.gd           # user://profiles.json, named layout snapshots
│   ├── concept_manager.gd           # user://concepts.json, pushes to Rust on startup
│   ├── layout_manager.gd            # user://layout.json, workspace tile persistence
│   ├── focus_manager.gd             # Alt+Arrow geographic pane navigation
│   ├── toast_manager.gd             # Transient toast notifications
│   ├── shortcut_manager.gd          # Keyboard shortcut registry (via InputMap)
│   └── update_checker.gd            # Polls GitHub Releases for new versions on startup
├── terminal/
│   ├── workspace.gd                 # Root controller: tile grid, layout, sidebar, profiles
│   ├── terminal_pane.gd             # Control-based renderer: _draw(), input, selection
│   └── terminal_manager.gd          # Tile lifecycle, split/kill/expand, wrapper builder
├── ui/
│   ├── sidebar.gd                   # Side panel: buttons, profile section, pane list
│   ├── settings_panel.gd            # Overlay panel: cursor, colors, concepts, per-tab UI
│   ├── toast_overlay.gd             # Toast UI renderer
│   └── icons.gd                     # Icons class with const glyph constants
├── panes/
│   ├── code_viewer.gd              # Read-only code viewer pane
│   ├── file_tree.gd                # Directory listing pane
│   └── observer_pane.gd            # AI observer output pane
└── main.tscn                       # Scene entry point
```

### Data flow

```
Shell → PTY I/O thread → vte parser → alacritty_terminal grid
  → Arc<Mutex<TermGrid>> → GodoptyTerminal (gdext) → GDScript _draw()
```

## Testing

### Rust

```bash
cargo test --workspace          # 57 tests across core, gdext, cli
cargo test -p godopty-core      # core library only (44 tests)
```

### GDScript (GUT)

Tests live in `godot/tests/` — `unit/` for pure-logic classes, `integration/` for scene-tree tests.

```bash
godot --headless --path godot --import         # required before first run
godot --headless --path godot -s addons/gut/gut_cmdln.gd -d \
  -gdir=res://tests/unit -gdir=res://tests/integration
```

**Mocking autoloads**: Use `MockAutoloads.setup()` / `teardown()` in `before_each`/`after_each`.
Persistence managers (`SettingsManager`, `ProfileManager`, `LayoutManager`) are mocked via
`set_script()` on the existing autoload node, redirecting `_read_file`/`_write_file` to an
in-memory Dictionary. This avoids touching disk and preserves Godot 4 global name bindings
(`SettingsManager` etc. are static constants — never `free()` autoload nodes).

**Signal testing**: GDScript lambdas cannot capture outer primitives. Use GUT's
`watch_signals(node)` + `assert_signal_emitted(node, "signal_name")` instead of
`node.signal.connect(func(): captured_var = true)`.

**Type checks**: `body is SomeClass` requires a compile-time class name. For runtime type
discrimination, use `body._pane_type()` string discriminators.

**Headless resource leaks**: GUT warnings about unfreed children and GDExtension `RID`/`ObjectDB`
leaks are benign in headless mode — the dummy render server doesn't track GDExtension resources.
Production renderer handles these correctly.

## Conventions

### GDScript
- **Indentation**: tabs
- **Icons**: ALL UI icon glyphs live in `icons.gd` as `const` strings (`Icons.CLOSE`, `Icons.DELETE`, etc.). Never hardcode `"✕"` or `"🗑"` in button text — use the constant. Adding a new icon: add a `const` to `icons.gd`. Changing the glyph for every instance: one edit.
- **Profiles**: named terminal-layout snapshots (`user://profiles.json`). `ProfileManager` autoload manages CRUD + `profiles_changed` signal. Save dialog is built inline in `workspace.gd` (not a separate scene). Profile activation clears the workspace (`_reset()`) then rebuilds tiles — follows `_do_restore()` pattern.
- **JSON → typed arrays**: `JSON.parse()` returns untyped `Array`. Assignment to `Array[Dictionary]` fails at runtime. Always iterate and build the typed array element-by-element: `for item in raw: if item is Dictionary: typed.append(item)`.
- **Private members**: underscore prefix (`_cell_w`, `_settings_panel`)
- **Config vars**: `_cfg_` prefix (`_cfg_cursor_shape`)
- **Persistence**: All persistent user data follows the same autoload pattern. Each manager extends `BasePersistenceManager`, which provides `_read_file(path)` / `_write_file(path, data)` and sets `PROCESS_MODE_ALWAYS`. Subclasses override `_on_init()` instead of `_ready()`. Four managers: `SettingsManager`, `ProfileManager`, `ConceptManager`, `LayoutManager`. Never inline `FileAccess.open()` in UI code — go through `_read_file`/`_write_file`.
- **Directory layout**: Scripts are grouped by role: `autoloads/` (7 managers + 1 base), `terminal/` (core terminal), `ui/` (sidebar, settings, toast), `panes/` (specialty pane types). `project.godot` autoload paths and `preload()`/`load()` calls use the full `res://scenes/<dir>/<file>.gd` path.
- **Settings pipeline**: `_cfg_*` → `_save_settings()` → `user://settings.json`. To add a new setting: (1) add `_cfg_` var, (2) add UI control, (3) add one line to `_apply_settings_to()`. `_build_wrapper()` calls it automatically — no other wiring needed.
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

### Security
- **Concept Engine ReDoS**: The `godopty-core` crate MUST always use the standard Rust `regex` crate. PCRE or back-tracking engines are strictly prohibited to prevent ReDoS (Regex Denial of Service) attacks when parsing large amounts of terminal output.
- **OSC 52 Clipboard Syncing**: `parser.rs` currently discards all terminal escape sequences, keeping copy/paste safely bound to Godot UI inputs. Do NOT implement OSC 52 clipboard injection/syncing without placing it behind an explicit Godot confirmation dialog to prevent drive-by clipboard hijacking.

### Commits
- **Format**: [Conventional Commits](https://www.conventionalcommits.org/) — `feat(scope):`, `fix(scope):`, `chore(scope):`
- Scopes: `settings`, `terminal`, `layout`, `sidebar`, `gdext`, `core`, `cli`, `profiles`, `concepts`, `icons`

### Pitfalls
- **`Drop` impl for external resources**: Any Rust struct holding a child process (`portable_pty::Child`) or I/O thread MUST implement `Drop` to call `.kill()`. Otherwise closing a terminal in Godot orphans the shell process and reader thread.
- **`tokio::select!` None branches**: When a channel returns `None` (closed), `select!` disables that branch but keeps polling others instantly — causing 100% CPU. Bind to a variable first (`msg = rx.recv()`), then `let Ok(v) = msg else { break; }`.
- **vte `Perform::execute` CR/LF**: PTY output uses CRLF pairs. The vte parser calls `execute` per byte. If you commit on both `\r` and `\n`, every line produces a spurious empty string. Track `last_was_cr` and skip the `\n` commit when preceded by `\r`.
- **`alacritty_terminal` display_iter**: returns **negative** line numbers for scrollback history rows. Never cast directly to `usize` — it wraps to a huge value. Always add the grid's `display_offset()` to normalize: `let line = (indexed.point.line.0 + offset) as usize`.
- **GDScript `\UXXXXXXXX` escape**: GDScript only supports `\uXXXX` (4-hex-digit BMP). `\UXXXXXXXX` (8-digit) does not exist — the parser mangles it. For non-BMP codepoints like 🗑 (U+1F5D1), use `char(0x1F5D1)` in `static var` initializers. BMP codepoints like ✕ (U+2715) work fine as `"\u2715"`.
- **Typed arrays break Rust FFI**: gdext `Array<Variant>` parameters reject GDScript's `Array[Dictionary]` at runtime ("expected array of type Untyped, got Builtin(DICTIONARY)"). Always pass untyped `Array` across the FFI boundary. Prefer `func f(arr: Array)` over `func f(arr: Array[Dictionary])` when the array originates from or goes to Rust.
- **Multi-line `for` array colon**: `for x in [...]` with a multi-line array literal requires `]:` at the end. Forgetting the colon produces a parse error at an unrelated line. Double-check after replacing inline array content.
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
