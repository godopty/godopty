extends Node
# Focus Manager — autoload singleton for geographic pane navigation.

const AXIS_ALIGNED_THRESHOLD = 50
const DIAGONAL_PENALTY = 0.5

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	ShortcutManager.register("focus:left", "Alt+Left", func(): _shift_focus(Vector2(-1, 0)))
	ShortcutManager.register("focus:right", "Alt+Right", func(): _shift_focus(Vector2(1, 0)))
	ShortcutManager.register("focus:up", "Alt+Up", func(): _shift_focus(Vector2(0, -1)))
	ShortcutManager.register("focus:down", "Alt+Down", func(): _shift_focus(Vector2(0, 1)))

func _shift_focus(dir: Vector2):
	var current = get_viewport().gui_get_focus_owner()
	if current == null:
		return

	var panes_nodes = get_tree().get_nodes_in_group("panes")
	var panes: Array[Control] = []
	for n in panes_nodes: if n is Control: panes.append(n)
	if panes.is_empty(): return

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

func _pane_center(node: Control) -> Vector2:
	var rect = node.get_global_rect()
	return rect.position + rect.size * 0.5
