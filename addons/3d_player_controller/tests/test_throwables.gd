extends GutTest

## Purpose: the "throw" action throws inventory items and throwable equipment. The equipped equipment goes first
## when it is throwable, else the picked (or first) throwable item; one leaves the inventory and sits in the throwing
## hand while the charge runs, flies as a ThrownItem on release, lands as a pickup that can be taken again, hurts what
## has take_hit, and pausing mid-charge puts it back. The Throw emote rides the spine blend, so locomotion goes on.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const WOODEN_SWORD_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/demo/wooden_sword.tscn")

class HitTarget extends StaticBody3D:
	var hits: Array[float] = []

	func take_hit(damage: float, _from: Vector3) -> void:
		hits.append(damage)

var root: Node3D
var player: Player
var rock: Item
var apple: Item


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(40.0, 1.0, 40.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.position = Vector3(0.0, 0.1, 0.0)
	rock = Item.new()
	rock.id = &"test_rock"
	rock.throwable = true
	rock.throw_damage = 5.0
	apple = Item.new()
	apple.id = &"test_apple"
	apple.category = Item.Category.FOOD
	apple.throwable = true
	await wait_physics_frames(3)


func after_each() -> void:
	Input.action_release("throw")
	Input.action_release("move_up")
	if is_instance_valid(root):
		root.free()
		root = null
	await wait_process_frames(1) # a thrown piece's attachment was queued for freeing (Inventory.forget_equipment)


## The inventory demo's sword, flagged throwable on the world copy so the equipped copy inherits it; it has a scene to come back from.
func _equip_throwable_sword() -> Equipment:
	var pickup: Equipment = WOODEN_SWORD_SCENE.instantiate()
	pickup.is_throwable = true
	pickup.throw_damage = 10.0
	root.add_child(pickup)
	var copy: Equipment = player.inventory.equip_pickup(pickup)
	pickup.free()
	return copy


func _thrown_items() -> Array:
	return root.get_children().filter(func(node: Node) -> bool: return node is ThrownItem)


func _item_pickups() -> Array:
	return root.get_children().filter(func(node: Node) -> bool: return node is ItemPickup)


func test_the_flags_default_to_false() -> void:
	assert_false(Item.new().throwable)
	assert_eq(Item.new().throw_damage, 0.0)
	var equipment: Equipment = Equipment.new()
	assert_false(equipment.is_throwable)
	assert_eq(equipment.throw_damage, 0.0)
	equipment.free()


func test_throwable_equipment_is_thrown_and_unequipped() -> void:
	_equip_throwable_sword()
	player.inventory.add_item(rock, 2)
	assert_true(player.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H))
	assert_true(player.held_object.start_throwable_throw(), "The equipped sword is throwable, so the throw starts")
	assert_true(player.held_object.is_holding_throwable())
	assert_true(player.held_object.is_charging_throw, "The same charge as a carried object")
	assert_eq(player.held_object.held_throwable.get_parent(), player.held_object.throw_hand, "Its scene sits in the throwing hand")
	assert_eq(player.held_object.throwable_equipment.resource_path, WOODEN_SWORD_SCENE.resource_path)
	assert_false(player.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "Unequipped")
	assert_eq(player.inventory.get_all_weapons().size(), 0, "and out of the backpack")
	assert_eq(player.inventory.count_of(rock), 2, "The rocks stay: equipment goes first")
	player.held_object.release_charging_throw()
	assert_false(player.held_object.is_holding_object())
	var thrown: Array = _thrown_items()
	assert_eq(thrown.size(), 1, "A quick tap still throws")
	var body: ThrownItem = thrown[0]
	assert_eq(body.equipment_scene.resource_path, WOODEN_SWORD_SCENE.resource_path, "The body carries the equipment's scene")
	assert_eq(body.damage, 10.0)
	assert_almost_eq(body.linear_velocity.length(), player.held_object.throw_speed * HeldObject.MIN_THROW_POWER, 0.5, "at tap power")
	assert_true(body.get_collision_exceptions().has(player), "and leaves the hand without hitting the Player")


func test_non_throwable_equipment_leaves_the_picked_item_to_be_thrown() -> void:
	var sword: Equipment = Equipment.new()
	sword.equipment_type = Equipment.EquipmentType.SWORD_1H
	sword.bone_attachment_bone_name = "RightHand"
	root.add_child(sword)
	player.inventory.equip_pickup(sword)
	player.inventory.add_item(rock, 3)
	player.inventory.add_item(apple, 2)
	player.selected_throwable = apple
	assert_true(player.held_object.start_throwable_throw())
	assert_true(player.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The sword stays in hand")
	assert_eq(player.inventory.count_of(apple), 1, "One apple left the inventory")
	assert_eq(player.inventory.count_of(rock), 3)
	assert_eq(player.held_object.throwable_item, apple)
	assert_true(player.held_object.held_throwable is Sprite3D, "No model, so the icon is in hand")
	player.held_object.execute_instant_throw(Vector3.FORWARD, 1.0)
	var thrown: Array = _thrown_items()
	assert_eq(thrown.size(), 1)
	assert_eq((thrown[0] as ThrownItem).item, apple)
	assert_null((thrown[0] as ThrownItem).equipment_scene)


func test_with_nothing_picked_the_first_throwable_goes() -> void:
	var arrows := AmmoItem.new()
	arrows.id = &"test_arrows"
	player.inventory.add_item(arrows, 5)
	player.inventory.add_item(rock, 1)
	assert_true(player.held_object.start_throwable_throw())
	assert_eq(player.held_object.throwable_item, rock, "Ammunition is not throwable; the rock is the first throwable")
	assert_eq(player.inventory.count_of(rock), 0)
	assert_eq(player.inventory.count_of(arrows), 5)


func test_nothing_throwable_means_no_throw_and_nothing_consumed() -> void:
	var arrows := AmmoItem.new()
	arrows.id = &"test_arrows"
	player.inventory.add_item(arrows, 5)
	var sword: Equipment = Equipment.new()
	sword.equipment_type = Equipment.EquipmentType.SWORD_1H
	sword.bone_attachment_bone_name = "RightHand"
	root.add_child(sword)
	player.inventory.equip_pickup(sword)
	assert_false(player.held_object.start_throwable_throw(), "Nothing throwable")
	assert_false(player.held_object.is_holding_object())
	assert_false(player.held_object.is_charging_throw)
	assert_eq(player.inventory.count_of(arrows), 5)
	assert_true(player.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H))
	assert_eq(_thrown_items().size(), 0)


func test_the_landed_item_is_a_pickup_that_can_be_taken_again() -> void:
	player.inventory.add_item(rock, 1)
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	assert_true(player.held_object.start_throwable_throw())
	player.held_object.execute_instant_throw(Vector3(0.0, -0.4, -1.0).normalized(), 1.0)
	var body: ThrownItem = _thrown_items()[0]
	await wait_for_signal(body.landed, 3.0)
	await wait_physics_frames(2)
	assert_false(is_instance_valid(body), "The body is gone once it lands")
	var pickups: Array = _item_pickups()
	assert_eq(pickups.size(), 1, "and an ItemPickup lies where it fell")
	var pickup: ItemPickup = pickups[0]
	assert_true(pickup.item.is_same(rock))
	assert_eq(pickup.count, 1)
	assert_eq(pickup.get_parent(), root)
	player.global_position = pickup.global_position
	player.velocity = Vector3.ZERO
	await wait_physics_frames(3)
	assert_eq(pickup.player, player, "Walking up to it is the walk-over pickup")
	assert_true(pickup.action_prompt.visible)
	var sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	sender.action_down("action")
	await wait_physics_frames(2)
	sender.action_up("action")
	await wait_physics_frames(2)
	assert_eq(player.inventory.count_of(rock), 1, "Action takes the rock back")
	assert_false(is_instance_valid(pickup))
	sender.release_all()
	sender.clear()


func test_throw_damage_reaches_a_take_hit_target() -> void:
	var target := HitTarget.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(4.0, 4.0, 0.2)
	target.add_child(shape)
	target.position = Vector3(0.0, 1.5, -3.0)
	root.add_child(target)
	player.inventory.add_item(rock, 1)
	assert_true(player.held_object.start_throwable_throw())
	player.held_object.execute_instant_throw(Vector3.FORWARD, 1.0)
	var body: ThrownItem = _thrown_items()[0]
	await wait_for_signal(body.landed, 3.0)
	assert_eq(target.hits, [5.0], "The rock's throw_damage landed once")
	await wait_physics_frames(2)
	assert_eq(_item_pickups().size(), 1, "and the rock lies there to be picked up")


func test_pausing_mid_charge_puts_the_throwable_back() -> void:
	player.inventory.add_item(rock, 1)
	assert_true(player.held_object.start_throwable_throw())
	assert_eq(player.inventory.count_of(rock), 0)
	player.is_paused = true
	assert_false(player.held_object.is_holding_object(), "The pause menu cancels the throw")
	assert_false(player.held_object.is_charging_throw)
	assert_eq(player.inventory.count_of(rock), 1, "The rock is back in the inventory")
	assert_eq(_thrown_items().size(), 0)
	player.is_paused = false
	var sword: Equipment = _equip_throwable_sword()
	assert_true(player.held_object.start_throwable_throw())
	assert_false(player.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H))
	player.is_paused = true
	assert_true(player.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The sword is back in hand")
	assert_ne(player.inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H), sword, "as a fresh copy from its scene")
	player.is_paused = false


func test_the_throw_emote_plays_while_the_player_keeps_moving() -> void:
	player.inventory.add_item(rock, 1)
	Input.action_press("move_up")
	await wait_physics_frames(10)
	assert_gt(player.velocity.length(), 0.5, "Running before the throw")
	assert_true(player.held_object.start_throwable_throw())
	await wait_physics_frames(20) # past CHARGE_START_DELAY, before the full charge
	var emote_state: AnimationNodeStateMachinePlayback = player.animation_tree.get(Player.EMOTE_STATE_PLAYBACK_PATH)
	assert_true(player.held_object.is_throwing, "The wind-up is on")
	assert_eq(String(emote_state.get_current_node()), "Throw", "The Throw emote plays on the emote layer")
	assert_eq(player.animation_tree.get("parameters/EmoteSpineBlend2/blend_amount"), 1.0, "blended over the spine only")
	assert_gt(player.velocity.length(), 0.5, "while the legs keep running")
	assert_true(player.held_object.is_holding_object())
	player.execute_throw() # what the Throw animation's call method track does at its release frame
	assert_eq(_thrown_items().size(), 1, "The call track releases the rock")
	assert_false(player.held_object.is_holding_object())
	Input.action_release("move_up")
