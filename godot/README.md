# godopty — Godot Project

## Running

```bash
# Build the Rust extension first
cd .. && cargo build -p godopty-gdext

# Launch Godot (editor)
cd godot && godot -e

# Press F5 to run the application
```

## Structure

```
godot/
├── project.godot            # Godot 4.7 project config
├── godopty.gdextension      # GDExtension library config
├── fonts/                   # Bundled monospace fonts
│   ├── DejaVuSansMono.ttf
│   ├── DejaVuSansMono-Bold.ttf
│   └── DejaVuSansMono-Oblique.ttf
└── scenes/
    ├── main.tscn            # Root scene (Workspace)
    ├── workspace.gd         # Workspace controller — grid layout, sidebar, palette
    ├── terminal_pane.gd     # Terminal Control — rendering, keyboard, focus
    └── focus_manager.gd     # Autoload — Alt+Arrow pane navigation
```

## Key Bindings

| Shortcut | Action |
|----------|--------|
| Ctrl+N | Spawn new terminal |
| Ctrl+W | Close focused terminal |
| Ctrl+B | Toggle sidebar |
| Ctrl+P | Command palette |
| Ctrl+Shift+R | Emergency reset |
| Ctrl+Shift+C | Copy selection |
| Ctrl+Shift+V | Paste from clipboard |
| Alt+←↑↓→ | Jump to adjacent pane |

## Sidebar

- [+ Terminal] — spawn a new terminal
- [⚙ Settings] — open global settings panel
- [↺ Reset] — clear all terminals and layout

Layout is auto-saved on close and auto-restored on startup via `user://layout.json`.

## Command Palette (Ctrl+P)

Type partial commands: `new`, `close`, `settings`, `reset`, `save`, `load`.
