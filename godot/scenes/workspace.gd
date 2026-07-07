extends Control
# godopty Workspace — tiling grid of terminal panes with title bars.

const LAYOUT_FILE = "user://layout.json"
const DEFAULT_SHELL = "/bin/bash"
const GRID = 12  # virtual grid size
const MIN_TILE = 2  # minimum tile size in grid cells (each dimension)

var _sidebar: Control
var _sidebar_on := true
var _palette: Control
var _grid: Control
var _last_body: Control
var _tiles: Array = []  # [{wrapper, col, row, cspan, rspan}]

func _ready():
	show()  # safety: always visible regardless of scene file state
	print("[Workspace] _ready() starting")
	DisplayServer.window_set_min_size(Vector2i(500, 300))

	_grid = Control.new()
	_grid.add_theme_color_override("panel", Color(0.05, 0.05, 0.05))
	add_child(_grid)
	print("[Workspace] grid added")

	_build_sidebar()
	print("[Workspace] sidebar built, visible=", _sidebar.visible, " on=", _sidebar_on)
	_sidebar.show()
	_apply_layout()
	print("[Workspace] layout applied, grid size=", _grid.size)

	if FileAccess.file_exists(LAYOUT_FILE):
		print("[Workspace] layout file exists, restoring...")
		_restore()
	else:
		print("[Workspace] no layout file, blank canvas")

	print("[Workspace] _ready() done, tiles=", _tiles.size(), " sidebar_visible=", _sidebar.visible)

# ═══════════════════════════════════════════════════════════════════════
# Layout engine
# ═══════════════════════════════════════════════════════════════════════

func _notification(what):
	if what == NOTIFICATION_RESIZED: _apply_layout()
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _save()

func _apply_layout():
	if _grid == null: return
	# Grid fills space right of sidebar
	var m = 180 if _sidebar_on else 0
	_grid.offset_left = m
	_grid.offset_right = 0
	_grid.offset_top = 0
	_grid.offset_bottom = 0
	_grid.anchor_left = 0.0
	_grid.anchor_right = 1.0
	_grid.anchor_top = 0.0
	_grid.anchor_bottom = 1.0

	# Position every tile
	var cw = maxf(_grid.size.x, 1.0) / GRID
	var ch = maxf(_grid.size.y, 1.0) / GRID
	print("[layout] grid=", _grid.size, " cell=", cw, "x", ch, " tiles=", _tiles.size())
	for t in _tiles:
		var x = t.col * cw; var y = t.row * ch
		var w = t.cspan * cw; var h = t.rspan * ch
		t.wrapper.offset_left = x; t.wrapper.offset_top = y
		t.wrapper.offset_right = x + w; t.wrapper.offset_bottom = y + h
		t.wrapper.anchor_left = 0.0; t.wrapper.anchor_right = 0.0
		t.wrapper.anchor_top = 0.0; t.wrapper.anchor_bottom = 0.0
		print("  tile cspan=", t.cspan, " rspan=", t.rspan, " calc=", w, "x", h, " actual=", t.wrapper.size)


# ═══════════════════════════════════════════════════════════════════════
# Tile operations
# ═══════════════════════════════════════════════════════════════════════

func _spawn(shell := DEFAULT_SHELL, rows := 24, cols := 80) -> Control:
	var w = _build_wrapper(shell, rows, cols)
	if _tiles.is_empty():
		_tiles.append({wrapper = w, col = 0, row = 0, cspan = GRID, rspan = GRID})
	else:
		if not _split_for(w):
			w.queue_free()
			_show_message("Cannot add terminal — panes would be too small")
			return null
	_grid.add_child(w)
	_apply_layout()
	_list()
	var body = _find_body(w)
	body.focus_entered.connect(func(): _last_body = body)
	return body  # caller calls grab_focus()

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

	# Expand first adjacent tile into the gap
	for t in _tiles:
		if t.row == rm.row and t.rspan == rm.rspan:
			if t.col + t.cspan == rm.col: t.cspan += rm.cspan; break
			if rm.col + rm.cspan == t.col: t.col = rm.col; t.cspan += rm.cspan; break
		if t.col == rm.col and t.cspan == rm.cspan:
			if t.row + t.rspan == rm.row: t.rspan += rm.rspan; break
			if rm.row + rm.rspan == t.row: t.row = rm.row; t.rspan += rm.rspan; break

	rm.wrapper.queue_free()
	_apply_layout()
	_list()

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
	# PanelContainer draws the border; VBoxContainer stacks children
	var root = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	sb.border_width_left = 1; sb.border_width_right = 1
	sb.border_width_top = 1; sb.border_width_bottom = 1
	sb.border_color = Color(0.25, 0.25, 0.25, 0.6)
	root.add_theme_stylebox_override("panel", sb)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(vbox)

	# Title bar — simple HBox with background
	var bar = Panel.new()
	bar.custom_minimum_size = Vector2(0, 22)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	bar.add_child(hbox)
	vbox.add_child(bar)

	var lbl = Label.new()
	lbl.text = " " + (shell.get_file() if shell else "terminal")
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)

	# Buttons — flat style, no nesting
	for item in [
		["_", func(): _toggle_minimize(root)],
		["✕", func(): _kill(_find_body(root))],
	]:
		var btn = Button.new()
		btn.text = item[0]
		btn.flat = true
		btn.custom_minimum_size = Vector2(22, 18)
		btn.pressed.connect(item[1])
		hbox.add_child(btn)

	# Terminal body
	var term = load("res://scenes/terminal_pane.gd").new()
	term.name = "Body"
	term.shell_command = shell if shell != "" else DEFAULT_SHELL
	term.rows = rows; term.cols = cols
	term.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	term.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(term)

	return root

func _find_body(w: Control) -> Control:
	for ch in w.get_children():
		if ch.name == "Body": return ch
		var f = _find_body(ch); if f: return f
	return null

func _show_message(msg: String):
	var lbl = Label.new()
	lbl.text = msg
	lbl.add_theme_color_override("font_color", Color.YELLOW)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.position = Vector2(200, size.y - 30)
	add_child(lbl)
	var t = create_tween()
	t.tween_property(lbl, "modulate:a", 0.0, 2.0).set_delay(1.5)
	t.tween_callback(lbl.queue_free)

func _toggle_minimize(w: Control):
	var body = _find_body(w)
	if body: body.visible = not body.visible

# ═══════════════════════════════════════════════════════════════════════
# Sidebar
# ═══════════════════════════════════════════════════════════════════════

func _build_sidebar():
	# ColorRect as visible sidebar background — impossible to miss
	var bg = ColorRect.new()
	bg.name = "SidebarBg"
	bg.color = Color(0.12, 0.12, 0.15, 1.0)
	bg.size = Vector2(180, 0)
	bg.anchor_top = 0.0; bg.anchor_bottom = 1.0
	bg.anchor_right = 0.0
	add_child(bg)

	# VBoxContainer for content, overlaid on the ColorRect
	_sidebar = Control.new()
	_sidebar.offset_right = 180
	_sidebar.anchor_top = 0.0; _sidebar.anchor_bottom = 1.0
	add_child(_sidebar)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sidebar.add_child(v)

	v.add_child(_lbl(" godopty", 16))

	for b in [
		["+ Terminal", func(): var p = _spawn(); if p: p.grab_focus()],
		["✕ Close Active", _kill_last],
		["↺ Reset", _reset],
	]:
		var btn = Button.new(); btn.text = b[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(b[1]); v.add_child(btn)

	v.add_child(_lbl(" Panes:", 12))
	var sc = ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var pl = VBoxContainer.new(); pl.name = "PaneList"
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(pl)

	var sp = Control.new(); sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)

	for b in [["Save", _save], ["Load", _restore]]:
		var btn = Button.new(); btn.text = b[0]; btn.pressed.connect(b[1]); v.add_child(btn)

func _lbl(t: String, s: int) -> Label:
	var l = Label.new(); l.text = t; l.add_theme_font_size_override("font_size", s); return l

func _list():
	var pl = _sidebar.get_node_or_null("VBoxContainer/ScrollContainer/PaneList")
	if pl == null: return
	for c in pl.get_children(): c.queue_free()
	for i in _tiles.size():
		var body = _find_body(_tiles[i].wrapper)
		var row = HBoxContainer.new()
		var btn = Button.new(); btn.text = "T%d" % (i + 1)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(): body.grab_focus())
		row.add_child(btn)
		var x = Button.new(); x.text = "✕"; x.flat = true
		x.custom_minimum_size = Vector2(22, 0)
		x.pressed.connect(func(): _kill(body))
		row.add_child(x)
		pl.add_child(row)

func _toggle_sidebar():
	_sidebar_on = not _sidebar_on
	if _sidebar_on:
		_sidebar.show()
		var bg = get_node_or_null("SidebarBg"); if bg: bg.show()
	else:
		_sidebar.hide()
		var bg = get_node_or_null("SidebarBg"); if bg: bg.hide()
	_apply_layout()

# ═══════════════════════════════════════════════════════════════════════
# Serialization
# ═══════════════════════════════════════════════════════════════════════

func _save():
	var arr = []
	for t in _tiles:
		var body = _find_body(t.wrapper)
		var d = {col = t.col, row = t.row, cspan = t.cspan, rspan = t.rspan,
			shell = DEFAULT_SHELL, rows = 24, cols = 80}
		if body.has_method("_get_layout_state"):
			var s = body._get_layout_state()
			if s is Dictionary: d.merge(s)
		arr.append(d)
	var f = FileAccess.open(LAYOUT_FILE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"tiles": arr}, "\t"))

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
		var w = _build_wrapper(sh, td.get("rows", 24), td.get("cols", 80))
		_grid.add_child(w)
		var body = _find_body(w)
		body.focus_entered.connect(func(): _last_body = body)
		_tiles.append({wrapper = w, col = td.get("col", 0), row = td.get("row", 0),
			cspan = td.get("cspan", GRID), rspan = td.get("rspan", GRID)})
	_apply_layout(); _list()

# ═══════════════════════════════════════════════════════════════════════
# Keyboard & palette
# ═══════════════════════════════════════════════════════════════════════

func _input(event):
	if not (event is InputEventKey and event.pressed): return
	# Emergency reset: Ctrl+Shift+R
	if event.keycode == KEY_R and event.ctrl_pressed and event.shift_pressed:
		_sidebar.show(); _sidebar_on = true
		_reset(); _apply_layout(); _list()
		print("[Workspace] Emergency reset")
		return
	if event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
		match event.keycode:
			KEY_N: var p = _spawn(); if p: p.grab_focus()
			KEY_W: _kill_last()
			KEY_B: _toggle_sidebar()
			KEY_P: _toggle_palette()

func _toggle_palette():
	if _palette == null: _palette = _build_palette(); add_child(_palette)
	_palette.visible = not _palette.visible
	if _palette.visible: _palette.get_node("LineEdit").grab_focus()

func _build_palette() -> Control:
	var bg = Panel.new(); bg.size = Vector2(350, 240)
	bg.position = (size - bg.size) * 0.5
	var v = VBoxContainer.new(); bg.add_child(v)
	var inp = LineEdit.new(); inp.placeholder_text = "Command..."; v.add_child(inp)
	var lst = ItemList.new(); lst.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(lst)
	for c in ["new terminal", "close active", "reset layout", "save", "load"]: lst.add_item(c)
	inp.text_changed.connect(func(t: String):
		lst.clear(); for c in ["new terminal", "close active", "reset layout", "save", "load"]:
			if t == "" or c.find(t) != -1: lst.add_item(c))
	inp.text_submitted.connect(func(t: String): _run(t); _palette.visible = false)
	lst.item_activated.connect(func(i: int): _run(lst.get_item_text(i)); _palette.visible = false)
	inp.gui_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE: _palette.visible = false)
	return bg

func _run(c: String):
	match c:
		"new terminal": var p = _spawn(); if p: p.grab_focus()
		"close active": _kill_last()
		"reset layout": _reset()
		"save": _save()
		"load": _restore()
		_: if "new" in c: var p = _spawn(); if p: p.grab_focus()
		elif "close" in c: _kill_last()
		elif "reset" in c: _reset()
		elif "save" in c: _save()
		elif "load" in c: _restore()
