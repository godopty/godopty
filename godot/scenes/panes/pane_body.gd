class_name PaneBody
extends Control
# Base class for all pane types — shared infrastructure for settings,
# serialization, and the pane settings panel.

signal title_changed(new_title: String)

@export var pane_name := ""
@export var font_size: int = 14:
	set(value):
		font_size = value
		if _font != null:
			_recompute_cell_metrics()


var pane_label: String = ""  # "T1", "C3", etc. Assigned by TerminalManager.
var _font: Font  # set by concrete types that render text

func _ready():
	add_to_group("panes")

func _recompute_cell_metrics():
	pass  # overridden by types that render text

func apply_settings(settings: Dictionary):
	for key in settings:
		var v = settings[key]
		match key:
			"pane_name": pane_name = v
			"font_size":  font_size = v
			_:            set(key, v)
	if settings.has("pane_name"):
		title_changed.emit(pane_name if pane_name != "" else _default_title())

func _default_title() -> String:
	return get_class()

func _get_layout_state() -> Dictionary:
	return {"type": _pane_type(), "pane_name": pane_name, "font_size": font_size}

func _pane_type() -> String:
	return "base"  # overridden by concrete types

# Override to add type-specific settings controls.
# `panel` provides `_debounce_timer` and `_gather_func` (set by each type).
func _build_pane_settings_ui(_panel: Control) -> Control:
	return VBoxContainer.new()
