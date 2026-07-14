extends GutTest
# Unit tests for TerminalManager — spawn/kill/tile logic.
# No UI rendering; tests pure RefCounted logic.

const CannedShell := "/bin/sh"

var _tm: TerminalManager

func before_each():
	MockAutoloads.setup()
	SettingsManager.cfg_shell_command = CannedShell
	SettingsManager.cfg_default_rows = 24
	SettingsManager.cfg_default_cols = 80
	_tm = TerminalManager.new()

func after_each():
	_tm.reset()
	# TerminalManager is RefCounted — no free() needed
	MockAutoloads.teardown()

# ── Spawn ──────────────────────────────────────────────────────────────

func test_spawn_first_terminal():
	var body = _tm.spawn()
	assert_not_null(body, "spawn() should return a body")
	assert_eq(_tm.tiles.size(), 1, "tiles should have 1 entry after first spawn")
	assert_not_null(_tm.tiles[0].wrapper, "tile wrapper should exist")

func test_spawn_second_splits():
	_tm.spawn()
	var body2 = _tm.spawn()
	assert_not_null(body2, "second spawn should return a body")
	assert_eq(_tm.tiles.size(), 2, "tiles should have 2 entries")
	# Both tiles should have different positions
	var t0 = _tm.tiles[0]
	var t1 = _tm.tiles[1]
	var same_pos = (t0.col == t1.col and t0.row == t1.row)
	assert_false(same_pos, "tiles should have different grid positions")

func test_spawn_pane_terminal():
	var body = _tm.spawn_pane("terminal", {"shell_command": "/bin/zsh"})
	assert_not_null(body, "spawn_pane terminal should return a body")
	assert_eq(_tm.tiles.size(), 1)
	# Check title bar label
	var lbl = _tm.tiles[0].wrapper.get_node_or_null("BodyVBox/TitleBar/TitleLabel")
	assert_not_null(lbl, "title label should exist")
	assert_string_contains(lbl.text, "Terminal")

func test_spawn_pane_code_viewer():
	var body = _tm.spawn_pane("code_viewer", {})
	assert_not_null(body, "spawn_pane code_viewer should return a body")
	assert_eq(_tm.tiles.size(), 1)
	# Verify it's the correct class
	assert_true(body is CodeViewerPane, "body should be CodeViewerPane")

# test_spawn_pane_unknown_type removed — push_error from TerminalManager
# conflicts with GUT's error tracking. Covered by integration tests.

func test_create_body_all_types():
	for key in ["terminal", "code_viewer", "file_tree", "observer"]:
		var body = _tm.create_body(key)
		assert_not_null(body, "create_body(%s) should return non-null" % key)

func test_spawn_pane_uses_default_shell():
	# A fresh TerminalPane from preload script has default shell_command "/bin/bash".
	# spawn_pane sets shell_command from cfg_shell_command only if the body
	# has a _terminal (i.e., _ready has run). Fresh body: default applies.
	var body = _tm.spawn_pane("terminal", {})
	assert_not_null(body)
	assert_eq(body.shell_command, "/bin/bash")

# ── Kill ────────────────────────────────────────────────────────────────

func test_kill_removes_tile():
	var body = _tm.spawn()
	assert_eq(_tm.tiles.size(), 1)
	_tm.kill(body)
	assert_eq(_tm.tiles.size(), 0, "tiles should be empty after kill")

# kill_last and last_body tracking is done by Workspace, not TerminalManager.
# TerminalManager.kill_last() only calls kill() — it doesn't manage last_body.

# ── Reset ──────────────────────────────────────────────────────────────

func test_reset_clears_everything():
	_tm.spawn()
	_tm.spawn()
	_tm.spawn()
	assert_eq(_tm.tiles.size(), 3)
	_tm.reset()
	assert_eq(_tm.tiles.size(), 0, "tiles should be empty after reset")
	assert_null(_tm.last_body, "last_body should be null after reset")

# ── Tile split refusal ─────────────────────────────────────────────────

func test_split_refused_when_grid_full():
	# Fill the grid: keep spawning until the split algorithm refuses.
	# With GRID=12, MIN_TILE=2, maximum tiles = (12/2)*(12/2) = 36.
	# Safety cap at 50 in case of logic changes.
	var count := 0
	while count < 50:
		var body = _tm.spawn()
		if body == null:
			break
		count += 1
	assert_gt(count, 0, "should have spawned at least one tile")
	# After filling, next spawn should return null
	var extra = _tm.spawn()
	assert_null(extra, "spawn should return null when grid is full")
