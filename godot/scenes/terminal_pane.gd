extends Control
class_name TerminalPane
# godopty Terminal Pane — Control-based node for focus + rendering.

signal title_changed(new_title: String)

const CURSOR_BLINK_INTERVAL = 0.5
const SCROLL_LINES = 3
@export var scroll_lines: int = SCROLL_LINES
const PADDING = 4
const FOCUS_BORDER_COLOR = Color(0.4, 0.7, 1.0, 0.3)
const FOCUS_BORDER_WIDTH = 2.0
const SELECTION_COLOR = Color(0.3, 0.5, 1.0, 0.4)
const SCROLLBACK_INDICATOR_COLOR = Color.YELLOW
const BEAM_CURSOR_WIDTH = 2
const UNDERLINE_CURSOR_HEIGHT = 3
const PRINTABLE_ASCII_MIN = 32
const PRINTABLE_ASCII_MAX = 126

@export var shell_command: String = "/bin/bash"
@export var rows: int = 24
@export var cols: int = 80
@export var font_size: int = 14:
	set(value):
		font_size = value
		if _font != null:
			_recompute_cell_metrics()

@export var font_path: String = "res://fonts/DejaVuSansMono.ttf"
@export var font_bold_path: String = "res://fonts/DejaVuSansMono-Bold.ttf"
@export var font_italic_path: String = "res://fonts/DejaVuSansMono-Oblique.ttf"

@export var cursor_shape: int = 0
@export var cursor_color: Color = Color(0.8, 0.8, 0.8, 0.7)
@export var cursor_blink: bool = true
@export var cursor_blink_speed: float = CURSOR_BLINK_INTERVAL

@export var default_fg: Color = Color(0.8, 0.8, 0.8)
@export var default_bg: Color = Color(0.12, 0.12, 0.12)

var _terminal: GodoptyTerminal
var _font: Font
var _font_bold: Font
var _font_italic: Font
var _cell_cache: Array = []  # Array of Array[Dictionary] from gdext (untyped bridge)
var _cell_w: float = 0.0
var _cell_h: float = 0.0
var _cursor_blink_timer: float = 0.0
var _cursor_visible: bool = true
var _last_title: String = ""
var _selecting: bool = false
var _sel_start: Vector2i = Vector2i(-1, -1)
var _sel_end: Vector2i = Vector2i(-1, -1)
var _last_grid_gen: int = -1

func _ready():
	_terminal = GodoptyTerminal.new()
	add_child(_terminal)
	_terminal.start_shell(shell_command, rows, cols)

	_font = _load_font(font_path, "res://fonts/DejaVuSansMono.ttf")
	_font_bold = _load_font(font_bold_path, "res://fonts/DejaVuSansMono-Bold.ttf")
	_font_italic = _load_font(font_italic_path, "res://fonts/DejaVuSansMono-Oblique.ttf")

	_recompute_cell_metrics()

	focus_mode = Control.FOCUS_CLICK
	clip_contents = true

func _on_resize():
	if _terminal == null or _cell_w == 0: return
	var new_cols = maxi(int((size.x - PADDING) / _cell_w), 1)
	var new_rows = maxi(int((size.y - PADDING) / _cell_h), 1)
	if new_cols != cols or new_rows != rows:
		cols = new_cols; rows = new_rows
		_terminal.resize_grid(rows, cols)

func _notification(what):
	if what == NOTIFICATION_RESIZED: _on_resize()

func _get_layout_state() -> Dictionary:
	return {"shell": shell_command, "rows": rows, "cols": cols}

func _load_font(path: String, fallback: String) -> Font:
	var f: Font
	if path != "" and ResourceLoader.exists(path): f = load(path)
	else: f = load(fallback)
	f.fixed_size = font_size
	return f

func _recompute_cell_metrics():
	_font.fixed_size = font_size
	_font_bold.fixed_size = font_size
	_font_italic.fixed_size = font_size
	_cell_w = _font.get_char_size('W'.unicode_at(0), font_size).x
	_cell_h = _font.get_height(font_size)
	custom_minimum_size = Vector2(PADDING * _cell_w + PADDING, _cell_h * 2 + PADDING)

func _process(delta):
	if cursor_blink:
		_cursor_blink_timer += delta
		if _cursor_blink_timer > cursor_blink_speed:
			_cursor_blink_timer = 0.0
			_cursor_visible = not _cursor_visible
	else:
		_cursor_visible = true

	var gen = _terminal.get_grid_generation()
	if gen != _last_grid_gen:
		_last_grid_gen = gen
		var new_grid = _terminal.get_grid_rows()
		if _cell_changed(new_grid):
			_cell_cache = new_grid
			_cursor_visible = true
			_cursor_blink_timer = 0.0
	queue_redraw()

	var t = _terminal.get_title()
	if t != _last_title and t != "":
		_last_title = t; title_changed.emit(t)

func _cell_changed(new_grid: Array) -> bool:
	if _cell_cache.size() != new_grid.size(): return true
	for r in new_grid.size():
		var nr: Array = new_grid[r]; var or_: Array = _cell_cache[r]
		if nr.size() != or_.size(): return true
		for c in nr.size():
			var nc: Dictionary = nr[c]; var oc: Dictionary = or_[c]
			if nc["ch"] != oc["ch"] or nc["fg"] != oc["fg"] or nc["bg"] != oc["bg"]: return true
			if nc.get("bold", false) != oc.get("bold", false): return true
			if nc.get("inverse", false) != oc.get("inverse", false): return true
	return false

func _grid_offset() -> Vector2:
	var gc = _cell_cache[0].size() if _cell_cache.size() > 0 else 1
	var gr = _cell_cache.size()
	var tw = gc * _cell_w; var th = gr * _cell_h
	return Vector2(2 + maxf((size.x - PADDING - tw) / 2.0, 0), 2 + maxf((size.y - PADDING - th) / 2.0, 0))

func _draw():
	if _cell_cache.is_empty(): return

	var off = _grid_offset()
	var baseline = _font.get_ascent(font_size)

	draw_rect(Rect2(Vector2.ZERO, size), default_bg)
	_draw_cells(off, baseline)

	# Focus border
	if has_focus():
		draw_rect(Rect2(0, 0, size.x, size.y), FOCUS_BORDER_COLOR, false, FOCUS_BORDER_WIDTH)

	# Cursor
	if _cursor_visible:
		_draw_cursor(off, baseline)

	# Scrollback indicator
	var so = _terminal.get_scroll_offset()
	if so > 0:
		draw_string(_font, Vector2(off.x + _cell_w * 0.5, off.y + _cell_h * 0.5),
			"[Scroll: %d/%d lines]" % [so, _terminal.get_history_size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SCROLLBACK_INDICATOR_COLOR)

	# Selection
	if _sel_start.x >= 0 and _sel_end.x >= 0:
		_draw_selection(off)

func _draw_cells(off: Vector2, baseline: float):
	for r in _cell_cache.size():
		var row: Array = _cell_cache[r]
		for c in row.size():
			var cell: Dictionary = row[c]
			var x = off.x + c * _cell_w; var y = off.y + r * _cell_h
			var fg = cell["fg"] as Color; var bg = cell["bg"] as Color
			if cell.get("inverse", false): var tmp = fg; fg = bg; bg = tmp

			draw_rect(Rect2(x, y, _cell_w, _cell_h), bg)

			var ch: String = cell["ch"]
			if ch != " " and ch != "":
				var uf = _font
				if cell.get("bold", false): uf = _font_bold
				if cell.get("italic", false): uf = _font_italic
				draw_string(uf, Vector2(x, y + baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fg)

			if cell.get("underline", false):
				draw_line(Vector2(x, y + baseline + 2), Vector2(x + _cell_w, y + baseline + 2), fg, 1.0)

func _draw_cursor(off: Vector2, baseline: float):
	var cr = _terminal.get_cursor_row(); var cc = _terminal.get_cursor_col()
	if cr < 0 or cc < 0: return
	var cx = off.x + cc * _cell_w; var cy = off.y + cr * _cell_h
	var cursor_ch = ""
	if cr < _cell_cache.size():
		var rw: Array = _cell_cache[cr]
		if cc < rw.size(): cursor_ch = rw[cc]["ch"]

	match cursor_shape:
		0:
			draw_rect(Rect2(cx, cy, _cell_w, _cell_h), cursor_color)
			if cursor_ch != " " and cursor_ch != "":
				draw_string(_font, Vector2(cx, cy + baseline), cursor_ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
		1:
			draw_rect(Rect2(cx, cy + _cell_h - UNDERLINE_CURSOR_HEIGHT, _cell_w, UNDERLINE_CURSOR_HEIGHT), cursor_color)
		2:
			draw_rect(Rect2(cx, cy, BEAM_CURSOR_WIDTH, _cell_h), cursor_color)
		_:
			draw_rect(Rect2(cx, cy, _cell_w, _cell_h), cursor_color)
			if cursor_ch != " " and cursor_ch != "":
				draw_string(_font, Vector2(cx, cy + baseline), cursor_ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

func _draw_selection(off: Vector2):
	var sr0 = mini(_sel_start.y, _sel_end.y); var sr1 = maxi(_sel_start.y, _sel_end.y)
	var sc0 = mini(_sel_start.x, _sel_end.x); var sc1 = maxi(_sel_start.x, _sel_end.x)
	for r in range(sr0, sr1 + 1):
		if r < 0 or r >= _cell_cache.size(): continue
		var cb = sc0 if r == sr0 else 0; var ce = (sc1 if r == sr1 else cols - 1) + 1
		for c in range(cb, ce):
			if c >= 0 and c < cols:
				draw_rect(Rect2(off.x + c * _cell_w, off.y + r * _cell_h, _cell_w, _cell_h), SELECTION_COLOR)


func _get_selected_text() -> String:
	if _sel_start.x < 0 or _sel_end.x < 0 or _cell_cache.is_empty(): return ""
	var sr0 = mini(_sel_start.y, _sel_end.y); var sr1 = maxi(_sel_start.y, _sel_end.y)
	var sc0 = mini(_sel_start.x, _sel_end.x); var sc1 = maxi(_sel_start.x, _sel_end.x)
	var lines: Array[String] = []
	for r in range(sr0, sr1 + 1):
		if r < 0 or r >= _cell_cache.size(): continue
		var row: Array = _cell_cache[r]
		var cb = sc0 if r == sr0 else 0; var ce = (sc1 if r == sr1 else cols - 1)
		var line = ""
		for c in range(cb, ce + 1):
			if c < row.size(): line += row[c]["ch"]
		lines.append(line.rstrip(" "))
	return "\n".join(lines)

func _gui_input(event):
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_handle_mouse(event)
	elif event is InputEventKey and event.pressed:
		_handle_keyboard(event)

func _handle_mouse(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				grab_focus(); _selecting = true
				_sel_start = _mouse_to_cell(event.position); _sel_end = _sel_start; queue_redraw()
			else: _selecting = false; queue_redraw()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: _terminal.scroll_up(scroll_lines)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: _terminal.scroll_down(scroll_lines)
	if event is InputEventMouseMotion and _selecting:
		_sel_end = _mouse_to_cell(event.position); queue_redraw()

func _handle_keyboard(event: InputEventKey):
	if event.keycode == KEY_C and event.ctrl_pressed and event.shift_pressed:
		var st = _get_selected_text()
		if st != "": DisplayServer.clipboard_set(st)
		_sel_start = Vector2i(-1, -1); _sel_end = Vector2i(-1, -1); queue_redraw(); accept_event(); return
	if event.keycode == KEY_V and event.ctrl_pressed and event.shift_pressed:
		var cl = DisplayServer.clipboard_get()
		if cl != "": _terminal.send_text(cl)
		accept_event(); return
	_sel_start = Vector2i(-1, -1); _sel_end = Vector2i(-1, -1)
	if event.keycode == KEY_PAGEUP: _terminal.scroll_up(rows); accept_event(); return
	if event.keycode == KEY_PAGEDOWN: _terminal.scroll_down(rows); accept_event(); return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_terminal.send_line(""); _terminal.scroll_reset(); accept_event(); return
	_terminal.scroll_reset()
	var tx = _key_to_text(event)
	if tx != "": _terminal.send_text(tx); accept_event()

func _mouse_to_cell(pos: Vector2) -> Vector2i:
	var off = _grid_offset()
	return Vector2i(int((pos.x - off.x) / _cell_w), int((pos.y - off.y) / _cell_h))

func _key_to_text(event: InputEventKey) -> String:
	if event.unicode >= PRINTABLE_ASCII_MIN and event.unicode <= PRINTABLE_ASCII_MAX: return char(event.unicode)
	match event.keycode:
		KEY_BACKSPACE: return "\u007f"
		KEY_TAB: return "\t"
		KEY_ESCAPE: return "\u001b"
		KEY_UP: return "\u001b[A"
		KEY_DOWN: return "\u001b[B"
		KEY_RIGHT: return "\u001b[C"
		KEY_LEFT: return "\u001b[D"
		KEY_HOME: return "\u001b[H"
		KEY_END: return "\u001b[F"
		KEY_DELETE: return "\u001b[3~"
	return ""
