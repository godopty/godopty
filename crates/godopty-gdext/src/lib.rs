//! Godot 4 GDExtension for godopty — bridges the Rust terminal engine
//! to Godot's rendering pipeline.
//!
//! ## Architecture
//!
//! - A **global tokio runtime** is started at extension init and shared
//!   across all terminal nodes.
//! - Each [`GodoptyTerminal`] node wraps a [`SpawnedTerminal`], which runs
//!   a background task feeding PTY output into a renderable grid.
//! - GDScript polls the grid in `_process()` and renders it in `_draw()`.
//! - Keyboard input flows GDScript → Rust → PTY stdin.

use std::sync::{Arc, LazyLock};

use godot::prelude::*;

use godopty_core::engine::{SpawnedTerminal, WorkspaceEngine};
use godopty_core::types::TerminalConfig;

// ═══════════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════════

const TOKIO_WORKERS: usize = 2;
const MIN_DIM: i64 = 1;
const RGB_SCALE: f32 = 1.0 / 255.0;

// ═══════════════════════════════════════════════════════════════════════
// Global tokio runtime + engine
// ═══════════════════════════════════════════════════════════════════════

static RUNTIME: LazyLock<tokio::runtime::Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(TOKIO_WORKERS)
        .enable_all()
        .build()
        .expect("failed to start tokio runtime")
});

static ENGINE: LazyLock<WorkspaceEngine> =
    LazyLock::new(|| WorkspaceEngine::new(Vec::new()));

// ═══════════════════════════════════════════════════════════════════════
// GodoptyTerminal — a Godot node backed by a Rust PTY session
// ═══════════════════════════════════════════════════════════════════════

#[derive(GodotClass)]
#[class(base = Node2D)]
struct GodoptyTerminal {
    spawned: Option<SpawnedTerminal>,
    next_id: u32,
}

#[godot_api]
impl INode2D for GodoptyTerminal {
    fn init(_base: Base<Node2D>) -> Self {
        Self {
            spawned: None,
            next_id: 1,
        }
    }
}

#[godot_api]
impl GodoptyTerminal {
    /// Start a shell in this terminal pane.
    ///
    /// Spawns a PTY at `rows × cols`. Call once during `_ready()`.
    ///
    /// # Edge cases
    /// - Calling twice replaces the previous session.
    /// - If spawning fails, the grid stays empty and `get_grid_rows()` returns `[]`.
    /// - `rows` and `cols` are clamped to ≥1.
    #[func]
    fn start_shell(&mut self, command: GString, rows: i64, cols: i64, envs: GString) {
        let id = self.next_id;
        self.next_id += 1;

        let config = TerminalConfig {
            id,
            labels: Vec::new(),
        };

        let rows = rows.max(MIN_DIM) as usize;
        let cols = cols.max(MIN_DIM) as usize;

        // Parse "KEY=value" lines into Vec<String>
        let env_list: Vec<String> = envs.to_string()
            .lines()
            .map(|l| l.trim().to_string())
            .filter(|l| !l.is_empty() && l.contains('='))
            .collect();

        godot_print!("[GDExt] Starting PTY {id}: {command} ({rows}×{cols})");

        match RUNTIME.block_on(ENGINE.spawn_terminal_with_grid(
            config,
            &command.to_string(),
            &[],
            &env_list,
            rows,
            cols,
        )) {
            Ok(spawned) => {
                // Attach SQLite history store for persistent scrollback
                if let Ok(mut grid) = spawned.grid.lock() {
                    let db_path = godot::classes::ProjectSettings::singleton()
                        .globalize_path("user://history.db")
                        .to_string();
                    match godopty_core::history::HistoryStore::open(&db_path, id) {
                        Ok(store) => {
                            grid.history = Some(Arc::new(std::sync::Mutex::new(store)));
                        }
                        Err(e) => {
                            godot_warn!("[GDExt] Could not open history store for pane {id}: {e}");
                        }
                    }
                }
                self.spawned = Some(spawned);
            }
            Err(e) => {
                godot_error!("Failed to spawn PTY for '{command}': {e}");
            }
        }
    }

    /// Send raw text to the PTY — NO newline appended.
    ///
    /// Use this for interactive keyboard input. The shell's line discipline
    /// handles echo, backspace, and line buffering. For submitting a command
    /// (Enter key), use `send_line()`.
    #[func]
    fn send_text(&self, text: GString) {
        if let Some(ref spawned) = self.spawned {
            spawned.handle.send_text(&text.to_string());
        }
    }

    /// Send a complete line to the PTY (appends `\n`).
    ///
    /// Use this for the Enter key to submit a command, or for concept-triggered
    /// action commands.
    #[func]
    fn send_line(&self, text: GString) {
        if let Some(ref spawned) = self.spawned {
            spawned.handle.send_line(&text.to_string());
        }
    }

    // ── Grid access helpers ─────────────────────────────────────────

    /// Lock the grid immutably, call `f`, return its result.
    /// Returns `default` if no shell started or the mutex is poisoned.
    fn with_grid<T>(&self, f: impl FnOnce(&godopty_core::term::TermGrid) -> T, default: T) -> T {
        if let Some(ref spawned) = self.spawned {
            match spawned.grid.lock() {
                Ok(g) => f(&g),
                Err(e) => {
                    godot_error!("godopty: TermGrid lock poisoned: {e}");
                    default
                }
            }
        } else {
            default
        }
    }
    fn with_grid_mut_ret<T>(&self, f: impl FnOnce(&mut godopty_core::term::TermGrid) -> T, default: T) -> T {
        if let Some(ref spawned) = self.spawned {
            match spawned.grid.lock() {
                Ok(mut g) => f(&mut g),
                Err(e) => {
                    godot_error!("godopty: TermGrid lock poisoned: {e}");
                    default
                }
            }
        } else {
            default
        }
    }


    /// Lock the grid mutably and call `f`. No-op if no shell or lock poisoned.
    fn with_grid_mut(&self, f: impl FnOnce(&mut godopty_core::term::TermGrid)) {
        if let Some(ref spawned) = self.spawned {
            match spawned.grid.lock() {
                Ok(mut g) => f(&mut g),
                Err(e) => godot_error!("godopty: TermGrid lock poisoned: {e}"),
            }
        }
    }

    /// Cursor row position (0-based). Returns -1 if no shell or cursor hidden.
    #[func]
    fn get_cursor_row(&self) -> i64 {
        self.with_grid(
            |g| g.cursor_position().map(|(r, _)| r as i64).unwrap_or(-1),
            -1,
        )
    }

    /// Cursor column position (0-based). Returns -1 if no shell or cursor hidden.
    #[func]
    fn get_cursor_col(&self) -> i64 {
        self.with_grid(
            |g| g.cursor_position().map(|(_, c)| c as i64).unwrap_or(-1),
            -1,
        )
    }

    /// Cursor shape: 0 = Block, 1 = Underline, 2 = Beam.
    #[func]
    fn get_cursor_shape(&self) -> i64 {
        self.with_grid(|g| g.cursor_shape() as u8 as i64, -1)
    }

    /// Resize the terminal grid and PTY to `rows × cols`.
    /// Sends SIGWINCH to the child process so bash/zsh reflows.
    #[func]
    fn resize_grid(&mut self, rows: i64, cols: i64) {
        let rows = rows.max(MIN_DIM) as usize;
        let cols = cols.max(MIN_DIM) as usize;
        self.with_grid_mut(|g| g.resize(rows, cols));
        if let Some(ref spawned) = self.spawned {
            spawned.handle.resize_pty(rows as u16, cols as u16);
        }
    }

    /// Terminal window title (from OSC escape sequences). Empty string if none set.
    #[func]
    fn get_title(&self) -> GString {
        self.with_grid(|g| GString::from(&g.title()), GString::new())
    }

    // ── Scrollback ──────────────────────────────────────────────────

    /// Scroll up by `lines` (back in terminal history).
    #[func]
    fn scroll_up(&mut self, lines: i64) {
        self.with_grid_mut(|g| g.scroll_up(lines.max(0) as usize));
    }

    /// Scroll down by `lines` (forward in terminal history).
    #[func]
    fn scroll_down(&mut self, lines: i64) {
        self.with_grid_mut(|g| g.scroll_down(lines.max(0) as usize));
    }

    /// Reset scroll position to follow live output.
    #[func]
    fn scroll_reset(&mut self) {
        self.with_grid_mut(|g| g.scroll_reset());
    }

    /// Current scrollback offset (lines above visible viewport).
    #[func]
    fn get_scroll_offset(&self) -> i64 {
        self.with_grid(|g| g.display_offset() as i64, 0)
    }

    /// Total lines of scrollback history available.
    #[func]
    fn get_history_size(&self) -> i64 {
        self.with_grid(|g| g.history_size() as i64, 0)
    }

    /// Number of rows in the terminal grid (0 if no shell started).
    #[func]
    fn get_rows(&self) -> i64 {
        self.with_grid(|g| g.num_rows() as i64, 0)
    }

    /// Number of columns in the terminal grid.
    #[func]
    fn get_cols(&self) -> i64 {
        self.with_grid(|g| g.num_cols() as i64, 0)
    }

    /// Monotonically increasing counter; changes every time the grid is
    /// updated. GDScript can compare to a cached value to skip redundant
    /// `get_grid_rows()` calls when nothing changed.
    #[func]
    fn get_grid_generation(&self) -> i64 {
        self.with_grid(|g| g.generation as i64, -1)
    }

    /// Load a color scheme from a comma-separated string of 16 hex colors.
    /// Example: "#002b36,#dc322f,...". Empty string resets to default.
    #[func]
    fn set_palette(&mut self, hex_csv: GString) {
        let spawned = match &self.spawned {
            Some(s) => s,
            None => return,
        };
        let mut grid = match spawned.grid.lock() {
            Ok(g) => g,
            Err(_) => return,
        };
        if hex_csv.is_empty() {
            grid.palette = godopty_core::color::SYSTEM_COLORS;
            grid.generation += 1;
            return;
        }
        let s = hex_csv.to_string();
        let mut changed = false;
        for (i, hex) in s.split(',').enumerate().take(16) {
            let h = hex.trim();
            if h.len() == 7 && h.starts_with('#') {
                if let (Ok(r), Ok(g), Ok(b)) = (
                    u8::from_str_radix(&h[1..3], 16),
                    u8::from_str_radix(&h[3..5], 16),
                    u8::from_str_radix(&h[5..7], 16),
                ) {
                    grid.palette[i] = [r, g, b];
                    changed = true;
                }
            }
        }
        if changed {
            grid.generation += 1;
        }
    }

    /// Return the grid as flat parallel arrays (no per-cell Dictionary overhead).
    /// Returns a Dictionary: rows, cols, chars (String per row), fg/bg (Color array), attrs (int array).
    #[func]
    fn get_grid_packed(&self) -> Dictionary<Variant, Variant> {
        self.with_grid(
            |g| {
                let rows = g.renderable_rows();
                let n_rows = rows.len();
                let n_cols = if n_rows > 0 { rows[0].len() } else { 0 };
                let mut chars: Array<Variant> = Array::new();
                let mut fg: Array<Variant> = Array::new();
                let mut bg: Array<Variant> = Array::new();
                let mut attrs: Array<Variant> = Array::new();
                for row in rows.iter() {
                    let mut line = String::with_capacity(n_cols);
                    for cell in row.iter() {
                        line.push(cell.ch);
                        fg.push(&Variant::from(Color::from_rgb(cell.fg[0] as f32 * RGB_SCALE, cell.fg[1] as f32 * RGB_SCALE, cell.fg[2] as f32 * RGB_SCALE)));
                        bg.push(&Variant::from(Color::from_rgb(cell.bg[0] as f32 * RGB_SCALE, cell.bg[1] as f32 * RGB_SCALE, cell.bg[2] as f32 * RGB_SCALE)));
                        let mut a: i64 = 0;
                        if cell.bold { a |= 1; } if cell.italic { a |= 2; } if cell.underline { a |= 4; } if cell.inverse { a |= 8; } if cell.wide { a |= 16; }
                        attrs.push(&Variant::from(a));
                    }
                    chars.push(&Variant::from(line));
                }
                let mut dict = Dictionary::<Variant, Variant>::new();
                dict.set("rows", &Variant::from(n_rows as i64)); dict.set("cols", &Variant::from(n_cols as i64));
                dict.set("chars", &Variant::from(chars)); dict.set("fg", &Variant::from(fg));
                dict.set("bg", &Variant::from(bg)); dict.set("attrs", &Variant::from(attrs));
                dict
            }, Dictionary::<Variant, Variant>::new(),
        )
    }
    /// Fetches grid updates incrementally using damage tracking.
    /// If `force_full` is true (or damage triggers a full redraw), returns `is_full = true`
    /// along with parallel arrays (`chars`, `fg`, `bg`, `attrs`) covering the entire grid.
    /// Otherwise, returns `is_full = false` along with `indices` and modified data arrays
    /// for only the cells that changed since the last frame.
    #[func]
    fn get_grid_updates(&self, force_full: bool) -> Dictionary<Variant, Variant> {
        self.with_grid_mut_ret(
            |g| {
                let updates = g.get_grid_updates(force_full);
                match updates {
                    godopty_core::term::GridUpdate::Full(rows) => {
                        let n_rows = rows.len();
                        let n_cols = if n_rows > 0 { rows[0].len() } else { 0 };
                        let mut chars: Array<Variant> = Array::new();
                        let mut fg: Array<Variant> = Array::new();
                        let mut bg: Array<Variant> = Array::new();
                        let mut attrs: Array<Variant> = Array::new();
                        for row in rows.iter() {
                            let mut line = String::with_capacity(n_cols);
                            for cell in row.iter() {
                                line.push(cell.ch);
                                fg.push(&Variant::from(Color::from_rgb(cell.fg[0] as f32 * RGB_SCALE, cell.fg[1] as f32 * RGB_SCALE, cell.fg[2] as f32 * RGB_SCALE)));
                                bg.push(&Variant::from(Color::from_rgb(cell.bg[0] as f32 * RGB_SCALE, cell.bg[1] as f32 * RGB_SCALE, cell.bg[2] as f32 * RGB_SCALE)));
                                let mut a: i64 = 0;
                                if cell.bold { a |= 1; } if cell.italic { a |= 2; } if cell.underline { a |= 4; } if cell.inverse { a |= 8; } if cell.wide { a |= 16; }
                                attrs.push(&Variant::from(a));
                            }
                            chars.push(&Variant::from(line));
                        }
                        let mut dict = Dictionary::<Variant, Variant>::new();
                        dict.set("is_full", &Variant::from(true));
                        dict.set("rows", &Variant::from(n_rows as i64)); dict.set("cols", &Variant::from(n_cols as i64));
                        dict.set("chars", &Variant::from(chars)); dict.set("fg", &Variant::from(fg));
                        dict.set("bg", &Variant::from(bg)); dict.set("attrs", &Variant::from(attrs));
                        dict
                    }
                    godopty_core::term::GridUpdate::Partial(cells) => {
                        let mut indices: Array<Variant> = Array::new();
                        let mut chars: Array<Variant> = Array::new();
                        let mut fg: Array<Variant> = Array::new();
                        let mut bg: Array<Variant> = Array::new();
                        let mut attrs: Array<Variant> = Array::new();
                        let cols = g.num_cols();
                        for u in cells {
                            indices.push(&Variant::from((u.row * cols + u.col) as i64));
                            chars.push(&Variant::from(u.cell.ch.to_string()));
                            fg.push(&Variant::from(Color::from_rgb(u.cell.fg[0] as f32 * RGB_SCALE, u.cell.fg[1] as f32 * RGB_SCALE, u.cell.fg[2] as f32 * RGB_SCALE)));
                            bg.push(&Variant::from(Color::from_rgb(u.cell.bg[0] as f32 * RGB_SCALE, u.cell.bg[1] as f32 * RGB_SCALE, u.cell.bg[2] as f32 * RGB_SCALE)));
                            let mut a: i64 = 0;
                            if u.cell.bold { a |= 1; } if u.cell.italic { a |= 2; } if u.cell.underline { a |= 4; } if u.cell.inverse { a |= 8; } if u.cell.wide { a |= 16; }
                            attrs.push(&Variant::from(a));
                        }
                        let mut dict = Dictionary::<Variant, Variant>::new();
                        dict.set("is_full", &Variant::from(false));
                        dict.set("indices", &Variant::from(indices));
                        dict.set("chars", &Variant::from(chars));
                        dict.set("fg", &Variant::from(fg));
                        dict.set("bg", &Variant::from(bg));
                        dict.set("attrs", &Variant::from(attrs));
                        dict
                    }
                }
            }, Dictionary::<Variant, Variant>::new(),
        )
    }

	/// Same as `get_grid_updates` but returns PackedColorArray and PackedInt32Array
	/// instead of generic Array, avoiding per-element Variant boxing overhead.
	/// This is the preferred path for GDScript rendering.
	#[func]
	fn get_grid_updates_packed(&self, force_full: bool) -> Dictionary<Variant, Variant> {
		self.with_grid_mut_ret(
			|g| {
				let updates = g.get_grid_updates(force_full);
				let mut dict = Dictionary::<Variant, Variant>::new();
				match updates {
					godopty_core::term::GridUpdate::Full(rows) => {
						let n_rows = rows.len();
						let n_cols = if n_rows > 0 { rows[0].len() } else { 0 };
						let mut chars: Array<Variant> = Array::new();
						let mut fg_arr = PackedColorArray::new();
						let mut bg_arr = PackedColorArray::new();
						let mut attrs_arr = PackedInt32Array::new();
						for row in rows.iter() {
							let mut line = String::with_capacity(n_cols);
							for cell in row.iter() {
								line.push(cell.ch);
								fg_arr.push(Color::from_rgb(
									cell.fg[0] as f32 * RGB_SCALE,
									cell.fg[1] as f32 * RGB_SCALE,
									cell.fg[2] as f32 * RGB_SCALE,
								));
								bg_arr.push(Color::from_rgb(
									cell.bg[0] as f32 * RGB_SCALE,
									cell.bg[1] as f32 * RGB_SCALE,
									cell.bg[2] as f32 * RGB_SCALE,
								));
								let mut a: i32 = 0;
								if cell.bold { a |= 1; }
								if cell.italic { a |= 2; }
								if cell.underline { a |= 4; }
								if cell.inverse { a |= 8; }
								if cell.wide { a |= 16; }
								attrs_arr.push(a);
							}
							chars.push(&Variant::from(line));
						}
						dict.set("is_full", &Variant::from(true));
						dict.set("rows", &Variant::from(n_rows as i64));
						dict.set("cols", &Variant::from(n_cols as i64));
						dict.set("chars", &Variant::from(chars));
						dict.set("fg", &Variant::from(fg_arr));
						dict.set("bg", &Variant::from(bg_arr));
						dict.set("attrs", &Variant::from(attrs_arr));
					}
					godopty_core::term::GridUpdate::Partial(cells) => {
						let mut indices_arr = PackedInt32Array::new();
						let mut chars: Array<Variant> = Array::new();
						let mut fg_arr = PackedColorArray::new();
						let mut bg_arr = PackedColorArray::new();
						let mut attrs_arr = PackedInt32Array::new();
						let cols = g.num_cols();
						for u in cells {
							indices_arr.push((u.row * cols + u.col) as i32);
							chars.push(&Variant::from(u.cell.ch.to_string()));
							fg_arr.push(Color::from_rgb(
								u.cell.fg[0] as f32 * RGB_SCALE,
								u.cell.fg[1] as f32 * RGB_SCALE,
								u.cell.fg[2] as f32 * RGB_SCALE,
							));
							bg_arr.push(Color::from_rgb(
								u.cell.bg[0] as f32 * RGB_SCALE,
								u.cell.bg[1] as f32 * RGB_SCALE,
								u.cell.bg[2] as f32 * RGB_SCALE,
							));
							let mut a: i32 = 0;
							if u.cell.bold { a |= 1; }
							if u.cell.italic { a |= 2; }
							if u.cell.underline { a |= 4; }
							if u.cell.inverse { a |= 8; }
							if u.cell.wide { a |= 16; }
							attrs_arr.push(a);
						}
						dict.set("is_full", &Variant::from(false));
						dict.set("indices", &Variant::from(indices_arr));
						dict.set("chars", &Variant::from(chars));
						dict.set("fg", &Variant::from(fg_arr));
						dict.set("bg", &Variant::from(bg_arr));
						dict.set("attrs", &Variant::from(attrs_arr));
					}
				}
				dict
			},
			Dictionary::<Variant, Variant>::new(),
		)
	}

	/// Search the full grid (scrollback + visible) for `pattern`.
	///
	/// Returns a Dictionary: `{count: int, rows: Array[int], cols: Array[int], error: String}`.
	/// `rows[i]` is the 0-based line index from top of scrollback history.
	/// `cols[i]` is the byte offset within that line.
	/// On regex error, `error` is set and `count` is 0.
	#[func]
	fn search_grid(&self, pattern: GString) -> Dictionary<Variant, Variant> {
		self.with_grid(
			|g| {
				let mut dict = Dictionary::<Variant, Variant>::new();
				match g.search(&pattern.to_string()) {
					Ok(matches) => {
						let mut rows: Array<Variant> = Array::new();
						let mut cols: Array<Variant> = Array::new();
						for (row, col) in matches {
							rows.push(&Variant::from(row));
							cols.push(&Variant::from(col));
						}
						dict.set("count", &Variant::from(rows.len() as i64));
						dict.set("rows", &Variant::from(rows));
						dict.set("cols", &Variant::from(cols));
					}
					Err(e) => {
						dict.set("error", &Variant::from(e.to_string()));
						dict.set("count", &Variant::from(0i64));
					}
				}
				dict
			},
			Dictionary::<Variant, Variant>::new(),
		)
	}

	/// Convert a Godot key event to the raw PTY bytes (escape sequences for
	/// special keys, empty for unhandled keys that should use the unicode path).
	#[func]
	fn key_to_bytes(&self, keycode: i64, shift: bool, alt: bool, ctrl: bool, meta: bool) -> PackedByteArray {
		let mut m: u8 = 0;
		if shift { m |= godopty_core::keymap::Modifiers::SHIFT; }
		if alt   { m |= godopty_core::keymap::Modifiers::ALT; }
		if ctrl  { m |= godopty_core::keymap::Modifiers::CTRL; }
		if meta  { m |= godopty_core::keymap::Modifiers::SUPER; }

		// Translate Godot KEY_* constants to evdev scancodes
		let evdev = godot_key_to_evdev(keycode);
		match godopty_core::keymap::key_event_to_bytes(evdev, m) {
			Some(bytes) => PackedByteArray::from(bytes.as_slice()),
			None => PackedByteArray::new(),
		}
	}

	/// Replace all concepts in the global engine.
	/// `concepts_array` is an Array of Dictionaries, each with:
	///   "name": String, "trigger": String (regex), "actions": Array[{"cmd":String,"target":String}]
	#[func]
	fn set_global_concepts(&self, concepts_array: Array<Variant>) {
		use godopty_core::types::{Concept, Action};
		let mut concepts = Vec::new();
		for item in concepts_array.iter_shared() {
			let obj: Dictionary<Variant, Variant> = item.to();
			let name = obj.get("name").and_then(|v| v.try_to::<GString>().ok()).map(|s| s.to_string()).unwrap_or_default();
			let trigger = obj.get("trigger").and_then(|v| v.try_to::<GString>().ok()).map(|s| s.to_string()).unwrap_or_default();
			let Ok(re) = regex::Regex::new(&trigger) else { continue; };
			let mut actions = Vec::new();
			if let Some(acts) = obj.get("actions").and_then(|v| v.try_to::<Array<Variant>>().ok()) {
				for a in acts.iter_shared() {
					let ad: Dictionary<Variant, Variant> = a.to();
					let cmd = ad.get("cmd").and_then(|v| v.try_to::<GString>().ok()).map(|s| s.to_string()).unwrap_or_default();
					let target = ad.get("target").and_then(|v| v.try_to::<GString>().ok()).map(|s| s.to_string()).unwrap_or_default();
					actions.push(Action { command_template: cmd, target_label: target });
				}
			}
			concepts.push(Concept { name, trigger_regex: re, destinations: actions });
		}
		ENGINE.set_concepts(concepts);
	}
	/// Get all concepts as an Array of Dictionaries.
	#[func]
	fn get_global_concepts(&self) -> Array<Variant> {
		let concepts = ENGINE.get_concepts();
		let mut arr = Array::<Variant>::new();
		for c in &concepts {
			let mut obj = Dictionary::<Variant, Variant>::new();
			obj.set("name", &Variant::from(c.name.clone()));
			obj.set("trigger", &Variant::from(c.trigger_regex.as_str()));
			let mut acts = Array::<Variant>::new();
			for a in &c.destinations {
				let mut ad = Dictionary::<Variant, Variant>::new();
				ad.set("cmd", &Variant::from(a.command_template.clone()));
				ad.set("target", &Variant::from(a.target_label.clone()));
				acts.push(&Variant::from(ad));
			}
			obj.set("actions", &Variant::from(acts));
			arr.push(&Variant::from(obj));
		}
		arr
	}

}

/// Map Godot `Key` enum values to Linux evdev scancodes.
///
/// Godot keycodes for printable ASCII characters match the ASCII value
/// (e.g. KEY_A = 65, KEY_0 = 48). For these, we convert to evdev by
/// using the US QWERTY layout mapping. Special keys (arrows, F-keys, etc.)
/// use Godot-specific values in the 0x1000000 range.
fn godot_key_to_evdev(kc: i64) -> u32 {
	let k = kc as u32;
	match k {
		// Printable ASCII → evdev US QWERTY scancodes
		0x20 => 57,  // Space
		0x21..=0x2F => return k, // ! " # $ % & ' ( ) * + , - . / → raw
		0x30..=0x39 => k - 0x30 + 2,  // 0-9 → evdev 2-11
		0x3A..=0x40 => return k, // : ; < = > ? @ → raw
		0x41..=0x5A => k - 0x41 + 30, // A-Z → evdev 30-55
		0x5B..=0x60 => return k, // [ \ ] ^ _ ` → raw
		0x61..=0x7A => k - 0x61 + 30, // a-z → evdev 30-55
		0x7B..=0x7E => return k, // { | } ~ → raw

		// Godot special keys (0x1000000+)
		0x1000001 => 1,    // KEY_ESCAPE
		0x1000002 => 15,   // KEY_TAB
		0x1000003 => 14,   // KEY_BACKSPACE
		0x1000006 => 28,   // KEY_ENTER
		0x1000080 => 96,   // KEY_KP_ENTER
		0x1000007 => 111,  // KEY_DELETE
		0x1000008 => 110,  // KEY_INSERT
		0x100000A => 102,  // KEY_HOME
		0x100000B => 107,  // KEY_END
		0x100000C => 105,  // KEY_LEFT
		0x100000D => 103,  // KEY_UP
		0x100000E => 106,  // KEY_RIGHT
		0x100000F => 108,  // KEY_DOWN
		0x1000010 => 104,  // KEY_PAGEUP
		0x1000011 => 109,  // KEY_PAGEDOWN
		0x1000016 => 119,  // KEY_PAUSE

		// Function keys
		0x1000029 => 59,   // KEY_F1
		0x100002A => 60,   // KEY_F2
		0x100002B => 61,   // KEY_F3
		0x100002C => 62,   // KEY_F4
		0x100002D => 63,   // KEY_F5
		0x100002E => 64,   // KEY_F6
		0x100002F => 65,   // KEY_F7
		0x1000030 => 66,   // KEY_F8
		0x1000031 => 67,   // KEY_F9
		0x1000032 => 68,   // KEY_F10
		0x1000033 => 87,   // KEY_F11
		0x1000034 => 88,   // KEY_F12

		// Numpad
		0x1000081 => 55,   // KEY_KP_MULTIPLY
		0x1000083 => 98,   // KEY_KP_DIVIDE
		0x1000086 => 74,   // KEY_KP_SUBTRACT
		0x1000087 => 78,   // KEY_KP_ADD
		0x1000089 => 83,   // KEY_KP_PERIOD
		0x1000058 => 71,   // KEY_KP_7
		0x1000059 => 72,   // KEY_KP_8
		0x100005A => 73,   // KEY_KP_9
		0x100005B => 75,   // KEY_KP_4
		0x100005C => 76,   // KEY_KP_5
		0x100005D => 77,   // KEY_KP_6
		0x100005E => 79,   // KEY_KP_1
		0x100005F => 80,   // KEY_KP_2
		0x1000060 => 81,   // KEY_KP_3
		0x1000061 => 82,   // KEY_KP_0

		// Fallback: return as-is (won't match keymap but won't crash)
		_ => k,
	}

}

// ═══════════════════════════════════════════════════════════════════════
// Extension entry point
// ═══════════════════════════════════════════════════════════════════════

struct GodoptyExtension;

#[gdextension]
unsafe impl ExtensionLibrary for GodoptyExtension {}
