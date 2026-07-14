extends BasePersistenceManager

const PROFILES_FILE = "user://profiles.json"

var profiles: Array[Dictionary] = []

signal profiles_changed

func _on_init():
	load_profiles()

func load_profiles():
	var d = _read_file(PROFILES_FILE)
	if d.is_empty(): return
	var raw: Array = d.get("profiles", [])
	profiles = []
	for item in raw:
		if item is Dictionary:
			profiles.append(item)

func save_profiles():
	var d = {"profiles": profiles}
	_write_file(PROFILES_FILE, d)
	profiles_changed.emit()

func add_profile(p_name: String, p_tiles: Array[Dictionary]):
	if p_name == "":
		return
	var result_name = p_name
	var base = p_name
	var n = 1
	while _find_by_name(result_name) != -1:
		n += 1
		result_name = "%s (%d)" % [base, n]
	profiles.append({"name": result_name, "tiles": p_tiles})
	save_profiles()

func update_profile(index: int, p_name: String, p_tiles: Array[Dictionary]):
	if index < 0 or index >= profiles.size():
		return
	profiles[index] = {"name": p_name, "tiles": p_tiles}
	save_profiles()

func delete_profile(index: int):
	if index < 0 or index >= profiles.size():
		return
	profiles.remove_at(index)
	save_profiles()

func get_profiles() -> Array[Dictionary]:
	return profiles

func _find_by_name(p_name: String) -> int:
	for i in profiles.size():
		if profiles[i].get("name", "") == p_name:
			return i
	return -1
