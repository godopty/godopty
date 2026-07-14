extends Node
# Autoload: polls GitHub Releases on startup, notifies if update available.
# Non-blocking — runs in background, degrades silently on network errors.

const REPO_OWNER := "you"
const REPO_NAME := "godopty"
const RELEASES_URL := "https://api.github.com/repos/%s/%s/releases/latest"

var _http: HTTPRequest

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_check()

func _check():
	var current = ProjectSettings.get_setting("application/config/version", "0.0.0")
	if current == "0.0.0":
		return  # dev build, skip

	# Skip update check when installed via system package manager
	# (AUR, apt, dnf, etc.) — updates come through the package manager.
	if OS.get_executable_path().begins_with("/usr/"):
		return
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_response.bind(current))
	var url = RELEASES_URL % [REPO_OWNER, REPO_NAME]
	_http.request(url, ["Accept: application/vnd.github+json"])

func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, current: String):
	if code != 200:
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		return
	var latest = json.get("tag_name", "").lstrip("v")
	if latest == "" or latest == current:
		return

	# Compare semver — only notify if strictly newer
	if not _is_newer(latest, current):
		return

	var html_url = json.get("html_url", "https://github.com/%s/%s/releases" % [REPO_OWNER, REPO_NAME])
	ToastManager.info("Update available: v%s → v%s" % [current, latest])
	# TODO: add clickable link or dialog to open html_url

	_http.queue_free()

func _is_newer(latest: String, current: String) -> bool:
	var la = latest.split(".")
	var ca = current.split(".")
	var n = mini(la.size(), ca.size())
	for i in n:
		var lv = la[i].to_int()
		var cv = ca[i].to_int()
		if lv > cv: return true
		if lv < cv: return false
	return la.size() > ca.size()
