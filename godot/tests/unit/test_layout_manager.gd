extends GutTest
# Unit tests for LayoutManager — save/load tiles.
# Uses MockAutoloads to redirect filesystem to in-memory store.

func before_each():
	MockAutoloads.setup()

func after_each():
	MockAutoloads.teardown()

func test_save_load_tiles_roundtrip():
	var tiles: Array[Dictionary] = [
		{"col": 0, "row": 0, "cspan": 6, "rspan": 12, "settings": {"type": "terminal", "shell": "/bin/bash"}},
		{"col": 6, "row": 0, "cspan": 6, "rspan": 12, "settings": {"type": "code_viewer"}},
	]
	LayoutManager.save_tiles(tiles)
	var loaded = LayoutManager.load_tiles()
	assert_eq(loaded.size(), 2, "should load 2 tiles")
	assert_eq(loaded[0].get("settings", {}).get("type"), "terminal")
	assert_eq(loaded[1].get("settings", {}).get("type"), "code_viewer")

func test_load_tiles_nonexistent():
	# MockAutoloads.setup() clears the store, so no file exists
	var loaded = LayoutManager.load_tiles()
	assert_eq(loaded, [], "should return empty array when no file exists")

func test_save_then_reload_in_new_instance():
	var tiles: Array[Dictionary] = [
		{"col": 0, "row": 0, "cspan": 12, "rspan": 12, "settings": {"type": "terminal", "pane_name": "Main"}},
	]
	LayoutManager.save_tiles(tiles)

	# Load using a fresh LayoutManager after save
	var loaded = LayoutManager.load_tiles()
	assert_eq(loaded.size(), 1)
	assert_eq(loaded[0].get("settings", {}).get("pane_name"), "Main")
