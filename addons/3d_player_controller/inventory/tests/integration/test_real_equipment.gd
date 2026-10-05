extends GutTest

## Needs the real player controller: the Mixamo skeleton, the Player's equipped flags and its walk-over pickups.
##
## Purpose: an equipment item picked up through the inventory sits on the real RightHand bone with its offsets and
## turns the Player's equipped flag on; the real addon's Equipment.equip goes through Inventory.equip_pickup and
## remembers the copy; dropped equipment is taken again by walking back over it.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const SWORD: Item = preload("res://addons/3d_player_controller/inventory/resources/items/wooden_sword.tres")

var root: Node3D
var player: Player
var inventory: Inventory


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(20.0, 1.0, 20.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	inventory = player.inventory
	await wait_physics_frames(3)


func test_equipment_sits_on_the_right_hand_bone_with_its_offsets() -> void:
	assert_eq(inventory.add_item(SWORD), 0)
	var sword: Equipment = inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H)
	var attachment: BoneAttachment3D = sword.get_parent() as BoneAttachment3D
	assert_eq(attachment.get_parent(), player.skeleton, "The attachment hangs off the Player's skeleton")
	assert_ne(player.skeleton.find_bone("RightHand"), -1, "The Mixamo skeleton has a RightHand bone")
	assert_eq(attachment.bone_idx, player.skeleton.find_bone("RightHand"), "and the sword is on it")
	assert_eq(sword.position, sword.position_offset, "The copy carries the scene's position offset")
	assert_almost_eq(sword.rotation_degrees.y, sword.rotation_offset_degrees.y, 0.01, "and its rotation offset")
	assert_true(player.equipped_sword_1h, "The Player's own equipped flag reads the inventory")
	inventory.unequip_all()
	assert_false(player.equipped_sword_1h)


func test_equip_on_a_world_pickup_goes_through_the_inventory_and_remembers_the_copy() -> void:
	var pickup: Equipment = SWORD.equipment_scene.instantiate() as Equipment
	root.add_child(pickup)
	pickup.global_position = player.global_position + Vector3(0.0, 0.0, 4.0) # beyond its walk-over reach
	await wait_physics_frames(2)
	assert_eq(inventory.get_all_weapons().size(), 0, "Out of reach, nothing is taken")
	assert_true(pickup.equip(player), "The real addon's entry point equips")
	var copy: Equipment = inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H)
	assert_eq(pickup.equipment_instance, copy, "and the pickup remembers the copy the inventory made")
	assert_eq(copy.player, player)
	var attachment: BoneAttachment3D = copy.get_parent() as BoneAttachment3D
	assert_eq(attachment.get_parent(), player.skeleton, "Under the skeleton")
	assert_eq(attachment.bone_name, "RightHand", "on the scene's bone")
	assert_eq(player.skeleton.get_child(player.skeleton.get_child_count() - 1), attachment, "added last")
	assert_eq(copy.position, pickup.position_offset, "with the scene's offsets")
	assert_almost_eq(copy.rotation_degrees.y, pickup.rotation_offset_degrees.y, 0.01)
	assert_eq(copy.scale, pickup.scale_offset)
	assert_true((copy.get_node("PlayerDetection/CollisionShape3D") as CollisionShape3D).disabled, "The copy detects nobody")
	assert_false((copy.get_node("Hitbox/CollisionShape3D") as CollisionShape3D).disabled, "but its hitbox still counts")
	assert_true(copy.weapon_body.get_collision_exceptions().has(player), "and its weapon body never hits its own Player")
	assert_false(pickup.equip(player), "A second of the same type on the same bone is refused")
	assert_eq(pickup.equipment_instance, copy, "and the copy remembered stays")
	inventory.unequip_all()
	assert_false(player.equipped_sword_1h)


func test_walking_back_over_dropped_equipment_picks_it_up_again() -> void:
	inventory.add_item(SWORD)
	var sword: Equipment = inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H)
	var dropped: Node3D = inventory.drop_equipment(sword)
	await wait_physics_frames(2)
	assert_eq(inventory.get_all_weapons().size(), 0, "Standing on the dropped sword does not take it straight back")
	assert_eq(dropped.get_meta("dropped_by"), player, "Until the Player steps away")
	player.warp_to(Transform3D(Basis(), player.global_position + Vector3(6.0, 0.0, 0.0)))
	await wait_physics_frames(2)
	assert_false(dropped.has_meta("dropped_by"), "Stepping away re-arms the pickup")
	player.warp_to(Transform3D(Basis(), dropped.global_position))
	await wait_physics_frames(2)
	assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "Walking back over it picks it up again")
