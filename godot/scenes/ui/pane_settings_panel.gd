extends Control
class_name PaneSettingsPanel

var _target: Control  # the TerminalPane body
var _debounce_timer: Timer

# UI widget refs
var _cursor_shape_opt: OptionButton
var _cursor_blink_cb: CheckBox
var _cursor_blink_spin: SpinBox
var _scroll_spin: SpinBox
var _rows_spin: SpinBox
var _cols_spin: SpinBox
var _font_spin: SpinBox
var _font_path_current: String
var _scheme_path_current: String
var _fg_btn: ColorPickerButton
var _bg_btn: ColorPickerButton
var _env_te: TextEdit
var _pane_name_le: LineEdit

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func _unhandled_input(event):
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()

func open_for(body: Control):
	_target = body
	if _target == null: return
	_build_ui()
	visible = true

func _build_ui():
	for c in get_children():
		c.queue_free()

	var cc = CenterContainer.new()
	add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg = Panel.new()
	bg.custom_minimum_size = Vector2(380, 420)
	cc.add_child(bg)

	var mc = MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 16)
	mc.add_theme_constant_override("margin_right", 16)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 16)
	bg.add_child(mc)
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	mc.add_child(v)

	# Header with close button
	var h = HBoxContainer.new()
	var t = Label.new(); t.text = "Pane Settings"
	t.add_theme_font_size_override("font_size", 18)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(t)
	var x = Button.new(); x.text = Icons.CLOSE; x.flat = true
	x.pressed.connect(func(): visible = false); h.add_child(x)
	v.add_child(h)
	v.add_child(HSeparator.new())

	# Tab container
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)

	# Tab: Terminal
	var t_term = _create_tab(tabs, "Terminal")
	_add_pane_name_control(t_term)
	_add_shell_env_control(t_term)
	t_term.add_child(HSeparator.new())
	_add_cursor_shape_control(t_term)
	_add_cursor_blink_control(t_term)
	_add_cursor_blink_speed_control(t_term)
	_add_scroll_control(t_term)
	t_term.add_child(HSeparator.new())
	_add_dims_control(t_term)

	# Tab: Appearance
	var t_app = _create_tab(tabs, "Appearance")
	_add_font_control(t_app)
	_add_font_picker(t_app)
	_add_scheme_picker(t_app)
	t_app.add_child(HSeparator.new())
	_add_fg_bg_controls(t_app)

	# Debounce timer
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true; _debounce_timer.wait_time = 0.15
	_debounce_timer.timeout.connect(_apply_to_target)
	bg.add_child(_debounce_timer)

func _apply_to_target():
	if _target == null: return
	var name_val = _pane_name_le.text.strip_edges()
	_target.apply_settings({
		"shell_env": _env_te.text,
		"cursor_shape": _cursor_shape_opt.selected,
		"cursor_blink": _cursor_blink_cb.button_pressed,
		"cursor_blink_speed": _cursor_blink_spin.value,
		"scroll_lines": int(_scroll_spin.value),
		"rows": int(_rows_spin.value),
		"cols": int(_cols_spin.value),
		"font_size": int(_font_spin.value),
		"font_path": _font_path_current,
		"color_scheme_path": _scheme_path_current,
		"default_fg": _fg_btn.color,
		"default_bg": _bg_btn.color,
		"pane_name": name_val,
	})
# ═══════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════

func _create_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var sc = ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)

	var mc = MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 8)
	mc.add_theme_constant_override("margin_right", 8)
	mc.add_theme_constant_override("margin_top", 8)
	mc.add_theme_constant_override("margin_bottom", 8)
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(mc)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_child(v)
	return v

func _lbl(txt: String) -> Label:
	var l = Label.new(); l.text = txt; l.add_theme_font_size_override("font_size", 12); return l

func _add_pane_name_control(v: VBoxContainer):
	var hb = HBoxContainer.new()
	hb.add_child(_lbl("Name:"))
	_pane_name_le = LineEdit.new()
	_pane_name_le.text = _target.pane_name
	_pane_name_le.placeholder_text = _target.shell_command.get_file()
	_pane_name_le.add_theme_font_size_override("font_size", 12)
	_pane_name_le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pane_name_le.text_changed.connect(func(_s: String): _debounce_timer.start())
	hb.add_child(_pane_name_le)
	v.add_child(hb)

func _add_shell_env_control(v: VBoxContainer):
	v.add_child(_lbl("Environment:"))
	_env_te = TextEdit.new()
	_env_te.text = _target.shell_env
	_env_te.placeholder_text = "KEY=value (one per line)"
	_env_te.custom_minimum_size = Vector2(0, 60)
	_env_te.add_theme_font_size_override("font_size", 11)
	_env_te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_env_te.text_changed.connect(func(): _debounce_timer.start())
	v.add_child(_env_te)

func _add_cursor_shape_control(v: VBoxContainer):
	var hs = HBoxContainer.new()
	hs.add_child(_lbl("Cursor:"))
	_cursor_shape_opt = OptionButton.new()
	_cursor_shape_opt.add_item("Block (█)")
	_cursor_shape_opt.add_item("Underline (_)")
	_cursor_shape_opt.add_item("Beam (|)")
	_cursor_shape_opt.selected = _target.cursor_shape
	_cursor_shape_opt.item_selected.connect(func(_idx: int): _debounce_timer.start())
	hs.add_child(_cursor_shape_opt)
	v.add_child(hs)

func _add_cursor_blink_control(v: VBoxContainer):
	_cursor_blink_cb = CheckBox.new()
	_cursor_blink_cb.text = "Cursor blink"
	_cursor_blink_cb.add_theme_font_size_override("font_size", 12)
	_cursor_blink_cb.button_pressed = _target.cursor_blink
	_cursor_blink_cb.toggled.connect(func(_pressed: bool): _debounce_timer.start())
	v.add_child(_cursor_blink_cb)

func _add_cursor_blink_speed_control(v: VBoxContainer):
	var hb = HBoxContainer.new()
	hb.add_child(_lbl("Blink speed:"))
	_cursor_blink_spin = SpinBox.new()
	_cursor_blink_spin.get_line_edit().add_theme_font_size_override("font_size", 12)
	_cursor_blink_spin.min_value = 0.1; _cursor_blink_spin.max_value = 2.0
	_cursor_blink_spin.step = 0.1; _cursor_blink_spin.value = _target.cursor_blink_speed
	_cursor_blink_spin.value_changed.connect(func(_v: float): _debounce_timer.start())
	hb.add_child(_cursor_blink_spin)
	v.add_child(hb)

func _add_scroll_control(v: VBoxContainer):
	var hs = HBoxContainer.new()
	hs.add_child(_lbl("Scroll lines:"))
	_scroll_spin = SpinBox.new()
	_scroll_spin.get_line_edit().add_theme_font_size_override("font_size", 12)
	_scroll_spin.min_value = 1; _scroll_spin.max_value = 10
	_scroll_spin.step = 1; _scroll_spin.value = _target.scroll_lines
	_scroll_spin.value_changed.connect(func(_v: float): _debounce_timer.start())
	hs.add_child(_scroll_spin)
	v.add_child(hs)

func _add_dims_control(v: VBoxContainer):
	var hr = HBoxContainer.new()
	hr.add_child(_lbl("Size:"))
	_rows_spin = SpinBox.new()
	_rows_spin.get_line_edit().add_theme_font_size_override("font_size", 12)
	_rows_spin.min_value = 10; _rows_spin.max_value = 100
	_rows_spin.value = _target.rows
	_rows_spin.value_changed.connect(func(_v: float): _debounce_timer.start())
	hr.add_child(_rows_spin)
	hr.add_child(_lbl("×"))
	_cols_spin = SpinBox.new()
	_cols_spin.get_line_edit().add_theme_font_size_override("font_size", 12)
	_cols_spin.min_value = 40; _cols_spin.max_value = 200
	_cols_spin.value = _target.cols
	_cols_spin.value_changed.connect(func(_v: float): _debounce_timer.start())
	hr.add_child(_cols_spin)
	v.add_child(hr)

func _add_font_control(v: VBoxContainer):
	var hf = HBoxContainer.new()
	hf.add_child(_lbl("Font size:"))
	_font_spin = SpinBox.new()
	_font_spin.get_line_edit().add_theme_font_size_override("font_size", 12)
	_font_spin.min_value = 8; _font_spin.max_value = 32
	_font_spin.value = _target.font_size
	_font_spin.value_changed.connect(func(_v: float): _debounce_timer.start())
	hf.add_child(_font_spin)
	v.add_child(hf)

func _add_font_picker(v: VBoxContainer):
	_font_path_current = _target.font_path
	var h = HBoxContainer.new()
	h.add_child(_lbl("Font:"))
	var btn = Button.new()
	btn.text = _font_path_current.get_file()
	btn.add_theme_font_size_override("font_size", 12)
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func():
		var dlg = FileDialog.new()
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dlg.current_path = _font_path_current
		dlg.add_filter("*.ttf", "TrueType Fonts")
		dlg.file_selected.connect(func(path: String):
			_font_path_current = path
			btn.text = path.get_file()
			_debounce_timer.start()
			dlg.queue_free())
		dlg.canceled.connect(dlg.queue_free)
		add_child(dlg)
		dlg.popup_centered())
	h.add_child(btn)
	v.add_child(h)

func _add_scheme_picker(v: VBoxContainer):
	_scheme_path_current = _target.color_scheme_path
	var h = HBoxContainer.new()
	h.add_child(_lbl("Color scheme:"))
	var btn = Button.new()
	btn.text = _scheme_path_current.get_file() if _scheme_path_current != "" else "(none)"
	btn.add_theme_font_size_override("font_size", 12)
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func():
		var dlg = FileDialog.new()
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dlg.current_path = _scheme_path_current
		dlg.add_filter("*.txt; *.json; *.csv", "Scheme files")
		dlg.file_selected.connect(func(path: String):
			_scheme_path_current = path
			btn.text = path.get_file()
			_debounce_timer.start()
			dlg.queue_free())
		dlg.canceled.connect(dlg.queue_free)
		add_child(dlg)
		dlg.popup_centered())
	h.add_child(btn)
	v.add_child(h)

func _add_fg_bg_controls(v: VBoxContainer):
	var h1 = HBoxContainer.new()
	h1.add_child(_lbl("Default FG:"))
	_fg_btn = ColorPickerButton.new()
	_fg_btn.color = _target.default_fg
	_fg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fg_btn.color_changed.connect(func(_c: Color): _debounce_timer.start())
	h1.add_child(_fg_btn)
	v.add_child(h1)

	var h2 = HBoxContainer.new()
	h2.add_child(_lbl("Default BG:"))
	_bg_btn = ColorPickerButton.new()
	_bg_btn.color = _target.default_bg
	_bg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bg_btn.color_changed.connect(func(_c: Color): _debounce_timer.start())
	h2.add_child(_bg_btn)
	v.add_child(h2)
