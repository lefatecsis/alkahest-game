extends GutTest

## Purpose: the head looks up and down with the camera, in either perspective, through the HeadLookAtModifier3D,
## and never turns sideways with it. Something held still claims the head, and letting go hands it back.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(20.0, 1.0, 20.0)
	ground.add_child(shape)
	ground.position.y = -0.5
	root.add_child(ground)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await wait_physics_frames(10)


## Holds the camera at [param pitch_degrees] (and [param yaw_degrees] off the body) for a second, for the head to
## settle, and returns where the head bone's own forward points.
func _look(pitch_degrees: float, yaw_degrees: float = 0.0) -> Vector3:
	for frame: int in 60:
		player.camera_mount.rotation_degrees.x = pitch_degrees
		player.camera_mount.rotation_degrees.y = player.player_model.rotation_degrees.y + 180.0 + yaw_degrees
		await wait_physics_frames(1)
	return player.camera.first_person_bone_attachment.global_basis.z.normalized() # rides the Head bone as posed


func test_the_head_follows_the_camera_target_when_nothing_is_held() -> void:
	assert_true(player.head_look_at_modifier.active, "The head look is on from the start")
	assert_eq(player.head_look_at_modifier.get_node(player.head_look_at_modifier.target_node), player.head_look_target,
			"aimed at the camera's head target")


func test_looking_down_puts_the_target_below_and_ahead_of_the_head() -> void:
	await _look(-40.0)
	var head: Vector3 = player.camera.first_person_bone_attachment.global_position
	var to: Vector3 = player.head_look_target.global_position - head
	var facing: Vector3 = player.player_model.global_basis.z.slide(Vector3.UP).normalized()
	assert_lt(to.y, -0.5, "Looking down, the head's target is below it")
	assert_gt(to.dot(facing), 1.0, "and ahead of the body")


func test_the_head_bone_pitches_with_the_camera() -> void:
	var down: Vector3 = await _look(-40.0)
	var up: Vector3 = await _look(30.0)
	assert_gt(rad_to_deg(down.angle_to(up)), 25.0, "The head itself tips down and up with the camera")


func test_the_head_looks_as_far_up_and_down_as_a_neck_goes() -> void:
	assert_almost_eq(rad_to_deg(asin((await _look(-40.0)).y)), -40.0, 4.0, "Looking 40 degrees down, the head does too")
	assert_almost_eq(rad_to_deg(asin((await _look(30.0)).y)), 30.0, 4.0, "and 30 up")
	var furthest_up: float = rad_to_deg(asin((await _look(85.0)).y))
	assert_between(furthest_up, 30.0, 65.0, "Straight up, it stops where a neck would")


func test_turning_the_camera_sideways_does_not_turn_the_target() -> void:
	await _look(0.0, 60.0)
	var head: Vector3 = player.camera.first_person_bone_attachment.global_position
	var to: Vector3 = (player.head_look_target.global_position - head).slide(Vector3.UP).normalized()
	var facing: Vector3 = player.player_model.global_basis.z.slide(Vector3.UP).normalized()
	assert_gt(to.dot(facing), 0.99, "Up and down only: the target stays ahead of the body")


func test_first_person_pitches_the_head_too() -> void:
	player.camera.perspective = Camera.Perspective.FIRST_PERSON
	var down: Vector3 = await _look(-40.0)
	var up: Vector3 = await _look(30.0)
	assert_gt(rad_to_deg(down.angle_to(up)), 25.0, "In first person as in third")


func test_something_held_claims_the_head_and_letting_go_returns_it() -> void:
	var box := Node3D.new()
	root.add_child(box)
	player.set_head_look_at_target(box)
	assert_eq(player.head_look_at_modifier.get_node(player.head_look_at_modifier.target_node), box, "Held, the head watches it")
	player.set_head_look_at_target(null)
	assert_eq(player.head_look_at_modifier.get_node(player.head_look_at_modifier.target_node), player.head_look_target,
			"let go of, it follows the camera again")
	assert_true(player.head_look_at_modifier.active)
