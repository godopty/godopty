extends Control
class_name SettingsPanel

var _debounce_timer: Timer = null
var _workspace: Control

func _init(workspace: Control):
	_workspace = workspace

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _unhandled_input(event):
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()

func _build_ui():
	var cc = CenterContainer.new()
	add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg = Panel.new()
	bg.custom_minimum_size = Vector2(420, 540)
	cc.add_child(bg)

	var mc = MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 16)
	mc.add_theme_constant_override("margin_right", 16)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 16)
	bg.add_child(mc)
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var v = VBoxContainer.new(); v.name = "VBox"
	v.add_theme_constant_override("separation", 6)
	mc.add_child(v)

	_add_settings_header(v)
	v.add_child(HSeparator.new())

	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)

	# Tab 1: Terminal
	var t_term = _create_tab(tabs, "Terminal")
	var shape_opt = _add_cursor_control(t_term)
	var blink_cb = _add_blink_control(t_term)
	var blink_spin = _add_blink_speed_control(t_term)
	var cursor_px = _add_cursor_thickness_control(t_term)
	t_term.add_child(HSeparator.new())
	var dims = _add_dims_control(t_term)
	var scroll_spin = _add_scroll_control(t_term)

	# Tab 2: Appearance
	var t_app = _create_tab(tabs, "Appearance")
	_add_font_picker(t_app)
	var fs_spin = _add_font_control(t_app)
	t_app.add_child(HSeparator.new())
	_add_scheme_picker(t_app)
	t_app.add_child(HSeparator.new())
	var color_btns = _add_color_section(t_app)

	# Tab 3: System
	var t_sys = _create_tab(tabs, "System")
	_add_fps_control(t_sys)

	v.add_child(HSeparator.new())

	_debounce_timer = Timer.new()
	_debounce_timer.name = "DebounceTimer"
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = 0.15
	_debounce_timer.timeout.connect(func():
		SettingsManager.cfg_cursor_shape = shape_opt.selected
		SettingsManager.cfg_cursor_blink = blink_cb.button_pressed
		SettingsManager.cfg_font_size = int(fs_spin.value)
		SettingsManager.cfg_cursor_blink_speed = blink_spin.value
		SettingsManager.cfg_scroll_lines = int(scroll_spin.value)
		SettingsManager.cfg_default_rows = int(dims[0].value)
		SettingsManager.cfg_default_cols = int(dims[1].value)
		SettingsManager.cfg_beam_width = int(cursor_px[0].value)
		SettingsManager.cfg_underline_height = int(cursor_px[1].value)
		SettingsManager.save_settings()
	)
	bg.add_child(_debounce_timer)

	shape_opt.item_selected.connect(func(_idx): _debounce_timer.start())
	blink_cb.toggled.connect(func(_pressed): _debounce_timer.start())
	blink_spin.value_changed.connect(func(_v): _debounce_timer.start())
	fs_spin.value_changed.connect(func(_v): _debounce_timer.start())
	scroll_spin.value_changed.connect(func(_v): _debounce_timer.start())

	_add_reset_button(v, shape_opt, blink_cb, blink_spin, scroll_spin, dims, cursor_px, color_btns, fs_spin)

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

func _add_settings_header(v: VBoxContainer):
	var h = HBoxContainer.new()
	var t = Label.new(); t.text = "Settings"; t.add_theme_font_size_override("font_size", 18)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(t)
	var x = Button.new(); x.text = "X"; x.flat = true
	x.pressed.connect(func(): visible = false); h.add_child(x)
	v.add_child(h)

func _lbl(t: String) -> Label:
	var l = Label.new(); l.text = t; l.add_theme_font_size_override("font_size", 12); return l

func _add_cursor_control(v: VBoxContainer) -> OptionButton:
	var hs = HBoxContainer.new()
	hs.add_child(_lbl("Cursor:"))
	var opt = OptionButton.new(); opt.name = "ShapeOpt"
	opt.add_item("Block (█)"); opt.add_item("Underline (_)"); opt.add_item("Beam (|)")
	opt.selected = SettingsManager.cfg_cursor_shape
	hs.add_child(opt)
	v.add_child(hs)
	return opt

func _add_blink_control(v: VBoxContainer) -> CheckBox:
	var cb = CheckBox.new(); cb.name = "BlinkCb"; cb.text = "Cursor blink"
	cb.add_theme_font_size_override("font_size", 12)
	cb.button_pressed = SettingsManager.cfg_cursor_blink
	v.add_child(cb)
	return cb

func _add_blink_speed_control(v: VBoxContainer) -> SpinBox:
	var hb = HBoxContainer.new()
	hb.add_child(_lbl("Blink speed:"))
	var spin = SpinBox.new(); spin.name = "BlinkSpeedSpin"
	spin.get_line_edit().add_theme_font_size_override("font_size", 12)
	spin.min_value = 0.1; spin.max_value = 2.0; spin.step = 0.1
	spin.value = SettingsManager.cfg_cursor_blink_speed
	hb.add_child(spin)
	v.add_child(hb)
	return spin

func _add_font_control(v: VBoxContainer) -> SpinBox:
	var hf = HBoxContainer.new()
	hf.add_child(_lbl("Font size:"))
	var spin = SpinBox.new(); spin.name = "FontSpin"
	spin.get_line_edit().add_theme_font_size_override("font_size", 12)
	spin.min_value = 8; spin.max_value = 32
	spin.value = SettingsManager.cfg_font_size
	hf.add_child(spin)
	v.add_child(hf)
	return spin

func _add_scroll_control(v: VBoxContainer) -> SpinBox:
	var hs = HBoxContainer.new()
	hs.add_child(_lbl("Scroll lines:"))
	var spin = SpinBox.new(); spin.name = "ScrollSpin"
	spin.get_line_edit().add_theme_font_size_override("font_size", 12)
	spin.min_value = 1; spin.max_value = 10; spin.step = 1
	spin.value = SettingsManager.cfg_scroll_lines
	hs.add_child(spin)
	v.add_child(hs)
	return spin

func _add_dims_control(v: VBoxContainer) -> Array:
	var hr = HBoxContainer.new()
	hr.add_child(_lbl("Default size:"))
	var rspin = SpinBox.new()
	rspin.get_line_edit().add_theme_font_size_override("font_size", 12)
	rspin.min_value = 10; rspin.max_value = 100
	rspin.value = SettingsManager.cfg_default_rows
	hr.add_child(rspin)
	hr.add_child(_lbl("×"))
	var cspin = SpinBox.new()
	cspin.get_line_edit().add_theme_font_size_override("font_size", 12)
	cspin.min_value = 40; cspin.max_value = 200
	cspin.value = SettingsManager.cfg_default_cols
	hr.add_child(cspin)
	v.add_child(hr)
	return [rspin, cspin]

func _add_color_control(v: VBoxContainer, label: String, value: Color, setter: Callable) -> ColorPickerButton:
	var h = HBoxContainer.new()
	h.add_child(_lbl(label))
	var btn = ColorPickerButton.new()
	btn.color = value
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.color_changed.connect(setter)
	h.add_child(btn)
	v.add_child(h)
	return btn

func _add_file_picker(v: VBoxContainer, label: String, current_path: String, filters: Array, on_selected: Callable) -> void:
	var h = HBoxContainer.new()
	h.add_child(_lbl(label))
	var btn = Button.new()
	btn.text = current_path.get_file()
	btn.add_theme_font_size_override("font_size", 12)
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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

func _add_fps_control(v: VBoxContainer):
	var hf = HBoxContainer.new()
	hf.add_child(_lbl("Max FPS:"))
	
	var fps_opt = OptionButton.new(); fps_opt.name = "FpsOpt"
	fps_opt.add_theme_font_size_override("font_size", 12)
	fps_opt.add_item("60");
	fps_opt.add_item("120");
	fps_opt.add_item("144")
	fps_opt.add_item("165");
	fps_opt.add_item("240");
	fps_opt.add_item("Native");
	fps_opt.add_item("Unlimited");
	
	var presets = [60, 120, 144, 165, 240, -1, 0]
	fps_opt.selected = presets.find(SettingsManager.cfg_max_fps)
	fps_opt.item_selected.connect(func(idx: int):
		SettingsManager.cfg_max_fps = presets[idx]
		SettingsManager.save_settings()
	)
	hf.add_child(fps_opt)
	v.add_child(hf)

func _add_scheme_picker(v: VBoxContainer):
	_add_file_picker(v, "Color scheme:", SettingsManager.cfg_color_scheme_path, [["*.txt; *.json; *.csv", "Scheme files"]], func(path: String):
		SettingsManager.cfg_color_scheme_path = path
		SettingsManager.save_settings()
	)

func _add_font_picker(v: VBoxContainer):
	_add_file_picker(v, "Font:", SettingsManager.cfg_font_path, [["*.ttf", "TrueType Fonts"]], func(path: String):
		SettingsManager.cfg_font_path = path
		SettingsManager.save_settings()
	)

func _add_color_section(v: VBoxContainer) -> Array:
	v.add_child(_lbl("UI Colors:"))
	var btns = []
	for item in [
		["Wrapper bg", SettingsManager.cfg_wrapper_bg, func(c: Color): SettingsManager.cfg_wrapper_bg = c; _debounce_timer.start()],
		["Title bar", SettingsManager.cfg_title_bar_bg, func(c: Color): SettingsManager.cfg_title_bar_bg = c; _debounce_timer.start()],
		["Border", SettingsManager.cfg_wrapper_border, func(c: Color): SettingsManager.cfg_wrapper_border = c; _debounce_timer.start()],
		["Sidebar", SettingsManager.cfg_sidebar_bg, func(c: Color): SettingsManager.cfg_sidebar_bg = c; _debounce_timer.start()],
		["Focus", SettingsManager.cfg_focus_border, func(c: Color): SettingsManager.cfg_focus_border = c; _debounce_timer.start()],
		["Selection", SettingsManager.cfg_selection, func(c: Color): SettingsManager.cfg_selection = c; _debounce_timer.start()],
		["Scroll", SettingsManager.cfg_scrollback_indicator, func(c: Color): SettingsManager.cfg_scrollback_indicator = c; _debounce_timer.start()],
	]:
		var b = _add_color_control(v, item[0], item[1], item[2])
		btns.append([item[0], b])
	return btns

func _add_cursor_thickness_control(v: VBoxContainer) -> Array:
	var h1 = HBoxContainer.new()
	h1.add_child(_lbl("Beam width (|):"))
	var bspin = SpinBox.new()
	bspin.get_line_edit().add_theme_font_size_override("font_size", 12)
	bspin.min_value = 1; bspin.max_value = 8
	bspin.value = SettingsManager.cfg_beam_width
	h1.add_child(bspin)
	h1.add_child(_lbl("px"))
	v.add_child(h1)

	var h2 = HBoxContainer.new()
	h2.add_child(_lbl("Underline height (_):"))
	var uspin = SpinBox.new()
	uspin.get_line_edit().add_theme_font_size_override("font_size", 12)
	uspin.min_value = 1; uspin.max_value = 8
	uspin.value = SettingsManager.cfg_underline_height
	h2.add_child(uspin)
	h2.add_child(_lbl("px"))
	v.add_child(h2)

	return [bspin, uspin]

func _reset_colors(btns: Array):
	var defaults = [SettingsManager.WRAPPER_BG_COLOR, SettingsManager.TITLE_BAR_BG_COLOR, SettingsManager.WRAPPER_BORDER_COLOR, SettingsManager.SIDEBAR_BG_COLOR, Color(0.4, 0.7, 1.0, 0.3), Color(0.3, 0.5, 1.0, 0.4), Color(1.0, 1.0, 0.0)]
	for i in btns.size():
		if btns[i] is Array:
			(btns[i][1] as ColorPickerButton).color = defaults[i]
		else:
			(btns[i] as ColorPickerButton).color = defaults[i]

func _add_reset_button(v: VBoxContainer, shape_opt: OptionButton, blink_cb: CheckBox, blink_spin: SpinBox, scroll_spin: SpinBox, dims: Array, cursor_px: Array, color_btns: Array, fs_spin: SpinBox):
	var btn = Button.new(); btn.text = "Reset to defaults"
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(func():
		SettingsManager.cfg_cursor_shape = 0
		SettingsManager.cfg_cursor_blink = true
		SettingsManager.cfg_cursor_blink_speed = 0.5
		SettingsManager.cfg_scroll_lines = 3
		SettingsManager.cfg_default_rows = 24
		SettingsManager.cfg_default_cols = 80
		SettingsManager.cfg_beam_width = 2
		SettingsManager.cfg_underline_height = 3
		SettingsManager.cfg_wrapper_bg = SettingsManager.WRAPPER_BG_COLOR
		SettingsManager.cfg_title_bar_bg = SettingsManager.TITLE_BAR_BG_COLOR
		SettingsManager.cfg_wrapper_border = SettingsManager.WRAPPER_BORDER_COLOR
		SettingsManager.cfg_sidebar_bg = SettingsManager.SIDEBAR_BG_COLOR
		SettingsManager.cfg_focus_border = Color(0.4, 0.7, 1.0, 0.3)
		SettingsManager.cfg_selection = Color(0.3, 0.5, 1.0, 0.4)
		SettingsManager.cfg_scrollback_indicator = Color(1.0, 1.0, 0.0)
		SettingsManager.cfg_color_scheme_path = ""
		SettingsManager.cfg_font_path = "res://fonts/DejaVuSansMono.ttf"
		SettingsManager.cfg_font_size = 14
		SettingsManager.save_settings()
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
	)
	v.add_child(btn)
