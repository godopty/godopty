extends Node
# Focus Manager — autoload singleton for geographic pane navigation.
# Listens for Alt+Arrow to jump to the nearest pane in that direction.

const AXIS_ALIGNED_THRESHOLD = 50
const DIAGONAL_PENALTY = 0.5

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)

func _input(event):
	if not (event is InputEventKey and event.pressed and event.alt_pressed):
		return

	var dir: Vector2
	match event.keycode:
		KEY_LEFT:  dir = Vector2(-1, 0)
		KEY_RIGHT: dir = Vector2(1, 0)
		KEY_UP:    dir = Vector2(0, -1)
		KEY_DOWN:  dir = Vector2(0, 1)
		_: return

	var current = get_viewport().gui_get_focus_owner()
	if current == null:
		return

	# Collect all focusable panes
	var panes: Array[Control] = _collect_panes(get_tree().root)
	if panes.is_empty():
		return

	# Find the geographically closest pane in the given direction
	var current_center = _pane_center(current)
	var best: Control = null
	var best_dist = INF

	for p in panes:
		if p == current:
			continue
		var pc = _pane_center(p)
		var delta = pc - current_center

		# Must be in the requested direction (with 45° tolerance)
		if dir.x < 0 and delta.x >= 0: continue
		if dir.x > 0 and delta.x <= 0: continue
		if dir.y < 0 and delta.y >= 0: continue
		if dir.y > 0 and delta.y <= 0: continue

		# Use Manhattan distance as tiebreaker; prefer straight-ahead panes
		var dist = abs(delta.x) + abs(delta.y)
		# Bonus for being axis-aligned (not diagonal)
		if abs(delta.x) < AXIS_ALIGNED_THRESHOLD or abs(delta.y) < AXIS_ALIGNED_THRESHOLD:
			dist *= DIAGONAL_PENALTY

		if dist < best_dist:
			best_dist = dist
			best = p

	if best != null:
		best.grab_focus()

func _collect_panes(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	if node is Control and node.focus_mode != Control.FOCUS_NONE:
		# Only collect leaf panes that are actual terminals (avoid containers)
		if node.get_script() != null:
			result.append(node)
	for child in node.get_children():
		result.append_array(_collect_panes(child))
	return result

func _pane_center(node: Control) -> Vector2:
	var rect = node.get_global_rect()
	return rect.position + rect.size * 0.5
