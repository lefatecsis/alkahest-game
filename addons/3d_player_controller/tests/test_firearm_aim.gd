extends GutTest

## Purpose: a pistol or rifle in hand turns the Player's torso to the crosshair while focus or shoot is held,
## through the same spine LookAtModifier3D the bow uses, and hands it back when the gun comes down or is stowed.
## Also pins how that modifier is set up: it pitches only, relative to the animation, so a stance keeps its twist
## and the gun stays on the crosshair the body already faces.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const FIREARM_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/firearm.gd")

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release("focus")
	Input.action_release("shoot")


## A gun built in code loses its node references when equip_pickup duplicates it, so the copy is pointed at its own.
func _equip(type: Equipment.EquipmentType) -> Firearm:
	var gun: Firearm = FIREARM_SCRIPT.new()
	gun.player = player
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.3, 1.2, -0.4)
	gun.add_child(muzzle)
	gun.muzzle = muzzle
	var timer := Timer.new()
	timer.name = "FireTimer"
	timer.one_shot = true
	gun.add_child(timer)
	gun.fire_timer = timer
	gun.equipment_type = type
	gun.bone_attachment_bone_name = "RightHand"
	gun.can_shoot = true
	root.add_child(gun)
	var held: Firearm = player.inventory.equip_pickup(gun) as Firearm
	held.muzzle = held.get_node("Muzzle") as Marker3D
	held.fire_timer = held.get_node("FireTimer") as Timer
	return held


var _spine_forward: Vector3 = Vector3.ZERO ## Where the Spine bone's front pointed at the last skeleton update, in the Player's frame: +Y is up.


## Reads the pose the renderer gets. Between the AnimationTree's write and the skeleton's deferred update the bone
## still holds the raw animation, so a read in the test body would miss what the modifier did.
func _sample_spine() -> void:
	var skeleton: Skeleton3D = player.look_at_modifier.get_skeleton()
	var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Spine"))
	_spine_forward = player.global_basis.inverse() * pose.basis.z.normalized()


func test_focusing_with_a_pistol_points_the_torso_at_the_crosshair() -> void:
	_equip(Equipment.EquipmentType.PISTOL)
	await wait_physics_frames(2)
	var spine: LookAtModifier3D = player.look_at_modifier as LookAtModifier3D
	assert_false(spine.active, "Carrying the gun alone leaves the torso to the animation")

	Input.action_press("focus")
	await wait_physics_frames(2)
	assert_true(player.is_aiming_firearm, "Focus with a pistol in hand is aiming")
	assert_true(spine.active, "and aiming turns the torso to the crosshair")
	assert_eq(spine.get_node(spine.target_node), player.look_at_target,
			"at the point out along the projectile ray, the same one the bow aims at")

	Input.action_release("focus")
	await wait_physics_frames(2)
	assert_false(spine.active, "Lowering the gun hands the torso back to the animation")
	assert_eq(spine.target_node, NodePath(""))


func test_shooting_a_rifle_points_the_torso_and_stowing_it_lets_go() -> void:
	_equip(Equipment.EquipmentType.RIFLE)
	await wait_physics_frames(2)
	var spine: LookAtModifier3D = player.look_at_modifier as LookAtModifier3D

	Input.action_press("shoot")
	await wait_physics_frames(2)
	assert_true(player.is_shooting, "Shoot with a rifle in hand is shooting")
	assert_true(spine.active, "and shooting turns the torso to the crosshair even without focus")

	player.inventory.unequip_all()
	await wait_physics_frames(2)
	assert_false(spine.active, "Stowing the gun mid-burst gives the torso back")


func test_the_torso_pitches_with_the_aim() -> void:
	_equip(Equipment.EquipmentType.PISTOL)
	player.look_at_modifier.get_skeleton().skeleton_updated.connect(_sample_spine)
	player.camera_mount.rotation.x = 0.0
	Input.action_press("shoot")
	await wait_physics_frames(20)
	var level: Vector3 = _spine_forward

	player.camera_mount.rotation.x = deg_to_rad(45.0)
	await wait_physics_frames(20)
	var up: Vector3 = _spine_forward
	assert_gt(up.y, level.y + 0.4, "Aiming 45 degrees up tips the torso back: %s to %s" % [level, up])

	player.camera_mount.rotation.x = deg_to_rad(-45.0)
	await wait_physics_frames(20)
	var down: Vector3 = _spine_forward
	assert_lt(down.y, level.y - 0.4, "and aiming 45 degrees down bends it forward: %s to %s" % [level, down])

	Input.action_release("shoot")
	await wait_physics_frames(20)
	assert_almost_eq(_spine_forward.y, -0.2, 0.15, "Lowering the gun gives the animation's own lean back")


func test_the_bow_pitches_about_its_side_on_stance_and_a_gun_about_its_front() -> void:
	var spine: LookAtModifier3D = player.look_at_modifier as LookAtModifier3D
	player.set_look_at_target(player.look_at_target, Bow.AIM_AXIS)
	assert_eq(spine.forward_axis, SkeletonModifier3D.BONE_AXIS_PLUS_X,
			"The archer stands side-on, so the spine's +X is what runs down the aim")
	assert_eq(spine.primary_rotation_axis, Vector3.AXIS_Z, "and the pitch is about Z, the axis square to it")

	player.set_look_at_target(null)
	_equip(Equipment.EquipmentType.RIFLE)
	Input.action_press("focus")
	await wait_physics_frames(2)
	assert_true(spine.active)
	assert_eq(spine.forward_axis, SkeletonModifier3D.BONE_AXIS_PLUS_Z, "A gun is held out in front, so +Z again")
	assert_eq(spine.primary_rotation_axis, Vector3.AXIS_X, "pitching about X")


func test_the_spine_modifier_pitches_relative_to_the_stance() -> void:
	var spine: LookAtModifier3D = player.look_at_modifier as LookAtModifier3D
	assert_eq(spine.bone_name, "Spine", "The lowest spine bone, so the whole top half comes with it")
	assert_eq(spine.forward_axis, SkeletonModifier3D.BONE_AXIS_PLUS_Z,
			"PLUS_Z is the front of the chest, the same axis the head modifier uses, and the default a gun leaves it on")
	assert_eq(spine.primary_rotation_axis, Vector3.AXIS_X, "Pitch is a turn about X")
	assert_false(spine.use_secondary_rotation,
			"and pitch is all of it: the body already turns to the camera, so a yaw here would swing the gun off the crosshair")
	assert_true(spine.relative, "Relative to the animation, so a rifle stance keeps the twist its clip gave it")
	assert_true(spine.use_angle_limitation)
	assert_true(spine.symmetry_limitation)
	assert_between(rad_to_deg(spine.primary_limit_angle), 90.0, 150.0,
			"The symmetric limit is the whole arc, so this is about 60 degrees up or down")
	assert_gt(spine.duration, 0.0, "It eases in and out rather than snapping")
