extends Control
class_name Workspace
# godopty Workspace — tiling grid of terminal panes with title bars.

const LAYOUT_FILE = "user://layout.json"
const DEFAULT_SHELL = "/bin/bash"
const GRID = 12
const MIN_TILE = 2

# Layout
const TITLE_BAR_HEIGHT = 26
const BUTTON_MIN_WIDTH = 22
const BUTTON_MIN_HEIGHT = 18

const MIN_WINDOW_W = 500
const MIN_WINDOW_H = 300

# Content
const PALETTE_COMMANDS = ["new terminal", "close active", "settings", "reset layout", "save", "load"]

const TerminalPaneScript = preload("res://scenes/terminal_pane.gd")

var _sidebar: Sidebar
var _sidebar_bg: ColorRect
var _palette: Control
var _grid: Control
var _last_body: Control
var _tiles: Array[Dictionary] = []  # [{wrapper, col, row, cspan, rspan}]
var _settings_panel: SettingsPanel

func _ready():
	show()
	DisplayServer.window_set_min_size(Vector2i(MIN_WINDOW_W, MIN_WINDOW_H))

	_grid = Control.new()
	add_child(_grid)
	
	var overlay = load("res://scenes/toast_overlay.gd").new()
	add_child(overlay)
	
	_build_sidebar()
	_apply_layout()

	if FileAccess.file_exists(LAYOUT_FILE): _restore()

	ShortcutManager.register("app:new_pane", "Ctrl+Shift+N", func(): var p = _spawn(); if p: p.grab_focus())
	ShortcutManager.register("app:close_pane", "Ctrl+Shift+W", _kill_last)
	ShortcutManager.register("app:toggle_sidebar", "Ctrl+Shift+B", _toggle_sidebar)
	ShortcutManager.register("app:toggle_palette", "Ctrl+Shift+P", _toggle_palette)
	ShortcutManager.register("app:toggle_fps", "Ctrl+Shift+F", _toggle_fps)
	ShortcutManager.register("app:reset_workspace", "Ctrl+Shift+R", func():
		_reset(); _apply_layout(); _list()
	)

	SettingsManager.settings_changed.connect(_on_settings_changed)
	_on_settings_changed()

func _on_settings_changed():
	var all_bodies: Array[Control] = []
	for t in _tiles:
		var body = _find_body(t.wrapper)
		if body: all_bodies.append(body)
	for body in all_bodies:
		SettingsManager.apply_to_terminal(body)
	_apply_fps_setting()

func _apply_fps_setting():
	if SettingsManager.cfg_max_fps == -1:
		var rr = DisplayServer.screen_get_refresh_rate()
		Engine.max_fps = int(rr) if rr > 0 else 0
	else:
		Engine.max_fps = SettingsManager.cfg_max_fps

func _notification(what):
	if what == NOTIFICATION_RESIZED: _apply_layout()
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _save()

# ═══════════════════════════════════════════════════════════════════════
# Layout
# ═══════════════════════════════════════════════════════════════════════

func _apply_layout():
	if _grid == null: return
	var m = _sidebar.offset_right if _sidebar else 180
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
	var w = _build_wrapper(shell, SettingsManager.cfg_default_rows, SettingsManager.cfg_default_cols)
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
	sb.bg_color = SettingsManager.cfg_wrapper_bg
	sb.border_width_left = 1; sb.border_width_right = 1
	sb.border_width_top = 1; sb.border_width_bottom = 1
	sb.border_color = SettingsManager.cfg_wrapper_border
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

	SettingsManager.apply_to_terminal(term)
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

	var tbg = ColorRect.new()
	tbg.color = SettingsManager.cfg_title_bar_bg
	tbg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(tbg)

	var lbl = Label.new()
	lbl.text = " " + (shell.get_file() if shell else "terminal")
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(lbl)

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

func _toggle_minimize(w: Control, btn: Button):
	var body = _find_body(w)
	if body:
		body.visible = not body.visible
		btn.text = "▼" if body.visible else "▲"

# ═══════════════════════════════════════════════════════════════════════
# Sidebar
# ═══════════════════════════════════════════════════════════════════════

func _build_sidebar():
	var SidebarScript = load("res://scenes/sidebar.gd")
	_sidebar_bg = ColorRect.new()
	_sidebar_bg.color = SettingsManager.cfg_sidebar_bg
	_sidebar_bg.size = Vector2(180, 0)
	_sidebar_bg.anchor_top = 0.0; _sidebar_bg.anchor_bottom = 1.0; _sidebar_bg.anchor_right = 0.0
	add_child(_sidebar_bg)
	
	_sidebar = SidebarScript.new()
	_sidebar.offset_right = 180
	add_child(_sidebar)
	_sidebar.build(_sidebar_bg)
	_sidebar.request_new_pane.connect(func(): var p = _spawn(); if p: p.grab_focus())
	_sidebar.request_close_last.connect(_kill_last)
	_sidebar.request_close.connect(_kill)
	_sidebar.request_settings.connect(_open_settings)
	_sidebar.request_reset.connect(_reset)
	_sidebar.request_focus.connect(func(body): body.grab_focus())
	_sidebar.toggled.connect(_apply_layout)
	
	SettingsManager.settings_changed.connect(func():
		_sidebar_bg.color = SettingsManager.cfg_sidebar_bg
	)

func _process(_delta):
	if Engine.get_process_frames() % 6 == 0:
		var fps = Engine.get_frames_per_second()
		if _last_body and _last_body.get_script() == TerminalPaneScript:
			_sidebar.update_fps(fps, _last_body._fetch_ms, _last_body._draw_ms)
		else:
			_sidebar.update_fps(fps)

func _list():
	var panes_nodes = get_tree().get_nodes_in_group("panes")
	var panes = []
	for n in panes_nodes: if n is Control: panes.append(n)
	_sidebar.update_pane_list(panes)

func _toggle_sidebar():
	_sidebar._toggle_sidebar()

# ═══════════════════════════════════════════════════════════════════════
# Settings
# ═══════════════════════════════════════════════════════════════════════

func _open_settings():
	if _settings_panel == null:
		var SettingsPanelScript = load("res://scenes/settings_panel.gd")
		_settings_panel = SettingsPanelScript.new(self)
		add_child(_settings_panel)
	_settings_panel.visible = true

# ═══════════════════════════════════════════════════════════════════════
# Serialization
# ═══════════════════════════════════════════════════════════════════════

func _save():
	var arr = []
	for t in _tiles:
		var body = _find_body(t.wrapper)
		var d = {col = t.col, row = t.row, cspan = t.cspan, rspan = t.rspan,
			shell = DEFAULT_SHELL, rows = SettingsManager.cfg_default_rows, cols = SettingsManager.cfg_default_cols}
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
		var w = _build_wrapper(sh, td.get("rows", SettingsManager.cfg_default_rows), td.get("cols", SettingsManager.cfg_default_cols))
		_grid.add_child(w)
		var body = _find_body(w)
		body.focus_entered.connect(func(): _last_body = body)
		_tiles.append({wrapper = w, col = td.get("col", 0), row = td.get("row", 0),
			cspan = td.get("cspan", GRID), rspan = td.get("rspan", GRID)})
	_apply_layout(); _list()

# ═══════════════════════════════════════════════════════════════════════
# Palette
# ═══════════════════════════════════════════════════════════════════════

func _unhandled_input(event):
	if _palette and _palette.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_palette.visible = false
		get_viewport().set_input_as_handled()

func _toggle_palette():
	if _palette == null:
		_palette = _build_palette()
		add_child(_palette)
	_palette.visible = not _palette.visible
	if _palette.visible:
		var inp = _palette.find_child("*", true, false) as LineEdit
		if inp: inp.grab_focus()

func _toggle_fps():
	pass # fps label is inside sidebar now

func _build_palette() -> Control:
	var bg = Panel.new(); bg.custom_minimum_size = Vector2(350, 240); bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
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
