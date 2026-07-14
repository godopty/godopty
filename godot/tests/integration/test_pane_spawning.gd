extends GutTest
# Integration tests: pane creation via TerminalManager with mock autoloads.
# Verifies that pane types, title labels, and options are wired correctly.

var _scene: Control
var _tm: TerminalManager

func before_each():
	MockAutoloads.setup()
	SettingsManager.cfg_shell_command = "/bin/sh"
	SettingsManager.cfg_default_rows = 24
	SettingsManager.cfg_default_cols = 80
	_scene = TestScene.create()
	add_child(_scene)
	_tm = TerminalManager.new()

func after_each():
	# Free wrapper nodes synchronously; they're not in the scene tree
	# (TerminalManager creates them but our test has no grid parent).
	for t in _tm.tiles:
		if t.wrapper:
			t.wrapper.free()
	_tm.tiles.clear()
	_tm.last_body = null
	MockAutoloads.teardown()
	if _scene:
		remove_child(_scene)
		_scene.free()

# ── Spawn terminal via TerminalManager ─────────────────────────────────

func test_spawn_terminal_creates_body():
	var body = _tm.spawn()
	assert_not_null(body, "spawn should return a body")
	assert_eq(_tm.tiles.size(), 1, "tiles should have 1 entry")
	var wrapper = _tm.tiles[0].wrapper
	assert_not_null(wrapper, "wrapper should exist")

	# Title bar label should contain "Terminal"
	var lbl = wrapper.get_node_or_null("BodyVBox/TitleBar/TitleLabel")
	assert_not_null(lbl, "title label should exist")
	assert_string_contains(lbl.text, "Terminal")

func test_spawn_terminal_body_is_terminal_pane():
	var body = _tm.spawn()
	assert_true(body is TerminalPane, "body should be TerminalPane")

# ── Spawn all pane types ───────────────────────────────────────────────

func test_spawn_all_four_types():
	# Verify each pane type via _pane_type() discriminator.
	var expected := ["terminal", "code_viewer", "file_tree", "observer"]
	for type_name in expected:
		_tm.reset()
		var body = _tm.spawn_pane(type_name, {})
		assert_not_null(body, "spawn_pane(%s) should return a body" % type_name)
		assert_eq(body._pane_type(), type_name, "body._pane_type() should be %s" % type_name)

func test_spawn_applies_rows_cols():
	var body = _tm.spawn_pane("terminal", {"rows": 30, "cols": 100})
	assert_not_null(body)
	# rows/cols are set on the body but may be overridden by resize
	# Just check they were applied initially
	assert_eq(body.rows, 30, "rows should be applied")
	assert_eq(body.cols, 100, "cols should be applied")

func test_spawn_sets_title_label():
	var body = _tm.spawn_pane("code_viewer", {})
	assert_not_null(body)
	var wrapper = _tm.tiles[-1].wrapper
	var lbl = wrapper.get_node_or_null("BodyVBox/TitleBar/TitleLabel")
	assert_not_null(lbl)
	assert_string_contains(lbl.text, "Code Viewer")

func test_pane_name_overrides_title():
	var body = _tm.spawn_pane("terminal", {"pane_name": "MyTerm", "title_label": "MyTerm"})
	assert_not_null(body)
	var wrapper = _tm.tiles[-1].wrapper
	var lbl = wrapper.get_node_or_null("BodyVBox/TitleBar/TitleLabel")
	assert_not_null(lbl)
	# The title label shows the title_label from opts
	assert_string_contains(lbl.text, "MyTerm")
