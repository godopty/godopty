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
| `send_input(text: String)` | void | Send text to the PTY (appends `\n`) |
| `get_grid_rows()` | `Array[Array[Dictionary]]` | Get the full renderable grid |
| `get_rows()` | `int` | Grid row count (0 if no shell) |
| `get_cols()` | `int` | Grid column count |

### Grid Cell Dictionary

```gdscript
{
    "ch": "A",                     # String — the character
    "fg": Color(0.8, 0.8, 0.8),   # Color — foreground
    "bg": Color(0.12, 0.12, 0.12) # Color — background
}
```

### Edge Cases

- **No shell started**: `get_grid_rows()` returns `[]`, `get_rows()` returns `0`
- **Double start**: Calling `start_shell()` twice replaces the old PTY (child process terminates)
- **Spawn failure**: Grid stays empty, error logged to Godot console
- **Large grids**: `get_grid_rows()` copies the entire grid — poll at ~10-30 FPS
- **Concurrent access**: The grid is behind a `Mutex`; if locked by the background task, `get_grid_rows()` returns `[]`
