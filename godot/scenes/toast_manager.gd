extends Control
# Toast Notification Manager — autoload singleton.
# Displays non-intrusive notifications at the bottom of the window.
# Designed for future extension: interactive actions, history, Rust→GDScript.
#
# Usage:
#   ToastManager.info("Terminal spawned")
#   ToastManager.warn("Pane too small")
#   ToastManager.error("PTY spawn failed")
#   # Advanced:
#   ToastManager.emit({text = "Custom", level = 0, duration = 5.0, source = "gdext"})

const INFO = 0
const WARN = 1
const ERROR = 2

# Data model: each toast is a Dictionary
#   text:     String      — display text
#   level:    int         — INFO/WARN/ERROR (controls color + default duration)
#   duration: float       — display time in seconds (default: 3 info, 5 warn, 8 error)
#   source:   String      — caller identifier for future filtering/history ("workspace", "gdext", "")
#   actions:  Array[Callable] — future: interactive buttons (not yet rendered)

signal toast_requested(data: Dictionary)

var _queue: Array[Dictionary] = []
var _active := false
var _toast_count := 0
var _current_label: Label = null
var _current_tween: Tween = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	toast_requested.connect(_enqueue)

# ── Public API (convenience) ─────────────────────────────────────────

func info(text: String, duration: float = 3.0, source := ""):
	_enqueue({text = text, level = INFO, duration = duration, source = source})

func warn(text: String, duration: float = 5.0, source := ""):
	_enqueue({text = text, level = WARN, duration = duration, source = source})

func error(text: String, duration: float = 8.0, source := ""):
	_enqueue({text = text, level = ERROR, duration = duration, source = source})

# ── Queue + Display ──────────────────────────────────────────────────

func _enqueue(data: Dictionary):
	if not data.has("text"): return
	# Replace current toast immediately instead of queuing
	if _active:
		_dismiss_current()
	_queue.append(data)
	_show_next()

func _dismiss_current():
	if _current_tween:
		_current_tween.kill()
		_current_tween = null
	if _current_label:
		_current_label.queue_free()
		_current_label = null
	_active = false

func _show_next():
	if _queue.is_empty():
		_active = false
		return
	_active = true
	var data = _queue.pop_front()
	_toast_count += 1

	var lbl = Label.new()
	lbl.name = "Toast%d" % _toast_count
	lbl.z_index = 100
	lbl.text = data.text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)

	match data.level:
		INFO:
			lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		WARN:
			lbl.add_theme_color_override("font_color", Color.YELLOW)
		ERROR:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	lbl.offset_top = -40
	lbl.offset_bottom = 0
	add_child(lbl)

	_current_label = lbl
	var duration: float = data.get("duration", 3.0)
	var t = create_tween()
	_current_tween = t
	t.tween_property(lbl, "modulate:a", 1.0, 0.0).from(0.0)
	t.tween_property(lbl, "modulate:a", 1.0, 0.2).from(0.0)
	t.tween_interval(duration)
	t.tween_property(lbl, "modulate:a", 0.0, 0.5)
	t.tween_callback(func():
		_current_label = null
		_current_tween = null)
	t.tween_callback(lbl.queue_free)
	t.tween_callback(_show_next)
