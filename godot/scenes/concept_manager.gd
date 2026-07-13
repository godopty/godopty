extends Node

const CONCEPTS_FILE = "user://concepts.json"

signal concepts_changed

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_push_to_rust()

func _push_to_rust():
	var concepts = _load_from_file()
	if concepts.is_empty():
		return
	var t = GodoptyTerminal.new()
	t.set_global_concepts(concepts)

func _load_from_file() -> Array:
	if not FileAccess.file_exists(CONCEPTS_FILE):
		return []
	var f = FileAccess.open(CONCEPTS_FILE, FileAccess.READ)
	if not f:
		return []
	var j = JSON.new()
	if j.parse(f.get_as_text()) != OK:
		push_warning("[ConceptManager] Corrupt concepts.json, starting fresh")
		return []
	var d = j.get_data()
	if not (d is Dictionary and d.has("concepts")):
		return []
	var raw = d["concepts"]
	if not (raw is Array):
		return []
	return raw

func save_concepts(concepts: Array):
	var d = {"concepts": concepts}
	var f = FileAccess.open(CONCEPTS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
	concepts_changed.emit()
