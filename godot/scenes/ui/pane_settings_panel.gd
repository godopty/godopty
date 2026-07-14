extends Control
class_name PaneSettingsPanel
# Type-aware pane settings overlay. Builds a shared shell (header, close, ESC)
# and delegates content to the target pane's _build_pane_settings_ui().

var _target: Control
var _debounce_timer: Timer
var _gather_func: Callable

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
	Icons.style_button(x)
	x.pressed.connect(func(): visible = false); h.add_child(x)
	v.add_child(h)
	v.add_child(HSeparator.new())

	# Scrollable content area — filled by the pane type
	var sc = ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)

	var content = _target._build_pane_settings_ui(self)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)

	# Debounce timer — fires _apply_to_target after user stops typing
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true; _debounce_timer.wait_time = 0.15
	_debounce_timer.timeout.connect(_apply_to_target)
	bg.add_child(_debounce_timer)

func _apply_to_target():
	if _target == null or not _gather_func.is_valid(): return
	_target.apply_settings(_gather_func.call())
