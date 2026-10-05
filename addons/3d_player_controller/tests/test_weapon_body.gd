extends GutTest

## Purpose: A melee weapon's WeaponBody is a kinematic blade on the Weapons layer that shoves Hittable props with the
## swing's real motion and nothing else; an equipped copy ignores its Player, collides only mid-swing, and
## HitDetection applies no synthetic knockback of its own.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const SWORD_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/demo/wooden_sword.tscn")

const WEAPONS_BIT: int = 1 << (HitDetection.WEAPONS_LAYER - 1)
const HITTABLE_LAYER: int = 11
const HITTABLE_BIT: int = 1 << (HITTABLE_LAYER - 1)


class Spy extends CharacterBody3D:
	var hits: int = 0
	var impulses: int = 0

	func register_weapon_hit(_equipment: Node, _hit_node: Node) -> void:
		hits += 1

	func apply_impulse(_impulse: Vector3, _position: Vector3 = Vector3.ZERO) -> void:
		impulses += 1


func _rigid(at: Vector3, layer: int, mask: int) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.collision_layer = layer
	body.collision_mask = mask
	body.gravity_scale = 0.0
	body.can_sleep = false
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	(shape.shape as SphereShape3D).radius = 0.2
	body.add_child(shape)
	body.position = at
	add_child_autofree(body)
	return body


func test_the_sword_scene_carries_a_kinematic_blade_on_the_weapons_layer() -> void:
	var sword: Equipment = SWORD_SCENE.instantiate()
	add_child_autofree(sword)
	var body: AnimatableBody3D = sword.get_node("WeaponBody")
	assert_eq(sword.weapon_body, body, "Equipment finds its WeaponBody")
	assert_false(body.sync_to_physics, "A synced body ignores the bone attachment moving it; off, it follows and still pushes")
	assert_eq(body.collision_layer, WEAPONS_BIT, "On the Weapons layer and nothing else")
	assert_eq(body.collision_mask, HITTABLE_BIT, "Masking only Hittable props, never characters on layer 1")
	var shape: CollisionShape3D = body.get_node("CollisionShape3D")
	assert_eq(shape.shape, (sword.get_node("Hitbox/CollisionShape3D") as CollisionShape3D).shape, "The blade is the Hitbox's shape")


func test_an_equipped_copy_ignores_its_player_and_collides_only_mid_swing() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var pickup: Equipment = SWORD_SCENE.instantiate()
	add_child_autofree(pickup)
	var copy: Equipment = player.inventory.equip_pickup(pickup)
	assert_not_null(copy, "The sword is equipped")
	var body: AnimatableBody3D = copy.weapon_body
	assert_not_null(body, "The copy keeps its WeaponBody")
	assert_false((body.get_node("CollisionShape3D") as CollisionShape3D).disabled, "Its shape stays enabled on the skeleton")
	var exceptions: Array[PhysicsBody3D] = body.get_collision_exceptions()
	assert_true(exceptions.has(player), "The blade never touches the Player swinging it")
	assert_gt(exceptions.size(), 1, "nor their ragdoll bones")
	assert_false(body.get_collision_layer_value(HitDetection.WEAPONS_LAYER), "At rest the blade is on no layer, so a drawn sword nudges nothing")

	var hit_detection: HitDetection = player.get_node("HitDetection")
	hit_detection._on_locomotion_node_changed("GreatSword/GreatSwordDownwardSlash")
	assert_true(body.get_collision_layer_value(HitDetection.WEAPONS_LAYER), "A swing node puts it on the Weapons layer")
	hit_detection._on_locomotion_node_changed("Standing")
	assert_false(body.get_collision_layer_value(HitDetection.WEAPONS_LAYER), "and the next node takes it off again")
	hit_detection._on_locomotion_node_changed("ShortHeadJab")
	player.inventory.stow_equipment(copy)
	assert_false(body.get_collision_layer_value(HitDetection.WEAPONS_LAYER), "Stowing mid-swing switches the blade off")


func test_the_moving_blade_shoves_hittable_props_and_nothing_on_layer_one() -> void:
	var sword: Equipment = SWORD_SCENE.instantiate()
	add_child_autofree(sword)
	var prop: RigidBody3D = _rigid(Vector3(1.0, 0.45, 0.0), HITTABLE_BIT, WEAPONS_BIT)
	var bystander: RigidBody3D = _rigid(Vector3(2.0, 0.45, 0.0), 1, 1)
	var npc: CharacterBody3D = CharacterBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	npc.add_child(shape)
	npc.position = Vector3(3.0, 0.45, 0.0)
	add_child_autofree(npc)
	await wait_physics_frames(2)
	# The bone attachment carries the weapon in play; here the sword root plays that part
	for i: int in range(40):
		sword.global_position.x += 0.1
		await wait_physics_frames(1)
	assert_gt(prop.linear_velocity.length(), 0.5, "The Hittable prop takes the blade's velocity")
	assert_almost_eq(bystander.linear_velocity, Vector3.ZERO, Vector3.ONE * 0.001, "A body on layer 1 is never touched")
	assert_almost_eq(npc.global_position, Vector3(3.0, 0.45, 0.0), Vector3.ONE * 0.001, "nor a character on layer 1")


func test_hit_detection_registers_the_hit_without_any_impulse() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var hit_detection: HitDetection = player.get_node("HitDetection")
	var spy: Spy = Spy.new()
	add_child_autofree(spy)
	hit_detection._on_locomotion_node_changed("ShortHeadJab")
	hit_detection._on_hitbox_body_entered(spy, hit_detection.right_hand_hitbox, null)
	assert_eq(spy.hits, 1, "The target is told about the hit")
	assert_eq(spy.impulses, 0, "and is never shoved by HitDetection")
	var source: String = FileAccess.get_file_as_string("res://addons/3d_player_controller/scripts/hit_detection.gd")
	assert_false(source.contains("apply_impulse"), "No knockback code is left in HitDetection")
	assert_false(source.contains("no_knockback_until"), "nor the log's knockback grace")
