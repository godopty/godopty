extends Node
# Toast Notification Manager — autoload singleton.
# Pure event bus for non-intrusive notifications.

const INFO = 0
const WARN = 1
const ERROR = 2

signal toast_requested(data: Dictionary)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func info(text: String, duration: float = 3.0, source := ""):
	toast_requested.emit({text = text, level = INFO, duration = duration, source = source})

func warn(text: String, duration: float = 5.0, source := ""):
	toast_requested.emit({text = text, level = WARN, duration = duration, source = source})

func error(text: String, duration: float = 8.0, source := ""):
	toast_requested.emit({text = text, level = ERROR, duration = duration, source = source})
