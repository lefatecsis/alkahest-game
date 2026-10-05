extends GutTest

## Purpose: the Breath of the Wild combat and landing touches. A raised shield blocks a hit from in front and a parry
## throws the attacker back and staggers an enemy; hits shove the one they land on; a hard landing hurts and a lethal
## one kills and screams on the way down; a climbing hop costs stamina.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/enemy_npc.tscn")

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	(floor_shape.shape as BoxShape3D).size = Vector3(60.0, 1.0, 60.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	await wait_physics_frames(5)


func after_each() -> void:
	Input.action_release(&"focus")


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


## A point [param metres] in front of the Player (the way its model faces), or behind it with a negative distance.
func _ahead(metres: float) -> Vector3:
	return player.global_position + player.player_model.global_basis.z.slide(Vector3.UP).normalized() * metres + Vector3.UP


func _send(action_name: StringName, pressed: bool = true) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	Input.parse_input_event(event)


## Something that answers a parry, standing where [param at] is.
class Attacker:
	extends Node3D
	var parried_by: NodePath = ^""
	func parried(by_path: NodePath) -> void:
		parried_by = by_path


# --- Shield --------------------------------------------------------------------------------------------------------

func test_focus_with_a_shield_on_the_arm_raises_it() -> void:
	_equip_shield()
	Input.action_press(&"focus")
	await wait_physics_frames(3)
	assert_true(player.is_guarding, "Focus with a shield raises it")
	var emote: AnimationNodeStateMachinePlayback = player.animation_tree.get(Player.EMOTE_STATE_PLAYBACK_PATH)
	assert_eq(emote.get_current_node(), Player.GUARD_EMOTE, "in the guard pose")
	assert_eq(player.controls.action_label(&"action").text, "Parry", "and Action says it parries")
	Input.action_release(&"focus")
	await wait_physics_frames(3)
	assert_false(player.is_guarding, "Let go, it comes down")


func test_no_shield_no_guard() -> void:
	Input.action_press(&"focus")
	await wait_physics_frames(3)
	assert_false(player.is_guarding, "Without a shield Focus only focuses")


func test_a_raised_shield_blocks_a_hit_from_in_front_but_not_behind() -> void:
	_equip_shield()
	Input.action_press(&"focus")
	await wait_physics_frames(3)
	var full: float = player.health.health
	player.take_hit(20.0, _ahead(2.0))
	assert_eq(player.health.health, full, "A hit from in front lands on the shield")
	player.take_hit(20.0, _ahead(-2.0))
	assert_lt(player.health.health, full, "one from behind gets through")


func test_action_just_before_the_hit_parries_it_and_throws_the_attacker_back() -> void:
	_equip_shield()
	var attacker := Attacker.new()
	root.add_child(attacker)
	attacker.global_position = _ahead(1.5)
	Input.action_press(&"focus")
	await wait_physics_frames(3)
	watch_signals(player.shield_guard)
	_send(&"action")
	await wait_physics_frames(1)
	_send(&"action", false)
	var full: float = player.health.health
	player.take_hit(20.0, attacker.global_position, player.get_path_to(attacker))
	assert_eq(player.health.health, full, "Parried, nothing gets through")
	assert_signal_emitted(player.shield_guard, "parried")
	assert_eq(attacker.get_node_or_null(attacker.parried_by), player, "and the attacker is told who parried it")


func test_a_late_press_only_blocks() -> void:
	_equip_shield()
	var attacker := Attacker.new()
	root.add_child(attacker)
	attacker.global_position = _ahead(1.5)
	Input.action_press(&"focus")
	await wait_physics_frames(3)
	watch_signals(player.shield_guard)
	_send(&"action")
	await wait_physics_frames(1)
	_send(&"action", false)
	await wait_seconds(player.shield_guard.parry_window + 0.1)
	player.take_hit(20.0, attacker.global_position, player.get_path_to(attacker))
	assert_signal_emitted(player.shield_guard, "blocked", "Too late for a parry, it is a block")
	assert_signal_not_emitted(player.shield_guard, "parried")
	assert_eq(attacker.parried_by, ^"", "and the attacker is left alone")


func test_a_parried_enemy_reels_back_and_holds_its_next_swing() -> void:
	var enemy: EnemyNpc = ENEMY_SCENE.instantiate()
	enemy.position = _ahead(1.5) - Vector3.UP
	root.add_child(enemy)
	await wait_physics_frames(3)
	var start: Vector3 = enemy.global_position
	enemy.parried(enemy.get_path_to(player))
	assert_gt(enemy._staggered_until, Time.get_ticks_msec() / 1000.0, "It reels, and cannot swing again yet")
	assert_eq(enemy.anim_state, "GettingHit")
	await wait_seconds(0.4)
	assert_gt((enemy.global_position - start).slide(Vector3.UP).length(), 0.3, "thrown back from the Player")


# --- Knockback -----------------------------------------------------------------------------------------------------

func test_a_hit_shoves_the_player_away_from_it() -> void:
	var start: Vector3 = player.global_position
	player.take_hit(5.0, _ahead(1.0))
	await wait_seconds(0.4)
	var moved: Vector3 = (player.global_position - start).slide(Vector3.UP)
	assert_gt(moved.length(), 0.3, "The hit shoves the Player")
	assert_lt(moved.dot(player.player_model.global_basis.z), 0.0, "away from where it came from")


func test_a_hit_shoves_an_enemy_away_from_the_one_who_landed_it() -> void:
	var enemy: EnemyNpc = ENEMY_SCENE.instantiate()
	enemy.position = Vector3(0.0, 0.0, -3.0)
	root.add_child(enemy)
	await wait_physics_frames(3)
	var start: Vector3 = enemy.global_position
	enemy.register_weapon_hit(player, null)
	await wait_seconds(0.4)
	var moved: Vector3 = (enemy.global_position - start).slide(Vector3.UP)
	assert_gt(moved.length(), 0.3, "The hit shoves the enemy")
	assert_gt(moved.dot(start - player.global_position), 0.0, "away from the Player")


# --- Landing -------------------------------------------------------------------------------------------------------

func test_a_hard_landing_hurts_and_a_lethal_one_kills() -> void:
	var full: float = player.health.health
	player.take_fall(player.safe_fall_speed - 1.0)
	assert_eq(player.health.health, full, "A short drop is free")
	player.take_fall((player.safe_fall_speed + player.lethal_fall_speed) * 0.5)
	assert_almost_eq(player.health.health, full * 0.5, 1.0, "Halfway to lethal costs half the health")
	player.take_fall(player.lethal_fall_speed)
	assert_false(player.health.is_alive(), "A lethal landing kills")


func test_a_doomed_fall_screams_once() -> void:
	assert_not_null(player.sfx_fall_scream.stream, "The Wilhelm Scream is loaded")
	player.scream_if_doomed(player.lethal_fall_speed - 1.0)
	assert_false(player.sfx_fall_scream.playing, "Not yet: this fall is survivable")
	player.scream_if_doomed(player.lethal_fall_speed + 1.0)
	assert_true(player.sfx_fall_scream.playing, "Past the lethal speed, it screams")
	player.sfx_fall_scream.stop()
	player.scream_if_doomed(player.lethal_fall_speed + 2.0)
	assert_false(player.sfx_fall_scream.playing, "once per fall")


# --- Climbing jump -------------------------------------------------------------------------------------------------

func test_a_climbing_hop_costs_stamina() -> void:
	player.enable_stamina = true
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(10.0, 20.0, 1.0)
	wall.add_child(shape)
	root.add_child(wall)
	wall.global_position = _ahead(0.9) + Vector3(0.0, 9.0, 0.0)
	player.global_position += Vector3.UP * 3.0
	await wait_physics_frames(2)
	_send(&"jump")
	await wait_physics_frames(1)
	_send(&"jump", false)
	for frame: int in 60:
		await wait_physics_frames(1)
		if player.current_locomotion_node == "ClimbingLocomotion":
			break
	assert_eq(player.current_locomotion_node, "ClimbingLocomotion", "Jump at a wall in the air grabs it")
	var before: float = player.stamina.stamina
	_send(&"jump")
	await wait_physics_frames(1)
	_send(&"jump", false)
	var climbing: Climbing = player.get_node("NodeStateMachine/Climbing")
	assert_almost_eq(before - player.stamina.stamina, climbing.hop_stamina_cost, 3.0, "A hop takes its chunk of the wheel")
