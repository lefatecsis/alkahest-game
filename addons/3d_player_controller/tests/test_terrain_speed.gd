extends GutTest

## Purpose: terrain_speed_scale slows the Player through deep going (snow above the knee, mud) without touching
## movement_scale, which a Frostbolt's slow owns and resets when it wears off.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const ContractActions: GDScript = preload("res://addons/3d_player_controller/inventory/tests/contract_actions.gd")

var player: Player
var sender
var actions: RefCounted = ContractActions.new()


func before_all() -> void:
	actions.add_missing()


func after_all() -> void:
	actions.remove_added()


func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(200.0, 1.0, 200.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	await wait_physics_frames(5)


func after_each() -> void:
	sender.release_all()
	sender.clear()


## Walks forward on the real move input for [param frames] and returns how far the Player went.
func _walk(frames: int) -> float:
	var start: Vector3 = player.global_position
	sender.action_down("move_up")
	await wait_physics_frames(frames)
	sender.action_up("move_up")
	await wait_physics_frames(20)
	return (player.global_position - start).slide(Vector3.UP).length()


func test_deep_going_slows_the_walk() -> void:
	var free: float = await _walk(60)
	player.terrain_speed_scale = 0.4
	var wading: float = await _walk(60)
	assert_gt(free, 1.0, "The Player walks")
	assert_lt(wading, free * 0.6, "and wades a good deal less far in the same time")
	assert_gt(wading, 0.1, "but still makes way")


func test_a_slow_wearing_off_leaves_the_terrain_alone() -> void:
	player.terrain_speed_scale = 0.4
	player.slow(0.5, 0.05)
	await wait_seconds(0.2)
	assert_eq(player.movement_scale, 1.0, "The slow wore off")
	assert_eq(player.terrain_speed_scale, 0.4, "and did not reset what the ground allows")
