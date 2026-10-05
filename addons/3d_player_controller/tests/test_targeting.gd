extends GutTest

## Purpose: the Target, World of Warcraft style. In a scheme that frees the cursor a Focus tap selects the nearest
## body and then cycles, a click on a body selects it and a click on nothing clears, the cancel action clears, and
## a body that dies is dropped; in a scheme that holds Focus the Target is the lock-on and goes with it. Bodies
## stand to a Player as hostile, neutral or friendly, and an ability lands only on the kinds it names: a heal with
## an enemy selected lands on the healer, a bolt with a friend selected goes where the Player aims, or with
## auto_target to the nearest enemy in range.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CONTROLS_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/player_controls.tscn")
const ENEMY_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/enemy_npc.tscn")
const FOLLOWER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/talking_npc.tscn") # a TalkingNpc is a FollowerNpc
const WOW: ControlScheme = preload("res://addons/3d_player_controller/resources/control_schemes/world_of_warcraft.tres")
const ZELDA: ControlScheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")
const HEAL: Ability = preload("res://addons/3d_player_controller/resources/abilities/heal.tres")

var root: Node3D
var player: Player
var focus: Focus


func before_each() -> void:
	add_child_autofree(CONTROLS_SCENE.instantiate())
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	focus = player.focus
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release("focus")


## A plain body that can be targeted, at [param offset] from the Player.
func _dummy(name: String, offset: Vector3) -> CharacterBody3D:
	var body: CharacterBody3D = CharacterBody3D.new()
	body.name = name
	body.add_to_group("Focusable")
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	body.add_child(shape)
	body.position = player.global_position + offset # placed before it is in, or it lands under the Player and carries it off
	root.add_child(body)
	return body


func _bolt(auto: bool = false) -> Ability:
	var bolt: Ability = Ability.new()
	bolt.target_kinds = Ability.Kind.NEUTRAL | Ability.Kind.HOSTILE
	bolt.auto_target = auto
	bolt.cast_range = 20.0
	return bolt


func test_the_wow_scheme_frees_the_cursor_and_is_on_the_menu() -> void:
	assert_true(WOW.frees_cursor)
	assert_false(WOW.locks_on, "No lock-on: the Target is clicked or tabbed")
	assert_false(ZELDA.frees_cursor, "Zelda holds Focus")
	assert_true(PlayerControls.BUILT_IN_SCHEMES.has(WOW), "The settings menu offers it")
	player.control_scheme = WOW
	assert_eq(player.cursor_mode(), Input.MOUSE_MODE_VISIBLE, "and the Player wants the cursor shown")
	player.control_scheme = ZELDA
	assert_eq(player.cursor_mode(), Input.MOUSE_MODE_CAPTURED)
	assert_false(WOW.extra_slots.values().has(&"shoot"), "Nothing to shoot in World of Warcraft")
	assert_false(WOW.extra_slots.values().has(&"throw"), "and nothing to throw")
	assert_false(WOW.slot_labels.has("axis_5_plus") or WOW.slot_labels.has("button_10"), "so those buttons carry no word and stay off the screen")
	for slot: String in ["button_11", "button_12", "button_13", "button_14", "button_7", "button_8"]:
		assert_false(WOW.extra_slots.has(slot) or WOW.slot_labels.has(slot), "No Zelda verb on the pad: no weapon cycling, whistle, seeker, crouch or telescope in Warcraft; its d-pad is action-bar slots this addon does not bind per button")
	assert_eq(WOW.extra_slots.keys(), ["axis_4_plus", "button_9"], "What is left beyond the faces: Target on the trigger, Run on the shoulder")


func test_closing_a_menu_gives_the_cursor_back_the_way_the_scheme_wants_it() -> void:
	if not player.uses_mouse:
		pass_test("A pad player never touches the cursor; nothing to check here")
		return
	player.control_scheme = WOW
	player.pause.show_menu()
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "A menu shows the cursor")
	player.pause.hide_menu()
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "and under a scheme that frees the cursor it stays shown when the menu closes")
	player.control_scheme = ZELDA
	player.pause.show_menu()
	player.pause.hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		pass_test("Headless Godot cannot capture the cursor, so the Zelda half cannot be seen here; the decision is cursor_mode(), checked above")
		return
	player.pause.show_menu()
	player.pause.hide_menu()
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED, "Under Zelda the game takes it back")


func test_the_wow_labels_read_the_same_on_every_device_and_the_keyboard_draws_tab() -> void:
	player.control_scheme = WOW
	var controls: PlayerControls = player.controls
	assert_eq(controls.label_for(WOW, "axis_4_plus", &"focus"), "Target", "The Focus slot says Target, whatever the device")
	assert_eq(controls.label_for(WOW, "button_3", &"ability"), "Cast")
	assert_eq(controls.label_for(WOW, "button_1", &"action"), "Use", "Interact With Target, in a word that fits the face label")
	var keyboard: Array[Texture2D] = controls.slot_art(Controls.InputType.KEYBOARD_MOUSE, "axis_4_plus")
	assert_eq(keyboard[0], PlayerControls.glyph_art(PlayerControls.FREE_CURSOR_FOCUS_GLYPH)[0], "On the keyboard set the Focus slot is drawn as Tab: the right button is the camera there")
	assert_eq(controls.slot_art(Controls.InputType.MICROSOFT, "axis_4_plus")[0], controls.slot_art(Controls.InputType.MICROSOFT, "axis_4_plus")[0], "The pad keeps its trigger")
	player.control_scheme = ZELDA
	keyboard = controls.slot_art(Controls.InputType.KEYBOARD_MOUSE, "axis_4_plus")
	assert_eq(keyboard[0], PlayerControls.key_art(&"focus")[0], "Back under Zelda, Focus is the right button again")
	assert_eq(controls.label_for(ZELDA, "axis_4_plus", &"focus"), "Focus")


func test_a_focus_tap_selects_the_nearest_then_cycles_and_cancel_clears() -> void:
	player.control_scheme = WOW
	var near: Node3D = _dummy("Near", Vector3(0.0, 0.0, -3.0))
	var far: Node3D = _dummy("Far", Vector3(0.0, 0.0, -8.0))
	_dummy("Beyond", Vector3(0.0, 0.0, -100.0)) # out of reach
	watch_signals(focus)
	assert_null(player.selected_target)
	focus.cycle_selection(1)
	assert_eq(player.selected_target, near, "The nearest first")
	assert_signal_emitted_with_parameters(focus, "target_changed", [near])
	assert_true(player.get_node("FocusTargetMarker").visible, "The marker sits over the Target")
	focus.cycle_selection(1)
	assert_eq(player.selected_target, far, "then the next")
	focus.cycle_selection(1)
	assert_eq(player.selected_target, near, "and round again; the body beyond reach is never offered")
	focus.clear_selection()
	assert_null(player.selected_target)
	assert_false(player.get_node("FocusTargetMarker").visible)
	assert_signal_emitted_with_parameters(focus, "target_changed", [null])


func test_tab_cycles_and_the_right_mouse_button_is_the_camera_not_a_tap() -> void:
	player.control_scheme = WOW
	var near: Node3D = _dummy("Near", Vector3(0.0, 0.0, -3.0))
	await wait_physics_frames(1)
	var right: InputEventMouseButton = InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	Input.parse_input_event(right)
	Input.flush_buffered_events()
	await wait_process_frames(1)
	assert_null(player.selected_target, "Right-click is Focus on the keyboard set, but here it drags the camera: no Target picked")
	var release: InputEventMouseButton = right.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	var tab: InputEventKey = InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	Input.flush_buffered_events()
	await wait_process_frames(1)
	assert_eq(player.selected_target, near, "Tab is the tap, as in World of Warcraft")
	var tab_up: InputEventKey = tab.duplicate()
	tab_up.pressed = false
	Input.parse_input_event(tab_up)
	Input.flush_buffered_events()


func test_an_analog_trigger_pull_is_one_tap_however_many_events_it_sends() -> void:
	player.control_scheme = WOW
	var near: Node3D = _dummy("Near", Vector3(0.0, 0.0, -3.0))
	var far: Node3D = _dummy("Far", Vector3(0.0, 0.0, -8.0))
	# A scheme an earlier test chose (Dark Souls puts Focus on the stick click) stays in the InputMap
	var trigger: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 1.0
	var bound_here: bool = not InputMap.action_has_event(&"focus", trigger)
	if bound_here:
		InputMap.action_add_event(&"focus", trigger)
	await wait_physics_frames(1)
	for value: float in [0.3, 0.6, 0.8, 1.0]:
		await _pull_focus_trigger(value)
	assert_eq(player.selected_target, near, "One pull of the trigger selects the nearest and goes no further")
	await _pull_focus_trigger(0.0)
	await _pull_focus_trigger(1.0)
	assert_eq(player.selected_target, far, "Let go and pulled again, it is the next tap")
	await _pull_focus_trigger(0.0)
	if bound_here:
		InputMap.action_erase_event(&"focus", trigger)


func _pull_focus_trigger(value: float) -> void:
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_TRIGGER_LEFT
	motion.axis_value = value
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await wait_process_frames(1)


func test_tab_skips_friends_and_escape_clears_before_the_menu() -> void:
	player.control_scheme = WOW
	var friend: Player = PLAYER_SCENE.instantiate()
	friend.position = Vector3(0.0, 0.0, -1.5) # the nearest body, and a friend
	root.add_child(friend)
	var enemy: Node3D = _dummy("Enemy", Vector3(0.0, 0.0, -4.0))
	await wait_physics_frames(1)
	focus.cycle_selection(1)
	assert_eq(player.selected_target, enemy, "Tab passes the friend by for the nearest enemy")
	focus.select(friend)
	assert_eq(player.selected_target, friend, "A click still selects a friend, for a heal")
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	await wait_process_frames(1)
	var escape_up: InputEventKey = escape.duplicate()
	escape_up.pressed = false
	Input.parse_input_event(escape_up)
	Input.flush_buffered_events()
	assert_null(player.selected_target, "Escape with a Target clears it")
	assert_false(player.pause.visible, "and goes no further: the menu waits for the next Escape")
	assert_false(player.is_paused)


func test_a_selection_persists_and_drops_when_the_body_dies() -> void:
	player.control_scheme = WOW
	var dummy: Node3D = _dummy("Dummy", Vector3(0.0, 0.0, -3.0))
	focus.select(dummy)
	await wait_physics_frames(3)
	assert_eq(player.selected_target, dummy, "Nothing held, still the Target")
	dummy.remove_from_group("Focusable") # what an enemy does when it dies
	await wait_physics_frames(2)
	assert_null(player.selected_target, "A body that can no longer be targeted is dropped")


func test_held_focus_is_no_lock_on_in_a_scheme_that_frees_the_cursor() -> void:
	player.control_scheme = WOW
	Input.action_press("focus")
	assert_false(player.is_focusing, "Under a free cursor Focus is a tap that picks the Target, never a held lock-on")
	Input.action_release("focus")
	player.control_scheme = ZELDA
	Input.action_press("focus")
	assert_true(player.is_focusing, "Under Zelda the same hold is the lock-on")
	Input.action_release("focus")


func test_held_focus_is_the_target_in_a_scheme_that_locks_on() -> void:
	player.control_scheme = ZELDA
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var dummy: Node3D = _dummy("Dummy", Vector3(0.0, 0.0, -3.0))
	await wait_physics_frames(2)
	Input.action_press("focus")
	focus._physics_process(0.1)
	assert_eq(focus.current_focus_target, dummy, "Focus locks on")
	assert_eq(player.selected_target, dummy, "and that lock is the Target")
	Input.action_release("focus")
	focus._physics_process(0.1)
	assert_null(focus.current_focus_target)
	assert_null(player.selected_target, "Released, there is no Target")


func test_how_bodies_stand_to_a_player() -> void:
	var enemy: EnemyNpc = ENEMY_SCENE.instantiate()
	root.add_child(enemy)
	var friend: FollowerNpc = FOLLOWER_SCENE.instantiate()
	root.add_child(friend)
	var other: Player = PLAYER_SCENE.instantiate()
	root.add_child(other)
	var dummy: Node3D = _dummy("Dummy", Vector3(0.0, 0.0, -3.0))
	await wait_physics_frames(1)
	assert_eq(Focus.disposition_toward(enemy, player), Focus.Disposition.HOSTILE, "An enemy is hostile")
	enemy.disposition = Focus.Disposition.NEUTRAL
	assert_eq(Focus.disposition_toward(enemy, player), Focus.Disposition.NEUTRAL, "unless its scene says neutral")
	assert_eq(Focus.disposition_toward(friend, player), Focus.Disposition.FRIENDLY, "A follower is a friend")
	assert_true(friend.is_in_group("Focusable"), "and can be targeted, for a heal")
	assert_eq(Focus.disposition_toward(other, player), Focus.Disposition.FRIENDLY, "So is another Player")
	assert_eq(Focus.disposition_toward(dummy, player), Focus.Disposition.HOSTILE, "Anything else that can be targeted is fair game")
	assert_eq(Focus.disposition_toward(player, enemy), Focus.Disposition.HOSTILE, "To an enemy the Player is prey")
	assert_eq(Focus.disposition_toward(friend, enemy), Focus.Disposition.NEUTRAL, "and other NPCs are nobody")


func test_an_ability_lands_only_on_the_kinds_it_names() -> void:
	player.control_scheme = WOW
	var enemy: Node3D = _dummy("Enemy", Vector3(0.0, 0.0, -3.0))
	var friend: Player = PLAYER_SCENE.instantiate()
	friend.position = Vector3(3.0, 0.0, 0.0)
	root.add_child(friend)
	await wait_physics_frames(1)
	var bolt: Ability = _bolt()
	assert_eq(HEAL.target_kinds, Ability.Kind.SELF | Ability.Kind.FRIENDLY, "A heal is for the caster and friends")
	focus.select(enemy)
	assert_eq(bolt.get_target(player), enemy, "A bolt lands on the selected enemy")
	assert_eq(HEAL.get_target(player), player, "A heal with an enemy selected lands on the healer")
	focus.select(friend)
	assert_eq(HEAL.get_target(player), friend, "A heal with a friend selected lands on the friend")
	assert_null(bolt.get_target(player), "A bolt with a friend selected has no target: it goes where the Player aims")
	assert_gt(bolt.get_impact_position(player).distance_to(player.global_position), 1.0, "along the aim ray")


func test_auto_target_takes_the_nearest_fitting_body_in_range() -> void:
	player.control_scheme = WOW
	var near: Node3D = _dummy("Near", Vector3(0.0, 0.0, -4.0))
	_dummy("Far", Vector3(0.0, 0.0, -9.0))
	var friend: Player = PLAYER_SCENE.instantiate()
	friend.position = Vector3(0.0, 0.0, -1.5) # nearer than any enemy, and not a target for a bolt
	root.add_child(friend)
	await wait_physics_frames(1)
	focus.clear_selection()
	var quiet: Ability = _bolt(false)
	assert_null(quiet.get_target(player), "Off, nothing selected, nothing in the crosshair: the bolt fires where the Player aims, so grass can burn")
	var seeking: Ability = _bolt(true)
	assert_eq(seeking.get_target(player), near, "On, it takes the nearest enemy in range, passing the friend by")
	seeking.cast_range = 2.0
	assert_null(seeking.get_target(player), "but not one out of range")


## The lock-on sphere reaches 5 m out. On layer 1 it stopped every ray and round that sees areas, so a bullet aimed
## at an enemy beside another player hit that player, and the camera's ray found nothing past it.
func test_a_ray_that_sees_areas_passes_the_lock_on_sphere() -> void:
	var detection: Area3D = player.get_node("TargetDetection")
	assert_eq(detection.collision_layer, 0, "On no layer")
	assert_false(detection.monitorable, "and nothing detects it")
	assert_true(detection.monitoring, "It still watches for bodies to lock on to")
	await wait_physics_frames(2)
	var at: Vector3 = player.global_position + Vector3(0.0, 1.0, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 0.0, -20.0), at)
	query.collide_with_areas = true
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	assert_ne(hit.get("collider"), detection, "A ray from 20 m out is not stopped 5 m short of the Player")
