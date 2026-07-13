class_name BasePersistenceManager
extends Node

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_on_init()

func _on_init():
	pass

func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var j = JSON.new()
	if j.parse(f.get_as_text()) != OK:
		push_warning("[%s] Corrupt %s, starting fresh" % [name, path])
		return {}
	var d = j.get_data()
	if not (d is Dictionary):
		return {}
	return d

func _write_file(path: String, data: Dictionary):
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
