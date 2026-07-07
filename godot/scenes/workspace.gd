extends Control
# godopty Workspace — tiling grid of terminal panes with title bars.

const LAYOUT_FILE = "user://layout.json"
const DEFAULT_SHELL = "/bin/bash"
const GRID = 12
const MIN_TILE = 2

var _sidebar: Control
var _sidebar_bg: ColorRect
var _sidebar_on := true
var _palette: Control
var _grid: Control
var _last_body: Control
var _tiles: Array = []  # [{wrapper, col, row, cspan, rspan}]

func _ready():
	show()
	DisplayServer.window_set_min_size(Vector2i(500, 300))

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
	var m = 180 if _sidebar_on else 20
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

	var bar = Control.new()
	bar.custom_minimum_size = Vector2(0, 26)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tbg = ColorRect.new()
	tbg.color = Color(0.18, 0.18, 0.20, 1.0)
	tbg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(tbg)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(center)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	center.add_child(hbox)
	vbox.add_child(bar)

	var lbl = Label.new()
	lbl.text = " " + (shell.get_file() if shell else "terminal")
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)

	for item in [
		["_", func(): _toggle_minimize(root)],
		["✕", func(): _kill(_find_body(root))],
	]:
		var btn = Button.new()
		btn.text = item[0]; btn.flat = true; btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(22, 18)
		btn.pressed.connect(item[1]); hbox.add_child(btn)

	var term = load("res://scenes/terminal_pane.gd").new()
	term.name = "Body"
	term.shell_command = shell if shell != "" else DEFAULT_SHELL
	term.rows = rows; term.cols = cols
	term.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	term.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(term)

	term.title_changed.connect(func(t: String): lbl.text = " " + t)

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
	var sbg = ColorRect.new()
	sbg.name = "SidebarBg"; sbg.color = Color(0.12, 0.12, 0.15, 1.0)
	sbg.size = Vector2(180, 0); sbg.anchor_top = 0.0; sbg.anchor_bottom = 1.0; sbg.anchor_right = 0.0
	add_child(sbg)
	_sidebar_bg = sbg

	_sidebar = Control.new()
	_sidebar.offset_right = 180
	_sidebar.clip_contents = true; _sidebar.anchor_top = 0.0; _sidebar.anchor_bottom = 1.0
	add_child(_sidebar)

	var v = VBoxContainer.new(); v.name = "SidebarContent"
	v.add_theme_constant_override("separation", 4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sidebar.add_child(v)

	var header = HBoxContainer.new(); header.name = "Header"
	header.add_theme_constant_override("separation", 0)
	var title = _lbl(" godopty", 16)
	title.name = "SidebarTitle"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var arrow = Button.new()
	arrow.text = "◀"; arrow.name = "SidebarArrow"
	arrow.custom_minimum_size = Vector2(22, 22)
	arrow.pressed.connect(_toggle_sidebar)
	header.add_child(arrow)
	v.add_child(header)

	for b in [
		["+ Terminal", func(): var p = _spawn(); if p: p.grab_focus()],
		["↺ Reset", _reset],
	]:
		var btn = Button.new(); btn.text = b[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(b[1]); v.add_child(btn)

	v.add_child(_lbl(" Panes:", 12))
	var sc = ScrollContainer.new(); sc.name = "PaneScroll"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(sc)
	var pl = VBoxContainer.new(); pl.name = "PaneList"
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(pl)

	for b in [["Save", _save], ["Load", _restore]]:
		var btn = Button.new(); btn.text = b[0]; btn.pressed.connect(b[1]); v.add_child(btn)

	# Collapsed-state button — direct child of sidebar, only visible when collapsed
	var coll_btn = Button.new()
	coll_btn.text = "▶"; coll_btn.name = "SidebarCollapsedBtn"
	coll_btn.custom_minimum_size = Vector2(18, 22)
	coll_btn.offset_left = 1; coll_btn.offset_top = 2
	coll_btn.offset_right = 19; coll_btn.visible = false
	coll_btn.pressed.connect(_toggle_sidebar)
	_sidebar.add_child(coll_btn)

func _lbl(t: String, s: int) -> Label:
	var l = Label.new(); l.text = t; l.add_theme_font_size_override("font_size", s); return l

func _list():
	var pl = _sidebar.get_node_or_null("SidebarContent/PaneScroll/PaneList")
	if pl == null: print("[sidebar] PaneList not found!"); return
	print("[sidebar] listing ", _tiles.size(), " panes")
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
	var content = _sidebar.get_node_or_null("SidebarContent")
	var title = _sidebar.get_node_or_null("SidebarContent/Header/SidebarTitle")
	var a = _sidebar.get_node_or_null("SidebarArrow")
	var coll = _sidebar.get_node_or_null("SidebarCollapsedBtn")
	if _sidebar_on:
		_sidebar.offset_right = 180; _sidebar_bg.size.x = 180
		if content: content.show()
		if title: title.visible = true
		if a: a.visible = true
		if coll: coll.visible = false
	else:
		_sidebar.offset_right = 20; _sidebar_bg.size.x = 20
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
	if _palette == null: _palette = _build_palette(); add_child(_palette)
	_palette.visible = not _palette.visible
	if _palette.visible: _palette.get_node("LineEdit").grab_focus()

func _build_palette() -> Control:
	var bg = Panel.new(); bg.size = Vector2(350, 240); bg.position = (size - bg.size) * 0.5
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
		"save": _save();
		"load": _restore()
		_: if "new" in c: var p = _spawn(); if p: p.grab_focus()
		elif "close" in c: _kill_last()
		elif "reset" in c: _reset()
		elif "save" in c: _save()
		elif "load" in c: _restore()
