extends BasePersistenceManager

const CONCEPTS_FILE = "user://concepts.json"
const DEFAULTS_FILE = "res://concepts.default.json"

signal concepts_changed

func _on_init():
	_push_to_rust()

func _push_to_rust():
	var concepts = _merge_concepts()
	if concepts.is_empty():
		return
	var t = GodoptyTerminal.new()
	t.set_global_concepts(concepts)

func _merge_concepts() -> Array:
	var defaults = _load_defaults()
	var user = _load_from_file()
	# Build a name→index map for user concepts
	var user_map := {}
	for i in user.size():
		var c = user[i]
		if c is Dictionary:
			user_map[c.get("name", "")] = i
	# Merge: start with defaults, override with user entries
	var merged: Array = []
	for d in defaults:
		if not (d is Dictionary):
			continue
		var name = d.get("name", "")
		if name in user_map:
			merged.append(user[user_map[name]])
		else:
			merged.append(d)
	# Append user-only concepts (not in defaults)
	for i in user.size():
		var c = user[i]
		if not (c is Dictionary):
			continue
		# Already merged above — skip
		if c.get("name", "") in _default_names(defaults):
			continue
		merged.append(c)
	return merged

func _default_names(defaults: Array) -> Dictionary:
	var names := {}
	for d in defaults:
		if d is Dictionary:
			names[d.get("name", "")] = true
	return names

func _load_defaults() -> Array:
	if not FileAccess.file_exists(DEFAULTS_FILE):
		return []
	var f = FileAccess.open(DEFAULTS_FILE, FileAccess.READ)
	if not f:
		return []
	var text = f.get_as_text()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		return []
	var data = json.get_data()
	if not (data is Dictionary):
		return []
	var raw = data.get("concepts", [])
	if not (raw is Array):
		return []
	var result: Array = []
	for item in raw:
		if item is Dictionary:
			result.append(item)
	return result

func _load_from_file() -> Array:
	var d = _read_file(CONCEPTS_FILE)
	if d.is_empty():
		return []
	var raw = d.get("concepts", [])
	if not (raw is Array):
		return []
	return raw

func save_concepts(concepts: Array):
	var d = {"concepts": concepts}
	_write_file(CONCEPTS_FILE, d)
	concepts_changed.emit()
