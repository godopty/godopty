extends Control
class_name Workspace
# godopty Workspace — tiling grid of terminal panes with title bars.

const LAYOUT_FILE = "user://layout.json"
const SETTINGS_FILE = "user://settings.json"
const DEFAULT_SHELL = "/bin/bash"
const GRID = 12
const MIN_TILE = 2

# Default terminal dimensions
const DEFAULT_ROWS = 24
const DEFAULT_COLS = 80

# Layout
const SIDEBAR_WIDTH = 180
const SIDEBAR_COLLAPSED_WIDTH = 20
const TITLE_BAR_HEIGHT = 26
const BUTTON_MIN_WIDTH = 22
const BUTTON_MIN_HEIGHT = 18

# Colors
const WRAPPER_BG_COLOR = Color(0.1, 0.1, 0.1, 1.0)
const TITLE_BAR_BG_COLOR = Color(0.18, 0.18, 0.20, 1.0)
const WRAPPER_BORDER_COLOR = Color(0.25, 0.25, 0.25, 0.6)
const SIDEBAR_BG_COLOR = Color(0.12, 0.12, 0.15, 1.0)

# UI sizes
const SETTINGS_PANEL_W = 320
const SETTINGS_PANEL_H = 520
const PALETTE_PANEL_W = 350
const PALETTE_PANEL_H = 240
const MIN_FONT_SIZE = 8
const MAX_FONT_SIZE = 32
const MIN_WINDOW_W = 500
const MIN_WINDOW_H = 300

# Timing
const SETTINGS_DEBOUNCE = 0.15
const TOAST_DURATION = 2.0
const TOAST_DELAY = 1.5

# Content
const PALETTE_COMMANDS = ["new terminal", "close active", "settings", "reset layout", "save", "load"]

const TerminalPaneScript = preload("res://scenes/terminal_pane.gd")

# Default settings (overridden by settings.json)
var _cfg_cursor_shape := 0
var _cfg_cursor_blink := true
var _cfg_cursor_blink_speed := 0.5
var _cfg_scroll_lines := 3
var _cfg_default_rows := 24
var _cfg_default_cols := 80
var _cfg_beam_width := 2
var _cfg_underline_height := 3
var _cfg_wrapper_bg := WRAPPER_BG_COLOR
var _cfg_title_bar_bg := TITLE_BAR_BG_COLOR
var _cfg_wrapper_border := WRAPPER_BORDER_COLOR
var _cfg_sidebar_bg := SIDEBAR_BG_COLOR
var _cfg_focus_border := TerminalPane.FOCUS_BORDER_COLOR
var _cfg_selection := TerminalPane.SELECTION_COLOR
var _cfg_scrollback_indicator := TerminalPane.SCROLLBACK_INDICATOR_COLOR
var _cfg_font_path := "res://fonts/DejaVuSansMono.ttf"
var _cfg_font_size := 14

var _sidebar: Control
var _sidebar_bg: ColorRect
var _sidebar_on := true
var _palette: Control
var _grid: Control
var _last_body: Control
var _tiles: Array[Dictionary] = []  # [{wrapper, col, row, cspan, rspan}]

func _ready():
	show()
	DisplayServer.window_set_min_size(Vector2i(MIN_WINDOW_W, MIN_WINDOW_H))
	_load_settings()

	_grid = Control.new()
	add_child(_grid)
	_build_sidebar()
	_sidebar.show()
	_apply_layout()

	if FileAccess.file_exists(LAYOUT_FILE): _restore()

func _notification(what):
	if what == NOTIFICATION_RESIZED: _apply_layout()
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _save()

# ═══════════════════════════════════════════════════════════════════════
# Layout
# ═══════════════════════════════════════════════════════════════════════

func _apply_layout():
	if _grid == null: return
	var m = SIDEBAR_WIDTH if _sidebar_on else SIDEBAR_COLLAPSED_WIDTH
	_grid.offset_left = m; _grid.offset_right = 0
	_grid.offset_top = 0; _grid.offset_bottom = 0
	_grid.anchor_left = 0.0; _grid.anchor_right = 1.0
	_grid.anchor_top = 0.0; _grid.anchor_bottom = 1.0

	var cw = maxf(_grid.size.x, 1.0) / GRID
	var ch = maxf(_grid.size.y, 1.0) / GRID
	for t in _tiles:
		var x = t.col * cw; var y = t.row * ch
		var w = t.cspan * cw; var h = t.rspan * ch
		t.wrapper.offset_left = x; t.wrapper.offset_top = y
		t.wrapper.offset_right = x + w; t.wrapper.offset_bottom = y + h
		t.wrapper.anchor_left = 0.0; t.wrapper.anchor_right = 0.0
		t.wrapper.anchor_top = 0.0; t.wrapper.anchor_bottom = 0.0

# ═══════════════════════════════════════════════════════════════════════
# Spawn / Kill
# ═══════════════════════════════════════════════════════════════════════

func _spawn(shell := DEFAULT_SHELL) -> Control:
	var w = _build_wrapper(shell, _cfg_default_rows, _cfg_default_cols)
	if _tiles.is_empty():
		_tiles.append({wrapper = w, col = 0, row = 0, cspan = GRID, rspan = GRID})
	else:
		if not _split_for(w):
			w.queue_free()
			ToastManager.warn("Cannot add terminal — panes would be too small")
			return null
	_grid.add_child(w)
	_apply_layout()
	_list()
	var body = _find_body(w)
	body.focus_entered.connect(func(): _last_body = body)
	ToastManager.info("Terminal spawned")
	return body

func _split_for(w: Control) -> bool:
	var bi = 0; var ba = 0
	for i in _tiles.size():
		var a = _tiles[i].cspan * _tiles[i].rspan
		if a > ba: ba = a; bi = i
	var s = _tiles[bi]
	var oc = s.col; var or1 = s.row; var os = s.cspan; var ot = s.rspan

	if os >= ot:
		var half = maxi(os / 2, 1)
		if half < MIN_TILE or (os - half) < MIN_TILE: return false
		s.cspan = half
		_tiles.append({wrapper = w, col = oc + half, row = or1, cspan = os - half, rspan = ot})
	else:
		var half = maxi(ot / 2, 1)
		if half < MIN_TILE or (ot - half) < MIN_TILE: return false
		s.rspan = half
		_tiles.append({wrapper = w, col = oc, row = or1 + half, cspan = os, rspan = ot - half})
	return true

func _kill(body: Control):
	if _last_body == body: _last_body = null
	var wi = -1
	for i in _tiles.size():
		if _find_body(_tiles[i].wrapper) == body: wi = i; break
	if wi == -1: return
	var rm = _tiles[wi]
	_tiles.remove_at(wi)

	# Expand tiles to fill the gap. Try exact-match first, then partial.
	if not _expand_exact(rm):
		_expand_partial(rm)

	rm.wrapper.queue_free()
	ToastManager.info("Terminal closed")
	_apply_layout()
	_list()

func _expand_exact(rm: Dictionary) -> bool:
	for t in _tiles:
		if t.row == rm.row and t.rspan == rm.rspan:
			if t.col + t.cspan == rm.col: t.cspan += rm.cspan; return true
			if rm.col + rm.cspan == t.col: t.col = rm.col; t.cspan += rm.cspan; return true
		if t.col == rm.col and t.cspan == rm.cspan:
			if t.row + t.rspan == rm.row: t.rspan += rm.rspan; return true
			if rm.row + rm.rspan == t.row: t.row = rm.row; t.rspan += rm.rspan; return true
	return false

func _expand_partial(rm: Dictionary):
	# Expand ALL tiles that share an edge with rm
	var left = []; var right = []; var up = []; var down = []
	for t in _tiles:
		if t.col + t.cspan == rm.col: left.append(t)
		if rm.col + rm.cspan == t.col: right.append(t)
		if t.row + t.rspan == rm.row: up.append(t)
		if rm.row + rm.rspan == t.row: down.append(t)

	if left.size() > 0 or right.size() > 0:
		var new_right = rm.col + rm.cspan
		for t in left: t.cspan = new_right - t.col
		for t in right: t.col = rm.col; t.cspan = (t.col + t.cspan) - rm.col
		return
	if up.size() > 0 or down.size() > 0:
		var new_bottom = rm.row + rm.rspan
		for t in up: t.rspan = new_bottom - t.row
		for t in down: t.row = rm.row; t.rspan = (t.row + t.rspan) - rm.row
		return
	if _tiles.size() > 0:
		_tiles[0].col = 0; _tiles[0].row = 0
		_tiles[0].cspan = GRID; _tiles[0].rspan = GRID

func _kill_last():
	if _last_body: _kill(_last_body)

func _reset():
	for t in _tiles: t.wrapper.queue_free()
	_tiles.clear()
	_last_body = null
	_apply_layout()
	_list()

# ═══════════════════════════════════════════════════════════════════════
# Terminal wrapper builder
# ═══════════════════════════════════════════════════════════════════════

func _build_wrapper(shell: String, rows: int, cols: int) -> Control:
	var root = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = WRAPPER_BG_COLOR
	sb.border_width_left = 1; sb.border_width_right = 1
	sb.border_width_top = 1; sb.border_width_bottom = 1
	sb.border_color = WRAPPER_BORDER_COLOR
	root.add_theme_stylebox_override("panel", sb)

	var vbox = _make_vbox()
	root.add_child(vbox)

	var lbl = _add_title_bar(vbox, shell, root)

	var term = TerminalPaneScript.new()
	term.name = "Body"
	term.shell_command = shell if shell != "" else DEFAULT_SHELL
	term.rows = rows; term.cols = cols
	term.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	term.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(term)

	# Apply global settings to every new terminal — no caller needs to remember
	_apply_settings_to(term)

	term.title_changed.connect(func(t: String): lbl.text = " " + t)

	return root

func _make_vbox() -> VBoxContainer:
	var v = VBoxContainer.new()
	v.name = "BodyVBox"
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return v

func _add_title_bar(parent: VBoxContainer, shell: String, root: Control) -> Label:
	var bar = Control.new()
	bar.custom_minimum_size = Vector2(0, TITLE_BAR_HEIGHT)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(bar)

	# Background fill
	var tbg = ColorRect.new()
	tbg.color = TITLE_BAR_BG_COLOR
	tbg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(tbg)

	# Centered label (fills bar, text centered both axes)
	var lbl = Label.new()
	lbl.text = " " + (shell.get_file() if shell else "terminal")
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(lbl)

	# Right-aligned buttons
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 2)
	btn_hbox.anchor_left = 1.0; btn_hbox.anchor_right = 1.0
	btn_hbox.anchor_top = 0.0; btn_hbox.anchor_bottom = 1.0
	var btn_total = 2 * BUTTON_MIN_WIDTH + 6
	btn_hbox.offset_left = -btn_total
	btn_hbox.offset_right = -2
	bar.add_child(btn_hbox)

	var min_btn = Button.new()
	min_btn.text = "▼"; min_btn.focus_mode = Control.FOCUS_NONE
	min_btn.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH, BUTTON_MIN_HEIGHT)
	min_btn.pressed.connect(func(): _toggle_minimize(root, min_btn))
	btn_hbox.add_child(min_btn)

	var close_btn = Button.new()
	close_btn.text = "✕"; close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH, BUTTON_MIN_HEIGHT)
	close_btn.pressed.connect(func(): _kill(_find_body(root)))
	btn_hbox.add_child(close_btn)

	return lbl

func _find_body(w: Control) -> Control:
	return w.get_node_or_null("BodyVBox/Body")

func _show_message(msg: String):
	var lbl = Label.new()
	lbl.text = msg
	lbl.add_theme_color_override("font_color", Color.YELLOW)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.position = Vector2(200, size.y - 30)
	add_child(lbl)
	var t = create_tween()
	t.tween_property(lbl, "modulate:a", 0.0, TOAST_DURATION).set_delay(TOAST_DELAY)
	t.tween_callback(lbl.queue_free)

func _toggle_minimize(w: Control, btn: Button):
	var body = _find_body(w)
	if body:
		body.visible = not body.visible
		btn.text = "▼" if body.visible else "▲"

# ═══════════════════════════════════════════════════════════════════════
# Sidebar
# ═══════════════════════════════════════════════════════════════════════

func _build_sidebar():
	_sidebar_bg = _make_sidebar_bg()
	_sidebar = Control.new()
	_sidebar.offset_right = SIDEBAR_WIDTH
	_sidebar.clip_contents = true; _sidebar.anchor_top = 0.0; _sidebar.anchor_bottom = 1.0
	add_child(_sidebar)

	var v = VBoxContainer.new(); v.name = "SidebarContent"
	v.add_theme_constant_override("separation", 4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sidebar.add_child(v)

	_add_sidebar_header(v)
	_add_sidebar_buttons(v)
	_add_pane_list(v)
	_add_collapsed_button()

func _make_sidebar_bg() -> ColorRect:
	var bg = ColorRect.new()
	bg.name = "SidebarBg"; bg.color = SIDEBAR_BG_COLOR
	bg.size = Vector2(SIDEBAR_WIDTH, 0); bg.anchor_top = 0.0; bg.anchor_bottom = 1.0; bg.anchor_right = 0.0
	add_child(bg)
	return bg

func _add_sidebar_header(v: VBoxContainer):
	var h = HBoxContainer.new(); h.name = "Header"
	h.add_theme_constant_override("separation", 0)
	var title = _lbl(" godopty", 16)
	title.name = "SidebarTitle"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title)
	var arrow = Button.new()
	arrow.text = "◀"; arrow.name = "SidebarArrow"
	arrow.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH, BUTTON_MIN_WIDTH)
	arrow.pressed.connect(_toggle_sidebar)
	h.add_child(arrow)
	v.add_child(h)

func _add_sidebar_buttons(v: VBoxContainer):
	for b in [
		["+ Terminal", func(): var p = _spawn(); if p: p.grab_focus()],
		["⚙ Settings", _open_settings],
		["↺ Reset", _reset],
	]:
		var btn = Button.new(); btn.text = b[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(b[1]); v.add_child(btn)

func _add_pane_list(v: VBoxContainer):
	v.add_child(_lbl(" Panes:", 12))
	var sc = ScrollContainer.new(); sc.name = "PaneScroll"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(sc)
	var pl = VBoxContainer.new(); pl.name = "PaneList"
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(pl)

func _add_collapsed_button():
	var btn = Button.new()
	btn.text = "▶"; btn.name = "SidebarCollapsedBtn"
	btn.custom_minimum_size = Vector2(BUTTON_MIN_HEIGHT, BUTTON_MIN_WIDTH)
	btn.offset_left = 1; btn.offset_top = 2
	btn.offset_right = 19; btn.visible = false
	btn.pressed.connect(_toggle_sidebar)
	_sidebar.add_child(btn)

func _lbl(t: String, s: int) -> Label:
	var l = Label.new(); l.text = t; l.add_theme_font_size_override("font_size", s); return l

func _collect_bodies(out: Array[Control]):
	for t in _tiles:
		var body = _find_body(t.wrapper)
		if body: out.append(body)

func _list():
	var pl = _sidebar.get_node_or_null("SidebarContent/PaneScroll/PaneList")
	if pl == null: return
	for c in pl.get_children(): c.queue_free()
	for i in _tiles.size():
		var body = _find_body(_tiles[i].wrapper)
		var row = HBoxContainer.new()
		var btn = Button.new(); btn.text = "T%d" % (i + 1)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(b = body): b.grab_focus())
		row.add_child(btn)
		var x = Button.new(); x.text = "✕"; x.flat = true
		x.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH, 0)
		x.pressed.connect(func(b = body): _kill(b))
		row.add_child(x)
		pl.add_child(row)

func _toggle_sidebar():
	_sidebar_on = not _sidebar_on
	var content = _sidebar.get_node_or_null("SidebarContent")
	var title = _sidebar.get_node_or_null("SidebarContent/Header/SidebarTitle")
	var a = _sidebar.get_node_or_null("SidebarArrow")
	var coll = _sidebar.get_node_or_null("SidebarCollapsedBtn")
	if _sidebar_on:
		_sidebar.offset_right = SIDEBAR_WIDTH; _sidebar_bg.size.x = SIDEBAR_WIDTH
		if content: content.show()
		if title: title.visible = true
		if a: a.visible = true
		if coll: coll.visible = false
	else:
		_sidebar.offset_right = SIDEBAR_COLLAPSED_WIDTH; _sidebar_bg.size.x = SIDEBAR_COLLAPSED_WIDTH
		if content: content.hide()
		if title: title.visible = false
		if a: a.visible = false
		if coll: coll.visible = true
	_apply_layout()

# ═══════════════════════════════════════════════════════════════════════
# Serialization
# ═══════════════════════════════════════════════════════════════════════

func _save():
	var arr = []
	for t in _tiles:
		var body = _find_body(t.wrapper)
		var d = {col = t.col, row = t.row, cspan = t.cspan, rspan = t.rspan,
			shell = DEFAULT_SHELL, rows = DEFAULT_ROWS, cols = DEFAULT_COLS}
		if body.has_method("_get_layout_state"):
			var s = body._get_layout_state()
			if s is Dictionary: d.merge(s)
		arr.append(d)
	var f = FileAccess.open(LAYOUT_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"tiles": arr}, "\t"))
		ToastManager.info("Layout saved")

func _restore():
	if not FileAccess.file_exists(LAYOUT_FILE): return
	var f = FileAccess.open(LAYOUT_FILE, FileAccess.READ)
	if not f: return
	var j = JSON.new()
	if j.parse(f.get_as_text()) != OK: return
	var d = j.get_data()
	if not (d is Dictionary and d.has("tiles")): return
	for t in _tiles: t.wrapper.queue_free()
	_tiles.clear()
	for td in d.tiles:
		if not (td is Dictionary): continue
		var sh = td.get("shell", DEFAULT_SHELL)
		if sh == null or sh == "": sh = DEFAULT_SHELL
		var w = _build_wrapper(sh, td.get("rows", DEFAULT_ROWS), td.get("cols", DEFAULT_COLS))
		_grid.add_child(w)
		var body = _find_body(w)
		body.focus_entered.connect(func(b = body): _last_body = b)
		_tiles.append({wrapper = w, col = td.get("col", 0), row = td.get("row", 0),
			cspan = td.get("cspan", GRID), rspan = td.get("rspan", GRID)})
	_apply_layout(); _list()

func _load_settings():
	if not FileAccess.file_exists(SETTINGS_FILE): return
	var f = FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if not f: return
	var j = JSON.new()
	if j.parse(f.get_as_text()) == OK and j.get_data() is Dictionary:
		var d: Dictionary = j.get_data()
		_cfg_cursor_shape = d.get("cursor_shape", 0)
		_cfg_cursor_blink = d.get("cursor_blink", true)
		_cfg_cursor_blink_speed = d.get("cursor_blink_speed", 0.5)
		_cfg_scroll_lines = d.get("scroll_lines", 3)
		_cfg_default_rows = d.get("default_rows", 24)
		_cfg_default_cols = d.get("default_cols", 80)
		_cfg_beam_width = d.get("beam_width", 2)
		_cfg_underline_height = d.get("underline_height", 3)
		_cfg_wrapper_bg = _color_from_hex(d.get("wrapper_bg", ""), WRAPPER_BG_COLOR)
		_cfg_title_bar_bg = _color_from_hex(d.get("title_bar_bg", ""), TITLE_BAR_BG_COLOR)
		_cfg_wrapper_border = _color_from_hex(d.get("wrapper_border", ""), WRAPPER_BORDER_COLOR)
		_cfg_sidebar_bg = _color_from_hex(d.get("sidebar_bg", ""), SIDEBAR_BG_COLOR)
		_cfg_focus_border = _color_from_hex(d.get("focus_border", ""), TerminalPane.FOCUS_BORDER_COLOR)
		_cfg_selection = _color_from_hex(d.get("selection", ""), TerminalPane.SELECTION_COLOR)
		_cfg_scrollback_indicator = _color_from_hex(d.get("scrollback_indicator", ""), TerminalPane.SCROLLBACK_INDICATOR_COLOR)
		_cfg_font_path = d.get("font_path", "res://fonts/DejaVuSansMono.ttf")
		_cfg_font_size = d.get("font_size", 14)

func _save_settings():
	var d = {"cursor_shape": _cfg_cursor_shape, "cursor_blink": _cfg_cursor_blink, "cursor_blink_speed": _cfg_cursor_blink_speed, "scroll_lines": _cfg_scroll_lines, "default_rows": _cfg_default_rows, "default_cols": _cfg_default_cols, "beam_width": _cfg_beam_width, "underline_height": _cfg_underline_height, "wrapper_bg": _cfg_wrapper_bg.to_html(), "title_bar_bg": _cfg_title_bar_bg.to_html(), "wrapper_border": _cfg_wrapper_border.to_html(), "sidebar_bg": _cfg_sidebar_bg.to_html(), "focus_border": _cfg_focus_border.to_html(), "selection": _cfg_selection.to_html(), "scrollback_indicator": _cfg_scrollback_indicator.to_html(), "font_path": _cfg_font_path, "font_size": _cfg_font_size}
	var f = FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

func _color_from_hex(hex: String, fallback: Color) -> Color:
	if hex == "": return fallback
	return Color.from_string(hex, fallback)

func _apply_settings_to(body: Control):
	body.cursor_shape = _cfg_cursor_shape
	body.cursor_blink = _cfg_cursor_blink
	body.cursor_blink_speed = _cfg_cursor_blink_speed
	body.scroll_lines = _cfg_scroll_lines
	body.rows = _cfg_default_rows
	body.cols = _cfg_default_cols
	body.beam_cursor_width = _cfg_beam_width
	body.underline_cursor_height = _cfg_underline_height
	body.focus_border_color = _cfg_focus_border
	body.selection_color = _cfg_selection
	body.scrollback_indicator_color = _cfg_scrollback_indicator
	body.font_path = _cfg_font_path
	body.font_size = _cfg_font_size

# ═══════════════════════════════════════════════════════════════════════
# Settings panel
# ═══════════════════════════════════════════════════════════════════════

var _settings_panel: Control = null
var _settings_debounce_timer: Timer = null

func _open_settings():
	if _settings_panel == null:
		_settings_panel = _build_settings()
		add_child(_settings_panel)
	_settings_panel.visible = true

func _build_settings() -> Control:
	var bg = Panel.new()
	bg.size = Vector2(SETTINGS_PANEL_W, SETTINGS_PANEL_H)
	bg.position = (size - bg.size) * 0.5

	var v = VBoxContainer.new(); v.name = "VBox"
	v.add_theme_constant_override("separation", 6)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(v)

	_add_settings_header(v)
	var shape_opt = _add_cursor_control(v)
	var blink_cb = _add_blink_control(v)
	var blink_spin = _add_blink_speed_control(v)
	var fs_spin = _add_font_control(v)
	var scroll_spin = _add_scroll_control(v)
	var dims = _add_dims_control(v)
	var cursor_px = _add_cursor_thickness_control(v)
	_add_font_picker(v)
	var color_btns = _add_color_section(v)

	# Debounce timer — defers the apply so rapid changes (e.g. SpinBox drag)
	# only trigger one save + propagate cycle.
	_settings_debounce_timer = Timer.new()
	_settings_debounce_timer.name = "DebounceTimer"
	_settings_debounce_timer.one_shot = true
	_settings_debounce_timer.wait_time = SETTINGS_DEBOUNCE
	_settings_debounce_timer.timeout.connect(func():
		_apply_current_settings(shape_opt.selected, blink_cb.button_pressed, int(fs_spin.value), blink_spin.value, int(scroll_spin.value), int(dims[0].value), int(dims[1].value), int(cursor_px[0].value), int(cursor_px[1].value)))
	bg.add_child(_settings_debounce_timer)

	# Wire controls to debounced apply
	shape_opt.item_selected.connect(func(_idx): _settings_debounce_timer.start())
	blink_cb.toggled.connect(func(_pressed): _settings_debounce_timer.start())
	blink_spin.value_changed.connect(func(_v): _settings_debounce_timer.start())
	fs_spin.value_changed.connect(func(_v): _settings_debounce_timer.start())
	scroll_spin.value_changed.connect(func(_v): _settings_debounce_timer.start())

	# Reset
	_add_reset_button(v, shape_opt, blink_cb, blink_spin, scroll_spin, dims, cursor_px, color_btns, fs_spin)

	return bg

func _add_settings_header(v: VBoxContainer):
	var h = HBoxContainer.new()
	var t = Label.new(); t.text = "Global Settings"; t.add_theme_font_size_override("font_size", 18)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(t)
	var x = Button.new(); x.text = "X"; x.flat = true
	x.pressed.connect(func(): _settings_panel.visible = false); h.add_child(x)
	v.add_child(h)

func _add_cursor_control(v: VBoxContainer) -> OptionButton:
	var hs = HBoxContainer.new()
	hs.add_child(_lbl("Cursor:", 13))
	var opt = OptionButton.new(); opt.name = "ShapeOpt"
	opt.add_item("Block"); opt.add_item("Underline"); opt.add_item("Beam")
	opt.selected = _cfg_cursor_shape
	hs.add_child(opt)
	v.add_child(hs)
	return opt

func _add_blink_control(v: VBoxContainer) -> CheckBox:
	var cb = CheckBox.new(); cb.name = "BlinkCb"; cb.text = " Cursor blink"
	cb.button_pressed = _cfg_cursor_blink
	v.add_child(cb)
	return cb

func _add_blink_speed_control(v: VBoxContainer) -> SpinBox:
	var hb = HBoxContainer.new()
	hb.add_child(_lbl("Blink speed:", 13))
	var spin = SpinBox.new(); spin.name = "BlinkSpeedSpin"
	spin.min_value = 0.1; spin.max_value = 2.0; spin.step = 0.1
	spin.value = _cfg_cursor_blink_speed
	hb.add_child(spin)
	v.add_child(hb)
	return spin

func _add_font_control(v: VBoxContainer) -> SpinBox:
	var hf = HBoxContainer.new()
	hf.add_child(_lbl("Font size:", 13))
	var spin = SpinBox.new(); spin.name = "FontSpin"
	spin.min_value = MIN_FONT_SIZE; spin.max_value = MAX_FONT_SIZE
	spin.value = _cfg_font_size
	hf.add_child(spin)
	v.add_child(hf)
	return spin

func _add_scroll_control(v: VBoxContainer) -> SpinBox:
	var hs = HBoxContainer.new()
	hs.add_child(_lbl("Scroll lines:", 13))
	var spin = SpinBox.new(); spin.name = "ScrollSpin"
	spin.min_value = 1; spin.max_value = 10; spin.step = 1
	spin.value = _cfg_scroll_lines
	hs.add_child(spin)
	v.add_child(hs)
	return spin

func _add_dims_control(v: VBoxContainer) -> Array:
	var hr = HBoxContainer.new()
	hr.add_child(_lbl("Default size:", 13))
	var rspin = SpinBox.new()
	rspin.min_value = 10; rspin.max_value = 100
	rspin.value = _cfg_default_rows
	hr.add_child(rspin)
	hr.add_child(_lbl("×", 13))
	var cspin = SpinBox.new()
	cspin.min_value = 40; cspin.max_value = 200
	cspin.value = _cfg_default_cols
	hr.add_child(cspin)
	v.add_child(hr)
	return [rspin, cspin]

func _add_color_control(v: VBoxContainer, label: String, value: Color, setter: Callable) -> ColorPickerButton:
	var h = HBoxContainer.new()
	h.add_child(_lbl(label, 12))
	var btn = ColorPickerButton.new()
	btn.color = value
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.color_changed.connect(setter)
	h.add_child(btn)
	v.add_child(h)
	return btn

# Opens a FileDialog and invokes on_selected with the chosen path.
# Reusable for font, color-scheme, shell-path, etc.
func _add_file_picker(v: VBoxContainer, label: String, current_path: String, filters: Array, on_selected: Callable) -> void:
	var h = HBoxContainer.new()
	h.add_child(_lbl(label, 13))
	var btn = Button.new()
	btn.text = current_path.get_file()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func():
		var dlg = FileDialog.new()
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dlg.current_path = current_path
		for f in filters: dlg.add_filter(f[0], f[1])
		dlg.file_selected.connect(func(path: String):
			btn.text = path.get_file()
			on_selected.call(path)
			dlg.queue_free())
		dlg.canceled.connect(dlg.queue_free)
		add_child(dlg)
		dlg.popup_centered())
	h.add_child(btn)
	v.add_child(h)

func _add_font_picker(v: VBoxContainer):
	_add_file_picker(v, "Font:", _cfg_font_path, [["*.ttf", "TrueType Fonts"]], func(path: String):
		_cfg_font_path = path
		var all2: Array[Control] = []; _collect_bodies(all2)
		for body in all2: body.font_path = path
		_save_settings())

func _add_color_section(v: VBoxContainer) -> Array:
	v.add_child(_lbl("UI Colors:", 13))
	var btns = []
	for item in [
		["Wrapper bg", _cfg_wrapper_bg, func(c: Color): _cfg_wrapper_bg = c; _settings_debounce_timer.start()],
		["Title bar", _cfg_title_bar_bg, func(c: Color): _cfg_title_bar_bg = c; _settings_debounce_timer.start()],
		["Border", _cfg_wrapper_border, func(c: Color): _cfg_wrapper_border = c; _settings_debounce_timer.start()],
		["Sidebar", _cfg_sidebar_bg, func(c: Color): _cfg_sidebar_bg = c; _settings_debounce_timer.start()],
		["Focus", _cfg_focus_border, func(c: Color): _cfg_focus_border = c; _settings_debounce_timer.start()],
		["Selection", _cfg_selection, func(c: Color): _cfg_selection = c; _settings_debounce_timer.start()],
		["Scroll", _cfg_scrollback_indicator, func(c: Color): _cfg_scrollback_indicator = c; _settings_debounce_timer.start()],
	]:
		var b = _add_color_control(v, item[0], item[1], item[2])
		btns.append([item[0], b])
	return btns

func _add_cursor_thickness_control(v: VBoxContainer) -> Array:
	var hc = HBoxContainer.new()
	hc.add_child(_lbl("Cursor px:", 13))
	var bspin = SpinBox.new()
	bspin.min_value = 1; bspin.max_value = 8
	bspin.value = _cfg_beam_width
	hc.add_child(bspin)
	hc.add_child(_lbl("beam", 11))
	var uspin = SpinBox.new()
	uspin.min_value = 1; uspin.max_value = 8
	uspin.value = _cfg_underline_height
	hc.add_child(uspin)
	hc.add_child(_lbl("underline", 11))
	v.add_child(hc)
	return [bspin, uspin]

func _reset_colors(btns: Array):
	var defaults = [WRAPPER_BG_COLOR, TITLE_BAR_BG_COLOR, WRAPPER_BORDER_COLOR, SIDEBAR_BG_COLOR, TerminalPane.FOCUS_BORDER_COLOR, TerminalPane.SELECTION_COLOR, TerminalPane.SCROLLBACK_INDICATOR_COLOR]
	for i in btns.size():
		if btns[i] is Array:
			(btns[i][1] as ColorPickerButton).color = defaults[i]
		else:
			(btns[i] as ColorPickerButton).color = defaults[i]

func _add_reset_button(v: VBoxContainer, shape_opt: OptionButton, blink_cb: CheckBox, blink_spin: SpinBox, scroll_spin: SpinBox, dims: Array, cursor_px: Array, color_btns: Array, fs_spin: SpinBox):
	var btn = Button.new(); btn.text = "Reset to defaults"
	btn.pressed.connect(func():
		_cfg_cursor_shape = 0
		_cfg_cursor_blink = true
		_cfg_cursor_blink_speed = 0.5
		_cfg_scroll_lines = 3
		_cfg_default_rows = 24
		_cfg_default_cols = 80
		_cfg_beam_width = 2
		_cfg_underline_height = 3
		_cfg_wrapper_bg = WRAPPER_BG_COLOR
		_cfg_title_bar_bg = TITLE_BAR_BG_COLOR
		_cfg_wrapper_border = WRAPPER_BORDER_COLOR
		_cfg_sidebar_bg = SIDEBAR_BG_COLOR
		_cfg_focus_border = TerminalPane.FOCUS_BORDER_COLOR
		_cfg_selection = TerminalPane.SELECTION_COLOR
		_cfg_scrollback_indicator = TerminalPane.SCROLLBACK_INDICATOR_COLOR
		_cfg_font_path = "res://fonts/DejaVuSansMono.ttf"
		_cfg_font_size = 14
		_save_settings()
		shape_opt.selected = 0
		blink_cb.button_pressed = true
		blink_spin.value = 0.5
		scroll_spin.value = 3
		dims[0].value = 24
		dims[1].value = 80
		cursor_px[0].value = 2
		cursor_px[1].value = 3
		_reset_colors(color_btns)
		fs_spin.value = 14
		var all2: Array[Control] = []; _collect_bodies(all2)
		for body in all2: _apply_settings_to(body))
	v.add_child(btn)

func _apply_current_settings(cursor_shape: int, cursor_blink: bool, font_size: int, blink_speed: float, scroll_lines: int, default_rows: int, default_cols: int, beam_width: int, underline_height: int):
	_cfg_cursor_shape = cursor_shape
	_cfg_cursor_blink = cursor_blink
	_cfg_cursor_blink_speed = blink_speed
	_cfg_scroll_lines = scroll_lines
	_cfg_default_rows = default_rows
	_cfg_default_cols = default_cols
	_cfg_beam_width = beam_width
	_cfg_underline_height = underline_height
	_cfg_font_size = font_size
	_save_settings()
	var all2: Array[Control] = []; _collect_bodies(all2)
	for body in all2: _apply_settings_to(body)

# ═══════════════════════════════════════════════════════════════════════
# Keyboard & palette
# ═══════════════════════════════════════════════════════════════════════

func _input(event):
	if not (event is InputEventKey and event.pressed): return
	if event.keycode == KEY_ESCAPE:
		if _settings_panel and _settings_panel.visible:
			_settings_panel.visible = false; accept_event(); return
		if _palette and _palette.visible:
			_palette.visible = false; accept_event(); return
	if event.keycode == KEY_R and event.ctrl_pressed and event.shift_pressed:
		_sidebar_on = true; _sidebar.show(); _sidebar_bg.show()
		_reset(); _apply_layout(); _list()
		return
	if event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
		match event.keycode:
			KEY_N: var p = _spawn(); if p: p.grab_focus(); accept_event()
			KEY_W: _kill_last(); accept_event()
			KEY_B: _toggle_sidebar(); accept_event()
			KEY_P: _toggle_palette(); accept_event()

func _toggle_palette():
	if _palette == null:
		_palette = _build_palette()
		add_child(_palette)
	_palette.visible = not _palette.visible
	if _palette.visible:
		var inp = _palette.find_child("*", true, false) as LineEdit
		if inp: inp.grab_focus()

func _build_palette() -> Control:
	var bg = Panel.new(); bg.size = Vector2(PALETTE_PANEL_W, PALETTE_PANEL_H); bg.position = (size - bg.size) * 0.5
	var v = VBoxContainer.new(); v.name = "PaletteVBox"; bg.add_child(v)
	var inp = LineEdit.new(); inp.placeholder_text = "Command..."; v.add_child(inp)
	var lst = ItemList.new(); lst.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(lst)
	for c in PALETTE_COMMANDS: lst.add_item(c)
	inp.text_changed.connect(func(t: String):
		lst.clear(); for c in PALETTE_COMMANDS:
			if t == "" or c.find(t) != -1: lst.add_item(c))
	inp.text_submitted.connect(func(t: String): _run(t); _palette.visible = false)
	lst.item_activated.connect(func(i: int): _run(lst.get_item_text(i)); _palette.visible = false)

	return bg

func _run(c: String):
	match c:
		"new terminal": var p = _spawn(); if p: p.grab_focus()
		"close active": _kill_last()
		"settings": _open_settings()
		"reset layout": _reset()
		"save": _save();
		"load": _restore()
		_: if "new" in c: var p = _spawn(); if p: p.grab_focus()
		elif "close" in c: _kill_last()
		elif "reset" in c: _reset()
		elif "save" in c: _save()
		elif "load" in c: _restore()
