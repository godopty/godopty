extends Node

const LAYOUT_FILE = "user://layout.json"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func save_tiles(tiles: Array[Dictionary]):
	var d = {"tiles": tiles}
	var f = FileAccess.open(LAYOUT_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func load_tiles() -> Array[Dictionary]:
	if not FileAccess.file_exists(LAYOUT_FILE):
		return []
	var f = FileAccess.open(LAYOUT_FILE, FileAccess.READ)
	if not f:
		return []
	var j = JSON.new()
	if j.parse(f.get_as_text()) != OK:
		return []
	var d = j.get_data()
	if not (d is Dictionary and d.has("tiles")):
		return []
	# JSON.parse() returns untyped Array — build typed Array[Dictionary]
	var raw: Array = d["tiles"]
	var result: Array[Dictionary] = []
	for item in raw:
		if item is Dictionary:
			result.append(item)
	return result
