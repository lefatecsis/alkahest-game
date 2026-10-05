extends GutTest
## Covers the part of the HUD a consuming project actually configures: which action each button drives, what
## gets registered in the InputMap, which buttons are shown, and how the labels behave.

const CONTROLS_SCENE: PackedScene = preload("res://addons/controls/controls.tscn")

## Where the key faces live, for the tests that hand the HUD a different one.
const KEY_ART: String = "res://addons/controls/assets/kenney_nl/Icons/Input Prompts/Keyboard & Mouse/Vector"

## Action names invented for these tests, removed again in [method after_each] so one test cannot bind another.
const TEST_ACTIONS: PackedStringArray = [
	"test_interact", "test_attack", "test_aim", "test_menu", "test_look_up", "test_look_down",
	"test_dpad_up", "test_dpad_down", "test_dpad_left", "test_dpad_right", "test_puppet",
]

var _controls: Controls


func before_each() -> void:
	_clear_test_actions()


func after_each() -> void:
	_clear_test_actions()


func _clear_test_actions() -> void:
	for action_name: String in TEST_ACTIONS:
		if InputMap.has_action(action_name):
			InputMap.erase_action(action_name)


## Empties the screenshot folder so a count is a count of what this test took.
func _clear_screenshots() -> void:
	if not DirAccess.dir_exists_absolute(Controls.SCREENSHOT_DIR):
		return
	for file_name: String in DirAccess.get_files_at(Controls.SCREENSHOT_DIR):
		DirAccess.remove_absolute(Controls.SCREENSHOT_DIR.path_join(file_name))


func _screenshot_count() -> int:
	if not DirAccess.dir_exists_absolute(Controls.SCREENSHOT_DIR):
		return 0
	return DirAccess.get_files_at(Controls.SCREENSHOT_DIR).size()


## Builds the HUD with [param overrides] applied to its exports before it enters the tree, which is where it
## reads them.
func _make_controls(overrides: Dictionary = {}, extra: Dictionary = {}) -> Controls:
	var controls: Controls = CONTROLS_SCENE.instantiate()
	for property: String in overrides:
		controls.set(property, overrides[property])
	controls.extra_actions = extra
	add_child_autofree(controls)
	return controls


func test_defaults_are_godots_own_actions() -> void:
	_controls = _make_controls()
	assert_eq(_controls.joypad_button_0.action, &"ui_accept", "The bottom face button is Godot's accept")
	assert_eq(_controls.joypad_button_1.action, &"ui_cancel", "The right face button is Godot's cancel")
	assert_eq(_controls.joypad_button_3.action, &"ui_select", "The top face button is Godot's select")
	assert_eq(_controls.joypad_button_11.action, &"ui_up", "The d-pad drives the ui_* directions")
	assert_eq(_controls.joypad_button_14.action, &"ui_right")
	assert_eq(_controls.key_w.action, &"ui_up", "WASD drives the same directions as the left stick")
	assert_eq(_controls.left_joystick.action_left, &"ui_left")


func test_exported_action_reaches_the_button() -> void:
	_controls = _make_controls({"action_button_0": &"test_interact", "action_axis_4_plus": &"test_aim"})
	assert_eq(_controls.joypad_button_0.action, &"test_interact")
	assert_eq(_controls.joypad_axis_4_plus.action, &"test_aim")


## The d-pad and the I, J, K, L keys are two ways of pressing the same four things, so one export drives both.
func test_one_slot_drives_the_joypad_button_and_its_key() -> void:
	_controls = _make_controls({"action_button_11": &"test_menu"})
	assert_eq(_controls.joypad_button_11.action, &"test_menu")
	assert_eq(_controls.key_i.action, &"test_menu", "The [I] key is the keyboard face of d-pad up")


func test_stick_actions_reach_the_joysticks() -> void:
	_controls = _make_controls({"action_look_up": &"test_look_up", "action_look_down": &"test_look_down"})
	assert_eq(_controls.right_joystick.action_up, &"test_look_up")
	assert_eq(_controls.right_joystick.action_down, &"test_look_down")
	assert_eq(_controls.key_up.action, &"test_look_up", "The arrow keys are the keyboard face of the right stick")


func test_a_blank_slot_is_hidden() -> void:
	_controls = _make_controls()
	assert_false(_controls.joypad_button_2.visible, "The left face button has no Godot default, so it is unused")
	assert_false(_controls.right_joystick.visible, "Nothing looks around by default, so the right stick is unused")
	assert_true(_controls.joypad_button_0.visible, "The bottom face button is mapped, so it shows")


func test_a_mapped_slot_is_shown() -> void:
	_controls = _make_controls({"action_button_2": &"test_attack"})
	assert_true(_controls.joypad_button_2.visible, "Mapping the left face button brings it back")


## The cross is drawn for the d-pad buttons that sit on it, so with all four blanked there is nothing to draw
## it for, in the game and in the editor preview alike. One d-pad button left is still a d-pad.
func test_blanking_the_whole_dpad_takes_the_cross_with_it() -> void:
	_controls = _make_controls({
		"action_button_11": &"", "action_button_12": &"", "action_button_13": &"", "action_button_14": &"",
	})
	_controls.current_input_type = Controls.InputType.SONY
	assert_false(_controls.dpad_base.visible, "A pad shows no cross for a d-pad the game does not use")
	assert_true(_controls.unmapped_items().has(_controls.dpad_base), "and the editor preview hides it too")

	_controls = _make_controls({"action_button_12": &"", "action_button_13": &"", "action_button_14": &""})
	_controls.current_input_type = Controls.InputType.SONY
	assert_true(_controls.dpad_base.visible, "One button left is still a d-pad")
	assert_false(_controls.unmapped_items().has(_controls.dpad_base), "in the editor too")


## The whole point of the drop-in: a project names an action it never declared and the addon binds it to the
## button that slot stands for.
func test_an_unknown_action_is_registered_on_its_own_button() -> void:
	assert_false(InputMap.has_action("test_interact"), "The action does not exist before the HUD is built")
	_controls = _make_controls({"action_button_0": &"test_interact"})
	assert_true(InputMap.has_action("test_interact"), "The HUD registered it")
	var pressed: InputEventJoypadButton = InputEventJoypadButton.new()
	pressed.button_index = JOY_BUTTON_A
	assert_true(InputMap.action_has_event("test_interact", pressed), "Bound to the button it is drawn on")


## An event made in code is for device 0, and the InputMap matches on device, so an action registered that way
## answered joypad 0 and nothing else: a second player's pad pressed every button and fired nothing.
func test_a_registered_action_fires_from_any_pad() -> void:
	_controls = _make_controls({"action_button_0": &"test_interact"})
	var second_pad: InputEventJoypadButton = InputEventJoypadButton.new()
	second_pad.device = 1
	second_pad.button_index = JOY_BUTTON_A
	second_pad.pressed = true
	assert_true(InputMap.event_is_action(second_pad, "test_interact"), "The second pad fires it")
	assert_true(InputMap.action_has_event("test_interact", second_pad), "because the binding is for every device")


func test_extra_actions_add_what_the_pad_cannot_describe() -> void:
	_controls = _make_controls(
		{"action_button_0": &"test_interact"},
		{"test_interact": {"keys": [KEY_E]}},
	)
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_E
	assert_true(InputMap.action_has_event("test_interact", key_event), "The keyboard binding came from extra_actions")
	var pressed: InputEventJoypadButton = InputEventJoypadButton.new()
	pressed.button_index = JOY_BUTTON_A
	assert_true(InputMap.action_has_event("test_interact", pressed), "and the slot still added its own button")


func test_a_project_action_is_left_alone() -> void:
	InputMap.add_action("test_attack")
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_Z
	InputMap.action_add_event("test_attack", key_event)

	_controls = _make_controls({"action_button_2": &"test_attack"})

	var pressed: InputEventJoypadButton = InputEventJoypadButton.new()
	pressed.button_index = JOY_BUTTON_X
	assert_false(InputMap.action_has_event("test_attack", pressed), "A binding the project already made is its own")
	assert_true(InputMap.action_has_event("test_attack", key_event), "and it is untouched")


## The View, pause and Screenshot slots draw an F5, an Escape and a Print Screen key, so those are the keys
## the addon has to register for them. A key face that names a key the slot does not answer to is a lie.
func test_the_system_slots_bind_the_keys_their_faces_show() -> void:
	_controls = _make_controls({
		"action_button_4": &"test_view",
		"action_button_6": &"test_pause",
		"action_button_15": &"test_shot",
	})

	for pair: Array in [["test_view", KEY_F5], ["test_pause", KEY_ESCAPE], ["test_shot", KEY_PRINT]]:
		var key_event: InputEventKey = InputEventKey.new()
		key_event.physical_keycode = pair[1]
		assert_true(InputMap.action_has_event(pair[0], key_event),
			"%s answers to %s" % [pair[0], OS.get_keycode_string(pair[1])])


## The d-pad slots draw [I], [J], [K] and [L] as their keyboard faces, so those are the keys they have to answer
## to, for the same reason the system slots answer to theirs.
func test_the_dpad_slots_bind_the_keys_their_faces_show() -> void:
	_controls = _make_controls({
		"action_button_11": &"test_dpad_up", "action_button_12": &"test_dpad_down",
		"action_button_13": &"test_dpad_left", "action_button_14": &"test_dpad_right",
	})

	for pair: Array in [["test_dpad_up", KEY_I], ["test_dpad_down", KEY_K], ["test_dpad_left", KEY_J], ["test_dpad_right", KEY_L]]:
		var key_event: InputEventKey = InputEventKey.new()
		key_event.physical_keycode = pair[1]
		assert_true(InputMap.action_has_event(pair[0], key_event),
			"%s answers to %s" % [pair[0], OS.get_keycode_string(pair[1])])


## A remote player's HUD is a puppet with no one to show it to. Left alone it sat on top of the local HUD with
## its touch buttons live, and registered actions for a player who is not at this keyboard.
func test_a_puppet_hud_hides_itself_and_registers_nothing() -> void:
	var puppet: Controls = CONTROLS_SCENE.instantiate()
	puppet.action_button_0 = &"test_puppet"
	puppet.set_multiplayer_authority(42)
	add_child_autofree(puppet)

	assert_false(puppet.is_multiplayer_authority(), "This peer is 1, so 42 is someone else")
	assert_false(puppet.visible, "so their HUD is not on this screen")
	assert_false(puppet.is_processing_input(), "and answers nothing pressed here")
	assert_false(InputMap.has_action("test_puppet"), "and bound nothing for a player who is not here")


## The editor gets its own pass, because _ready bails out there rather than registering actions or swapping
## textures. Without it a scene shows every button on the HUD, mapped or not, which is not what ships: an
## AlleyCat-style consumer instances controls.tscn with no overrides at all and would show a Zoom button for
## a game that never asked for one.
func test_the_editor_preview_hides_what_the_game_did_not_map() -> void:
	_controls = _make_controls()
	for item: CanvasItem in _controls._previewable_items():
		item.visible = true

	_controls.preview_in_editor()

	assert_false(_controls.joypad_button_8.visible, "The right stick click is blank by default, so no Zoom")
	assert_false(_controls.joypad_button_9.visible, "nor a shoulder")
	assert_false(_controls.joypad_axis_4_plus.visible, "nor a trigger")
	assert_false(_controls.right_joystick.visible, "nor the stick nothing looks around with")
	assert_true(_controls.joypad_button_0.visible, "The bottom face button is ui_accept, so it stays")
	assert_true(_controls.joypad_button_11.visible, "and the d-pad is ui_up and friends")


## Mapping a slot brings its button back, so the inspector shows the change as it is typed.
func test_the_editor_preview_follows_a_slot_being_mapped() -> void:
	_controls = _make_controls()
	_controls.preview_in_editor()
	assert_false(_controls.joypad_button_8.visible, "Blank to begin with")

	_controls.action_button_8 = &"test_zoom"
	_controls.preview_in_editor()
	assert_true(_controls.joypad_button_8.visible, "and back the moment it is mapped")


## The preview obeys the device the same way the running HUD does, so the editor is not showing a keyboard
## set over a pad set or the other way round.
func test_the_editor_preview_obeys_the_device() -> void:
	_controls = _make_controls()
	_controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	_controls.preview_in_editor()
	assert_true(_controls.key_w.visible, "On keyboard the mapped letter keys show")
	assert_false(_controls.left_joystick.visible, "and the stick does not")
	assert_false(_controls.dpad_base.visible, "nor the d-pad cross")

	_controls.current_input_type = Controls.InputType.SONY
	_controls.preview_in_editor()
	assert_false(_controls.key_w.visible, "On a pad the letter keys go away")
	assert_true(_controls.left_joystick.visible, "and the stick comes back")


## Writing a visibility that already matches would mark an untouched scene as modified in the editor.
func test_the_editor_preview_writes_nothing_when_it_already_matches() -> void:
	_controls = _make_controls()
	_controls.preview_in_editor()
	var before: Array[bool] = []
	for item: CanvasItem in _controls._previewable_items():
		before.append(item.visible)

	_controls.preview_in_editor()

	var after: Array[bool] = []
	for item: CanvasItem in _controls._previewable_items():
		after.append(item.visible)
	assert_eq(before, after, "A second pass changes nothing")


## Two slots may name the same action on purpose: a face button that jumps and the stick pushed up are
## both "up" in a game with one direction of it. Both slots then have to fire it, which means gathering the
## events rather than letting whichever slot comes last replace the other.
func test_two_slots_on_one_action_keep_both_bindings() -> void:
	_controls = _make_controls({"action_button_0": &"test_up", "action_move_up": &"test_up"})

	var face_button: InputEventJoypadButton = InputEventJoypadButton.new()
	face_button.button_index = JOY_BUTTON_A
	var stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = -1.0
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_W

	assert_true(InputMap.action_has_event("test_up", face_button), "The face button fires it")
	assert_true(InputMap.action_has_event("test_up", stick), "and so does the stick")
	assert_true(InputMap.action_has_event("test_up", key), "and the key the stick slot stands for")


## Joining the lists must not leave an action answering to the same event twice.
func test_merging_bindings_does_not_repeat_an_event() -> void:
	var merged: Dictionary = Controls.merge_bindings(
		{"keys": [KEY_W, KEY_UP], "buttons": [JOY_BUTTON_A]},
		{"keys": [KEY_UP], "buttons": [JOY_BUTTON_A, JOY_BUTTON_B], "deadzone": 0.4})

	assert_eq(merged["keys"], [KEY_W, KEY_UP], "A key both sides name is listed once")
	assert_eq(merged["buttons"], [JOY_BUTTON_A, JOY_BUTTON_B], "and the new button is added")
	assert_eq(merged["deadzone"], 0.4, "and a deadzone carries over")


## Merging returns a new dictionary, so the constant it was read from is not quietly edited.
func test_merging_bindings_leaves_its_inputs_alone() -> void:
	var base: Dictionary = {"keys": [KEY_W]}
	Controls.merge_bindings(base, {"keys": [KEY_UP]})
	assert_eq(base["keys"], [KEY_W], "SLOT_EVENTS is a const and has to stay what it was")


## Godot's own ui_* actions are the exception: they are extended rather than skipped, so the on-screen
## d-pad works even though the engine declared the action first.
func test_builtin_ui_actions_are_extended() -> void:
	_controls = _make_controls()
	var dpad_up: InputEventJoypadButton = InputEventJoypadButton.new()
	dpad_up.button_index = JOY_BUTTON_DPAD_UP
	assert_true(InputMap.action_has_event("ui_up", dpad_up), "ui_up answers to the d-pad")


func test_keyboard_and_joypad_sets_swap() -> void:
	_controls = _make_controls({"action_look_up": &"test_look_up"})

	_controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	assert_true(_controls.key_w.visible, "On keyboard the letter keys show")
	assert_false(_controls.left_joystick.visible, "and the sticks do not")
	assert_false(_controls.dpad_base.visible, "nor the cross the d-pad buttons sit on")

	_controls.current_input_type = Controls.InputType.SONY
	assert_false(_controls.key_w.visible, "On a pad the letter keys go away")
	assert_true(_controls.left_joystick.visible, "and the sticks come back")
	assert_true(_controls.dpad_base.visible, "and so does the d-pad cross")


## A virtual stick is analogue, and in a game that reads four directions and nothing in between that works
## against the player: a finger a fraction off the axis is a direction the game cannot express. Such a game
## asks for buttons instead, and gets the four movement buttons where the stick was.
func test_touch_movement_can_be_buttons_instead_of_the_stick() -> void:
	_controls = _make_controls()

	_controls.current_input_type = Controls.InputType.TOUCH
	assert_true(_controls.left_joystick.visible, "By default a touchscreen gets the stick")
	assert_false(_controls.key_w.visible, "and not the movement buttons")

	_controls.touch_movement = Controls.TouchMovement.BUTTONS
	assert_false(_controls.left_joystick.visible, "Asking for buttons takes the stick off")
	assert_true(_controls.key_w.visible, "and puts the four movement buttons up")
	assert_true(_controls.key_a.visible and _controls.key_s.visible and _controls.key_d.visible,
			"all four of them, or the player can only go one way")
	assert_eq(_controls.key_a.action, _controls.action_move_left, "driving the movement actions")

	# Only touch. A pad player has a real stick in their hands, and a keyboard player is drawn their own keys
	# either way, so neither is changed by the setting.
	_controls.current_input_type = Controls.InputType.SONY
	assert_true(_controls.left_joystick.visible, "A pad still gets the stick drawn for it")
	assert_false(_controls.key_w.visible, "and not the keyboard set")

	_controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	assert_false(_controls.left_joystick.visible, "A keyboard never gets the stick")
	assert_true(_controls.key_w.visible, "and always gets its own keys")


## A click is the only signal a mouse player gives on a HUD that starts out showing touch controls, so it has
## to count on its own rather than only while the mouse is captured.
func test_a_mouse_click_swaps_to_the_keyboard_set() -> void:
	_controls = _make_controls()
	_controls.current_input_type = Controls.InputType.TOUCH

	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_controls._input(click)

	assert_eq(_controls.current_input_type, Controls.InputType.KEYBOARD_MOUSE, "A click is someone at a mouse")
	assert_true(_controls.key_w.visible, "so the letter keys show")
	assert_false(_controls.left_joystick.visible, "and the touch sticks go away")


## A touchscreen sends mouse events of its own where the project emulates them, marked with
## DEVICE_ID_EMULATION. Taking those for a mouse would drop the touch controls the moment they were used.
func test_a_touch_emulated_click_stays_on_touch() -> void:
	_controls = _make_controls()
	_controls.current_input_type = Controls.InputType.TOUCH

	var emulated: InputEventMouseButton = InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	_controls._input(emulated)

	assert_eq(_controls.current_input_type, Controls.InputType.TOUCH, "An emulated click is a finger, not a mouse")


## Mouse motion still needs the mouse captured, so a knock of the desk does not take a pad player's HUD away.
func test_free_mouse_motion_leaves_a_pad_player_alone() -> void:
	_controls = _make_controls()
	_controls.current_input_type = Controls.InputType.MICROSOFT

	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(4, 4)
	_controls._input(motion)

	assert_eq(_controls.current_input_type, Controls.InputType.MICROSOFT, "The pad HUD stays put")


## A pad the name gives nothing away about is still a pad, so it gets the Xbox art rather than being left on
## the keyboard set. Only this fallback can be proved here: the name comes from Input.get_joy_name, which is
## whatever pad is in the socket, and a headless run has none, so the Nintendo and Sony branches need a real one.
func test_an_unrecognised_pad_is_drawn_as_an_xbox_pad() -> void:
	_controls = _make_controls()
	_controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE

	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.device = 7
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	_controls._input(press)

	assert_eq(Input.get_joy_name(7), "", "No pad is in that socket, so its name matches nothing")
	assert_eq(_controls.current_input_type, Controls.InputType.MICROSOFT, "and the HUD still swaps to a pad")
	assert_eq(_controls._pad_device, 7, "and remembers which pad, so a rumble reaches the one in hand")


## A text field with focus owns the keys. Typing into a chat box must not light the buttons whose keys the
## letters happen to be, and must not take a screenshot.
func test_a_focused_text_field_keeps_the_hud_from_reacting() -> void:
	_controls = _make_controls()
	var press: InputEventAction = InputEventAction.new()
	press.action = _controls.action_button_0
	press.pressed = true
	_controls._input(press)
	assert_eq(_controls.joypad_button_0.texture_normal, _controls.joypad_button_0.texture_pressed, "Without one the button lights up")
	var release: InputEventAction = InputEventAction.new()
	release.action = _controls.action_button_0
	_controls._input(release)

	var chat: LineEdit = LineEdit.new()
	add_child_autofree(chat)
	chat.grab_focus()
	_controls._input(press)
	assert_ne(_controls.joypad_button_0.texture_normal, _controls.joypad_button_0.texture_pressed, "With one the button stays as it was")


func test_input_type_change_swaps_the_button_art() -> void:
	_controls = _make_controls()
	_controls.current_input_type = Controls.InputType.SONY
	var sony: Texture2D = _controls.joypad_button_0.texture_normal
	_controls.current_input_type = Controls.InputType.NINTENDO
	assert_ne(_controls.joypad_button_0.texture_normal, sony, "The face button is drawn for the pad in hand")


## The vendor art is read off the exports by slot name, so every button gets the texture whose export names
## it, and there is no hand-kept order to slip.
func test_each_swappable_button_gets_the_export_named_for_it() -> void:
	_controls = _make_controls()
	for input_type: Controls.InputType in Controls.VENDOR_PREFIXES:
		_controls.current_input_type = input_type
		var prefix: String = Controls.VENDOR_PREFIXES[input_type]
		for slot: String in Controls.SWAPPABLE_SLOTS:
			var button: TouchScreenButton = _controls.get("joypad_%s" % slot)
			assert_eq(button.texture_normal, _controls.get("%s_%s_normal" % [prefix, slot]), "%s on %s" % [slot, prefix])
			assert_eq(button.texture_pressed, _controls.get("%s_%s_pressed" % [prefix, slot]), "%s on %s, pressed" % [slot, prefix])


## A game whose keys move about at run time redraws a slot with the key that now presses it, the pair it set
## is what the exports hold from then on, and the other devices' art is untouched.
## The device an event names is readable on its own, for a node that gets the event before this HUD does.
func test_the_device_an_event_names_is_readable_before_the_hud_sees_it() -> void:
	_controls = _make_controls()
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	assert_eq(_controls.input_type_of(key), Controls.InputType.KEYBOARD_MOUSE, "A key is the keyboard")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	assert_eq(_controls.input_type_of(pad), Controls.InputType.MICROSOFT, "A pad with no name is drawn as an Xbox pad")
	var touch := InputEventScreenTouch.new()
	assert_eq(_controls.input_type_of(touch), Controls.InputType.TOUCH)
	var motion := InputEventMouseMotion.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	assert_eq(_controls.input_type_of(motion), -1, "Free mouse motion says nothing about the device")
	assert_eq(_controls.current_input_type, Controls.InputType.TOUCH, "and asking changed nothing on the HUD")


func test_slot_art_can_be_changed_live() -> void:
	_controls = _make_controls()
	_controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	var normal: Texture2D = load(KEY_ART.path_join("keyboard_shift_icon_outline.svg"))
	var pressed: Texture2D = load(KEY_ART.path_join("keyboard_shift_icon.svg"))
	var xbox: Texture2D = _controls.microsoft_button_0_normal
	_controls.set_slot_art(Controls.InputType.KEYBOARD_MOUSE, "button_0", normal, pressed)
	assert_eq(_controls.joypad_button_0.texture_normal, normal, "The button showing that device is redrawn at once")
	assert_eq(_controls.joypad_button_0.texture_pressed, pressed)
	var art: Array[Texture2D] = _controls.slot_art(Controls.InputType.KEYBOARD_MOUSE, "button_0")
	assert_eq(art[0], normal, "and the exports hold the new pair")
	assert_eq(art[1], pressed)
	_controls.current_input_type = Controls.InputType.MICROSOFT
	assert_eq(_controls.joypad_button_0.texture_normal, xbox, "The pad's art is untouched")
	_controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	assert_eq(_controls.joypad_button_0.texture_normal, normal, "and the keyboard art survives a device swap")


func test_slot_art_for_another_device_waits_for_it() -> void:
	_controls = _make_controls()
	_controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	var before: Texture2D = _controls.joypad_button_0.texture_normal
	var art: Texture2D = load(KEY_ART.path_join("keyboard_e_outline.svg"))
	_controls.set_slot_art(Controls.InputType.SONY, "button_0", art, art)
	assert_eq(_controls.joypad_button_0.texture_normal, before, "Art set for a pad not in hand changes nothing on screen")
	_controls.current_input_type = Controls.InputType.SONY
	assert_eq(_controls.joypad_button_0.texture_normal, art, "and shows once that pad is picked up")


func test_input_type_changed_is_emitted() -> void:
	_controls = _make_controls()
	watch_signals(_controls)
	_controls.current_input_type = Controls.InputType.MICROSOFT
	assert_signal_emitted_with_parameters(_controls, "input_type_changed", [Controls.InputType.MICROSOFT])


func test_set_labels_writes_the_ones_given_and_clears_the_rest() -> void:
	_controls = _make_controls()
	_controls.set_labels({_controls.joypad_button_0_label: "Select"})
	assert_eq(_controls.joypad_button_0_label.text, "Select")
	assert_eq(_controls.joypad_button_3_label.text, "", "A label not named is cleared")


## A state names the joypad label and gets the key that does the same job for free.
func test_set_labels_mirrors_onto_the_keyboard_set() -> void:
	_controls = _make_controls()
	_controls.set_labels({
		_controls.joypad_button_11_label: "Inventory",
		_controls.left_joystick_label: "Walk",
	})
	assert_eq(_controls.key_i_label.text, "Inventory", "The [I] key reads what d-pad up reads")
	assert_eq(_controls.key_s_label.text, "Walk", "The [S] key reads what the left stick reads")


## The d-pad pairs go the other way too, and a pair named on both sides keeps both.
func test_set_labels_mirrors_the_keys_onto_the_dpad() -> void:
	_controls = _make_controls()
	_controls.set_labels({_controls.key_j_label: "Map", _controls.key_l_label: "Chart", _controls.joypad_button_14_label: "Atlas"})
	assert_eq(_controls.joypad_button_13_label.text, "Map", "D-pad left reads what the [J] key reads")
	assert_eq(_controls.joypad_button_14_label.text, "Atlas", "and a side named for itself keeps its own")
	assert_eq(_controls.key_l_label.text, "Chart")


## The HUD names no button for you. A label is what the game calls that button in that moment, and the addon
## cannot know it, so every one of them starts empty and a project writes them with set_labels or in its own
## scene - which is what the demo does. The share button is the exception, because the addon is what makes it
## do something, and what it does is the same on every device.
func test_every_label_starts_blank_but_the_share_button() -> void:
	_controls = _make_controls()
	for label: Label in _controls.all_labels:
		if label == _controls.joypad_button_15_label:
			continue
		assert_eq(label.text, "", "%s is the game's to name" % label.get_parent().name)
	assert_eq(_controls.joypad_button_15_label.text, "Screenshot", "and the share button names itself")


## The art has to name the button the slot is actually bound to, or the HUD is telling a player to press
## something that will not work. The slot is JOY_BUTTON_MISC1, which SDL - and so Godot - documents as the
## Xbox share button, the Switch Pro capture button and, on a DualSense, the microphone button. So PlayStation
## shows the mute button: not the touchpad, and not Create, which is JOY_BUTTON_BACK and a different slot.
func test_the_playstation_art_names_the_button_that_is_bound() -> void:
	_controls = _make_controls({"action_button_4": &"test_view"})
	assert_eq(Controls.SLOT_EVENTS["button_15"]["buttons"], [JOY_BUTTON_MISC1],
		"The slot is MISC1, the mic button on a DualSense")

	_controls.current_input_type = Controls.InputType.SONY
	var art: String = _controls.joypad_button_15.texture_normal.resource_path.get_file()
	assert_string_contains(art, "mute", "so the art is the mic button a player can actually press")
	assert_false(art.contains("touchpad"), "not the touchpad, which is a different button again")
	assert_ne(art, _controls.joypad_button_4.texture_normal.resource_path.get_file(),
		"and not Create, which is JOY_BUTTON_BACK and lives on the View slot")


## Sony and Xbox call the button Share, Nintendo calls it Capture, a keyboard has Print Screen - but it takes
## a screenshot on all of them, so the art is what changes per device and the label is what stays.
func test_the_share_label_holds_while_its_art_changes() -> void:
	_controls = _make_controls()
	var seen: Dictionary = {}
	for input_type: Controls.InputType in [Controls.InputType.KEYBOARD_MOUSE, Controls.InputType.MICROSOFT,
			Controls.InputType.NINTENDO, Controls.InputType.SONY]:
		_controls.current_input_type = input_type
		assert_eq(_controls.joypad_button_15_label.text, "Screenshot",
			"%s still calls it what it does" % Controls.InputType.keys()[input_type])
		seen[_controls.joypad_button_15.texture_normal] = true
	assert_eq(seen.size(), 4, "and every device brings its own art for the button")


func test_reset_labels_restores_the_scene_text() -> void:
	_controls = _make_controls()
	var original: String = _controls.joypad_button_0_label.text
	_controls.set_labels({_controls.joypad_button_0_label: "Select"})
	_controls.reset_labels()
	assert_eq(_controls.joypad_button_0_label.text, original)


func test_a_claimed_prompt_label_survives_a_reset() -> void:
	_controls = _make_controls()
	var owner: RefCounted = RefCounted.new()
	_controls.claim_action_label("Pick Up", owner)
	assert_eq(_controls.joypad_button_0_label.text, "Pick Up")
	_controls.reset_labels()
	assert_eq(_controls.joypad_button_0_label.text, "Pick Up", "The prompt keeps the button through a refresh")
	_controls.set_labels({_controls.joypad_button_1_label: "Back"})
	assert_eq(_controls.joypad_button_0_label.text, "Pick Up", "and through a state's own labels")


## Walking out of one prompt while standing in another must leave the second one's label alone.
func test_only_the_claimant_can_give_the_label_back() -> void:
	_controls = _make_controls()
	var first: RefCounted = RefCounted.new()
	var second: RefCounted = RefCounted.new()
	_controls.claim_action_label("Pick Up", first)
	_controls.claim_action_label("Get In", second)

	_controls.release_action_label(first)
	assert_eq(_controls.prompt_action_label, "Get In", "The first prompt cannot release the second's label")

	_controls.release_action_label(second)
	assert_eq(_controls.prompt_action_label, "", "Its own claimant can")


func test_releasing_asks_for_the_contextual_labels_back() -> void:
	_controls = _make_controls()
	var owner: RefCounted = RefCounted.new()
	_controls.claim_action_label("Pick Up", owner)
	watch_signals(_controls)
	_controls.release_action_label(owner)
	assert_signal_emitted(_controls, "contextual_labels_requested")


func test_rumble_is_for_pads_only() -> void:
	_controls = _make_controls()
	_controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	assert_false(_controls.rumble(0.5, 0.5, 0.1), "Keyboards do not rumble")
	_controls.current_input_type = Controls.InputType.TOUCH
	assert_false(_controls.rumble(0.5, 0.5, 0.1), "Nor does a touchscreen")
	_controls.current_input_type = Controls.InputType.MICROSOFT
	assert_true(_controls.rumble(0.5, 0.5, 0.1), "A pad does")


## The share button is the one slot the HUD fills in for itself, because it has something to put on it.
func test_the_share_button_is_the_screenshot_button() -> void:
	_controls = _make_controls()
	assert_eq(_controls.action_button_15, &"take_screenshot")
	assert_eq(_controls.joypad_button_15.action, &"take_screenshot", "and it is on the button")
	assert_true(InputMap.has_action("take_screenshot"), "registered like any other slot")
	assert_true(_controls.joypad_button_15.visible, "and shown, where every other unset slot is hidden")
	assert_eq(_controls.joypad_button_15_label.text, "Screenshot", "and named after what it does, not after what a vendor calls the button")


func test_a_project_can_still_have_the_slot_or_drop_it() -> void:
	_controls = _make_controls({"action_button_15": &"test_menu"})
	assert_eq(_controls.joypad_button_15.action, &"test_menu", "A project's own action goes on it")
	_controls = _make_controls({"action_button_15": &""})
	assert_false(_controls.joypad_button_15.visible, "and blanking it drops the button, as anywhere else")


func test_pressing_share_saves_a_png_of_the_screen() -> void:
	if DisplayServer.get_name() == "headless":
		pass_test("Headless draws nothing, so there is no screen to capture")
		return
	_controls = _make_controls()
	_clear_screenshots()
	var path: String = await _controls.take_screenshot()
	assert_eq(_screenshot_count(), 1, "One file for one press")
	assert_true(path.ends_with(".png"))
	assert_true(FileAccess.file_exists(path), "at %s" % ProjectSettings.globalize_path(path))
	var saved: Image = Image.load_from_file(path)
	assert_eq(saved.get_size(), get_viewport().size, "the whole screen, at its own size")
	assert_true(_controls.visible, "and the HUD is back afterwards")


func test_the_hud_is_not_in_the_picture() -> void:
	if DisplayServer.get_name() == "headless":
		pass_test("Headless draws nothing, so there is no screen to capture")
		return
	_controls = _make_controls()
	# Watching the frames themselves. The HUD is only down for the one that gets captured, which is over well
	# inside a single idle frame, so nothing slower than this can see it.
	# An array because a lambda captures a local by value, and this has to come back out of it.
	var seen_hidden: Array[bool] = [false]
	var watcher: Callable = func() -> void:
		seen_hidden[0] = seen_hidden[0] or not _controls.visible
	RenderingServer.frame_pre_draw.connect(watcher)
	await _controls.take_screenshot()
	RenderingServer.frame_pre_draw.disconnect(watcher)
	assert_true(seen_hidden[0], "The buttons are out of the frame")
	assert_true(_controls.visible, "and back the moment it is taken")


## A game that had already hidden the HUD - a cutscene, a menu - does not get it handed back lit up.
func test_a_hidden_hud_stays_hidden() -> void:
	if DisplayServer.get_name() == "headless":
		pass_test("Headless draws nothing, so there is no screen to capture")
		return
	_controls = _make_controls()
	_controls.hide()
	await _controls.take_screenshot()
	assert_false(_controls.visible)


func test_a_project_that_captures_its_own_way_can_turn_it_off() -> void:
	if DisplayServer.get_name() == "headless":
		pass_test("Headless draws nothing, so there is no screen to capture")
		return
	_controls = _make_controls({"takes_screenshots": false})
	_clear_screenshots()
	var press: InputEventAction = InputEventAction.new()
	press.action = _controls.action_button_15
	press.pressed = true
	_controls._input(press)
	await wait_frames(3)
	assert_eq(_screenshot_count(), 0, "The button is still there; the HUD just does not act on it")


## The keyboard set's stick and d-pad keys were baked into the scene, so a project binding anything other
## than WASD and IJKL showed its players the wrong keys with no way to say otherwise. They are exported now,
## the way the face buttons always were.
func test_the_stick_and_dpad_keys_take_a_projects_own_key_faces() -> void:
	var arrow_up: Texture2D = load(KEY_ART.path_join("keyboard_arrow_up_outline.svg"))
	var arrow_up_pressed: Texture2D = load(KEY_ART.path_join("keyboard_arrow_up.svg"))
	var controls: Controls = _make_controls({
		"keyboard_mouse_move_up_normal": arrow_up,
		"keyboard_mouse_move_up_pressed": arrow_up_pressed,
		"keyboard_mouse_button_11_normal": arrow_up,
		"keyboard_mouse_look_left_normal": arrow_up,
	})
	assert_eq(controls.key_w.texture_normal, arrow_up, "the left stick's forward key")
	assert_eq(controls.key_w.texture_pressed, arrow_up_pressed, "and its pressed state")
	assert_eq(controls.key_i.texture_normal, arrow_up, "the d-pad's up key")
	assert_eq(controls.key_left.texture_normal, arrow_up, "the right stick's left key")


## A project that binds WASD and the arrows like everyone else sets none of them, so a blank export has to
## leave the scene's own art alone rather than blanking the button.
func test_a_key_face_left_blank_keeps_the_scenes_own() -> void:
	var controls: Controls = _make_controls()
	for button: TouchScreenButton in [controls.key_w, controls.key_a, controls.key_s, controls.key_d,
			controls.key_i, controls.key_j, controls.key_k, controls.key_l,
			controls.key_up, controls.key_down, controls.key_left, controls.key_right]:
		assert_not_null(button.texture_normal, "%s keeps a face" % button.name)


## The override has to be in place before the held-state swap caches what "not pressed" looks like, or
## letting go of a key would put the addon's default art back.
func test_a_key_face_survives_being_pressed_and_released() -> void:
	var arrow_up: Texture2D = load(KEY_ART.path_join("keyboard_arrow_up_outline.svg"))
	var controls: Controls = _make_controls({"keyboard_mouse_move_up_normal": arrow_up})
	controls.update_input_ui()
	assert_eq(controls.key_w.texture_normal, arrow_up, "still the project's own after a redraw")


## The catalog turns every slot into a picker, so a project whose game only answers to a known list of
## actions cannot put anything else on a button.
func test_a_catalog_turns_the_slots_into_a_picker() -> void:
	var catalog: ControlsInputCatalog = ControlsInputCatalog.new()
	catalog.actions = [&"game_up", &"game_down", &"game_fire"]
	var controls: Controls = _make_controls({"input_catalog": catalog})
	for property: Dictionary in controls.get_property_list():
		if not String(property["name"]).begins_with("action_"):
			continue
		assert_eq(property["hint"], PROPERTY_HINT_ENUM, "%s is a picker" % property["name"])
		assert_eq(property["hint_string"], ",game_up,game_down,game_fire", property["name"])


## Without one the slots stay free text, which is every project that was using this before.
func test_no_catalog_leaves_the_slots_as_they_were() -> void:
	var controls: Controls = _make_controls()
	for property: Dictionary in controls.get_property_list():
		if String(property["name"]).begins_with("action_"):
			assert_ne(property["hint"], PROPERTY_HINT_ENUM, "%s is still free text" % property["name"])


## A slot left blank is a button the game does not use and the HUD hides it, so the picker has to offer
## that as a choice even though it is not in the catalog.
func test_the_picker_always_offers_a_blank_choice() -> void:
	var catalog: ControlsInputCatalog = ControlsInputCatalog.new()
	catalog.actions = [&"game_up"]
	assert_true(catalog.hint_string().begins_with(","), "the first choice is blank")
	assert_true(catalog.has_action(&""), "and blank is a valid slot")
	assert_true(catalog.has_action(&"game_up"))
	assert_false(catalog.has_action(&"game_sideways"))


## A catalog is written by hand or generated, and either way can end up with a blank or a repeat in it.
func test_the_picker_drops_blanks_and_repeats() -> void:
	var catalog: ControlsInputCatalog = ControlsInputCatalog.new()
	catalog.actions = [&"game_up", &"", &"game_up", &"game_down"]
	assert_eq(catalog.hint_string(), ",game_up,game_down")


## The HUD's size is its own, corner by corner: each cluster grows about the corner it is anchored to, so the
## bottom right stays in the bottom right and its buttons grow into the screen rather than off it.
func test_hud_scale_grows_each_corner_about_its_own_corner() -> void:
	_controls = _make_controls({"button_fraction": 0.0})
	await wait_process_frames(1)
	var corners: Dictionary = {}
	for cluster: Control in _controls._clusters:
		corners[cluster] = cluster.get_global_transform() * cluster.pivot_offset
	_controls.hud_scale = 2.0
	for cluster: Control in _controls._clusters:
		assert_eq(cluster.scale, Vector2(2, 2), "%s is drawn twice as big" % cluster.name)
		var anchored_corner: Vector2 = Vector2(cluster.anchor_left * cluster.size.x, cluster.anchor_top * cluster.size.y)
		assert_eq(cluster.pivot_offset, anchored_corner, "%s scales about its anchored corner" % cluster.name)
		var corner_now: Vector2 = cluster.get_global_transform() * cluster.pivot_offset
		assert_almost_eq(corner_now, corners[cluster] as Vector2, Vector2(0.5, 0.5), "%s's corner stays put" % cluster.name)


## The HUD sizes itself to the window, not to the project's stretch mode: a face button is a set fraction of
## the shorter side of the window in real pixels, on every device, going down as well as up, and hud_scale
## multiplies whatever that gives.
func test_the_hud_is_a_fraction_of_the_window_on_every_device() -> void:
	_controls = _make_controls({"button_fraction": 0.2})
	var window_size: Vector2 = Vector2(_controls.get_window().size)
	var drawn: float = Controls.BUTTON_SIZE * _controls.get_viewport().get_final_transform().get_scale().x
	var expected: float = 0.2 * minf(window_size.x, window_size.y) / drawn
	for device: Controls.InputType in [Controls.InputType.KEYBOARD_MOUSE, Controls.InputType.SONY, Controls.InputType.TOUCH]:
		_controls.current_input_type = device
		assert_almost_eq(_controls.get_effective_scale(), expected, 0.001, "a face button is a fifth of the shorter side on %s" % Controls.InputType.keys()[device])
	assert_almost_eq(_controls._clusters[0].scale.x, expected, 0.001, "and the corners are drawn at that")
	_controls.button_fraction = 0.02
	assert_lt(_controls.get_effective_scale(), 1.0, "a smaller fraction shrinks it, below one included")
	_controls.hud_scale = 2.0
	assert_almost_eq(_controls.get_effective_scale(), 2.0 * 0.02 * minf(window_size.x, window_size.y) / drawn, 0.001, "hud_scale multiplies the fit")
	_controls.hud_scale = 1.0
	_controls.button_fraction = 0.0
	assert_eq(_controls.get_effective_scale(), 1.0, "zero turns the fit off")


## A resized window is measured again, so the HUD keeps its fraction of the glass.
func test_the_hud_follows_the_window_when_it_resizes() -> void:
	_controls = _make_controls({"button_fraction": 0.1})
	var window: Window = _controls.get_window()
	var was: Vector2i = window.size
	var before: float = _controls.get_effective_scale()
	window.size = was * 2
	await wait_process_frames(2)
	assert_almost_eq(_controls._clusters[1].scale.x, _controls.get_effective_scale(), 0.001, "the corners were re-drawn for the new size")
	# What the doubled window asks for depends on the stretch mode; that it was measured again does not.
	assert_almost_eq(_controls.get_effective_scale(), 0.1 * minf(window.size.x, window.size.y) / (Controls.BUTTON_SIZE * _controls.get_viewport().get_final_transform().get_scale().x), 0.001, "and it is the fraction of the window as it is now")
	window.size = was
	await wait_process_frames(2)
	assert_almost_eq(_controls.get_effective_scale(), before, 0.001, "back to where it was")


## A thumb is not a pointer: every button takes a finger that slides onto it, and its hit area is the whole
## of the drawn art rather than a smaller disc inside it. The corner containers ignore the pointer, so a touch
## between two buttons reaches the game instead of dying on an invisible rectangle.
func test_touch_hit_areas_cover_the_art_and_take_a_sliding_thumb() -> void:
	_controls = _make_controls()
	for button: TouchScreenButton in _controls.all_buttons:
		assert_true(button.passby_press, "%s takes a finger that slides onto it" % button.name)
		if button.shape is CircleShape2D:
			assert_gte((button.shape as CircleShape2D).radius, Controls.BUTTON_SIZE / 2.0, "%s's hit area covers its art" % button.name)
		elif button.shape is RectangleShape2D:
			assert_gte((button.shape as RectangleShape2D).size.x, 48.0, "%s's hit area covers its key face" % button.name)
	for cluster: Control in _controls._clusters:
		assert_eq(cluster.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s lets touches through to the game" % cluster.name)


## With contextual_only on, a button is drawn only while its label says something the scene did not.
func test_contextual_only_shows_just_the_buttons_with_a_contextual_label() -> void:
	_controls = _make_controls({"action_button_0": &"test_interact", "action_button_3": &"test_menu"})
	_controls.current_input_type = Controls.InputType.MICROSOFT
	_controls.contextual_only = true
	assert_false(_controls.joypad_button_0.visible, "Resting labels draw nothing")
	assert_false(_controls.joypad_button_3.visible)
	assert_false(_controls.left_joystick.visible, "Nor do the sticks")
	assert_false(_controls.dpad_base.visible)
	_controls.claim_action_label("Pick Up", self)
	assert_true(_controls.joypad_button_0.visible, "A prompt's word shows its button")
	assert_eq(_controls.joypad_button_0_label.text, "Pick Up")
	assert_false(_controls.joypad_button_3.visible, "And that button alone")
	_controls.release_action_label(self)
	assert_false(_controls.joypad_button_0.visible, "Given back, it goes again")
	_controls.set_labels({_controls.joypad_button_3_label: "Climb", _controls.joypad_button_11_label: "Seeker"})
	assert_true(_controls.joypad_button_3.visible, "A state's label shows its button")
	assert_true(_controls.joypad_button_11.visible)
	assert_true(_controls.dpad_base.visible, "The d-pad cross comes with a d-pad button")
	assert_false(_controls.joypad_button_0.visible)
	_controls.set_labels({_controls.joypad_button_3_label: _controls._label_texts[_controls.joypad_button_3_label]})
	assert_false(_controls.joypad_button_3.visible, "The scene's own word is not contextual")
	_controls.contextual_only = false
	assert_true(_controls.joypad_button_0.visible, "Off, the whole set is back")
	assert_true(_controls.joypad_button_3.visible)
	assert_true(_controls.left_joystick.visible)


## A game that moves its interact action about the pad names it in prompt_action, and a prompt's word follows it.
func test_a_prompt_writes_the_button_bound_to_prompt_action() -> void:
	_controls = _make_controls({"action_button_0": &"test_sprint", "action_button_3": &"test_interact"})
	_controls.current_input_type = Controls.InputType.MICROSOFT
	_controls.prompt_action = &"test_interact"
	assert_eq(_controls.action_label(&"test_interact"), _controls.joypad_button_3_label, "Y carries interact")
	assert_eq(_controls.action_label(&"test_nothing", _controls.joypad_button_1_label), _controls.joypad_button_1_label, "Unbound falls back")
	assert_eq(_controls.prompt_label(), _controls.joypad_button_3_label)
	var sprint_text: String = _controls.joypad_button_0_label.text
	_controls.claim_action_label("Pick Up", self)
	assert_eq(_controls.joypad_button_3_label.text, "Pick Up", "The prompt lands on Y")
	assert_eq(_controls.joypad_button_0_label.text, sprint_text, "A is left alone")
	_controls.release_action_label(self)
	assert_ne(_controls.joypad_button_3_label.text, "Pick Up", "Given back")
	_controls.prompt_action = &""
	assert_eq(_controls.prompt_label(), _controls.joypad_button_0_label, "Unnamed, the bottom button as before")


## The world prompt draws the button the HUD binds to prompt_action, so the two agree on which button to press.
func test_a_world_prompt_draws_the_button_bound_to_prompt_action() -> void:
	_controls = _make_controls({"action_button_0": &"test_sprint", "action_button_3": &"test_interact"})
	_controls.current_input_type = Controls.InputType.MICROSOFT
	_controls.prompt_action = &"test_interact"
	var prompt: ActionPrompt = preload("res://addons/controls/action_prompt.tscn").instantiate()
	add_child_autofree(prompt)
	prompt.show_for(_controls, "Pick Up")
	var glyph: MeshInstance3D = prompt.get_node("Microsoft/MeshInstance3D")
	var material: StandardMaterial3D = glyph.get_surface_override_material(0) as StandardMaterial3D
	assert_not_null(material, "The glyph takes its own material")
	if material:
		assert_eq(material.albedo_texture, _controls.button_art(_controls.joypad_button_3), "Drawn as Y, where interact is")
	assert_eq(_controls.action_button(&"test_interact"), _controls.joypad_button_3)
	prompt.hide_for(_controls)


## The editor plugin is the one script nothing else here reaches. No test instantiates an [EditorPlugin], the
## demo project does not enable this one, and its [code]preload[/code] is written relative to the file, so a
## search for "res://" never lands on it: rename what it names and nothing points at the break. Loading a
## GDScript compiles it, though, and a preload of a file that is not there is a compile error, so a plugin in
## that state comes back null from [method @GDScript.load]. That is the whole guard.
func test_the_editor_plugin_still_compiles() -> void:
	assert_not_null(load("res://addons/controls/plugin.gd"), "plugin.gd compiles, so everything it preloads is there")


## Says which path is missing when one is, rather than leaving a bare null to work backwards from.
func test_every_path_the_plugin_preloads_resolves() -> void:
	var source: String = FileAccess.get_file_as_string("res://addons/controls/plugin.gd")
	assert_false(source.is_empty(), "plugin.gd is readable")
	var checked: int = 0
	for line: String in source.split("\n"):
		var opens: int = line.find("preload(\"")
		if opens < 0:
			continue
		var from: int = opens + 9
		var path: String = line.substr(from, line.find("\"", from) - from)
		var absolute: String = path if path.begins_with("res://") else "res://addons/controls/".path_join(path)
		checked += 1
		assert_true(ResourceLoader.exists(absolute), "plugin.gd preloads %s, which resolves to %s and is not there" % [path, absolute])
	assert_gt(checked, 0, "and there were preloads to check, so the scan is not passing on an empty list")
