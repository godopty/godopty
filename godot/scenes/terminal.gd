extends Node2D
# godopty Terminal Renderer
# Monospace font, scrollback, cursor shapes, cell attributes.
#
# All @export variables appear in the Godot editor Inspector and can be
# set per-terminal-instance.

@export var shell_command: String = "/bin/bash"
@export var rows: int = 24
@export var cols: int = 80
@export var font_size: int = 14

# ── Font ────────────────────────────────────────────────────────────
## Path to a .ttf monospace font. Leave empty to use the bundled DejaVu Sans Mono.
@export var font_path: String = "res://fonts/DejaVuSansMono.ttf"
## Bold variant (same family). Uses the bundled DejaVu Sans Mono Bold if empty.
@export var font_bold_path: String = "res://fonts/DejaVuSansMono-Bold.ttf"
## Italic/Oblique variant. Uses the bundled DejaVu Sans Mono Oblique if empty.
@export var font_italic_path: String = "res://fonts/DejaVuSansMono-Oblique.ttf"

# ── Cursor styling ──────────────────────────────────────────────────
## 0 = Block, 1 = Underline, 2 = Beam.  Overridden at runtime by the shell
## if it emits DECSCUSR escape sequences (via vte::ansi::CursorShape).
@export var cursor_shape: int = 0
## Cursor color when not overridden by the shell.
@export var cursor_color: Color = Color(0.8, 0.8, 0.8, 0.7)
## If false, the cursor does not blink.
@export var cursor_blink: bool = true

# ── Terminal colors (used as defaults; shell SGR sequences override) ─
@export var default_fg: Color = Color(0.8, 0.8, 0.8)   # light gray
@export var default_bg: Color = Color(0.12, 0.12, 0.12) # dark gray

var _terminal: GodoptyTerminal
var _font: Font
var _font_bold: Font
var _font_italic: Font
var _cell_cache: Array = []
var _cell_w: float = 0.0
var _cell_h: float = 0.0
var _cursor_blink_timer: float = 0.0
var _cursor_visible: bool = true
# ── Text selection ──────────────────────────────────────────────────
var _selecting: bool = false
var _sel_start: Vector2i = Vector2i(-1, -1)
var _sel_end: Vector2i = Vector2i(-1, -1)

func _ready():
	_terminal = GodoptyTerminal.new()
	add_child(_terminal)
	_terminal.start_shell(shell_command, rows, cols)

	# Load fonts from user-configured paths (fall back to bundled)
	_font = _load_font(font_path, "res://fonts/DejaVuSansMono.ttf")
	_font_bold = _load_font(font_bold_path, "res://fonts/DejaVuSansMono-Bold.ttf")
	_font_italic = _load_font(font_italic_path, "res://fonts/DejaVuSansMono-Oblique.ttf")

	_cell_w = _font.get_char_size('W'.unicode_at(0), font_size).x
	_cell_h = _font.get_height(font_size)

func _load_font(path: String, fallback: String) -> Font:
	var f: Font
	if path != "" and ResourceLoader.exists(path):
		f = load(path)
	else:
		f = load(fallback)
	f.fixed_size = font_size
	return f

func _process(delta):
	if cursor_blink:
		_cursor_blink_timer += delta
		if _cursor_blink_timer > 0.5:
			_cursor_blink_timer = 0.0
			_cursor_visible = not _cursor_visible
	else:
		_cursor_visible = true

	var new_grid = _terminal.get_grid_rows()
	if _cell_changed(new_grid):
		_cell_cache = new_grid
		_cursor_visible = true
		_cursor_blink_timer = 0.0
		queue_redraw()
	else:
		queue_redraw()

func _cell_changed(new_grid: Array) -> bool:
	if _cell_cache.size() != new_grid.size():
		return true
	for r in new_grid.size():
		var new_row: Array = new_grid[r]
		var old_row: Array = _cell_cache[r]
		if new_row.size() != old_row.size():
			return true
		for c in new_row.size():
			var nc: Dictionary = new_row[c]
			var oc: Dictionary = old_row[c]
			if nc["ch"] != oc["ch"] or nc["fg"] != oc["fg"] or nc["bg"] != oc["bg"]:
				return true
			if nc.get("bold", false) != oc.get("bold", false):
				return true
			if nc.get("inverse", false) != oc.get("inverse", false):
				return true
	return false

func _draw():
	if _cell_cache.is_empty():
		return

	for r in _cell_cache.size():
		var row: Array = _cell_cache[r]
		for c in row.size():
			var cell: Dictionary = row[c]
			var x = c * _cell_w
			var y = r * _cell_h

			var fg = cell["fg"] as Color
			var bg = cell["bg"] as Color
			if cell.get("inverse", false):
				var tmp = fg; fg = bg; bg = tmp

			draw_rect(Rect2(x, y, _cell_w, _cell_h), bg)

			var ch: String = cell["ch"]
			if ch != " " and ch != "":
				var use_font = _font
				if cell.get("bold", false):
					use_font = _font_bold
				if cell.get("italic", false):
					use_font = _font_italic
				draw_string(use_font, Vector2(x, y + _cell_h - 2), ch,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fg)

			if cell.get("underline", false):
				var ul_y = y + _cell_h - 2
				draw_line(Vector2(x, ul_y), Vector2(x + _cell_w, ul_y), fg, 1.0)

	# ── Cursor ──────────────────────────────────────────────────────
	if _cursor_visible:
		var crow = _terminal.get_cursor_row()
		var ccol = _terminal.get_cursor_col()
		if crow >= 0 and ccol >= 0:
			var cx = ccol * _cell_w
			var cy = crow * _cell_h
			var cshape = cursor_shape  # user config takes priority over DECSCUSR
			var _cur_color = cursor_color

			# Get the character under the cursor
			var cursor_ch = ""
			if crow < _cell_cache.size():
				var row: Array = _cell_cache[crow]
				if ccol < row.size():
					cursor_ch = row[ccol]["ch"]

			match cshape:
				0: # Block
					draw_rect(Rect2(cx, cy, _cell_w, _cell_h), _cur_color)
					if cursor_ch != " " and cursor_ch != "":
						draw_string(_font, Vector2(cx, cy + _cell_h - 2), cursor_ch,
							HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
				1: # Underline
					draw_rect(Rect2(cx, cy + _cell_h - 3, _cell_w, 3), _cur_color)
				2: # Beam (vertical bar)
					draw_rect(Rect2(cx, cy, 2, _cell_h), _cur_color)
				_: # Default Block
					draw_rect(Rect2(cx, cy, _cell_w, _cell_h), _cur_color)
					if cursor_ch != " " and cursor_ch != "":
						draw_string(_font, Vector2(cx, cy + _cell_h - 2), cursor_ch,
							HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

	# ── Scrollback indicator ─────────────────────────────────────────
	var offset = _terminal.get_scroll_offset()
	if offset > 0:
		draw_string(_font, Vector2(_cell_w * 0.5, _cell_h * 0.5),
			"[Scroll: %d/%d lines]" % [offset, _terminal.get_history_size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.YELLOW)

	# ── Selection highlight ──────────────────────────────────────────
	if _sel_start.x >= 0 and _sel_end.x >= 0:
		var sr0 = mini(_sel_start.y, _sel_end.y)
		var sr1 = maxi(_sel_start.y, _sel_end.y)
		var sc0 = mini(_sel_start.x, _sel_end.x)
		var sc1 = maxi(_sel_start.x, _sel_end.x)
		for r in range(sr0, sr1 + 1):
			if r < 0 or r >= _cell_cache.size():
				continue
			var c_begin = sc0 if r == sr0 else 0
			var c_end = (sc1 if r == sr1 else cols - 1) + 1
			for c in range(c_begin, c_end):
				if c >= 0 and c < cols:
					draw_rect(Rect2(c * _cell_w, r * _cell_h, _cell_w, _cell_h),
						Color(0.3, 0.5, 1.0, 0.4))

func _mouse_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / _cell_w), int(pos.y / _cell_h))

func _get_selected_text() -> String:
	if _sel_start.x < 0 or _sel_end.x < 0 or _cell_cache.is_empty():
		return ""
	var sr0 = mini(_sel_start.y, _sel_end.y)
	var sr1 = maxi(_sel_start.y, _sel_end.y)
	var sc0 = mini(_sel_start.x, _sel_end.x)
	var sc1 = maxi(_sel_start.x, _sel_end.x)
	var lines: Array[String] = []
	for r in range(sr0, sr1 + 1):
		if r < 0 or r >= _cell_cache.size():
			continue
		var row: Array = _cell_cache[r]
		var c_begin = sc0 if r == sr0 else 0
		var c_end = (sc1 if r == sr1 else cols - 1)
		var line = ""
		for c in range(c_begin, c_end + 1):
			if c < row.size():
				line += row[c]["ch"]
		lines.append(line.rstrip(" "))
	return "\n".join(lines)

func _input(event):
	# ── Mouse selection ────────────────────────────────────────────
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_selecting = true
				_sel_start = _mouse_to_cell(event.position)
				_sel_end = _sel_start
				queue_redraw()
			else:
				_selecting = false
				queue_redraw()

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_terminal.scroll_up(3)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_terminal.scroll_down(3)

	if event is InputEventMouseMotion and _selecting:
		_sel_end = _mouse_to_cell(event.position)
		queue_redraw()

	# ── Keyboard ────────────────────────────────────────────────────
	if event is InputEventKey and event.pressed:
		# Ctrl+Shift+C = copy selection
		if event.keycode == KEY_C and event.ctrl_pressed and event.shift_pressed:
			var sel_text = _get_selected_text()
			if sel_text != "":
				DisplayServer.clipboard_set(sel_text)
				print("[godopty] Copied %d chars" % sel_text.length())
			# Clear selection
			_sel_start = Vector2i(-1, -1)
			_sel_end = Vector2i(-1, -1)
			queue_redraw()
			return

		# Clear selection on any other key
		_sel_start = Vector2i(-1, -1)
		_sel_end = Vector2i(-1, -1)

		if event.keycode == KEY_PAGEUP:
			_terminal.scroll_up(rows)
			return
		if event.keycode == KEY_PAGEDOWN:
			_terminal.scroll_down(rows)
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_terminal.send_line("")
			_terminal.scroll_reset()
			return

		_terminal.scroll_reset()
		var text = _key_to_text(event)
		if text != "":
			_terminal.send_text(text)

func _key_to_text(event: InputEventKey) -> String:
	if event.unicode >= 32 and event.unicode <= 126:
		return char(event.unicode)

	match event.keycode:
		KEY_BACKSPACE:
			return "\u007f"
		KEY_TAB:
			return "\t"
		KEY_ESCAPE:
			return "\u001b"
		KEY_UP:
			return "\u001b[A"
		KEY_DOWN:
			return "\u001b[B"
		KEY_RIGHT:
			return "\u001b[C"
		KEY_LEFT:
			return "\u001b[D"
		KEY_HOME:
			return "\u001b[H"
		KEY_END:
			return "\u001b[F"
		KEY_DELETE:
			return "\u001b[3~"

	return ""
