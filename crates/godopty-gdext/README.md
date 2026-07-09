# godopty-gdext

Godot 4 GDExtension that bridges the Rust terminal engine to Godot's renderer.

## Building

```bash
# From the workspace root
cargo build -p godopty-gdext

# The shared library is at:
target/debug/libgodopty_gdext.so
```

## Running in Godot

1. Open the `godot/` directory in the Godot editor
2. The `.gdextension` file auto-loads the shared library
3. Open `scenes/main.tscn` and press F5

## GDScript API

### GodoptyTerminal (extends Node2D)

| Method | Returns | Description |
|--------|---------|-------------|
| `start_shell(cmd: String, rows: int, cols: int)` | void | Start a PTY session |
| `send_text(text: String)` | void | Send raw text to PTY (no newline) |
| `send_line(text: String)` | void | Send a line to PTY (appends `\n`) |
| `resize_grid(rows: int, cols: int)` | void | Resize grid + send SIGWINCH |
| `set_palette(hex_csv: String)` | void | Load color scheme (16 hex colors, CSV) |
| `get_grid_rows()` | `Array[Array[Dictionary]]` | Full renderable grid |
| `get_grid_generation()` | `int` | Monotonic counter, changes on grid update |
| `get_cursor_row()` | `int` | Cursor row (0-based, -1 if none) |
| `get_cursor_col()` | `int` | Cursor column (0-based) |
| `get_cursor_shape()` | `int` | 0=Block, 1=Underline, 2=Beam |
| `get_title()` | `String` | Terminal window title (OSC) |
| `get_rows()` | `int` | Grid row count |
| `get_cols()` | `int` | Grid column count |
| `scroll_up(lines: int)` | void | Scroll back in history |
| `scroll_down(lines: int)` | void | Scroll forward in history |
| `scroll_reset()` | void | Reset scroll to follow output |
| `get_scroll_offset()` | `int` | Lines above visible viewport |
| `get_history_size()` | `int` | Total scrollback lines available |

### Grid Cell Dictionary

```gdscript
{
    "ch": "A",                     # String — the character
    "fg": Color(0.8, 0.8, 0.8),   # Color — foreground
    "bg": Color(0.12, 0.12, 0.12) # Color — background
}
```

### Tips

- Use `get_grid_generation()` to skip redundant `get_grid_rows()` calls when the grid is idle
- Poll at ~10–30 FPS; `get_grid_rows()` copies the entire grid
- If the grid mutex is held by the background task, `get_grid_rows()` returns `[]`
