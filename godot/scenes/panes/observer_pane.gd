extends Control
class_name ObserverPane
# AI Observer pane — displays concept-triggered responses as formatted text.

@export var label_name := "observer"

var _terminal: GodoptyTerminal
var _display: RichTextLabel
var _shell_command := "/bin/bash"

func _ready():
	add_to_group("panes")
	
	_display = RichTextLabel.new()
	_display.name = "Display"
	_display.bbcode_enabled = true
	_display.fit_content = true
	_display.scroll_following = true
	_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_display)
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Spawn a shell with the observer label so concept events target it
	_terminal = GodoptyTerminal.new()
	_terminal.name = "GodoptyTerminal"
	add_child(_terminal)
	_terminal.start_shell(_shell_command, 24, 80, "")
	
	# Poll for output and append to display
	_fetch_output()

func _fetch_output():
	# Simple polling: read grid updates and append new text
	var gen = _terminal.get_grid_generation()
	var last_gen = -1
	while is_inside_tree():
		await get_tree().process_frame
		if not is_inside_tree():
			return
		var new_gen = _terminal.get_grid_generation()
		if new_gen != last_gen:
			last_gen = new_gen
			var updates = _terminal.get_grid_updates_packed(true)
			var chars: Array = updates.get("chars", [])
			for line in chars:
				var text: String = line.strip_edges(false, true)
				if text != "":
					_display.append_text("[color=#0f0]" + text + "[/color]\n")

func _get_layout_state() -> Dictionary:
	return {"shell": _shell_command, "rows": 24, "cols": 80, "label": label_name}
