extends GutHookScript
## Runs before the suite. A headless window is 64 pixels square and cannot be resized, and the game no longer
## sets a stretch mode (the HUD sizes itself to the window instead), so without this the fixed-size menus
## would have no canvas to lay out on. The tests get the design size back by turning the stretch on for the
## run only, which is what a real window of that size would give them.


func run() -> void:
	var root: Window = gut.get_tree().root
	root.content_scale_size = Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
