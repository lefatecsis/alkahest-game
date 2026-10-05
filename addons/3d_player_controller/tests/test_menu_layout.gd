extends GutTest

## Purpose: the pause, settings and controls menus size themselves to their buttons, the buttons fill the panel's width so a
## new one fits in like the rest, and every touch target keeps the size and place of the button it sits on.

const MENU_SCENES: Array[String] = [
	"res://addons/3d_player_controller/scenes/ui/pause.tscn",
	"res://addons/3d_player_controller/scenes/ui/settings.tscn",
	"res://addons/3d_player_controller/scenes/ui/controls_settings.tscn",
]


func test_menus_hug_their_buttons_and_buttons_fill_the_width() -> void:
	for path: String in MENU_SCENES:
		var menu: CanvasLayer = load(path).instantiate()
		add_child_autofree(menu)
		await wait_process_frames(2)
		var panel: Control = menu.get_node("Panel")
		var column: VBoxContainer = menu.get_node("Panel/VBoxContainer")
		assert_true(panel is PanelContainer, path + ": the panel is a container, so it grows with its buttons")
		assert_almost_eq(panel.size.x, column.size.x + 24.0, 0.5, path + ": the panel is the column plus its padding")
		assert_almost_eq(panel.size.y, column.size.y + 20.0, 0.5, path + ": no dead space above or below")
		assert_almost_eq(panel.position.x, (menu.get_viewport().get_visible_rect().size.x - panel.size.x) * 0.5, 0.5, path + ": centred")
		var buttons: int = 0
		for child: Node in column.get_children():
			if child is Button and (child as Button).visible:
				buttons += 1
				assert_almost_eq((child as Button).size.x, column.size.x, 0.5, path + ": " + child.name + " spans the column")
		assert_gt(buttons, 2, path + ": the buttons were found")


func test_touch_targets_match_their_buttons() -> void:
	for path: String in MENU_SCENES:
		var menu: CanvasLayer = load(path).instantiate()
		add_child_autofree(menu)
		await wait_process_frames(2)
		var touches: Array[Node] = menu.find_children("*", "TouchScreenButton", true, false)
		assert_gt(touches.size(), 2, path + ": the touch buttons were found")
		for found: Node in touches:
			var touch: TouchScreenButton = found as TouchScreenButton
			var host: Control = touch.get_parent()
			var shape: RectangleShape2D = touch.shape
			assert_eq(shape.size, host.size, path + ": " + host.name + "'s touch target is the button's size")
			assert_eq(touch.position, host.size * 0.5, path + ": and sits on its centre")
		var shapes: Array = touches.map(func(node: Node) -> Resource: return (node as TouchScreenButton).shape)
		assert_ne(shapes[0], shapes[1], path + ": each touch button owns its shape, so sizes do not bleed between buttons")
