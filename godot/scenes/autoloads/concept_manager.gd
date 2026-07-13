extends BasePersistenceManager

const CONCEPTS_FILE = "user://concepts.json"

signal concepts_changed

func _on_init():
	_push_to_rust()

func _push_to_rust():
	var concepts = _load_from_file()
	if concepts.is_empty():
		return
	var t = GodoptyTerminal.new()
	t.set_global_concepts(concepts)

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
