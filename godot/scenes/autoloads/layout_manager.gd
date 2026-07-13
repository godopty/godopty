extends BasePersistenceManager

const LAYOUT_FILE = "user://layout.json"

func save_tiles(tiles: Array[Dictionary]):
	var d = {"tiles": tiles}
	_write_file(LAYOUT_FILE, d)

func load_tiles() -> Array[Dictionary]:
	var d = _read_file(LAYOUT_FILE)
	if d.is_empty():
		return []
	var raw: Array = d.get("tiles", [])
	var result: Array[Dictionary] = []
	for item in raw:
		if item is Dictionary:
			result.append(item)
	return result
