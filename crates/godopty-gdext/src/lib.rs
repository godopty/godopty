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

use std::sync::LazyLock;

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
    fn start_shell(&mut self, command: GString, rows: i64, cols: i64) {
        let id = self.next_id;
        self.next_id += 1;

        let config = TerminalConfig {
            id,
            labels: Vec::new(),
        };

        let rows = rows.max(MIN_DIM) as usize;
        let cols = cols.max(MIN_DIM) as usize;

        godot_print!("[GDExt] Starting PTY {id}: {command} ({rows}×{cols})");

        match RUNTIME.block_on(ENGINE.spawn_terminal_with_grid(
            config,
            &command.to_string(),
            &[],
            rows,
            cols,
        )) {
            Ok(spawned) => {
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


}

// ═══════════════════════════════════════════════════════════════════════
// Extension entry point
// ═══════════════════════════════════════════════════════════════════════

struct GodoptyExtension;

#[gdextension]
unsafe impl ExtensionLibrary for GodoptyExtension {}
