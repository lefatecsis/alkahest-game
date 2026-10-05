extends GutTest

## Purpose: shield surfing, as in Breath of the Wild. Focus held and Action pressed in the air drops a Player with a
## shield onto it; a downhill speeds the ride up and flat ground brings it to a stop; the shield rides under the feet
## and goes back on the arm; Cancel steps off. Without the shield, or with the feature off, nothing happens.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)


func after_each() -> void:
	Input.action_release(&"focus")
	Input.action_release(&"move_up")


## Ground tilted [param degrees] about X, falling away toward +Z, and a Player dropped onto it from [param height].
func _ground(degrees: float, height: float = 1.5, surface: StringName = &"SNOW") -> void:
	var ground := StaticBody3D.new()
	if surface != &"":
		ground.add_to_group(surface) # the rides here are on snow unless a test says otherwise
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(40.0, 1.0, 200.0)
	ground.add_child(shape)
	root.add_child(ground)
	ground.rotation_degrees.x = degrees
	ground.position.y = -0.5
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.global_position = Vector3(0.0, height, 0.0)
	player.enable_shield_surfing = true
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	await wait_physics_frames(2)


func _equip_shield() -> Equipment:
	var pickup: Equipment = Equipment.new()
	pickup.name = "Shield"
	pickup.equipment_type = Equipment.EquipmentType.SWORD_AND_SHIELD
	pickup.bone_attachment_bone_name = "LeftHand"
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	pickup.add_child(mesh)
	add_child_autofree(pickup)
	return player.inventory.equip_pickup(pickup)


func _send(action_name: StringName, pressed: bool = true) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	Input.parse_input_event(event)


## Holds Focus and taps Action while the Player is in the air, the way into a ride.
func _surf_from_the_air() -> void:
	await wait_physics_frames(4) # dropping, not yet down
	Input.action_press(&"focus")
	_send(&"action")
	await wait_physics_frames(1)
	_send(&"action", false)
	Input.action_release(&"focus")


func test_focus_and_action_in_the_air_rides_the_shield() -> void:
	await _ground(0.0, 3.0)
	var shield: Equipment = _equip_shield()
	await _surf_from_the_air()
	assert_eq(player.current_state, NodeStateMachine.States.SURFING, "Focus held and Action in the air drops onto the shield")
	assert_true(player.is_shield_surfing)
	assert_eq(shield.get_parent(), player.get_node("PlayerModel/ShieldSurfMount"), "The shield is under the feet")


func test_without_a_shield_or_the_feature_nothing_happens() -> void:
	await _ground(0.0, 3.0)
	await _surf_from_the_air()
	assert_ne(player.current_state, NodeStateMachine.States.SURFING, "No shield, no surf")
	_equip_shield()
	player.enable_shield_surfing = false
	player.global_position = Vector3(0.0, 3.0, 0.0)
	await _surf_from_the_air()
	assert_ne(player.current_state, NodeStateMachine.States.SURFING, "and none with the feature off")


func test_a_downhill_speeds_the_ride_up() -> void:
	await _ground(30.0)
	_equip_shield()
	await _surf_from_the_air()
	await wait_seconds(0.5)
	var early: float = player.velocity.length()
	await wait_seconds(1.5)
	assert_eq(player.current_state, NodeStateMachine.States.SURFING, "Still riding down the slope")
	assert_gt(player.velocity.length(), early + 1.5, "and going faster")
	assert_lt(player.velocity.length(), 10.0, "but no faster than the snow lets it on 30 degrees")


func test_flat_ground_brings_it_to_a_stop_and_the_shield_back_to_the_arm() -> void:
	await _ground(0.0)
	var shield: Equipment = _equip_shield()
	var arm: Node = shield.get_parent()
	await _surf_from_the_air()
	player.velocity = Vector3(0.0, 0.0, 4.0)
	await wait_seconds(5.0)
	assert_eq(player.current_state, NodeStateMachine.States.STANDING, "On the flat it slows and the Player steps off")
	assert_false(player.is_shield_surfing)
	assert_eq(shield.get_parent(), arm, "The shield goes back on the arm")


func test_cancel_steps_off() -> void:
	await _ground(20.0)
	_equip_shield()
	await _surf_from_the_air()
	await wait_seconds(0.5)
	_send(&"crouch")
	await wait_physics_frames(2)
	_send(&"crouch", false)
	assert_false(player.is_shield_surfing, "Cancel steps off the shield")



func test_a_stowed_shield_surfs_too() -> void:
	await _ground(0.0, 3.0)
	var shield: Equipment = _equip_shield()
	player.inventory.stow_equipment(shield)
	var home: Node = shield.get_parent()
	await _surf_from_the_air()
	assert_true(player.is_shield_surfing, "The shield off the Player's back rides as well as one on the arm")
	_send(&"crouch")
	await wait_physics_frames(2)
	_send(&"crouch", false)
	assert_eq(shield.get_parent(), home, "and goes back where it was stowed")


func test_the_ride_holds_the_skateboard_stance() -> void:
	await _ground(20.0)
	_equip_shield()
	await _surf_from_the_air()
	await wait_seconds(1.0)
	var playback: AnimationNodeStateMachinePlayback = player.animation_tree.get(Player.LOCOMOTION_STATE_PLAYBACK_PATH)
	assert_eq(playback.get_current_node(), &"SkateboardingLocomotion", "Surfing, the Player stands as on a skateboard")


func test_the_hud_names_the_ride_s_own_buttons() -> void:
	await _ground(20.0)
	_equip_shield()
	await _surf_from_the_air()
	var controls: Controls = player.controls
	assert_eq(controls.left_joystick_label.text, "Steer / Lean")
	assert_eq(controls.action_label(&"jump").text, "Hop", "Jump hops, and says so in a word the HUD shows")
	assert_eq(controls.action_label(&"attack").text, "Spin")
	assert_eq(controls.action_label(&"crouch").text, "Get Off", "On the keyboard Crouch steps off")
	for label: Label in [controls.action_label(&"jump"), controls.action_label(&"attack"), controls.action_label(&"crouch")]:
		assert_true(controls.is_label_contextual(label), "%s differs from the button's own word, so it is shown" % label.text)


func test_attack_spins_the_body_round_once_not_the_facing() -> void:
	await _ground(20.0)
	_equip_shield()
	await _surf_from_the_air()
	await wait_seconds(0.5)
	var armature: Node3D = player.get_node("PlayerModel/Armature")
	var facing: Vector3 = player.player_model.global_basis.z
	var body_before: Vector3 = armature.global_basis.z
	_send(&"attack")
	await wait_physics_frames(1)
	_send(&"attack", false)
	await wait_seconds(0.2)
	assert_gt(rad_to_deg(body_before.angle_to(armature.global_basis.z)), 60.0, "Mid-spin the body faces well away from the ride")
	assert_lt(rad_to_deg(facing.angle_to(player.player_model.global_basis.z)), 20.0, "while the Player's facing, which the camera follows, does not turn")
	assert_ne(player.surf_spin, 0.0, "and the spin is in the replicated angle, for every peer")
	await wait_seconds(0.6)
	assert_eq(player.surf_spin, 0.0, "Round once, it is done")
	assert_lt(rad_to_deg(player.player_model.global_basis.z.angle_to(armature.global_basis.z)), 5.0, "and the body faces the ride again")
	assert_true(player.is_shield_surfing, "still on the shield")


func test_jump_hops_without_getting_off() -> void:
	await _ground(20.0)
	_equip_shield()
	await _surf_from_the_air()
	await wait_seconds(0.8)
	assert_true(player.is_on_floor(), "Riding the slope")
	_send(&"jump")
	await wait_physics_frames(1)
	_send(&"jump", false)
	var clip: bool = await wait_until(func() -> bool: return player.current_locomotion_node == "Jump", 0.5)
	assert_true(clip, "The jump clip plays, as on the skateboard")
	var mount: Node3D = player.get_node("PlayerModel/ShieldSurfMount")
	var highest: float = 0.0
	var mount_highest: float = 0.0
	for frame: int in 60:
		await wait_physics_frames(1)
		var ground: float = -player.global_position.z * tan(deg_to_rad(20.0)) # the slope falls 20 degrees toward +Z
		highest = maxf(highest, player.global_position.y - ground)
		mount_highest = maxf(mount_highest, mount.position.y)
	assert_gt(highest, 0.4, "and its push-off lifts the rider clear of the slope")
	assert_gt(mount_highest, 0.12 + 0.05, "with the shield following the feet up, not left on the ground")
	assert_true(player.is_shield_surfing, "still on the shield")
	await wait_seconds(1.0)
	assert_almost_eq(mount.position.y, 0.12, 0.02, "Landed, the shield rests under the feet again")


## Speed after a second on the flat from 6 m/s along the camera's forward, the stick held on [param stick] or not.
func _flat_run(stick: StringName) -> float:
	await _ground(0.0)
	_equip_shield()
	await _surf_from_the_air()
	await wait_physics_frames(20)
	var forward: Vector3 = (player.spring_arm.global_basis * Vector3.FORWARD).slide(Vector3.UP).normalized()
	player.velocity = forward * 6.0
	var surf: Node = player.get_node("NodeStateMachine/Surfing")
	surf.set("_heading", forward)
	surf.set("_speed", 6.0)
	if stick != &"":
		Input.action_press(stick)
	await wait_seconds(1.0)
	Input.action_release(stick) if stick != &"" else null
	return surf.get("_speed")


func test_leaning_in_speeds_the_ride_and_pulling_back_brakes_it() -> void:
	var coasting: float = await _flat_run(&"")
	root.free()
	root = Node3D.new()
	add_child_autofree(root)
	var leaning: float = await _flat_run(&"move_up")
	root.free()
	root = Node3D.new()
	add_child_autofree(root)
	var braking: float = await _flat_run(&"move_down")
	assert_gt(leaning, coasting + 1.0, "Pushing the stick along the ride keeps it going faster")
	assert_lt(braking, coasting - 1.0, "pulling it back brakes")


## Speed two seconds into a ride down 30 degrees of [param surface].
func _run_on(surface: StringName) -> float:
	await _ground(30.0, 1.5, surface)
	_equip_shield()
	await _surf_from_the_air()
	await wait_seconds(2.0)
	return player.velocity.length()


func test_snow_runs_faster_than_grass_and_rock_grinds() -> void:
	var on_snow: float = await _run_on(&"SNOW")
	root.free()
	root = Node3D.new()
	add_child_autofree(root)
	var on_grass: float = await _run_on(&"GRASS")
	root.free()
	root = Node3D.new()
	add_child_autofree(root)
	var on_rock: float = await _run_on(&"")
	assert_gt(on_snow, on_grass + 0.5, "Snow runs faster than grass")
	assert_gt(on_grass, on_rock, "and grass than bare rock, which grinds")


func test_the_ground_under_the_shield_sets_the_friction() -> void:
	await _ground(10.0, 1.5, &"ICE")
	_equip_shield()
	await _surf_from_the_air()
	await wait_seconds(0.5)
	var surfing: Surfing = player.get_node("NodeStateMachine/Surfing")
	assert_eq(surfing.surface_friction_under(), surfing.surface_friction[&"ICE"], "On ice, ice's friction")
