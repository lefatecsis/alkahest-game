extends GutTest
## Purpose: the UI Scale and On-Screen Controls settings. UI Scale drives the window's content_scale_factor, which
## scales the menus whatever the project's stretch mode is, with Auto following the window's shorter side; the
## on-screen controls show on touch only by default, and the Player restores that rule rather than showing outright.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var _backup: PackedByteArray
var _had_file: bool
var _factor_before: float


func before_each() -> void:
	_had_file = FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH)
	if _had_file:
		_backup = FileAccess.get_file_as_bytes(PlayerSettingsResource.SAVE_PATH)
		# Out of the way, not just backed up: a machine whose player picked Shown would otherwise fail the
		# tests that read the default rule
		DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
	PlayerSettingsResource._cached = null
	_factor_before = get_tree().root.content_scale_factor


func after_each() -> void:
	get_tree().root.content_scale_factor = _factor_before
	if _had_file:
		var file: FileAccess = FileAccess.open(PlayerSettingsResource.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_backup)
		file.close()
	else:
		DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
	PlayerSettingsResource._cached = null


func test_auto_scales_from_the_windows_shorter_side_and_never_shrinks() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.new()
	assert_eq(settings.ui_scale_index, 0, "Auto is the default")
	assert_almost_eq(settings.ui_scale_for(Vector2i(1280, 800)), 1.0, 0.001, "The design size draws as is")
	assert_almost_eq(settings.ui_scale_for(Vector2i(1920, 1200)), 1.5, 0.001, "A taller window scales up")
	assert_almost_eq(settings.ui_scale_for(Vector2i(3456, 2168)), 2.71, 0.001, "and a Retina screen more")
	assert_almost_eq(settings.ui_scale_for(Vector2i(1280, 720)), 1.0, 0.001, "A shorter one never shrinks the menus")
	assert_almost_eq(settings.ui_scale_for(Vector2i(64, 64)), 1.0, 0.001, "not even the headless window")


func test_a_chosen_scale_ignores_the_window() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.new()
	settings.ui_scale_index = 4
	assert_almost_eq(settings.ui_scale_for(Vector2i(1280, 800)), 2.0, 0.001, "200% is 200%")
	settings.ui_scale_index = 2
	assert_almost_eq(settings.ui_scale_for(Vector2i(3456, 2168)), 1.25, 0.001, "and 125% is 125%")


func test_apply_sets_the_windows_content_scale_factor_and_follows_resizes() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.new()
	var window: Window = get_tree().root
	settings.ui_scale_index = 3
	settings.apply_ui_scale(window)
	assert_almost_eq(window.content_scale_factor, 1.5, 0.001, "The window draws at 150%")
	settings.ui_scale_index = 0
	window.size_changed.emit() # what a resize does
	assert_almost_eq(window.content_scale_factor, settings.ui_scale_for(window.size), 0.001, "Auto re-measures on resize")
	assert_true(window.size_changed.is_connected(settings._on_window_resized), "connected once")
	settings.apply_ui_scale(window)
	assert_eq(window.size_changed.get_connections().filter(func(c: Dictionary) -> bool: return c.callable == Callable(settings, "_on_window_resized")).size(), 1, "and only once")


func test_ui_scale_and_hud_mode_persist() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.new()
	settings.ui_scale_index = 2
	settings.hud_mode = PlayerSettingsResource.HudMode.HIDDEN
	settings.save()
	PlayerSettingsResource._cached = null
	var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.ui_scale_index, 2, "UI scale persists")
	assert_eq(loaded.hud_mode, PlayerSettingsResource.HudMode.HIDDEN, "and so does the HUD mode")


func test_hud_shows_on_touch_only_by_default() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.new()
	assert_true(settings.hud_shown(Controls.InputType.TOUCH, true), "Touch players see the on-screen controls")
	assert_false(settings.hud_shown(Controls.InputType.TOUCH, false), "but not a desktop before its first key press, which the HUD also calls touch")
	assert_false(settings.hud_shown(Controls.InputType.KEYBOARD_MOUSE, true), "keyboard players do not")
	assert_false(settings.hud_shown(Controls.InputType.MICROSOFT, true), "nor do pad players")
	settings.hud_mode = PlayerSettingsResource.HudMode.SHOWN
	assert_true(settings.hud_shown(Controls.InputType.KEYBOARD_MOUSE, false), "Shown shows it everywhere")
	settings.hud_mode = PlayerSettingsResource.HudMode.HIDDEN
	assert_false(settings.hud_shown(Controls.InputType.TOUCH, true), "and Hidden hides it even on touch")


func test_the_player_follows_the_device_in_hand_and_the_setting() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)
	var touchscreen: bool = DisplayServer.is_touchscreen_available()
	player.controls.current_input_type = Controls.InputType.TOUCH
	assert_eq(not player.controls.contextual_only, touchscreen, "A touch player sees the HUD on a touchscreen")
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	assert_true(player.controls.contextual_only, "Picking up the keyboard leaves only the contextual hints")
	PlayerSettingsResource.load_or_create().hud_mode = PlayerSettingsResource.HudMode.SHOWN
	player.controls.hide() # something took the screen for a while
	player.apply_hud_visibility()
	assert_false(player.controls.contextual_only, "and giving it back restores the rule rather than the last state")
	PlayerSettingsResource.load_or_create().hud_mode = PlayerSettingsResource.HudMode.HIDDEN
	player.controls.current_input_type = Controls.InputType.TOUCH
	assert_true(player.controls.contextual_only, "Hidden wins over touch")


## The HUD node itself stays visible whatever the setting: a hidden HUD is the contextual-only one, so a prompt
## still pops its button in, and a demo can force the whole set with the override.
func test_a_hidden_hud_still_pops_contextual_hints_and_a_demo_can_force_it() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	settings.hud_mode = PlayerSettingsResource.HudMode.HIDDEN
	player.apply_hud_visibility()
	assert_true(player.controls.visible, "The node is never hidden outright")
	assert_true(player.controls.contextual_only)
	assert_false(player.controls.joypad_button_1.visible, "Resting, the Action button is off")
	player.controls.claim_action_label("Pick Up", self)
	assert_true(player.controls.joypad_button_1.visible, "A prompt's word brings its button in")
	player.controls.release_action_label(self)
	player.hud_mode_override = PlayerSettingsResource.HudMode.SHOWN
	assert_false(player.controls.contextual_only, "A demo forces the whole set")
	assert_true(player.controls.joypad_button_0.visible)
	player.hud_mode_override = -1
	assert_true(player.controls.contextual_only, "Back to the setting")
