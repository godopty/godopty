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

func add_profile(name: String, p_tiles: Array[Dictionary]):
	if name == "":
		return
	var base = name
	var n = 1
	while _find_by_name(name) != -1:
		n += 1
		name = "%s (%d)" % [base, n]
	profiles.append({"name": name, "tiles": p_tiles})
	save_profiles()

func update_profile(index: int, name: String, p_tiles: Array[Dictionary]):
	if index < 0 or index >= profiles.size():
		return
	profiles[index] = {"name": name, "tiles": p_tiles}
	save_profiles()

func delete_profile(index: int):
	if index < 0 or index >= profiles.size():
		return
	profiles.remove_at(index)
	save_profiles()

func get_profiles() -> Array[Dictionary]:
	return profiles

func _find_by_name(name: String) -> int:
	for i in profiles.size():
		if profiles[i].get("name", "") == name:
			return i
	return -1
