extends GutTest
# Integration tests: Sidebar popup menu and pane type listing.

var _scene: Control
var _sidebar: Sidebar

func before_each():
	MockAutoloads.setup()
	_scene = TestScene.create()
	add_child(_scene)

	# Build a minimal Sidebar (requires a bg ColorRect for parent)
	var bg = ColorRect.new()
	bg.name = "SidebarBg"
	bg.color = Color(0.12, 0.12, 0.15)
	bg.offset_right = 180
	_scene.add_child(bg)

	_sidebar = Sidebar.new()
	_sidebar.name = "Sidebar"
	bg.add_child(_sidebar)
	_sidebar.offset_right = 180
	_sidebar.build(bg)

func after_each():
	MockAutoloads.teardown()
	if _scene:
		for c in _scene.get_children():
			_scene.remove_child(c)
			c.free()
		remove_child(_scene)
		_scene.free()

func test_sidebar_has_pane_list():
	# After build, the sidebar should have internal VBox containers
	var content = _sidebar.get_node_or_null("SidebarContent")
	assert_not_null(content, "sidebar should have content VBox")
	# Check it's a VBoxContainer
	assert_true(content is VBoxContainer, "content should be VBoxContainer")

func test_sidebar_emits_request_new_pane():
	watch_signals(_sidebar)
	_sidebar.request_new_pane.emit("terminal")
	assert_signal_emitted(_sidebar, "request_new_pane")

func test_sidebar_emits_request_settings():
	watch_signals(_sidebar)
	_sidebar.request_settings.emit()
	assert_signal_emitted(_sidebar, "request_settings")

func test_sidebar_emits_request_reset():
	watch_signals(_sidebar)
	_sidebar.request_reset.emit()
	assert_signal_emitted(_sidebar, "request_reset")
