extends GutTest

## Purpose: first person is playable with a weapon. The camera sits at the eyes on the Head bone and stays there
## whatever the pitch, the face is clipped out, the body turns with the view at once so the hands never sweep
## across the screen, and a gun in hand keeps the torso following the view so the arms pitch with it.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const FIREARM_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/firearm.gd")
const BOW_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/bow.gd")
const ARROW_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/arrow.gd")

var root: Node3D
var player: Player
var camera: Camera


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	# Ground to stand on, or the Player falls throughout and every height read below is a different one
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	floor.add_child(shape)
	floor.position.y = -0.5
	root.add_child(floor)
	player = PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	camera = player.camera as Camera
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release("focus")
	Input.action_release("shoot")


## A bow with the four string markers and a template arrow, wired to the player the way equip() does.
func _equip_bow() -> Bow:
	var bow: Bow = BOW_SCRIPT.new()
	bow.equipment_type = Equipment.EquipmentType.BOW
	bow.bone_attachment_bone_name = "LeftHand"
	bow.player = player
	for entry in [["StringNocked", Vector3(0.0, 0.4, 0.1)], ["StringDrawn", Vector3(0.0, 0.8, 0.1)], ["StringHand", Vector3(0.0, 0.4, 0.1)], ["DrawElbow", Vector3(-0.3, 1.4, 0.5)]]:
		var marker := Marker3D.new()
		marker.name = entry[0]
		marker.position = entry[1]
		bow.add_child(marker)
	var arrow: RigidBody3D = RigidBody3D.new()
	arrow.set_script(ARROW_SCRIPT)
	arrow.name = "Arrow"
	arrow.position = Vector3(0.0, 0.4, 0.1)
	bow.add_child(arrow)
	root.add_child(bow)
	player.inventory.add_equipment(bow)
	player.inventory.can_player_shoot = true
	# The tests step the phases by hand; the Player's own state machine must not step them back meanwhile
	player.locomotion_node_changed.disconnect(bow._on_locomotion_node_changed)
	return bow


func _equip_pistol() -> Firearm:
	var gun: Firearm = FIREARM_SCRIPT.new()
	gun.player = player
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	gun.add_child(muzzle)
	gun.muzzle = muzzle
	var timer := Timer.new()
	timer.name = "FireTimer"
	timer.one_shot = true
	gun.add_child(timer)
	gun.fire_timer = timer
	gun.equipment_type = Equipment.EquipmentType.PISTOL
	gun.bone_attachment_bone_name = "RightHand"
	gun.can_shoot = true
	root.add_child(gun)
	var held: Firearm = player.inventory.equip_pickup(gun) as Firearm
	held.muzzle = held.get_node("Muzzle") as Marker3D
	held.fire_timer = held.get_node("FireTimer") as Timer
	return held


func test_first_person_sits_at_the_eyes_and_stays_there_looking_down() -> void:
	var original_near: float = camera.near
	camera.perspective = Camera.Perspective.FIRST_PERSON
	await wait_physics_frames(3)
	assert_true(player.is_first_person)
	assert_eq(camera.first_person_bone_attachment.bone_name, "Head", "The eye point rides the Head bone, not the neck")
	var eyes: Vector3 = camera.first_person_eyes.global_position
	assert_almost_eq(camera.global_position, eyes, Vector3.ONE * 0.01, "The camera is at the eyes")
	assert_between(eyes.y - player.global_position.y, 1.55, 1.8, "which are eye height on this rig")
	assert_almost_eq(camera.near, camera.first_person_near, 0.001, "with the face clipped out")

	player.camera_mount.rotation.x = deg_to_rad(-60.0)
	await wait_physics_frames(3)
	# The head tips down with the camera now, and the eyes ride it, so they dip a few centimetres; nothing like the
	# 26 cm drop into the chest this guards against
	assert_almost_eq(camera.global_position.y, eyes.y, 0.08,
			"Looking down leaves the camera at the eyes; it used to drop 26 cm into the chest")
	assert_almost_eq(rad_to_deg(camera.global_rotation.x), -60.0, 1.0, "and the view is the mount's pitch")

	camera.perspective = Camera.Perspective.THIRD_PERSON
	await wait_physics_frames(2)
	assert_almost_eq(camera.near, original_near, 0.001, "Third person gets the scene's near back")
	assert_gt(camera.global_position.distance_to(player.camera_mount.global_position), 1.0,
			"and its place out on the spring arm")


func test_the_body_turns_with_the_view_at_once_in_first_person() -> void:
	camera.perspective = Camera.Perspective.FIRST_PERSON
	await wait_physics_frames(3)
	player.camera_mount.rotation.y += deg_to_rad(90.0)
	await wait_physics_frames(2)
	var lag: float = rad_to_deg(wrapf(player.player_model.global_rotation.y - (player.camera_mount.global_rotation.y + PI), -PI, PI))
	assert_almost_eq(lag, 0.0, 1.0, "The model faces the view within a physics frame; it used to be 43 degrees behind 50 ms after a turn")


func test_a_gun_in_hand_glues_the_hands_to_the_view_in_first_person() -> void:
	var gun: Firearm = _equip_pistol()
	await wait_physics_frames(2)
	var spine: LookAtModifier3D = player.look_at_modifier as LookAtModifier3D
	assert_false(spine.active, "Third person with the gun lowered leaves the torso to the animation")
	assert_false(player.right_hand_ik.active)
	assert_false(player.left_hand_ik.active)

	camera.perspective = Camera.Perspective.FIRST_PERSON
	await wait_physics_frames(2)
	assert_true(player.right_hand_ik.active, "First person puts the right hand on its view marker")
	assert_eq(player.right_hand_ik.get_node(player.right_hand_ik.get_target_node(0)), player.first_person_right_hand)
	assert_almost_eq(player.right_hand_ik.influence, 1.0, 0.001)
	assert_true(player.left_hand_ik.active, "and the left on its own")
	assert_true(player.first_person_right_hand_rotation.active, "with both hands turned to the view")
	assert_true(player.first_person_left_hand_rotation.active)
	assert_eq(player.first_person_right_hand.transform, gun.first_person_right_hand, "where the gun says its grip sits")
	assert_eq(player.first_person_left_hand.transform, gun.first_person_left_hand)
	assert_false(spine.active, "and the torso, with the head and the camera on it, is left alone")

	Input.action_press("focus")
	await wait_physics_frames(2)
	assert_true(player.right_hand_ik.active, "Aiming in first person is the same rig")
	assert_false(spine.active)

	camera.perspective = Camera.Perspective.THIRD_PERSON
	await wait_physics_frames(2)
	assert_true(spine.active, "Back in third person the aim turns the torso instead")
	assert_false(player.right_hand_ik.active, "and the hands are given back")
	assert_eq(player.right_hand_ik.get_target_node(0), NodePath(""), "with the right IK's target cleared for whoever asks next")
	assert_false(player.left_hand_ik.active)
	assert_false(player.first_person_right_hand_rotation.active)

	Input.action_release("focus")
	await wait_physics_frames(2)
	assert_false(spine.active, "Lowering the gun in third person hands the torso back")


var _hand_forward: Vector3 = Vector3.ZERO ## The right hand's finger axis, sampled at the skeleton's update once the modifiers have run.
var _hand_vs_marker_deg: float = 0.0
var _spine_rotation: Quaternion = Quaternion.IDENTITY
var _right_hand_miss: float = 0.0


func _sample_rig() -> void:
	var skeleton: Skeleton3D = player.look_at_modifier.get_skeleton()
	var hand: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
	_hand_forward = hand.basis.y.normalized()
	_hand_vs_marker_deg = rad_to_deg(hand.basis.get_rotation_quaternion().angle_to(player.first_person_right_hand.global_basis.get_rotation_quaternion()))
	_spine_rotation = (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Spine"))).basis.get_rotation_quaternion()
	_right_hand_miss = player.first_person_right_hand.global_position.distance_to(hand.origin)


func test_the_hands_turn_with_the_view_and_the_spine_does_not_in_first_person() -> void:
	_equip_pistol()
	camera.perspective = Camera.Perspective.FIRST_PERSON
	player.camera_mount.rotation.x = 0.0
	var skeleton: Skeleton3D = player.look_at_modifier.get_skeleton()
	skeleton.skeleton_updated.connect(_sample_rig)
	# The draw clip turns the whole body into the twisted pistol stance; let it finish before reading the spine
	await wait_physics_frames(200)
	var level: Vector3 = _hand_forward
	var level_view: Vector3 = -camera.global_basis.z
	var spine_level: Quaternion = _spine_rotation
	assert_lt(_right_hand_miss, 0.03, "The right hand is on its marker (%.3f m off)" % _right_hand_miss)
	assert_lt(_hand_vs_marker_deg, 1.0, "and turned exactly as the marker is")

	player.camera_mount.rotation.x = deg_to_rad(40.0)
	await wait_physics_frames(30)
	var up_view: Vector3 = -camera.global_basis.z
	assert_almost_eq(rad_to_deg(level.angle_to(_hand_forward)), rad_to_deg(level_view.angle_to(up_view)), 3.0,
			"The hand, and the gun in it, turns by as much as the view does, so it stays where it was on screen")
	assert_lt(_hand_vs_marker_deg, 1.0, "still exactly as the marker is")
	assert_lt(rad_to_deg(spine_level.angle_to(_spine_rotation)), 5.0,
			"and the spine has not turned with it: the torso, and the head and camera on it, are not part of the rig")
	skeleton.skeleton_updated.disconnect(_sample_rig)


func test_the_hand_rig_runs_after_the_spine_and_the_ik_before_the_rotation_copy() -> void:
	var skeleton: Skeleton3D = player.look_at_modifier.get_skeleton()
	var order: Array[Node] = skeleton.get_children()
	assert_lt(order.find(player.look_at_modifier), order.find(player.right_hand_ik),
			"The spine modifier comes first: a parent bone's modifier has to run before a child bone's")
	assert_lt(order.find(player.right_hand_ik), order.find(player.first_person_right_hand_rotation),
			"and the hand's rotation is copied after the IK has put the arm under it")
	assert_lt(order.find(player.left_hand_ik), order.find(player.first_person_left_hand_rotation))
	assert_eq(player.left_hand_ik.get_node(player.left_hand_ik.get_pole_node(0)), player.right_hand_ik.get_node(player.right_hand_ik.get_pole_node(0)),
			"Both arms share the one elbow pole")


func test_the_camera_says_when_the_perspective_changes() -> void:
	watch_signals(camera)
	camera.perspective = Camera.Perspective.FIRST_PERSON
	assert_signal_emitted_with_parameters(camera, "perspective_changed", [Camera.Perspective.FIRST_PERSON])
	camera.perspective = Camera.Perspective.FIRST_PERSON
	assert_signal_emit_count(camera, "perspective_changed", 1, "Setting it to what it already is says nothing")
	camera.toggle_perspective()
	assert_signal_emitted_with_parameters(camera, "perspective_changed", [Camera.Perspective.THIRD_PERSON])


func test_a_bow_in_hand_is_carried_in_view_then_drawn_on_its_own_string() -> void:
	var bow: Bow = _equip_bow()
	await wait_physics_frames(2)
	camera.perspective = Camera.Perspective.FIRST_PERSON
	await wait_physics_frames(2)
	assert_true(player.left_hand_ik.active, "First person holds the bow up in view")
	assert_eq(player.left_hand_ik.get_node(player.left_hand_ik.get_target_node(0)), player.first_person_left_hand)
	assert_eq(player.first_person_left_hand.transform, bow.first_person_carry_hand, "low and to the left while it is only carried")
	assert_false(player.right_hand_ik.active, "with the string hand left to the animation")

	bow._on_locomotion_node_changed("Bow/BowDrawArrow")
	await wait_seconds(bow.first_person_raise_time + 0.1)
	assert_almost_eq(player.first_person_left_hand.transform.origin, bow.first_person_aim_hand.origin, Vector3.ONE * 0.01,
			"The draw raises the bow hand to the aim")
	assert_true(player.right_hand_ik.active, "and pulls the string hand onto the bow")
	assert_eq(player.right_hand_ik.get_node(player.right_hand_ik.get_target_node(0)), bow.string_hand)
	assert_eq(player.right_hand_ik.get_node(player.right_hand_ik.get_pole_node(0)), bow.draw_elbow, "with the drawing arm's own elbow pole")
	assert_eq(player.first_person_right_hand_rotation.get_node(player.first_person_right_hand_rotation.get_reference_node(0)), bow.string_hand)
	assert_false(player.look_at_modifier.active, "The spine is not part of it in first person")
	await wait_seconds(bow.first_person_draw_time)
	assert_almost_eq(bow.string_hand.position, bow.string_drawn.position, Vector3.ONE * 0.01, "The string hand reaches full draw over the draw time")
	assert_almost_eq(bow.arrow_node.position, Vector3(0.0, 0.8, 0.1), Vector3.ONE * 0.01, "and the arrow on the string comes back with it")
	assert_almost_eq(player.right_hand_ik.influence, 1.0, 0.01, "The hand has fully reached the string by then")

	bow._on_locomotion_node_changed("Bow/ArcheryLocomotion")
	await wait_physics_frames(2)
	assert_false(player.look_at_modifier.active, "Aiming in first person still leaves the spine alone")
	assert_almost_eq(bow.string_hand.position, bow.string_drawn.position, Vector3.ONE * 0.01)

	bow._on_locomotion_node_changed("Bow/BowFireArrow")
	await wait_physics_frames(2)
	assert_almost_eq(bow.string_hand.position, bow.string_nocked.position, Vector3.ONE * 0.01, "Release lets the string go at once")
	assert_almost_eq(bow.arrow_node.position, Vector3(0.0, 0.4, 0.1), Vector3.ONE * 0.01, "and the arrow is back at rest")
	assert_almost_eq(player.first_person_left_hand.transform.origin, bow.first_person_aim_hand.origin, Vector3.ONE * 0.01, "with the bow still up")

	bow._on_locomotion_node_changed("Bow/BowLocomotion")
	await wait_seconds(bow.first_person_raise_time + 0.1)
	assert_almost_eq(player.first_person_left_hand.transform.origin, bow.first_person_carry_hand.origin, Vector3.ONE * 0.01, "Lowering the bow carries it again")
	assert_false(player.right_hand_ik.active, "and frees the string hand")

	camera.perspective = Camera.Perspective.THIRD_PERSON
	await wait_physics_frames(2)
	assert_false(player.left_hand_ik.active, "Third person gives the arms back")
	bow._on_locomotion_node_changed("Bow/ArcheryLocomotion")
	assert_true(player.look_at_modifier.active, "and aims with the spine as before")
	assert_eq(player.right_hand_ik.get_node(player.right_hand_ik.get_pole_node(0)), player.hand_ik_pole, "The right IK's pole is back on the shared one")


func test_a_bow_without_string_markers_only_glues_the_bow_hand() -> void:
	var bow: Bow = BOW_SCRIPT.new()
	bow.equipment_type = Equipment.EquipmentType.BOW
	bow.player = player
	root.add_child(bow)
	player.inventory.add_equipment(bow)
	await wait_physics_frames(2)
	camera.perspective = Camera.Perspective.FIRST_PERSON
	await wait_physics_frames(2)
	bow._on_locomotion_node_changed("Bow/BowDrawArrow")
	await wait_physics_frames(2)
	assert_true(player.left_hand_ik.active, "The bow hand rides the view")
	assert_false(player.right_hand_ik.active, "but with nothing on the bow to pull it to, the string hand stays with the animation")

