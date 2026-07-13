extends Control
class_name FileTreePane
# Simple file tree pane — lists files in a directory.

@export var root_path := "/"

var _tree: Tree
var _dir: DirAccess

func _ready():
	add_to_group("panes")
	
	_tree = Tree.new()
	_tree.name = "FileTree"
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tree)
	_tree.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	_tree.create_item()
	_populate(_tree.get_root(), root_path)
	
	_tree.item_activated.connect(func():
		var item = _tree.get_selected()
		var path = item.get_metadata(0)
		if path and FileAccess.file_exists(path):
			OS.shell_open("file://" + path)
	)

func _populate(parent: TreeItem, path: String):
	var dir = DirAccess.open(path)
	if not dir: return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		var item = _tree.create_item(parent)
		item.set_text(0, file_name)
		var full = path.path_join(file_name)
		item.set_metadata(0, full)
		# TODO: add icon
		# if dir.current_is_dir():
			# item.set_icon(0, preload("res://icon.svg"))
		file_name = dir.get_next()
	dir.list_dir_end()

func _get_layout_state() -> Dictionary:
	return {"type": "file_tree", "root_path": root_path}
