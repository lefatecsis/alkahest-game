extends GutTest

## Purpose: the spyglass, Tears of the Kingdom style. It rides the right hand hidden until the scope action raises it
## (only with enable_spyglass on, and only standing, crouching or sprinting); the arm is brought to the face by its own
## IK with the eyepiece at the eye, the view then goes first person through the porthole, zoomed, looking slower, while
## the Player stands still; the wheel zooms within limits; pressing it again puts it away and gives back the view the
## Player had. Scoping replicates, so other peers see it held up.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const SPYGLASS_PATH: NodePath = ^"PlayerModel/Armature/GeneralSkeleton/SpyglassBoneAttachment/Spyglass"

var root: Node3D
var player: Player
var spyglass: Spyglass
var camera: Camera


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	floor.add_child(shape)
	floor.position.y = -0.5
	root.add_child(floor)
	player = PLAYER_SCENE.instantiate() as Player
	player.enable_spyglass = true
	root.add_child(player)
	spyglass = player.get_node(SPYGLASS_PATH) as Spyglass
	camera = player.camera as Camera
	spyglass.raise_time = 0.1
	await wait_physics_frames(3)


func after_each() -> void:
	Input.action_release("move_up")


func _press_scope() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"scope"
		event.pressed = pressed
		Input.parse_input_event(event)
	await wait_process_frames(2)


func test_it_rides_the_right_hand_hidden_and_is_off_by_default() -> void:
	assert_not_null(spyglass, "The Player carries a Spyglass")
	assert_false(spyglass.visible, "saved hidden")
	assert_eq((spyglass.get_parent() as BoneAttachment3D).bone_name, "RightHand", "on the right hand")
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	assert_false(fresh.enable_spyglass, "and like the paraglider it is off until a scene turns it on")
	fresh.free()


func test_without_enable_spyglass_the_scope_does_nothing() -> void:
	player.enable_spyglass = false
	await _press_scope()
	assert_false(player.is_scoping)


func test_raising_it_looks_through_it_zoomed_and_puts_it_away_again() -> void:
	assert_eq(camera.perspective, Camera.Perspective.THIRD_PERSON)
	await _press_scope()
	assert_true(player.is_scoping, "The scope action raises it")
	assert_true(spyglass.visible, "in hand on the way up")
	assert_true(spyglass.hand_ik.active, "brought to the face by its own IK")
	await wait_seconds(0.3)
	assert_true(spyglass.is_raised, "At the eye")
	assert_eq(camera.perspective, Camera.Perspective.FIRST_PERSON, "the view goes first person")
	assert_false(spyglass.visible, "and the spyglass gets out of the view")
	assert_eq(spyglass.hand_ik.influence, 0.0, "the arm too, which would fill the lens")
	assert_true(spyglass.overlay.visible, "through the porthole")
	assert_almost_eq(camera.fov, Spyglass.zoomed_fov(camera.default_fov, spyglass.magnification), 0.01, "zoomed")
	assert_almost_eq(camera.look_scale, 1.0 / spyglass.magnification, 0.0001, "and looking slower by as much")
	await _press_scope()
	assert_false(player.is_scoping, "Pressing it again puts it away")
	await wait_seconds(0.3)
	assert_eq(camera.perspective, Camera.Perspective.THIRD_PERSON, "back to the view the Player had")
	assert_eq(camera.fov, camera.default_fov)
	assert_eq(camera.look_scale, 1.0)
	assert_false(spyglass.overlay.visible)
	assert_false(spyglass.visible, "hidden again")
	assert_false(spyglass.hand_ik.active, "and the arm given back to the animation")


func test_the_eyepiece_comes_to_the_right_eye() -> void:
	spyglass.raise_time = 5.0 # stay on the way up, where it is still in hand
	await _press_scope()
	spyglass._tween.kill()
	spyglass.hand_ik.influence = 1.0
	spyglass.hand_rotation.influence = 1.0
	await wait_physics_frames(3)
	var facing: Basis = player.player_model.global_basis.orthonormalized()
	var from_eyes: Vector3 = facing.inverse() * (spyglass.global_position - spyglass.eyes.global_position)
	assert_almost_eq(from_eyes, spyglass.eye_offset, Vector3.ONE * 0.02, "The eyepiece sits at the right eye")
	assert_gt(spyglass.global_basis.z.dot(facing.z), 0.95, "looking the way the Player faces")


func test_the_player_stands_still_while_looking() -> void:
	await _press_scope()
	await wait_seconds(0.3)
	var start: Vector3 = player.global_position
	Input.action_press("move_up")
	await wait_seconds(1.0)
	Input.action_release("move_up")
	assert_lt((player.global_position - start).length(), 0.05, "Walking input does not move a Player looking through it")


func test_the_wheel_zooms_within_its_limits() -> void:
	await _press_scope()
	await wait_seconds(0.3)
	var before: float = spyglass.magnification
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await wait_process_frames(2)
	assert_almost_eq(spyglass.magnification, before * spyglass.zoom_step, 0.001, "The wheel zooms in a step")
	assert_eq(spyglass.zoom_label.text, "%.1fx" % spyglass.magnification, "and the porthole says how far")
	spyglass.zoom_to(1000.0)
	assert_eq(spyglass.magnification, spyglass.max_magnification, "never past its limit")
	spyglass.zoom_to(0.1)
	assert_eq(spyglass.magnification, spyglass.min_magnification)


func test_it_only_comes_out_standing_and_comes_down_when_that_ends() -> void:
	assert_true(Spyglass.can_scope_in(NodeStateMachine.States.STANDING))
	assert_true(Spyglass.can_scope_in(NodeStateMachine.States.CROUCHING))
	assert_false(Spyglass.can_scope_in(NodeStateMachine.States.SWIMMING), "Not swimming")
	assert_false(Spyglass.can_scope_in(NodeStateMachine.States.FALLING), "nor in the air")
	await _press_scope()
	player.current_state = NodeStateMachine.States.FALLING
	await wait_physics_frames(2)
	assert_false(player.is_scoping, "Knocked off the ground, it comes down on its own")


func test_the_magnification_narrows_the_view_as_a_lens_does() -> void:
	assert_almost_eq(Spyglass.zoomed_fov(75.0, 1.0), 75.0, 0.001, "1x is the view as it was")
	var four: float = Spyglass.zoomed_fov(75.0, 4.0)
	assert_almost_eq(tan(deg_to_rad(four) * 0.5) * 4.0, tan(deg_to_rad(75.0) * 0.5), 0.0001, "4x shows a quarter of the width")


func test_scoping_replicates() -> void:
	var sync: MultiplayerSynchronizer = null
	for child: Node in player.get_children():
		if child is MultiplayerSynchronizer and (child as MultiplayerSynchronizer).replication_config.has_property(^".:is_scoping"):
			sync = child
	assert_not_null(sync, "is_scoping is in the Player's replication, so every peer raises it")
	watch_signals(player)
	player.is_scoping = true
	assert_signal_emitted_with_parameters(player, "scoping_changed", [true])


## The arm at the eye is one a person can make: the elbow bent, low in front of the chest, and the wrist near straight.
## A grip with the fingers pointing down once put the forearm above the hand and folded the wrist back on itself.
func test_the_arm_holding_it_up_is_a_human_one() -> void:
	spyglass.raise_time = 5.0
	await _press_scope()
	spyglass._tween.kill()
	spyglass.hand_ik.influence = 1.0
	spyglass.hand_rotation.influence = 1.0
	var skeleton: Skeleton3D = player.get_node("PlayerModel/Armature/GeneralSkeleton")
	var joints: Dictionary = {}
	for bone: String in ["RightUpperArm", "RightLowerArm", "RightHand", "RightMiddleProximal"]:
		var at := BoneAttachment3D.new() # follows the pose after the IK, which a bone pose read does not
		at.bone_name = bone
		skeleton.add_child(at)
		joints[bone] = at
	await wait_physics_frames(4)
	var shoulder: Vector3 = (joints["RightUpperArm"] as Node3D).global_position
	var elbow: Vector3 = (joints["RightLowerArm"] as Node3D).global_position
	var wrist: Vector3 = (joints["RightHand"] as Node3D).global_position
	var knuckles: Vector3 = (joints["RightMiddleProximal"] as Node3D).global_position
	var wrist_bend: float = 180.0 - rad_to_deg((elbow - wrist).angle_to(knuckles - wrist))
	assert_lt(wrist_bend, 30.0, "The wrist bends %.0f degrees, well inside what a wrist does" % wrist_bend)
	assert_lt(elbow.y, shoulder.y, "The elbow is below the shoulder")
	assert_lt(elbow.y, wrist.y, "and below the hand, the forearm standing up under the fist")
