extends Node

const PROFILES_FILE = "user://profiles.json"

var profiles: Array[Dictionary] = []

signal profiles_changed

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_profiles()

func load_profiles():
	if not FileAccess.file_exists(PROFILES_FILE):
		return
	var f = FileAccess.open(PROFILES_FILE, FileAccess.READ)
	if not f:
		return
	var j = JSON.new()
	var err = j.parse(f.get_as_text())
	if err != OK:
		push_warning("[ProfileManager] Corrupt profiles.json, resetting to empty")
		profiles = []
		return
	var d = j.get_data()
	if not (d is Dictionary and d.has("profiles")):
		profiles = []
		return
	var raw: Array = d["profiles"]
	profiles = []
	for item in raw:
		if item is Dictionary:
			profiles.append(item)

func save_profiles():
	var d = {"profiles": profiles}
	var f = FileAccess.open(PROFILES_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
	profiles_changed.emit()

func add_profile(name: String, p_tiles: Array[Dictionary]):
	if name == "":
		return
	# Duplicate name? Append suffix
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
