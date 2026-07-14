extends GutTest
# Unit tests for SettingsManager — settings application to terminals,
# serialization, and signal emission.

var _scene: Control

func before_each():
	MockAutoloads.setup()
	_scene = TestScene.create()
	add_child(_scene)

func after_each():
	for c in _scene.get_children():
		c.queue_free()
	MockAutoloads.teardown()
	if _scene:
		_scene.queue_free()

# ── apply_to_terminal ──────────────────────────────────────────────────

func test_apply_to_terminal_sets_font_size():
	var body = PaneBody.new()
	_scene.add_child(body)

	SettingsManager.cfg_font_size = 16
	SettingsManager.apply_to_terminal(body)

	# font_size is declared on PaneBody, so the setter fires.
	assert_eq(body.font_size, 16)
	# cursor_shape, cursor_blink, scroll_lines are TerminalPane
	# properties; setting them on bare PaneBody via set() is a no-op
	# in Godot 4 (Control.set only handles known properties).
	# Those are covered by integration tests with real TerminalPanes.

func test_apply_pane_settings_delegates():
	var body = PaneBody.new()
	_scene.add_child(body)

	SettingsManager.apply_pane_settings(body, {"pane_name": "x"})
	assert_eq(body.pane_name, "x")

# ── Settings changed signal ────────────────────────────────────────────

func test_settings_changed_emits_on_save():
	watch_signals(SettingsManager)
	SettingsManager.save_settings()
	assert_signal_emitted(SettingsManager, "settings_changed")

# ── Save/load roundtrip ────────────────────────────────────────────────

func test_save_load_roundtrip():
	SettingsManager.cfg_shell_command = "/bin/zsh"
	SettingsManager.cfg_font_size = 20
	SettingsManager.cfg_cursor_shape = 2  # underline
	SettingsManager.save_settings()

	# Create a fresh SettingsManager to test load
	# (the mock's _read_file uses in-memory store, so it will see saved data)
	SettingsManager.cfg_shell_command = "overwritten"
	SettingsManager.cfg_font_size = 0
	SettingsManager.cfg_cursor_shape = 0
	SettingsManager.load_settings()

	assert_eq(SettingsManager.cfg_shell_command, "/bin/zsh")
	assert_eq(SettingsManager.cfg_font_size, 20)
	assert_eq(SettingsManager.cfg_cursor_shape, 2)

func test_load_settings_uses_defaults_when_empty():
	# Clear store and load — should keep compiled defaults
	SettingsManager.cfg_font_size = 14  # set a known default
	SettingsManager.load_settings()  # store is empty, so nothing changes
	assert_eq(SettingsManager.cfg_font_size, 14, "default should persist when no saved data")
