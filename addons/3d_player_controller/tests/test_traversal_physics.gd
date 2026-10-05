extends GutTest

const PLAYER_SCENE = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CONTROLS_SCENE = preload("res://addons/3d_player_controller/scenes/ui/player_controls.tscn")


func test_climbing_wall_back_eject_leap() -> void:
	var controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(controls)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	var climbing_node = player.get_node("NodeStateMachine/Climbing")
	assert_not_null(climbing_node, "Climbing state node should exist")

	# Set player in climbing state in air
	player.current_state = NodeStateMachine.States.CLIMBING
	player.is_climbing = true
	player.locomotion_state.start("ClimbingLocomotion")
	player.animation_tree.advance(0.01)

	# Hold down/back input on wall
	player.player_input.motion = Vector2(0, -1.0)

	var event = InputEventAction.new()
	event.action = "jump"
	event.pressed = true
	climbing_node._input(event)

	assert_true(player.is_falling, "Player should enter falling state after back-eject")
	assert_gt(player.velocity.y, 0.0, "Player should have upward impulse from back-eject leap")
	assert_false(player.is_climbing, "Player should no longer be climbing")


## Hanging from a ledge the Player shimmies along it; climbing up must land where they hang now, not snap back to
## where they grabbed it. Where the chest ray meets no wall (a thin lip, an eave) the ledge is carried along from
## where it was grabbed, rather than the climb being refused.
func test_climbing_up_from_a_hang_lands_where_the_player_hangs_now() -> void:
	add_child_autofree(CONTROLS_SCENE.instantiate())
	var world: Node3D = Node3D.new()
	add_child_autofree(world)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	await wait_physics_frames(2)
	var hanging: NodeStateMachine = player.get_node("NodeStateMachine/Hanging")
	var ray: RayCast3D = player.ledge_detection_horizontal
	var ahead: Vector3 = (ray.to_global(ray.target_position) - ray.global_position).normalized()
	ahead.y = 0.0
	ahead = ahead.normalized()
	var side: Vector3 = ahead.cross(Vector3.UP)
	player.climbing_on_target = player.global_position + ahead * 0.55 + Vector3(0.0, 1.62, 0.0) # what Climbing found
	player.state_machine.travel(player.current_state, NodeStateMachine.States.HANGING)
	await wait_physics_frames(2) # hanging holds the Player still, so the wall goes where it stays
	# A wall 1.6 m high and 8 m wide whose face is half a metre ahead: the chest-high ray meets its face and the
	# ledge ray comes down on its top
	var wall: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(8.0, 1.6, 1.0)
	wall.add_child(shape)
	world.add_child(wall)
	var centre: Vector3 = Vector3(ray.global_position.x, player.global_position.y + 0.8, ray.global_position.z) + ahead * 1.0
	wall.look_at_from_position(centre, centre + ahead)
	await wait_physics_frames(2)

	var grabbed: Vector3 = player.climbing_on_target
	player.global_position += side * 2.0 # the shimmy
	await wait_physics_frames(2)
	var press: InputEventAction = InputEventAction.new()
	press.action = &"jump"
	press.pressed = true
	hanging._input(press)
	assert_true(player.is_climbing_on, "Jump climbs on")
	assert_almost_eq((player.climbing_on_target - player.global_position).dot(side), 0.0, 0.3, "where the Player hangs now, not 2 m back where they grabbed on")
	assert_gt(player.climbing_on_target.distance_to(grabbed), 1.5)

	player.is_climbing_on = false
	player.global_position += side * 6.0 # beyond the wall: the chest ray meets nothing, as under a thin lip
	await wait_physics_frames(2)
	hanging._input(press)
	assert_true(player.is_climbing_on, "No wall under the chest ray is no reason to refuse the climb")
	assert_almost_eq((player.climbing_on_target - player.global_position).dot(side), 0.0, 0.3, "and the ledge is carried along the shimmy")


func test_paragliding_thermal_updraft_and_steep_dive() -> void:
	var controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(controls)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.enable_stamina = true

	var paragliding_node: Paragliding = player.get_node("NodeStateMachine/Paragliding") as Paragliding
	assert_not_null(paragliding_node, "Paragliding state node should exist")

	paragliding_node.start()
	assert_true(player.is_paragliding, "Player should be paragliding")

	# 1. Test normal descent
	player.velocity = Vector3(0, 0, 0)
	paragliding_node._physics_process(0.1)
	assert_lt(player.velocity.y, 0.0, "Normal paragliding should have gentle descent")

	# 2. Test steep dive (dive action is "sprint"; crouch cancels the glide)
	Input.action_press("sprint")
	player.velocity = Vector3(0, 0, 0)
	paragliding_node._physics_process(0.5)
	var dive_vy = player.velocity.y
	assert_lt(dive_vy, -4.0, "Steep dive should produce high downward descent rate")
	Input.action_release("sprint")

	# 3. Test thermal updraft lift
	var updraft = Area3D.new()
	updraft.add_to_group("Updraft")
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(20, 20, 20)
	col.shape = box
	updraft.add_child(col)
	add_child_autofree(updraft)
	updraft.global_position = player.global_position
	await wait_physics_frames(2) # the area reports the overlap once physics has run

	player.stamina.stamina = 50.0
	paragliding_node._physics_process(0.5)
	assert_gt(player.velocity.y, 0.0, "Updraft should provide upward lift")
	assert_gt(player.stamina.stamina, 50.0, "Updraft should replenish stamina through the setter, not just the bar")

	paragliding_node.stop()


func test_swimming_exhaustion_shore_respawn() -> void:
	var controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(controls)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	var swimming_node: Swimming = player.get_node("NodeStateMachine/Swimming") as Swimming
	assert_not_null(swimming_node, "Swimming state node should exist")

	# Establish safe shore position on land
	var shore_pos = Vector3(10, 0, 10)
	player.global_position = shore_pos
	player.last_safe_shore_position = shore_pos

	# Enter deep water far away
	var water_pos = Vector3(50, -5, 50)
	player.global_position = water_pos
	player.is_swimming = true
	player.current_state = NodeStateMachine.States.SWIMMING

	# Exhaust player in deep water
	player.is_exhausted = true
	swimming_node._physics_process(0.1)

	assert_eq(player.global_position, shore_pos, "Exhausted swimmer should respawn at last safe shore position")
	assert_false(player.is_swimming, "Swimmer should no longer be swimming after shore respawn")
	assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Swimmer should be in standing state on shore")


func test_jump_over_updraft_allows_paragliding() -> void:
	var controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(controls)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.enable_paraglider = true
	add_child_autofree(player)

	var jumping_node = player.get_node("NodeStateMachine/Jumping")
	assert_not_null(jumping_node, "Jumping state node should exist")

	# Put player in jumping state in mid-air (not on floor)
	player.current_state = NodeStateMachine.States.JUMPING
	player.is_jumping = true

	# Create updraft area over fire
	var updraft = Area3D.new()
	updraft.add_to_group("Updraft")
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(10, 10, 10)
	col.shape = box
	updraft.add_child(col)
	add_child_autofree(updraft)
	updraft.global_position = player.global_position
	await wait_physics_frames(2) # the area reports the overlap once physics has run

	assert_true(player.is_in_updraft(), "Player should detect being in updraft")

	# Press jump while in updraft
	var event = InputEventAction.new()
	event.action = "jump"
	event.pressed = true
	jumping_node._input(event)

	assert_true(player.is_paragliding, "Player should be allowed to paraglide over updraft even with ground raycast colliding")
	assert_gt(player.velocity.y, 0.0, "Paraglider deploying in updraft should provide immediate upward lift")


func test_paragliding_updraft_catch_boost_is_immediate() -> void:
	var controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(controls)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	var paragliding_node: Paragliding = player.get_node("NodeStateMachine/Paragliding") as Paragliding
	paragliding_node.start()

	var updraft = Area3D.new()
	updraft.add_to_group("Updraft")
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(20, 20, 20)
	col.shape = box
	updraft.add_child(col)
	add_child_autofree(updraft)
	updraft.global_position = player.global_position
	await wait_physics_frames(2) # the area reports the overlap once physics has run

	# Entering the updraft must grant the catch boost on the very first frame (BotW standard)
	player.velocity = Vector3.ZERO
	paragliding_node.is_in_updraft = false
	paragliding_node._physics_process(1.0 / 60.0)
	assert_gte(player.velocity.y, paragliding_node.updraft_catch_boost, "Updraft catch should immediately boost vertical speed to at least +%s m/s" % paragliding_node.updraft_catch_boost)

	paragliding_node.stop()


func test_crouch_cancels_paragliding_for_wall_grab() -> void:
	var controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(controls)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.enable_paraglider = true
	add_child_autofree(player)
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE

	var paragliding_node: Paragliding = player.get_node("NodeStateMachine/Paragliding") as Paragliding
	paragliding_node.start()
	assert_true(player.is_paragliding, "Player should be paragliding")

	# Crouch must cancel the glide so the player can fall and grab a wall to climb
	var event = InputEventAction.new()
	event.action = "crouch"
	event.pressed = true
	paragliding_node._input(event)

	assert_false(player.is_paragliding, "Crouch should cancel paragliding")
	assert_true(player.is_falling, "Cancelling the glide should start falling (wall grabs happen from falling)")


func test_ghost_updraft_grants_no_lift() -> void:
	var controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(controls)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	var updraft = Area3D.new()
	updraft.add_to_group("Updraft")
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(20, 20, 20)
	col.shape = box
	updraft.add_child(col)
	add_child_autofree(updraft)
	updraft.global_position = player.global_position
	await wait_physics_frames(2) # the area reports the overlap once physics has run

	assert_true(player.is_in_updraft(), "Active updraft should be detected")

	# A burned-out (disabled) thermal must not grant lift even while still grouped
	updraft.monitoring = false
	assert_false(player.is_in_updraft(), "Disabled updraft areas must not register as active thermals")


## Only an overlap with the area's shape counts: the old within-eight-metres guess for a shapeless area is gone.
func test_a_shapeless_area_nearby_is_no_updraft() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var updraft := Area3D.new()
	updraft.add_to_group("Updraft")
	add_child_autofree(updraft)
	updraft.global_position = player.global_position + Vector3(3.0, 0.0, 0.0)
	await wait_physics_frames(2)
	assert_false(player.is_in_updraft(), "An empty area three metres off grants no lift")


## The overlap comes from the Player's UpdraftDetection area, so an updraft freed while the Player is inside it is
## simply gone, with no dead reference left to trip over.
func test_a_freed_updraft_is_no_updraft() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var updraft := Area3D.new()
	updraft.add_to_group("Updraft")
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 20)
	col.shape = box
	updraft.add_child(col)
	add_child(updraft)
	updraft.global_position = player.global_position
	await wait_physics_frames(2)
	assert_true(player.is_in_updraft())
	updraft.free()
	assert_false(player.is_in_updraft(), "A freed updraft lifts nobody")
	await wait_physics_frames(2)
	assert_false(player.is_in_updraft(), "and nothing is left of it")


## An UpdraftAura a game hangs on its Player is a node of that Player on every peer, so a puppet shows it too
## when its copy stands in a thermal; it starts hidden with its particles off.
func test_the_updraft_aura_shows_on_a_puppet_in_a_thermal() -> void:
	var puppet: Player = PLAYER_SCENE.instantiate() as Player
	puppet.name = "999"
	var aura := Node3D.new()
	aura.name = "UpdraftAura"
	var particles := GPUParticles3D.new()
	particles.emitting = true
	aura.add_child(particles)
	puppet.add_child(aura)
	add_child_autofree(puppet)
	assert_false(puppet.is_multiplayer_authority(), "Peer 999's Player")
	assert_false(aura.visible, "Hidden on ready")
	assert_false(particles.emitting, "and not emitting")
	var updraft := Area3D.new()
	updraft.add_to_group("Thermal")
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 20)
	col.shape = box
	updraft.add_child(col)
	add_child_autofree(updraft)
	updraft.global_position = puppet.global_position
	await wait_seconds(0.5)
	assert_true(aura.visible, "The aura shows around the puppet in the thermal")
	assert_true(particles.emitting)
