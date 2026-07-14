class_name TestScene
extends Node
# Test helper: creates a minimal scene tree environment for UI components.
# Adds a Control root so UI nodes have a parent and can measure/layout.

static func create() -> Control:
	var root = Control.new()
	root.name = "TestRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return root
