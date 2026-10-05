extends GutTest

## Purpose: The Player answers to one of two pad layouts. Zelda is the scene's own: A is Action, B Sprint,
## X Attack, Y Jump, and Focus locks on. GTA, which ships with the gta addon rather than here, moves the face
## buttons about (A Sprint, B Attack, X Jump,
## Y Action) and makes Focus a free over-the-shoulder aim. The switch works mid-game, from the export or
## from the saved settings, and the buttons come off the actions they used to stand for.
##
## The GTA layout is built here with the values of the gta addon's gta.tres rather than preloaded from it, so this
## suite runs without that addon installed: the player controller never loads out of another addon.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var player: Player
var gta: ControlScheme
var _had_file: bool = false
var _backup: PackedByteArray = PackedByteArray()


## The settings are read off user://settings.tres on ready and the menu writes it, so the real file is put aside
## for the test and put back afterwards, the way test_settings_persistence does.
func before_each() -> void:
	_had_file = FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH)
	if _had_file:
		_backup = FileAccess.get_file_as_bytes(PlayerSettingsResource.SAVE_PATH)
		DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
	PlayerSettingsResource._cached = null
	gta = _gta_scheme()
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(20.0, 1.0, 20.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await wait_physics_frames(2)


func after_each() -> void:
	# Registrations are static, so they outlive the scene too and would leak into the next script
	PlayerControls.forget_registered_schemes()
	# The InputMap outlives the scene: put the pad back the way the other suites expect it
	if is_instance_valid(player):
		player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")
	if _had_file:
		var file: FileAccess = FileAccess.open(PlayerSettingsResource.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_backup)
		file.close()
	elif FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH):
		DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
	PlayerSettingsResource._cached = null


## The gta addon's gta.tres, value for value: A Sprint, B Attack, X Jump, Y Action, its pad beyond the faces, its
## own words on the buttons, and a free aim.
func _gta_scheme() -> ControlScheme:
	var scheme := ControlScheme.new()
	scheme.scheme_name = "GTA"
	scheme.action_button_0 = &"sprint"
	scheme.action_button_1 = &"attack"
	scheme.action_button_2 = &"jump"
	scheme.action_button_3 = &"action"
	scheme.extra_slots = {
		"axis_4_plus": &"focus",
		"axis_5_plus": &"shoot",
		"button_10": &"throw",
		"button_13": &"last_weapon",
		"button_14": &"next_weapon",
		"button_7": &"crouch",
		"button_8": &"scope",
		"button_9": &"seeker",
	}
	scheme.slot_labels = {
		"axis_4_plus": "Aim",
		"axis_5_plus": "Fire",
		"button_0": "Sprint",
		"button_1": "Melee",
		"button_10": "Cover",
		"button_2": "Jump",
		"button_3": "Enter",
		"button_7": "Stealth",
		"button_8": "Zoom",
		"button_9": "Weapons",
	}
	scheme.locks_on = false
	return scheme


func _has_button(action: StringName, button: JoyButton) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return true
	return false


func test_zelda_is_the_default_layout() -> void:
	assert_eq(player.control_scheme, preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres"))
	# Tears of the Kingdom's own layout. Its labels are Nintendo's, whose A is the right button and B the
	# bottom, mirrored from the Xbox naming Godot uses: the game's "A Action" is JOY_BUTTON_B here and its
	# "B Dash" is JOY_BUTTON_A.
	assert_true(_has_button(&"sprint", JOY_BUTTON_A), "The bottom button dashes, as B does in the game")
	assert_true(_has_button(&"action", JOY_BUTTON_B), "The right button is Action, as A is in the game")
	assert_true(_has_button(&"attack", JOY_BUTTON_X), "The left button attacks, as Y does in the game")
	assert_true(_has_button(&"jump", JOY_BUTTON_Y), "The top button jumps, as X does in the game")
	assert_true(player.lock_on_enabled(), "Zelda locks on")
	assert_eq(player.controls.joypad_button_0_label.text, "Dash", "Tears of the Kingdom calls it Dash, not Sprint")


func test_gta_moves_the_face_buttons_and_frees_the_aim() -> void:
	player.control_scheme = gta
	assert_true(_has_button(&"sprint", JOY_BUTTON_A), "A is Sprint")
	assert_true(_has_button(&"attack", JOY_BUTTON_B), "B is Attack")
	assert_true(_has_button(&"jump", JOY_BUTTON_X), "X is Jump")
	assert_true(_has_button(&"action", JOY_BUTTON_Y), "Y is Action")
	assert_false(_has_button(&"action", JOY_BUTTON_A), "A no longer does Action")
	assert_false(_has_button(&"sprint", JOY_BUTTON_B), "B no longer sprints")
	assert_false(player.lock_on_enabled(), "GTA aims freely")
	assert_eq(player.controls.joypad_button_0_label.text, "Sprint", "The resting label follows the button, in GTA's own word")
	assert_eq(player.controls.joypad_button_3_label.text, "Enter", "GTA puts Enter Vehicle on the top button")
	assert_true(InputMap.action_get_events(&"sprint").any(func(e: InputEvent) -> bool: return e is InputEventKey), "The keyboard key stays on the action")


func test_switching_back_restores_zelda() -> void:
	player.control_scheme = gta
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")
	assert_true(_has_button(&"sprint", JOY_BUTTON_A))
	assert_false(_has_button(&"action", JOY_BUTTON_A))
	assert_true(_has_button(&"jump", JOY_BUTTON_Y))
	assert_eq(player.controls.joypad_button_0_label.text, "Dash")


func test_focus_never_locks_on_under_gta() -> void:
	var target := StaticBody3D.new()
	target.add_to_group("Focusable")
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	target.add_child(shape)
	player.get_parent().add_child(target)
	target.global_position = player.global_position + Vector3(0.0, 1.0, -2.0)
	await wait_physics_frames(2)
	player.control_scheme = gta
	Input.action_press("focus")
	await wait_physics_frames(3)
	assert_null(player.current_focus_target, "Free aim acquires nobody")
	Input.action_release("focus")
	await wait_physics_frames(1)
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")
	Input.action_press("focus")
	await wait_physics_frames(3)
	assert_eq(player.current_focus_target, target, "Lock-on is back with Zelda")
	Input.action_release("focus")
	await wait_physics_frames(1)


func test_saved_setting_overrides_the_scene() -> void:
	# GTA ships with the gta addon, so a game offers it by registering it; nothing here loads across addons
	PlayerControls.register_scheme(gta)
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	settings.control_scheme_name = "GTA"
	settings.apply_control_scheme(player)
	assert_eq(player.control_scheme, gta)
	settings.control_scheme_name = ""
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")
	settings.apply_control_scheme(player)
	assert_eq(player.control_scheme, preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres"), "Game Default leaves the scene's choice")


func test_the_controls_settings_menu_lists_the_schemes() -> void:
	var menu: OptionButton = player.controls_settings.get_node("Panel/VBoxContainer/ControlScheme")
	assert_eq(menu.item_count, PlayerControls.BUILT_IN_SCHEMES.size(), "The layouts that ship here, and no redundant Default beside them")
	assert_eq(menu.get_item_text(0), "TotK")
	assert_eq(menu.get_item_text(1), "SMO")
	assert_eq(menu.selected, 0, "Nothing saved, so it shows the layout the Player is actually using")

	player.controls_settings._on_control_scheme_item_selected(1)
	assert_eq(player.control_scheme, preload("res://addons/3d_player_controller/resources/control_schemes/super_mario_odyssey.tres"),
		"Picking one in the menu lays the pad out that way at once")
	assert_eq(player.controls.action_button_0, &"jump", "Jump is on the bottom button")

	# A layout another addon ships joins the list the moment it registers, without this menu knowing about it
	PlayerControls.register_scheme(gta)
	player.controls_settings._fill_scheme_button()
	assert_eq(menu.item_count, PlayerControls.BUILT_IN_SCHEMES.size() + 1, "and a registered layout is offered too")
	var last: int = menu.item_count - 1
	assert_eq(menu.get_item_text(last), "GTA", "at the end, after the built-in ones")
	player.controls_settings._on_control_scheme_item_selected(last)
	assert_eq(player.control_scheme, gta)


## The layout lives under Settings > Controls, beside the on-screen controls, not among the video options.
func test_the_settings_menu_reaches_the_controls_page_and_back() -> void:
	player.settings.show_menu()
	player.settings._on_controls_pressed()
	assert_false(player.settings.visible, "The hub gives way to the page")
	assert_true(player.controls_settings.visible, "The Controls page is up")
	assert_null(player.video_settings.get_node_or_null("Panel/VBoxContainer/ControlScheme"), "The Video page no longer carries the layout")
	assert_null(player.video_settings.get_node_or_null("Panel/VBoxContainer/OnScreenControls"), "nor the on-screen controls")
	player.controls_settings._on_back_pressed()
	assert_false(player.controls_settings.visible, "BACK closes the page")
	assert_true(player.settings.visible, "and returns to the hub")
	player.settings.hide_menu()


## The point of a scheme being a resource: a game ships its own layout without editing this addon. Built here in
## code rather than loaded from a .tres, because a game's file would not be in the addon to load.
func test_a_game_can_ship_a_layout_of_its_own() -> void:
	var southpaw := ControlScheme.new()
	southpaw.scheme_name = "Southpaw"
	southpaw.action_button_0 = &"attack"
	southpaw.action_button_1 = &"jump"
	southpaw.action_button_2 = &"action"
	southpaw.action_button_3 = &"sprint"
	southpaw.locks_on = false

	player.control_scheme = southpaw

	assert_true(_has_button(&"attack", JOY_BUTTON_A), "A is whatever the game's scheme says")
	assert_true(_has_button(&"jump", JOY_BUTTON_B))
	assert_true(_has_button(&"action", JOY_BUTTON_X))
	assert_true(_has_button(&"sprint", JOY_BUTTON_Y))
	assert_false(_has_button(&"action", JOY_BUTTON_A), "and A came off the action it used to carry")
	assert_false(player.lock_on_enabled(), "The scheme decides the aim too, not a name this addon knows")
	assert_eq(player.controls.joypad_button_0_label.text, "Attack", "The resting label follows")


## Whether Focus locks on is something a scheme carries rather than a comparison against the Zelda one, which is
## what it used to be. Super Mario Odyssey has no lock-on, so the Platformer layout does not either.
func test_the_scheme_carries_whether_focus_locks_on() -> void:
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")
	assert_true(player.lock_on_enabled(), "Zelda locks on")
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/super_mario_odyssey.tres")
	assert_false(player.lock_on_enabled(), "Odyssey has no lock-on, so neither does Platformer")
	player.control_scheme = gta
	assert_false(player.lock_on_enabled())


## A name nothing answers to is not an error: the layout was renamed or its addon was uninstalled, so the
## Player keeps whatever its scene set. There is no migration of older settings files; the format moved on.
func test_a_name_nothing_answers_to_leaves_the_scene_alone() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	settings.control_scheme_name = "Platformer" # what SMO used to be called
	var scene_set: ControlScheme = player.control_scheme

	settings.apply_control_scheme(player)

	assert_null(settings.picked_scheme(), "Nothing answers to it")
	assert_eq(player.control_scheme, scene_set, "so the scene's own layout stands")


## An addon ships a layout without the player controller preloading out of it, which it must not do: the
## template would then depend on an addon that may not be installed.
func test_a_registered_scheme_is_offered_and_saved_by_name() -> void:
	var southpaw := ControlScheme.new()
	southpaw.scheme_name = "Southpaw"
	southpaw.action_button_0 = &"attack"
	southpaw.action_button_1 = &"jump"
	southpaw.action_button_2 = &"action"
	southpaw.action_button_3 = &"sprint"

	PlayerControls.register_scheme(southpaw)
	PlayerControls.register_scheme(southpaw) # twice is once

	assert_true(PlayerControls.schemes().has(southpaw), "It joins what the menu offers")
	assert_eq(PlayerControls.schemes().count(southpaw), 1, "and only once")
	assert_eq(PlayerControls.scheme_named("Southpaw"), southpaw, "and answers to its name")

	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	settings.control_scheme_name = "Southpaw"
	settings.apply_control_scheme(player)
	assert_eq(player.control_scheme, southpaw, "so a saved pick finds it")
	assert_true(_has_button(&"attack", JOY_BUTTON_A), "and the pad is laid out its way")

	PlayerControls.forget_registered_schemes()
	settings.control_scheme_name = ""
	assert_null(PlayerControls.scheme_named("Southpaw"), "Forgotten, nothing answers to it")


## Most games put verbs on the shoulders and triggers that this addon keeps on the faces, so a layout can move
## any slot, not just the four. Dark Souls is the case that needed it: it attacks on the right trigger.
func test_a_layout_can_move_the_shoulders_and_triggers() -> void:
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/dark_souls.tres")

	assert_true(_has_trigger(&"attack", JOY_AXIS_TRIGGER_RIGHT), "Dark Souls attacks on the right trigger")
	assert_false(_has_button(&"attack", JOY_BUTTON_X), "and not on the face button this addon usually uses")
	assert_true(_has_button(&"scope", JOY_BUTTON_LEFT_SHOULDER), "Its guard button is the left shoulder")
	assert_true(_has_button(&"focus", JOY_BUTTON_RIGHT_STICK), "and lock-on is the right stick, as the game has it")


## A slot one layout moved is handed back when a layout that says nothing about it comes on, or the last
## layout's reach would survive into the next one.
func test_a_moved_slot_is_handed_back() -> void:
	var before: StringName = player.controls.action_axis_5_plus

	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/dark_souls.tres")
	assert_eq(player.controls.action_axis_5_plus, &"attack", "Dark Souls takes the right trigger")

	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")
	assert_eq(player.controls.action_axis_5_plus, before, "and Tears of the Kingdom, which says nothing about it, gives it back")
	assert_true(_has_button(&"attack", JOY_BUTTON_X), "with attack back on the face button it belongs to")


## Whether [param action] answers to a trigger, which is an axis rather than a button.
func _has_trigger(action: StringName, axis: JoyAxis) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == axis:
			return true
	return false


## A layout is the whole pad of the game it is named after, not a patch on top of the scene's. Metal Gear had
## nothing on the stick clicks and nobody to whistle at, so those buttons come off the screen with their labels
## empty rather than quietly keeping Tears of the Kingdom's binding.
func test_a_layout_clears_the_slots_its_game_never_had() -> void:
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/metal_gear.tres")

	assert_eq(player.controls.action_button_12, &"", "The d-pad has no Whistle on it")
	assert_eq(player.controls.joypad_button_12_label.text, "", "and the label it used to carry is empty")
	assert_false(_has_button(&"whistle", JOY_BUTTON_DPAD_DOWN), "so the pad no longer whistles")
	assert_eq(player.controls.action_button_7, &"", "The PlayStation pad Metal Gear shipped on clicked no sticks")
	assert_eq(player.controls.action_button_9, &"last_weapon", "What the game did have is still bound")


## The sticks, Start, Screenshot and Perspective are this addon's own rather than any game's verbs, so no layout
## takes them away; a game that never had a first-person toggle still has one here.
func test_the_addons_own_slots_survive_every_layout() -> void:
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/metal_gear.tres")

	assert_eq(player.controls.action_button_6, &"start", "Pause stays")
	assert_eq(player.controls.action_button_15, &"share", "Screenshot stays")
	assert_eq(player.controls.action_button_4, &"perspective", "Perspective stays")
	assert_eq(player.controls.action_move_up, &"move_up", "and both sticks stay")
	assert_eq(player.controls.action_look_left, &"look_left")


## Clearing is not one-way: the next layout that has the slot puts it back, button, binding and label.
func test_a_cleared_slot_comes_back_with_a_layout_that_has_it() -> void:
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/metal_gear.tres")
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")

	assert_eq(player.controls.action_button_12, &"whistle")
	assert_true(_has_button(&"whistle", JOY_BUTTON_DPAD_DOWN))
	assert_eq(player.controls.joypad_button_12_label.text, "Whistle")


## A button says what it does in the words of the game the layout is named after, not this addon's name for
## the action underneath. Metal Gear's manual calls the left shoulder Change Item, so it does not read Last
## Weapon, and the action it fires is still last_weapon.
## The key face a slot of the keyboard set is drawn with, by file name.
func _key_face(slot: String) -> String:
	var button: TouchScreenButton = player.controls.get("joypad_" + slot)
	return button.texture_normal.resource_path.get_file()


## The keyboard set draws each button as the key behind the action it carries, so a layout that moves an action
## moves its key with it: Zelda sprints on the bottom button, so that button is [Shift] there, and Dark Souls
## interacts on it, so there it is [E]. The shoulders, triggers and stick clicks follow the same way.
func test_the_keyboard_set_draws_the_key_behind_each_button() -> void:
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	assert_eq(_key_face("button_0"), "keyboard_shift_icon_outline.svg", "Zelda sprints on the bottom button")
	assert_eq(_key_face("button_1"), "keyboard_e_outline.svg", "and interacts on the right one")
	assert_eq(_key_face("axis_5_plus"), "mouse_left_outline.svg", "Its right trigger shoots")

	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/dark_souls.tres")
	assert_eq(_key_face("button_0"), "keyboard_e_outline.svg", "Dark Souls interacts on the bottom button")
	assert_eq(_key_face("button_1"), "keyboard_shift_icon_outline.svg", "and sprints on the right one")
	assert_eq(_key_face("axis_5_plus"), "keyboard_alt_outline.svg", "Its right trigger attacks, which is Alt on the keyboard")
	assert_eq(_key_face("button_8"), "mouse_right_outline.svg", "and its right stick locks on, the right mouse button")
	assert_eq(_key_face("button_9"), "mouse_scroll_outline.svg", "Its left shoulder guards, the scope's wheel")

	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")
	assert_eq(_key_face("button_0"), "keyboard_shift_icon_outline.svg", "Back on Zelda the bottom button is [Shift] again")
	assert_eq(_key_face("button_1"), "keyboard_e_outline.svg")
	assert_eq(_key_face("axis_5_plus"), "mouse_left_outline.svg")
	assert_eq(_key_face("button_8"), "mouse_scroll_outline.svg", "and the right stick is the scope's wheel")


func test_a_layout_names_its_buttons_in_the_games_own_words() -> void:
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/metal_gear.tres")

	assert_eq(player.controls.joypad_button_9_label.text, "Item", "The left shoulder changes items, as the manual puts it")
	assert_eq(player.controls.action_button_9, &"last_weapon", "and the action underneath is untouched")
	assert_eq(player.controls.joypad_button_0_label.text, "Duck", "Cross ducks down")
	assert_eq(player.controls.joypad_button_2_label.text, "Fire", "Square fires the weapon")


## Most of Tears of the Kingdom's pad is where the scene already put it, so the renaming has to happen even
## when the binding does not change: the left stick is Stealth, not Crouch, though both fire crouch.
func test_a_slot_is_renamed_even_where_its_binding_is_unchanged() -> void:
	player.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")

	assert_eq(player.controls.action_button_7, &"crouch")
	assert_eq(player.controls.joypad_button_7_label.text, "Stealth")
	assert_eq(player.controls.joypad_button_8_label.text, "Telescope")
	assert_eq(player.controls.joypad_button_12_label.text, "Whistle")


func test_the_saved_scheme_is_on_the_hud_from_the_first_frame() -> void:
	var saved: PlayerSettingsResource = PlayerSettingsResource.new()
	saved.control_scheme_name = "WoW"
	saved.save()
	PlayerSettingsResource._cached = null
	var fresh: Player = PLAYER_SCENE.instantiate()
	player.get_parent().add_child(fresh)
	await wait_physics_frames(1)
	assert_eq(fresh.control_scheme.scheme_name, "WoW", "The Player takes the saved layout in its own _ready")
	assert_eq(fresh.controls.label_for(fresh.control_scheme, "axis_4_plus", &"focus"), "Target")
	assert_eq(fresh.controls.action_axis_5_plus, &"", "and the HUD is laid out for it from the start: nothing to shoot")
	assert_eq(fresh.controls.action_button_3, &"ability", "Cast on the top face")
	fresh.control_scheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")
	fresh.queue_free()


func test_reset_controls_is_the_new_game_default() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.new()
	settings.control_scheme_name = "WoW"
	settings.hud_mode = PlayerSettingsResource.HudMode.SHOWN
	settings.reset_controls()
	assert_eq(settings.control_scheme_name, "", "No layout picked: the scene's own")
	assert_null(settings.picked_scheme())
	assert_eq(settings.hud_mode, PlayerSettingsResource.HudMode.AUTO, "and the on-screen controls on Auto")
