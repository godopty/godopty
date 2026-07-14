extends GutTest
# Integration tests: Workspace palette commands.
# Tests that _build_palette_commands() includes all pane types.

func before_each():
	MockAutoloads.setup()

func after_each():
	MockAutoloads.teardown()

func test_palette_commands_include_all_types():
	var cmds = Workspace._build_palette_commands()
	assert_true(cmds.has("new terminal"), "should have new terminal")
	assert_true(cmds.has("new code viewer"), "should have new code viewer")
	assert_true(cmds.has("new file tree"), "should have new file tree")
	assert_true(cmds.has("new observer"), "should have new observer")

func test_palette_commands_include_actions():
	var cmds = Workspace._build_palette_commands()
	assert_true(cmds.has("close active"))
	assert_true(cmds.has("settings"))
	assert_true(cmds.has("reset layout"))

func test_pane_types_all_has_four_entries():
	assert_eq(PaneTypes.ALL.size(), 4)
	assert_true(PaneTypes.ALL.has("terminal"))
	assert_true(PaneTypes.ALL.has("code_viewer"))
	assert_true(PaneTypes.ALL.has("file_tree"))
	assert_true(PaneTypes.ALL.has("observer"))
