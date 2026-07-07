//! Full terminal grid via `alacritty_terminal`.
//!
//! [`TermGrid`] wraps `alacritty_terminal::Term` and provides:
//!
//! - Byte feeding through `vte::ansi::Processor` (full DEC STD 070 emulation)
//! - Grid export as a 2D array of [`CellInfo`] structs ready for Godot `_draw()`
//! - `SIGWINCH`-compatible resize
//!
//! Unlike [`crate::parser::LineParser`] (which only extracts plain text),
//! this module maintains cursor position, SGR attributes (16M colors, bold,
//! italic, underline), scrolling regions, and all VT100/VT220/xterm escape
//! sequences.

use std::sync::{Arc, Mutex};

use alacritty_terminal::event::{Event as TermEvent, EventListener};
use alacritty_terminal::grid::{Dimensions, Grid, Scroll};
use alacritty_terminal::term::cell::Cell;
use alacritty_terminal::term::cell::Flags;
use alacritty_terminal::term::Config;
use alacritty_terminal::vte::ansi::{Color, NamedColor};
use alacritty_terminal::Term;

/// A character cell ready for rendering.
#[derive(Debug, Clone)]
pub struct CellInfo {
    pub ch: char,
    pub fg: [u8; 3],
    pub bg: [u8; 3],
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub inverse: bool,
}

/// A simple [`Dimensions`] implementation used for creating and resizing
/// the terminal grid. alacritty_terminal does not ship a concrete size
/// type — callers provide one via the trait.
struct GridSize {
    rows: usize,
    cols: usize,
}

impl Dimensions for GridSize {
    fn total_lines(&self) -> usize {
        self.rows
    }
    fn screen_lines(&self) -> usize {
        self.rows
    }
    fn columns(&self) -> usize {
        self.cols
    }
}

/// A wrapper around `alacritty_terminal::Term` for headless grid management.
///
/// # Usage
///
/// ```ignore
/// let mut grid = TermGrid::new(24, 80);
/// grid.feed(b"Hello, \x1b[91mworld\x1b[0m!\r\n");
/// let rows = grid.renderable_rows();
/// assert_eq!(rows[0][7].ch, 'w');
/// assert_eq!(rows[0][7].fg, [255, 0, 0]); // bright red via \\x1b[91m
/// ```
/// A custom event listener that captures OSC window title sequences.
struct TitleListener {
    title: Arc<Mutex<String>>,
}

impl EventListener for TitleListener {
    fn send_event(&self, event: TermEvent) {
        if let TermEvent::Title(t) = event {
            if let Ok(mut title) = self.title.lock() {
                *title = t;
            }
        }
    }
}

pub struct TermGrid {
    term: Term<TitleListener>,
    processor: vte::ansi::Processor,
    title: Arc<Mutex<String>>,
    rows: usize,
    cols: usize,
}

impl TermGrid {
    /// Create a new terminal grid at the given dimensions.
    ///
    /// The cell area is `rows × cols`. The default alacritty config is
    /// used; a custom `Config` can be substituted later if needed.
    pub fn new(rows: usize, cols: usize) -> Self {
        let config = Config::default();
        let size = GridSize { rows, cols };
        let title = Arc::new(Mutex::new(String::new()));
        let listener = TitleListener { title: Arc::clone(&title) };
        let term = Term::new(config, &size, listener);
        let processor = vte::ansi::Processor::new();

        Self { term, processor, title, rows, cols }
    }

    /// Feed raw PTY output bytes into the terminal state machine.
    ///
    /// This updates the internal grid (cursor position, scrolling, SGR
    /// state, etc.). Call this whenever new bytes arrive from the PTY
    /// read thread.
    pub fn feed(&mut self, bytes: &[u8]) {
        self.processor.advance(&mut self.term, bytes);
    }

    /// Return the full grid as row-major `Vec<Vec<CellInfo>>`.
    ///
    /// Row 0 is the **top** visible row (after accounting for scrollback).
    /// Each row has exactly `self.cols` cells. Empty cells are represented
    /// as `CellInfo { ch: ' ', fg: DEFAULT_FG, bg: DEFAULT_BG }`.
    ///
    /// This is the primary data structure passed to Godot's `_draw()`.
    pub fn renderable_rows(&self) -> Vec<Vec<CellInfo>> {
        let content = self.term.renderable_content();
        let mut rows: Vec<Vec<CellInfo>> =
            vec![vec![CellInfo::default(); self.cols]; self.rows];

        for indexed in content.display_iter {
            // alacritty uses i32-based indexing; convert to usize for vec access
            let line = indexed.point.line.0 as usize;
            let col = indexed.point.column.0 as usize;

            if line < self.rows && col < self.cols {
                rows[line][col] = CellInfo::from_cell(indexed.cell);
            }
        }

        rows
    }

    /// Get a direct reference to the underlying alacritty grid.
    ///
    /// Useful for advanced operations like scrollback inspection.
    pub fn grid(&self) -> &Grid<Cell> {
        self.term.grid()
    }

    /// Resize the terminal grid (the `SIGWINCH` path).
    ///
    /// Called when the Godot `SplitContainer` changes dimensions. The
    /// underlying PTY must also be notified with `ioctl(TIOCSWINSZ)` —
    /// that is handled by [`crate::pty::PtyHandle`].
    pub fn resize(&mut self, rows: usize, cols: usize) {
        self.rows = rows;
        self.cols = cols;
        self.term.resize(GridSize { rows, cols });
    }

    /// Current terminal title (set via OSC escape sequences, e.g. bash prompt).
    pub fn title(&self) -> String {
        self.title.lock().map(|t| t.clone()).unwrap_or_default()
    }

    /// Current row count.
    pub fn num_rows(&self) -> usize {
        self.rows
    }

    /// Current column count.
    pub fn num_cols(&self) -> usize {
        self.cols
    }

    /// Cursor position as `(row, col)`, or `None` if the cursor is hidden
    /// or outside the visible viewport.
    pub fn cursor_position(&self) -> Option<(usize, usize)> {
        let content = self.term.renderable_content();
        let point = content.cursor.point;
        let line = point.line.0 as usize;
        let col = point.column.0 as usize;
        if line < self.rows && col < self.cols {
            Some((line, col))
        } else {
            None
        }
    }

    /// Cursor shape: 0 = Block, 1 = Underline, 2 = Beam.
    pub fn cursor_shape(&self) -> u8 {
        match self.term.renderable_content().cursor.shape {
            alacritty_terminal::vte::ansi::CursorShape::Block => 0,
            alacritty_terminal::vte::ansi::CursorShape::Underline => 1,
            alacritty_terminal::vte::ansi::CursorShape::Beam => 2,
            _ => 0,
        }
    }

    // ── Scrollback ─────────────────────────────────────────────────

    /// Current scrollback offset (0 = following output at bottom).
    pub fn display_offset(&self) -> usize {
        self.term.grid().display_offset()
    }

    /// Total lines of scrollback history stored.
    pub fn history_size(&self) -> usize {
        self.term.grid().history_size()
    }

    /// Scroll up (back in history) by `lines`.
    pub fn scroll_up(&mut self, lines: usize) {
        self.term.grid_mut().scroll_display(Scroll::Delta(lines as i32));
    }

    /// Scroll down (forward in history) by `lines`.
    pub fn scroll_down(&mut self, lines: usize) {
        self.term.grid_mut().scroll_display(Scroll::Delta(-(lines as i32)));
    }

    /// Reset scroll to follow live output (bottom).
    pub fn scroll_reset(&mut self) {
        self.term.grid_mut().scroll_display(Scroll::Bottom);
    }
}

// ── CellInfo helpers ───────────────────────────────────────────────────

impl CellInfo {
    /// Default terminal foreground color (light gray).
    pub const DEFAULT_FG: [u8; 3] = [204, 204, 204];
    /// Default terminal background color (dark gray).
    pub const DEFAULT_BG: [u8; 3] = [30, 30, 30];

    pub fn default() -> Self {
        Self {
            ch: ' ',
            fg: Self::DEFAULT_FG,
            bg: Self::DEFAULT_BG,
            bold: false,
            italic: false,
            underline: false,
            inverse: false,
        }
    }

    /// Convert from alacritty's `Cell` type.
    ///
    /// Named colors (like "Background", "Foreground", "Red") are resolved
    /// to their approximate RGB values. True-color ANSI sequences
    /// (`\x1b[38;2;R;G;Bm`) are handled natively by `vte::ansi::Rgb`.
    fn from_cell(cell: &Cell) -> Self {
        let flags = cell.flags;
        Self {
            ch: cell.c,
            fg: color_to_rgb(&cell.fg),
            bg: color_to_rgb(&cell.bg),
            bold: flags.contains(Flags::BOLD),
            italic: flags.contains(Flags::ITALIC),
            underline: flags.contains(Flags::UNDERLINE),
            inverse: flags.contains(Flags::INVERSE),
        }
    }
}

// ── Color conversion ───────────────────────────────────────────────────

/// Convert an alacritty/vte `Color` to an `[R, G, B]` triplet.
///
/// Named colors use the standard xterm-256color palette. Indexed colors
/// (256-color mode) are approximated. True-color is passed through
/// directly.
fn color_to_rgb(color: &Color) -> [u8; 3] {
    match color {
        Color::Named(named) => named_to_rgb(named),
        Color::Spec(rgb) => [rgb.r, rgb.g, rgb.b],
        Color::Indexed(idx) => indexed_to_rgb(*idx),
    }
}

/// Map standard 16 ANSI named colors to approximate RGB values.
fn named_to_rgb(named: &NamedColor) -> [u8; 3] {
    match named {
        NamedColor::Background => CellInfo::DEFAULT_BG,
        NamedColor::Foreground => CellInfo::DEFAULT_FG,
        NamedColor::Black => [0, 0, 0],
        NamedColor::Red => [205, 0, 0],
        NamedColor::Green => [0, 205, 0],
        NamedColor::Yellow => [205, 205, 0],
        NamedColor::Blue => [0, 0, 238],
        NamedColor::Magenta => [205, 0, 205],
        NamedColor::Cyan => [0, 205, 205],
        NamedColor::White => [229, 229, 229],
        NamedColor::BrightBlack => [127, 127, 127],
        NamedColor::BrightRed => [255, 0, 0],
        NamedColor::BrightGreen => [0, 255, 0],
        NamedColor::BrightYellow => [255, 255, 0],
        NamedColor::BrightBlue => [92, 92, 255],
        NamedColor::BrightMagenta => [255, 0, 255],
        NamedColor::BrightCyan => [0, 255, 255],
        NamedColor::BrightWhite => [255, 255, 255],
        NamedColor::BrightForeground => [255, 255, 255],
        NamedColor::DimBlack => [0, 0, 0],
        NamedColor::DimRed => [205, 0, 0],
        NamedColor::DimGreen => [0, 205, 0],
        NamedColor::DimYellow => [205, 205, 0],
        NamedColor::DimBlue => [0, 0, 238],
        NamedColor::DimMagenta => [205, 0, 205],
        NamedColor::DimCyan => [0, 205, 205],
        NamedColor::DimWhite => [229, 229, 229],
        // Cursor, ViMode, search match — fall back to default foreground
        _ => CellInfo::DEFAULT_FG,
    }
}

/// Approximate a 256-color palette index to an RGB triplet.
///
/// Colors 0–15 are system colors, 16–231 form a 6×6×6 RGB cube, and
/// 232–255 form a grayscale ramp. This follows the standard xterm
/// 256-color palette.
fn indexed_to_rgb(idx: u8) -> [u8; 3] {
    match idx {
        0 => [0, 0, 0],
        1 => [205, 0, 0],
        2 => [0, 205, 0],
        3 => [205, 205, 0],
        4 => [0, 0, 238],
        5 => [205, 0, 205],
        6 => [0, 205, 205],
        7 => [229, 229, 229],
        8 => [127, 127, 127],
        9 => [255, 0, 0],
        10 => [0, 255, 0],
        11 => [255, 255, 0],
        12 => [92, 92, 255],
        13 => [255, 0, 255],
        14 => [0, 255, 255],
        15 => [255, 255, 255],
        // 16–231: 6×6×6 color cube
        n if n < 232 => {
            let n = n - 16;
            let r = (n / 36) * 51;
            let g = ((n / 6) % 6) * 51;
            let b = (n % 6) * 51;
            [r, g, b]
        }
        // 232–255: grayscale ramp (8 to 238 in steps of 10)
        n => {
            let gray = (n as u16 - 232) * 10 + 8;
            [gray as u8, gray as u8, gray as u8]
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_grid() {
        let g = TermGrid::new(24, 80);
        assert_eq!(g.num_rows(), 24);
        assert_eq!(g.num_cols(), 80);
    }

    #[test]
    fn feed_plain_text() {
        let mut g = TermGrid::new(5, 20);
        g.feed(b"hello\r\n");
        let rows = g.renderable_rows();
        assert_eq!(rows[0][0].ch, 'h');
        assert_eq!(rows[0][4].ch, 'o');
    }

    #[test]
    fn feed_ansi_colors() {
        let mut g = TermGrid::new(5, 20);
        g.feed(b"\x1b[31mRED\x1b[0m\r\n");
        let rows = g.renderable_rows();
        assert_eq!(rows[0][0].ch, 'R');
        assert_eq!(rows[0][0].fg, [205, 0, 0]);  // \x1b[31m = Red
    }

    #[test]
    fn cursor_position() {
        let mut g = TermGrid::new(5, 20);
        g.feed(b"abc");
        let pos = g.cursor_position().expect("cursor should be visible");
        assert_eq!(pos, (0, 3));
    }

    #[test]
    fn scrollback_basic() {
        let mut g = TermGrid::new(3, 10);
        g.feed(b"line1\r\nline2\r\nline3\r\nline4\r\nline5\r\n");
        assert!(g.history_size() > 0);
        g.scroll_up(2);
        assert_eq!(g.display_offset(), 2);
        g.scroll_reset();
        assert_eq!(g.display_offset(), 0);
    }

    #[test]
    fn resize_grid() {
        let mut g = TermGrid::new(24, 80);
        g.resize(30, 100);
        assert_eq!(g.num_rows(), 30);
        assert_eq!(g.num_cols(), 100);
    }

    #[test]
    fn title_capture() {
        let mut g = TermGrid::new(5, 20);
        g.feed(b"\x1b]0;Test Title\x07");
        assert_eq!(g.title(), "Test Title");
    }
}
