extends GutTest

## Purpose: a rigid body the Player stands on is a prop, not a lift. Leaving one must not hand the Player the speed
## of its surface, the way leaving a moving platform does; a snowball rolling away from the Player's legs, its back
## coming up as it turned, used to launch the Player a metre and a half into the air.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)


func _floor(body: PhysicsBody3D) -> PhysicsBody3D:
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(20.0, 1.0, 20.0)
	body.add_child(shape)
	body.position.y = -0.5
	root.add_child(body)
	return body


func _stand_on(body: PhysicsBody3D) -> void:
	_floor(body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await wait_physics_frames(10)


func test_standing_on_a_rigid_body_takes_none_of_its_speed() -> void:
	var crate := RigidBody3D.new()
	crate.freeze = true # Held still so the Player can settle on it; it is still a RigidBody3D.
	await _stand_on(crate)
	assert_true(player.is_on_floor(), "The Player stands on it")
	assert_true(player.is_touching_rigid_body(), "and knows it is touching a rigid body")
	player.update_movement_and_rotation(1.0 / 60.0)
	assert_eq(player.platform_floor_layers, 0, "so it is no platform and does not carry the Player")
	assert_eq(player.platform_on_leave, CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING, "nor throw them with what it recorded last frame")


func test_walking_into_a_ball_takes_none_of_its_spin() -> void:
	await _stand_on(StaticBody3D.new())
	var ball := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	(shape.shape as SphereShape3D).radius = 0.3
	ball.add_child(shape)
	ball.gravity_scale = 0.0
	root.add_child(ball)
	ball.global_position = player.global_position + Vector3(0.0, 0.5, -1.2)
	await wait_physics_frames(2) # Into the physics space before the Player meets it.
	ball.angular_velocity = Vector3(-10.0, 0.0, 0.0) # Its back, toward the Player, coming up as it rolls away.
	var touched: bool = false
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	Input.action_press(&"move_up")
	for step: int in 60:
		await wait_physics_frames(1)
		if player.is_touching_rigid_body():
			touched = true
			player.update_movement_and_rotation(1.0 / 60.0) # The move after the contact is the one that decides.
			assert_eq(player.platform_floor_layers, 0, "A ball walked into is a wall, not a floor, and still no platform")
			assert_eq(player.platform_on_leave, CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING)
			break
	Input.action_release(&"move_up")
	assert_true(touched, "The Player walks into the ball")


func test_standing_on_the_ground_keeps_what_platforms_give() -> void:
	await _stand_on(StaticBody3D.new())
	assert_false(player.is_touching_rigid_body())
	player.update_movement_and_rotation(1.0 / 60.0)
	assert_eq(player.platform_floor_layers, 0xFFFFFFFF, "Anything else still can, so a moving platform carries the Player")
	assert_eq(player.platform_on_leave, CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY, "and off it")
