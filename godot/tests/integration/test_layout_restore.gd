extends GutTest
# Integration tests: layout save/restore cycle.
# Verifies that tiles can be persisted and restored with correct types and settings.

var _tm: TerminalManager

func before_each():
	MockAutoloads.setup()
	SettingsManager.cfg_shell_command = "/bin/sh"
	SettingsManager.cfg_default_rows = 24
	SettingsManager.cfg_default_cols = 80
	_tm = TerminalManager.new()

func after_each():
	_tm.reset()
	MockAutoloads.teardown()

# ── Helper: gather tiles in LayoutManager format ───────────────────────

func _gather_tiles() -> Array[Dictionary]:
	var ts: Array[Dictionary] = []
	for t in _tm.tiles:
		var body = _tm._find_body(t.wrapper)
		var settings = body._get_layout_state() if body and body.has_method("_get_layout_state") else {}
		ts.append({
			"col": t.col, "row": t.row,
			"cspan": t.cspan, "rspan": t.rspan,
			"settings": settings,
		})
	return ts

# ── Round-trip tests ───────────────────────────────────────────────────

func test_save_restore_terminal():
	var body = _tm.spawn()
	assert_not_null(body)
	var saved = _gather_tiles()
	assert_eq(saved.size(), 1)
	assert_eq(saved[0].get("settings", {}).get("type"), "terminal")

	LayoutManager.save_tiles(saved)
	var loaded = LayoutManager.load_tiles()
	assert_eq(loaded.size(), 1)
	assert_eq(loaded[0].get("settings", {}).get("type"), "terminal")

func test_save_restore_mixed_types():
	var t1 = _tm.spawn_pane("terminal", {"pane_name": "Term1"})
	assert_not_null(t1)
	var t2 = _tm.spawn_pane("code_viewer", {"pane_name": "Code1"})
	assert_not_null(t2)

	var saved = _gather_tiles()
	assert_eq(saved.size(), 2)

	LayoutManager.save_tiles(saved)
	var loaded = LayoutManager.load_tiles()
	assert_eq(loaded.size(), 2)

	var types := []
	for td in loaded:
		types.append(td.get("settings", {}).get("type"))
	assert_true(types.has("terminal"), "loaded tiles should include terminal")
	assert_true(types.has("code_viewer"), "loaded tiles should include code_viewer")

func test_restore_preserves_settings():
	var body = _tm.spawn_pane("terminal", {"pane_name": "Custom", "rows": 30, "cols": 100})
	assert_not_null(body)

	var saved = _gather_tiles()
	LayoutManager.save_tiles(saved)
	var loaded = LayoutManager.load_tiles()

	var settings = loaded[0].get("settings", {})
	assert_eq(settings.get("pane_name"), "Custom")
	assert_eq(settings.get("rows"), 30)
	assert_eq(settings.get("cols"), 100)

func test_restore_legacy_no_type_key():
	# Simulate legacy layout data without "type" key
	var legacy: Array[Dictionary] = [{
		"col": 0, "row": 0, "cspan": 12, "rspan": 12,
		"settings": {"shell": "/bin/bash", "pane_name": "OldPane"},
	}]
	LayoutManager.save_tiles(legacy)
	var loaded = LayoutManager.load_tiles()
	assert_eq(loaded.size(), 1)
	# No "type" key: workspace defaults to "terminal"
	assert_eq(loaded[0].get("settings", {}).get("type", "terminal"), "terminal")

func test_load_tiles_empty_when_no_file():
	var loaded = LayoutManager.load_tiles()
	assert_eq(loaded, [], "should return empty when no file exists")
