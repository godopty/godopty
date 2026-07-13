extends RefCounted
class_name TerminalManager
# godopty Terminal Manager — owns tile lifecycle and terminal building.

const GRID = 12
const MIN_TILE = 2
const TITLE_BAR_HEIGHT = 26
const BUTTON_MIN_WIDTH = 22
const BUTTON_MIN_HEIGHT = 18

const TerminalPaneScript = preload("res://scenes/terminal_pane.gd")

var on_close: Callable  # set by workspace to refresh layout after kill

var tiles: Array[Dictionary] = []
var last_body: Control

func spawn(shell := "") -> Control:
	var s = shell if shell != "" else SettingsManager.cfg_shell_command
	var w = _build_wrapper(s, SettingsManager.cfg_default_rows, SettingsManager.cfg_default_cols)
	if tiles.is_empty():
		tiles.append({wrapper = w, col = 0, row = 0, cspan = GRID, rspan = GRID})
	else:
		if not _split_for(w):
			w.queue_free()
			return null
	# Caller adds to scene tree and connects signals
	var body = _find_body(w)
	return body

func spawn_bulk(count: int, shell := "") -> Array[Control]:
	var spawned: Array[Control] = []
	var s = shell if shell != "" else SettingsManager.cfg_shell_command
	for i in count:
		var w = _build_wrapper(s, SettingsManager.cfg_default_rows, SettingsManager.cfg_default_cols)
		if tiles.is_empty():
			tiles.append({wrapper = w, col = 0, row = 0, cspan = GRID, rspan = GRID})
		else:
			if not _split_for(w):
				w.queue_free()
				break
		var body = _find_body(w)
		if body: spawned.append(body)
	return spawned

func kill(body: Control):
	if last_body == body: last_body = null
	var wi = -1
	for i in tiles.size():
		if _find_body(tiles[i].wrapper) == body: wi = i; break
	if wi == -1: return
	var rm = tiles[wi]
	tiles.remove_at(wi)
	if not _expand_exact(rm):
		_expand_partial(rm)
	rm.wrapper.queue_free()

func kill_last():
	if last_body: kill(last_body)

func reset():
	for t in tiles: t.wrapper.queue_free()
	tiles.clear()
	last_body = null

func _split_for(w: Control) -> bool:
	var bi = 0; var ba = 0
	for i in tiles.size():
		var a = tiles[i].cspan * tiles[i].rspan
		if a > ba: ba = a; bi = i
	var s = tiles[bi]
	var oc = s.col; var or1 = s.row; var os = s.cspan; var ot = s.rspan
	if os >= ot:
		var half = maxi(os / 2, 1)
		if half < MIN_TILE or (os - half) < MIN_TILE: return false
		s.cspan = half
		tiles.append({wrapper = w, col = oc + half, row = or1, cspan = os - half, rspan = ot})
	else:
		var half = maxi(ot / 2, 1)
		if half < MIN_TILE or (ot - half) < MIN_TILE: return false
		s.rspan = half
		tiles.append({wrapper = w, col = oc, row = or1 + half, cspan = os, rspan = ot - half})
	return true

func _expand_exact(rm: Dictionary) -> bool:
	for t in tiles:
		if t.row == rm.row and t.rspan == rm.rspan:
			if t.col + t.cspan == rm.col: t.cspan += rm.cspan; return true
			if rm.col + rm.cspan == t.col: t.col = rm.col; t.cspan += rm.cspan; return true
		if t.col == rm.col and t.cspan == rm.cspan:
			if t.row + t.rspan == rm.row: t.rspan += rm.rspan; return true
			if rm.row + rm.rspan == t.row: t.row = rm.row; t.rspan += rm.rspan; return true
	return false

func _expand_partial(rm: Dictionary):
	var left = []; var right = []; var up = []; var down = []
	for t in tiles:
		if t.col + t.cspan == rm.col: left.append(t)
		if rm.col + rm.cspan == t.col: right.append(t)
		if t.row + t.rspan == rm.row: up.append(t)
		if rm.row + rm.rspan == t.row: down.append(t)
	if left.size() > 0 or right.size() > 0:
		var new_right = rm.col + rm.cspan
		for t in left: t.cspan = new_right - t.col
		for t in right: t.cspan = (t.col + t.cspan) - rm.col; t.col = rm.col
		return
	if up.size() > 0 or down.size() > 0:
		var new_bottom = rm.row + rm.rspan
		for t in up: t.rspan = new_bottom - t.row
		for t in down: t.rspan = (t.row + t.rspan) - rm.row; t.row = rm.row
		return
	if tiles.size() > 0:
		tiles[0].col = 0; tiles[0].row = 0
		tiles[0].cspan = GRID; tiles[0].rspan = GRID

# ── Terminal wrapper builder ──────────────────────────────────────────

func build_wrapper(shell: String, rows: int, cols: int) -> Control:
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
	term.rows = rows; term.cols = cols
	term.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	term.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(term)

	SettingsManager.apply_to_terminal(term)
	# Override with this pane's specific shell (may differ from default)
	term.shell_command = shell if shell != "" else SettingsManager.cfg_shell_command
	term.title_changed.connect(func(t: String): lbl.text = " " + t)

	return root

func _build_wrapper(shell: String, rows: int, cols: int) -> Control:
	return build_wrapper(shell, rows, cols)

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
	bar.add_child(tbg)
	tbg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var lbl = Label.new()
	lbl.text = " " + (shell.get_file() if shell else "terminal")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(lbl)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 2)
	btn_hbox.anchor_left = 1.0; btn_hbox.anchor_right = 1.0
	btn_hbox.anchor_top = 0.0; btn_hbox.anchor_bottom = 1.0
	var btn_total = 2 * BUTTON_MIN_WIDTH + 6
	btn_hbox.offset_left = -btn_total
	btn_hbox.offset_right = -2
	bar.add_child(btn_hbox)

	var min_btn = Button.new()
	min_btn.text = Icons.MINIMIZE; min_btn.focus_mode = Control.FOCUS_NONE
	min_btn.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH, BUTTON_MIN_HEIGHT)
	min_btn.pressed.connect(func(): _toggle_minimize(root, min_btn))
	btn_hbox.add_child(min_btn)

	var close_btn = Button.new()
	close_btn.text = Icons.CLOSE; close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH, BUTTON_MIN_HEIGHT)
	close_btn.pressed.connect(func(): _handle_close(_find_body(root)))
	btn_hbox.add_child(close_btn)

	return lbl

func _find_body(w: Control) -> Control:
	return w.get_node_or_null("BodyVBox/Body")

func _toggle_minimize(w: Control, btn: Button):
	var body = _find_body(w)
	if body:
		body.visible = not body.visible
		btn.text = Icons.MINIMIZE if body.visible else Icons.RESTORE

func _handle_close(body: Control):
	if on_close.is_valid():
		on_close.call(body)
