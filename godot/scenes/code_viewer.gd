extends Control
class_name CodeViewerPane
# Simple read-only code viewer with syntax highlighting.

@export var file_path := ""
@export var language := ""

var _editor: CodeEdit

func _ready():
	add_to_group("panes")
	
	_editor = CodeEdit.new()
	_editor.name = "CodeEdit"
	_editor.editable = false
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_editor)
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	if file_path != "":
		load_file(file_path)

func load_file(path: String):
	file_path = path
	if not FileAccess.file_exists(path): return
	var f = FileAccess.open(path, FileAccess.READ)
	if not f: return
	var text = f.get_as_text()
	_editor.text = text
	
	# Basic syntax detection from extension
	var ext = path.get_extension().to_lower()
	match ext:
		"gd": _editor.add_comment_string("#")
		"py": _editor.add_comment_string("#")
		"rs": _editor.add_comment_string("//")
		"c", "cpp", "h", "hpp": _editor.add_comment_string("//")

func _get_layout_state() -> Dictionary:
	return {"type": "code_viewer", "file_path": file_path, "language": language}
