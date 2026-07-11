extends Control
class_name Workspace
# godopty Workspace — tiling grid of terminal panes with title bars.
# Tile lifecycle is delegated to TerminalManager.

const LAYOUT_FILE = "user://layout.json"
const GRID = 12
const MIN_WINDOW_W = 500
const MIN_WINDOW_H = 300

const PALETTE_COMMANDS = ["new terminal", "close active", "settings", "reset layout", "save", "load"]

var _sidebar: Sidebar
var _sidebar_bg: ColorRect
var _palette: Control
var _grid: Control
var _settings_panel: SettingsPanel
var _tm: TerminalManager = TerminalManager.new()

func _ready():
	show()
	DisplayServer.window_set_min_size(Vector2i(MIN_WINDOW_W, MIN_WINDOW_H))

	_grid = Control.new()
	add_child(_grid)

	var overlay = load("res://scenes/toast_overlay.gd").new()
	add_child(overlay)

	_build_sidebar()
	_apply_layout()
	_wire_sidebar_signals()
	_tm.on_close = func(body: Control): _kill(body)
	if FileAccess.file_exists(LAYOUT_FILE): _restore()

	ShortcutManager.register("app:new_pane", "Ctrl+Shift+N", func(): var p = _spawn(); if p: p.grab_focus())
	ShortcutManager.register("app:close_pane", "Ctrl+Shift+W", func(): _kill_last())
	ShortcutManager.register("app:toggle_sidebar", "Ctrl+Shift+B", _toggle_sidebar)
	ShortcutManager.register("app:toggle_palette", "Ctrl+Shift+P", _toggle_palette)
	ShortcutManager.register("app:toggle_fps", "Ctrl+Shift+F", _toggle_fps)
	ShortcutManager.register("app:reset_workspace", "Ctrl+Shift+R", func():
		_reset(); _apply_layout(); _list()
	)

	SettingsManager.settings_changed.connect(_on_settings_changed)
	_on_settings_changed()

func _on_settings_changed():
	for t in _tm.tiles:
		var body = _tm._find_body(t.wrapper)
		if body: SettingsManager.apply_to_terminal(body)
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
	var m = _sidebar_bg.size.x if (_sidebar_bg and _sidebar_bg.visible) else 0
	_grid.offset_left = m; _grid.offset_right = 0
	_grid.offset_top = 0; _grid.offset_bottom = 0
	_grid.anchor_left = 0.0; _grid.anchor_right = 1.0
	_grid.anchor_top = 0.0; _grid.anchor_bottom = 1.0

	var cw = maxf(_grid.size.x, 1.0) / GRID
	var ch = maxf(_grid.size.y, 1.0) / GRID
	for t in _tm.tiles:
		var x = t.col * cw; var y = t.row * ch
		var w = t.cspan * cw; var h = t.rspan * ch
		t.wrapper.offset_left = x; t.wrapper.offset_top = y
		t.wrapper.offset_right = x + w; t.wrapper.offset_bottom = y + h
		t.wrapper.anchor_left = 0.0; t.wrapper.anchor_right = 0.0
		t.wrapper.anchor_top = 0.0; t.wrapper.anchor_bottom = 0.0

# ═══════════════════════════════════════════════════════════════════════
# Spawn / Kill — delegate to TerminalManager
# ═══════════════════════════════════════════════════════════════════════

func _spawn(shell := "") -> Control:
	var body = _tm.spawn(shell)
	if body == null:
		ToastManager.warn("Cannot add terminal — panes would be too small")
		return null
	# TerminalManager already added the wrapper to its tiles; add to scene tree
	var w = _tm.tiles[-1].wrapper
	_grid.add_child(w)
	body.focus_entered.connect(func(): _tm.last_body = body)
	_apply_layout()
	_list()
	ToastManager.info("Terminal spawned")
	return body

func _spawn_bulk(count: int, shell := ""):
	var bodies = _tm.spawn_bulk(count, shell)
	if bodies.is_empty():
		ToastManager.warn("Cannot add terminals — grid is full")
		return
	for body in bodies:
		var w = body.get_parent().get_parent()  # BodyVBox → PanelContainer
		_grid.add_child(w)
		body.focus_entered.connect(func(): _tm.last_body = body)
	_apply_layout()
	_list()
	ToastManager.info("Spawned %d terminals" % bodies.size())
	if bodies.size() > 0: bodies[-1].grab_focus()

func _kill(body: Control):
	_tm.kill(body)
	_apply_layout()
	_list()
	ToastManager.info("Terminal closed")

func _kill_last():
	_tm.kill_last()
	_apply_layout()
	_list()

func _reset():
	_tm.reset()
	_apply_layout()
	_list()

# ═══════════════════════════════════════════════════════════════════════
# Persistence
# ═══════════════════════════════════════════════════════════════════════

func _save():
	var ts: Array[Dictionary] = []
	for t in _tm.tiles:
		var body = _tm._find_body(t.wrapper)
		var state = body._get_layout_state() if body and body.has_method("_get_layout_state") else {}
		state["col"] = t.col; state["row"] = t.row
		state["cspan"] = t.cspan; state["rspan"] = t.rspan
		ts.append(state)
	var d = {"tiles": ts}
	var f = FileAccess.open(LAYOUT_FILE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

func _restore():
	if not FileAccess.file_exists(LAYOUT_FILE): return
	var f = FileAccess.open(LAYOUT_FILE, FileAccess.READ)
	if not f: return
	var j = JSON.new()
	if j.parse(f.get_as_text()) != OK: return
	var d = j.get_data()
	if not (d is Dictionary and d.has("tiles")): return

	# Workspace trust: warn if saved shells differ from configured default
	var untrusted := false
	for td in d.tiles:
		if not (td is Dictionary): continue
		var sh = td.get("shell", "")
		if sh != "" and sh != SettingsManager.cfg_shell_command:
			untrusted = true
			break
	if untrusted:
		_show_trust_dialog(d)
		return
	_do_restore(d)

func _show_trust_dialog(d: Dictionary):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Workspace Trust"
	dialog.dialog_text = "This layout was saved with a different shell than your current default (%s).\n\nDo you want to restore it anyway?" % SettingsManager.cfg_shell_command
	dialog.ok_button_text = "Restore"
	dialog.cancel_button_text = "Cancel"
	dialog.confirmed.connect(func(): _do_restore(d); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _do_restore(d: Dictionary):
	_tm.reset()
	for td in d.tiles:
		if not (td is Dictionary): continue
		var sh = td.get("shell", SettingsManager.cfg_shell_command)
		if sh == null or sh == "": sh = SettingsManager.cfg_shell_command
		var w = _tm.build_wrapper(sh, td.get("rows", SettingsManager.cfg_default_rows), td.get("cols", SettingsManager.cfg_default_cols))
		_grid.add_child(w)
		var body = _tm._find_body(w)
		body.focus_entered.connect(func(): _tm.last_body = body)
		_tm.tiles.append({wrapper = w, col = td.get("col", 0), row = td.get("row", 0),
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
		_palette.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_palette.visible = not _palette.visible
	if _palette.visible:
		var inp = _palette.find_child("*", true, false) as LineEdit
		if inp: inp.grab_focus()

func _toggle_fps():
	pass

func _build_palette() -> Control:
	var bg = Panel.new()
	bg.custom_minimum_size = Vector2(320, 160)
	bg.name = "Palette"
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	bg.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mc = MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 8)
	mc.add_theme_constant_override("margin_right", 8)
	mc.add_theme_constant_override("margin_top", 8)
	mc.add_theme_constant_override("margin_bottom", 8)
	v.add_child(mc)
	var inp = LineEdit.new()
	inp.placeholder_text = "Type command..."
	inp.add_theme_font_size_override("font_size", 14)
	mc.add_child(inp)
	var results = VBoxContainer.new()
	v.add_child(results)

	inp.text_changed.connect(func(t: String):
		for c in results.get_children(): c.queue_free()
		for cmd in PALETTE_COMMANDS:
			if t == "" or cmd.findn(t) != -1:
				var btn = Button.new()
				btn.text = cmd; btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				btn.add_theme_font_size_override("font_size", 13)
				btn.pressed.connect(func():
					_execute_command(cmd); _palette.visible = false
				)
				results.add_child(btn)
	)

	inp.text_submitted.connect(func(_t: String):
		if results.get_child_count() > 0:
			(results.get_child(0) as Button).pressed.emit()
	)

	return bg

func _execute_command(cmd: String):
	match cmd:
		"new terminal": var p = _spawn(); if p: p.grab_focus()
		"close active": _kill_last()
		"settings": _toggle_settings()
		"reset layout": _reset()
		"save": _save()
		"load": _restore()

# ═══════════════════════════════════════════════════════════════════════
# Sidebar
# ═══════════════════════════════════════════════════════════════════════


# ── Sidebar ───────────────────────────────────────────────────────────

func _wire_sidebar_signals():
	_sidebar.request_new_pane.connect(func(): var p = _spawn(); if p: p.grab_focus())
	_sidebar.request_bulk_spawn.connect(func(count: int): _spawn_bulk(count))
	_sidebar.request_close_last.connect(func(): _kill_last())
	_sidebar.request_close.connect(func(body: Control): _kill(body))
	_sidebar.request_settings.connect(_toggle_settings)
	_sidebar.request_reset.connect(func(): _reset(); _apply_layout(); _list())
	_sidebar.request_focus.connect(func(body: Control): body.grab_focus())
	_sidebar.toggled.connect(func(): _apply_layout())

func _list():
	if _sidebar == null: return
	var panes: Array[Control] = []
	for t in _tm.tiles:
		var body = _tm._find_body(t.wrapper)
		if body: panes.append(body)
	_sidebar.update_pane_list(panes)

func _toggle_sidebar():
	if _sidebar == null: return
	_sidebar._toggle_sidebar()
	# Sync background rect to sidebar's new width
	_sidebar_bg.offset_right = _sidebar.offset_right
	_apply_layout()

func _process(delta: float):
	if _sidebar == null: return
	# FPS counter update (throttled to ~4 Hz)
	if Engine.get_process_frames() % 15 == 0:
		var fps = Engine.get_frames_per_second()
		var body = _tm.last_body
		var fetch_ms = -1; var draw_ms = -1
		if body and body.has_method("_draw"):
			fetch_ms = body.get("_fetch_ms") if "_fetch_ms" in body else -1
			draw_ms = body.get("_draw_ms") if "_draw_ms" in body else -1
		_sidebar.update_fps(fps, fetch_ms, draw_ms)

func _toggle_settings():
	if _settings_panel == null:
		_settings_panel = SettingsPanel.new(self)
		_settings_panel.name = "SettingsPanel"
		_settings_panel.visible = false
		add_child(_settings_panel)
		_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = not _settings_panel.visible

func _build_sidebar():
	_sidebar_bg = ColorRect.new()
	_sidebar_bg.name = "SidebarBg"
	_sidebar_bg.color = SettingsManager.cfg_sidebar_bg
	_sidebar_bg.anchor_top = 0.0; _sidebar_bg.anchor_bottom = 1.0
	_sidebar_bg.offset_right = 180
	add_child(_sidebar_bg)

	_sidebar = Sidebar.new()
	_sidebar.name = "Sidebar"
	_sidebar_bg.add_child(_sidebar)
	_sidebar.offset_right = 180
	_sidebar.build(_sidebar_bg)
