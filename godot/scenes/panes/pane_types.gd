class_name PaneTypes
# Registry of all pane types. Maps _pane_type() discriminator strings
# to display metadata. Consumers access PaneTypes.ALL directly.

static var ALL: Dictionary = {
	"terminal":    {"name": "Terminal",    "icon": ">_", "shortcut": "Ctrl+Shift+N"},
	"code_viewer": {"name": "Code Viewer", "icon": "{}", "shortcut": "Ctrl+Shift+V"},
	"file_tree":   {"name": "File Tree",   "icon": "/>", "shortcut": "Ctrl+Shift+T"},
	"observer":    {"name": "Observer",    "icon": "@",  "shortcut": "Ctrl+Shift+O"},
}
