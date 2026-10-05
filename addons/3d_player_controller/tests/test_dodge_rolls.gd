extends GutTest

## Purpose: the Souls roll dives. A control scheme that rolls (Dark Souls) turns the dodge on; a tap of Sprint while
## moving plays the standing dive from a stand and the sprinting dive out of a run, a backstep when still, the
## rifle's and the bow's own dives with those in hand, and Sprint in the air the falling dive. All six clips are
## libraries on the Player's AnimationPlayer and states the tree can reach.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const FIREARM_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/firearm.gd")
const BOW_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/bow.gd")
const DARK_SOULS: ControlScheme = preload("res://addons/3d_player_controller/resources/control_schemes/dark_souls.tres")
const TOTK: ControlScheme = preload("res://addons/3d_player_controller/resources/control_schemes/tears_of_the_kingdom.tres")
const DIVE_LIBRARIES: Array[String] = ["Standing Dive Forward", "Sprinting Dive Forward", "Falling To Dive Forward",
		"Rife Standing Dive Forward", "Rifle Running Dive Forward", "Bow Standing Dive Forward"]

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	floor.add_child(shape)
	floor.position.y = -0.5
	root.add_child(floor)
	player = PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	player.control_scheme = DARK_SOULS
	await wait_physics_frames(3)


func after_each() -> void:
	Input.action_release("move_up")
	Input.action_release("crouch")


func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


## A tap of Sprint: down one frame, up the next, then a few frames for the state machines to answer.
func _tap_sprint() -> void:
	_send(&"sprint", true)
	await wait_physics_frames(1)
	_send(&"sprint", false)
	await wait_physics_frames(8)


func test_the_dark_souls_scheme_turns_the_roll_on() -> void:
	assert_true(DARK_SOULS.rolls, "Dark Souls rolls on a tap of B")
	assert_false(TOTK.rolls, "Tears of the Kingdom does not")
	assert_true(player.dodge_enabled, "so the Player under it can dodge without enable_dodge")
	player.control_scheme = TOTK
	assert_false(player.dodge_enabled)
	player.enable_dodge = true
	assert_true(player.dodge_enabled, "and enable_dodge turns it on under any scheme")


func test_every_dive_clip_is_a_library_on_the_player() -> void:
	var animation_player: AnimationPlayer = player.get_node("PlayerModel/AnimationPlayer")
	for name in DIVE_LIBRARIES:
		assert_true(animation_player.has_animation(name + "/mixamo_com"), "%s is on the AnimationPlayer" % name)


func test_a_tap_while_moving_is_the_standing_dive_and_while_still_a_backstep() -> void:
	Input.action_press("move_up")
	await wait_physics_frames(3)
	await _tap_sprint()
	assert_true(player.is_dodging, "The tap rolled")
	assert_eq(player.current_locomotion_node, "StandingDive", "on the standing dive: the Player was walking, not at a run, when B went down")
	assert_true(player.dodge_invulnerable, "with its invulnerability frames")
	await wait_seconds(3.2)
	assert_false(player.is_dodging, "The roll ends when the clip hands back")
	assert_eq(player.current_locomotion_node, "StandingLocomotion", "and the clip has handed back by then")
	Input.action_release("move_up")
	await wait_physics_frames(3)
	await _tap_sprint()
	assert_true(player.is_dodging)
	assert_eq(player.current_locomotion_node, "Backflip", "Still, the tap is the backstep")


func test_a_tap_out_of_a_run_is_the_sprinting_dive() -> void:
	Input.action_press("move_up")
	await wait_physics_frames(3)
	player.smoothed_motion = Vector2(0.0, 1.5)
	await _tap_sprint()
	assert_true(player.is_dodging)
	assert_true(player.dodge_from_run, "At a run when B went down")
	assert_eq(player.current_locomotion_node, "SprintingDive", "so it is the longer sprinting dive")


func test_a_held_sprint_let_go_and_tapped_again_is_the_sprinting_dive() -> void:
	Input.action_press("move_up")
	await wait_physics_frames(3)
	_send(&"sprint", true)
	await wait_seconds(player.dodge_tap_seconds + 0.2)
	_send(&"sprint", false)
	await wait_physics_frames(2)
	assert_false(player.is_dodging, "A hold let go is not a roll")
	await _tap_sprint()
	assert_true(player.is_dodging)
	assert_eq(player.current_locomotion_node, "SprintingDive", "but a tap right after it rolls out of the run")


func _equip(script: Script, type: Equipment.EquipmentType, bone: String) -> Equipment:
	var item: Equipment = script.new()
	item.player = player
	if item is Firearm:
		var muzzle := Marker3D.new()
		muzzle.name = "Muzzle"
		item.add_child(muzzle)
		item.muzzle = muzzle
		var timer := Timer.new()
		timer.name = "FireTimer"
		timer.one_shot = true
		item.add_child(timer)
		item.fire_timer = timer
	item.equipment_type = type
	item.bone_attachment_bone_name = bone
	root.add_child(item)
	var held: Equipment = player.inventory.equip_pickup(item)
	if held is Firearm:
		held.muzzle = held.get_node("Muzzle") as Marker3D
		held.fire_timer = held.get_node("FireTimer") as Timer
	return held


func test_a_rifle_in_hand_rolls_on_its_own_dives_inside_its_group() -> void:
	_equip(FIREARM_SCRIPT, Equipment.EquipmentType.RIFLE, "RightHand")
	await wait_seconds(3.0) # the draw clip has to finish before a roll can leave RifleLocomotion
	Input.action_press("move_up")
	await wait_physics_frames(3)
	await _tap_sprint()
	assert_true(player.is_dodging)
	assert_eq(player.current_locomotion_path, "Rifle/RifleStandingDive", "The rifle's standing dive, in the Rifle group")
	await wait_seconds(3.2)
	player.smoothed_motion = Vector2(0.0, 1.5)
	await _tap_sprint()
	assert_eq(player.current_locomotion_path, "Rifle/RifleRunningDive", "and its running dive out of a run")


func test_a_bow_in_hand_rolls_on_the_bow_dive() -> void:
	_equip(BOW_SCRIPT, Equipment.EquipmentType.BOW, "LeftHand")
	await wait_seconds(3.0)
	Input.action_press("move_up")
	await wait_physics_frames(3)
	await _tap_sprint()
	assert_true(player.is_dodging)
	assert_eq(player.current_locomotion_path, "Bow/BowDive", "The bow's dive, in the Bow group")


func test_sprint_in_the_air_is_the_falling_dive() -> void:
	player.global_position.y += 4.0
	await wait_physics_frames(4)
	assert_true(player.is_falling, "Off the ground the Player is falling")
	_send(&"sprint", true)
	await wait_physics_frames(10)
	assert_true(player.is_dodging, "Sprint in the air dives")
	assert_eq(player.current_locomotion_node, "FallingDive", "on the falling dive that rolls out of the landing")


func test_throw_with_crouch_held_in_the_air_dives_too() -> void:
	player.global_position.y += 4.0
	await wait_physics_frames(4)
	Input.action_press("crouch")
	_send(&"throw", true)
	await wait_physics_frames(10)
	assert_true(player.is_dodging, "Odyssey's ZL and Y in the air is the same dive")
	assert_eq(player.current_locomotion_node, "FallingDive")
