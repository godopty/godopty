extends Node

const SETTINGS_FILE = "user://settings.json"

const WRAPPER_BG_COLOR = Color(0.1, 0.1, 0.1, 1.0)
const TITLE_BAR_BG_COLOR = Color(0.18, 0.18, 0.20, 1.0)
const WRAPPER_BORDER_COLOR = Color(0.25, 0.25, 0.25, 0.6)
const SIDEBAR_BG_COLOR = Color(0.12, 0.12, 0.15, 1.0)

var cfg_cursor_shape := 0
var cfg_cursor_blink := true
var cfg_cursor_blink_speed := 0.5
var cfg_scroll_lines := 3
var cfg_default_rows := 24
var cfg_default_cols := 80
var cfg_beam_width := 2
var cfg_underline_height := 3
var cfg_wrapper_bg := WRAPPER_BG_COLOR
var cfg_title_bar_bg := TITLE_BAR_BG_COLOR
var cfg_wrapper_border := WRAPPER_BORDER_COLOR
var cfg_sidebar_bg := SIDEBAR_BG_COLOR
var cfg_focus_border := Color(0.4, 0.7, 1.0, 0.3)
var cfg_selection := Color(0.3, 0.5, 1.0, 0.4)
var cfg_scrollback_indicator := Color(1.0, 1.0, 0.0)
var cfg_color_scheme_path := ""
var cfg_max_fps := 0
var cfg_font_path := "res://fonts/DejaVuSansMono.ttf"
var cfg_font_size := 14

signal settings_changed

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()

func load_settings():
	if not FileAccess.file_exists(SETTINGS_FILE): return
	var f = FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if not f: return
	var j = JSON.new()
	if j.parse(f.get_as_text()) == OK and j.get_data() is Dictionary:
		var d: Dictionary = j.get_data()
		cfg_cursor_shape = d.get("cursor_shape", 0)
		cfg_cursor_blink = d.get("cursor_blink", true)
		cfg_cursor_blink_speed = d.get("cursor_blink_speed", 0.5)
		cfg_scroll_lines = d.get("scroll_lines", 3)
		cfg_default_rows = d.get("default_rows", 24)
		cfg_default_cols = d.get("default_cols", 80)
		cfg_beam_width = d.get("beam_width", 2)
		cfg_underline_height = d.get("underline_height", 3)
		cfg_wrapper_bg = _color_from_hex(d.get("wrapper_bg", ""), WRAPPER_BG_COLOR)
		cfg_title_bar_bg = _color_from_hex(d.get("title_bar_bg", ""), TITLE_BAR_BG_COLOR)
		cfg_wrapper_border = _color_from_hex(d.get("wrapper_border", ""), WRAPPER_BORDER_COLOR)
		cfg_sidebar_bg = _color_from_hex(d.get("sidebar_bg", ""), SIDEBAR_BG_COLOR)
		cfg_focus_border = _color_from_hex(d.get("focus_border", ""), Color(0.4, 0.7, 1.0, 0.3))
		cfg_selection = _color_from_hex(d.get("selection", ""), Color(0.3, 0.5, 1.0, 0.4))
		cfg_scrollback_indicator = _color_from_hex(d.get("scrollback_indicator", ""), Color(1.0, 1.0, 0.0))
		cfg_color_scheme_path = d.get("color_scheme", "")
		cfg_max_fps = d.get("max_fps", 0)
		cfg_font_path = d.get("font_path", "res://fonts/DejaVuSansMono.ttf")
		cfg_font_size = d.get("font_size", 14)

func save_settings():
	var d = {"cursor_shape": cfg_cursor_shape, "cursor_blink": cfg_cursor_blink, "cursor_blink_speed": cfg_cursor_blink_speed, "scroll_lines": cfg_scroll_lines, "default_rows": cfg_default_rows, "default_cols": cfg_default_cols, "beam_width": cfg_beam_width, "underline_height": cfg_underline_height, "wrapper_bg": cfg_wrapper_bg.to_html(), "title_bar_bg": cfg_title_bar_bg.to_html(), "wrapper_border": cfg_wrapper_border.to_html(), "sidebar_bg": cfg_sidebar_bg.to_html(), "focus_border": cfg_focus_border.to_html(), "selection": cfg_selection.to_html(), "scrollback_indicator": cfg_scrollback_indicator.to_html(), "color_scheme": cfg_color_scheme_path, "max_fps": cfg_max_fps, "font_path": cfg_font_path, "font_size": cfg_font_size}
	var f = FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))
	settings_changed.emit()

func apply_to_terminal(body: Control):
	body.cursor_shape = cfg_cursor_shape
	body.cursor_blink = cfg_cursor_blink
	body.cursor_blink_speed = cfg_cursor_blink_speed
	body.scroll_lines = cfg_scroll_lines
	body.rows = cfg_default_rows
	body.cols = cfg_default_cols
	body.beam_cursor_width = cfg_beam_width
	body.underline_cursor_height = cfg_underline_height
	body.focus_border_color = cfg_focus_border
	body.selection_color = cfg_selection
	body.scrollback_indicator_color = cfg_scrollback_indicator
	body.color_scheme_path = cfg_color_scheme_path
	body.font_path = cfg_font_path
	body.font_size = cfg_font_size
	body.max_fps = cfg_max_fps

func _color_from_hex(hex: String, fallback: Color) -> Color:
	if hex == "": return fallback
	return Color.from_string(hex, fallback)
