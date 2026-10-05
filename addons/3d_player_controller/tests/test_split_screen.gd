extends GutTest

## Purpose: A SplitScreen puts each local Player in a view of its own on the shared world and gives each the
## pad of its number, with the action names untouched: a view forwards only its pad's events, and the Player's
## polled reads ask that pad alone, so one pad moves one Player. The keyboard and the mouse reach nobody there,
## and a lone Player still reads the whole input.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const SPLIT_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/split_screen.tscn")
const DEMO_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/demo/split_screen_demo.tscn")

var root: Node3D
var split: SplitScreen


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(40.0, 1.0, 40.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	split = SPLIT_SCENE.instantiate()
	split.player_scene = PLAYER_SCENE
	split.player_count = 2
	root.add_child(split)
	await wait_physics_frames(3)


func after_each() -> void:
	_pad_button(0, JOY_BUTTON_Y, false)
	_pad_button(1, JOY_BUTTON_Y, false)
	await wait_physics_frames(1)


## Presses or releases a pad button as the OS would report it, so both the events and Input's pad state move.
func _pad_button(device: int, button: JoyButton, pressed: bool) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func test_two_views_share_one_world_with_a_player_each() -> void:
	assert_eq(split.players.size(), 2)
	assert_eq(split.views.size(), 2)
	assert_eq(split.grid.columns, 1, "Two players stack top and bottom")
	assert_eq(split.views[0].get_child(0).world_3d, split.views[1].get_child(0).world_3d, "One world")
	assert_eq(split.views[0].get_child(0).world_3d, root.get_viewport().find_world_3d())
	assert_eq(split.get_player(0).get_viewport(), split.views[0].get_child(0), "Each Player lives in its view")
	assert_true(split.get_player(0).camera.current, "Each view has its own current camera")
	assert_true(split.get_player(1).camera.current)
	assert_eq(split.get_player(0).input_device, 0, "First pad, first player")
	assert_eq(split.get_player(1).input_device, 1)
	assert_false(split.get_player(1).uses_mouse)
	assert_true(InputMap.has_action(&"jump"))
	assert_false(InputMap.has_action(&"jump_p2"), "The action names are the ordinary ones")


func test_a_view_forwards_only_its_pads_events() -> void:
	var first: PlayerView = split.views[0]
	var second: PlayerView = split.views[1]
	var pad1: InputEventJoypadButton = InputEventJoypadButton.new()
	pad1.device = 1
	assert_false(first._propagate_input_event(pad1))
	assert_true(second._propagate_input_event(pad1))
	var key: InputEventKey = InputEventKey.new()
	assert_false(first._propagate_input_event(key), "The keyboard drives nobody in a split screen")
	var mouse: InputEventMouseMotion = InputEventMouseMotion.new()
	assert_false(second._propagate_input_event(mouse))
	var action: InputEventAction = InputEventAction.new()
	action.action = &"jump"
	assert_true(first._propagate_input_event(action), "A synthetic action reaches every view")
	assert_true(second._propagate_input_event(action))


func test_one_pad_moves_one_player() -> void:
	var first: Player = split.get_player(0)
	var second: Player = split.get_player(1)
	assert_eq(first.current_state, NodeStateMachine.States.STANDING)
	assert_eq(second.current_state, NodeStateMachine.States.STANDING)
	_pad_button(1, JOY_BUTTON_Y, true) # Y is Jump on the Zelda layout
	await wait_until(func() -> bool: return second.current_state == NodeStateMachine.States.JUMPING, 1.0)
	_pad_button(1, JOY_BUTTON_Y, false)
	await wait_physics_frames(1)
	assert_eq(second.current_state, NodeStateMachine.States.JUMPING, "The second pad jumps the second player")
	assert_eq(first.current_state, NodeStateMachine.States.STANDING, "And not the first")


## A press parsed into the input queue is not readable the instant it is sent: it lands on a later frame, and
## how many later depends on how loaded the machine is, so waiting a fixed frame or two is a flake on a busy
## CI runner. Each read here waits for the state it expects instead, up to a second, and the assertion is that
## it arrived at all and on the right player.
func test_polled_reads_ask_the_players_own_pad() -> void:
	var first: Player = split.get_player(0)
	var second: Player = split.get_player(1)
	_pad_button(0, JOY_BUTTON_Y, true)
	await wait_until(func() -> bool: return first.is_action_pressed(&"jump"), 1.0)
	assert_true(first.is_action_pressed(&"jump"), "The first pad's Y is the first player's jump")
	assert_false(second.is_action_pressed(&"jump"), "And nothing to the second")
	assert_true(Input.is_action_pressed(&"jump"), "The whole input sees it, as a lone player would")
	_pad_button(0, JOY_BUTTON_Y, false)
	await wait_until(func() -> bool: return not first.is_action_pressed(&"jump"), 1.0)
	assert_false(first.is_action_pressed(&"jump"))


func test_three_players_make_a_grid_on_three_pads() -> void:
	split.player_count = 3
	split.layout = SplitScreen.Layout.GRID
	split.spawn()
	await wait_physics_frames(2)
	assert_eq(split.players.size(), 3)
	assert_eq(split.grid.columns, 2)
	assert_eq(split.get_player(2).input_device, 2)


func test_a_lone_player_reads_the_whole_input() -> void:
	split.free()
	var lone: Player = PLAYER_SCENE.instantiate()
	root.add_child(lone)
	await wait_physics_frames(2)
	assert_eq(lone.input_device, -1)
	assert_true(lone.uses_mouse)
	_pad_button(1, JOY_BUTTON_Y, true)
	await wait_until(func() -> bool: return lone.is_action_pressed(&"jump"), 1.0)
	assert_true(lone.is_action_pressed(&"jump"), "Any pad")
	_pad_button(1, JOY_BUTTON_Y, false)
	await wait_until(func() -> bool: return not lone.is_action_pressed(&"jump"), 1.0)


func test_the_demo_arena_keeps_each_view_to_the_contextual_hints() -> void:
	var demo: Node3D = DEMO_SCENE.instantiate()
	add_child_autofree(demo)
	await wait_physics_frames(2)
	var split: SplitScreen = demo.get_node("SplitScreen")
	assert_eq(split.players.size(), 2, "Two players in the arena")
	for player: Player in split.players:
		assert_eq(player.hud_mode_override, PlayerSettingsResource.HudMode.AUTO, "Half a screen has no room for the whole button set, whatever the saved setting says")



## The split-screen demo instances the demo arena, which has no Player or HUD of its own, rather than stripping the
## demo's script off; so the arena keeps its script and its pool and Guide answer every view's Player.
func test_the_demo_arenas_pool_swims_every_view() -> void:
	var demo: Node3D = DEMO_SCENE.instantiate()
	add_child_autofree(demo)
	await wait_physics_frames(2)
	var arena: Node3D = demo.get_node("DemoArena")
	assert_not_null(arena.get_script(), "The arena keeps its script")
	assert_null(arena.get_node_or_null("Player"), "and brings no Player of its own")
	var second: Player = demo.get_node("SplitScreen").get_player(1)
	second.global_position = arena.get_node("Markers/Pool").global_position
	await wait_until(func() -> bool: return second.current_state == NodeStateMachine.States.SWIMMING, 1.0)
	assert_eq(second.current_state, NodeStateMachine.States.SWIMMING, "The second view's Player swims in the arena's pool")
