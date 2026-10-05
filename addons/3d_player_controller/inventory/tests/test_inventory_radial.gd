extends GutTest

## Purpose: To test weapon cycling, backpack equipping and the radial menu hold timer.

class InventoryTestBase:
	extends GutTest

	const ContractActions: GDScript = preload("res://addons/3d_player_controller/inventory/tests/contract_actions.gd")

	var PlayerScene = load("res://addons/3d_player_controller/scenes/player.tscn")
	var root: Node3D = null
	var player_instance: Player = null
	var actions: RefCounted = ContractActions.new()

	func before_all() -> void:
		actions.add_missing()

	func after_all() -> void:
		actions.remove_added()

	func before_each() -> void:
		root = Node3D.new()
		add_child_autofree(root)
		player_instance = PlayerScene.instantiate() as Player
		root.add_child(player_instance)
		await wait_physics_frames(2)

	func after_each() -> void:
		Input.action_release("last_weapon")
		Input.action_release("next_weapon")
		if is_instance_valid(root):
			root.free()
			root = null
			player_instance = null

	## A world item ready to be equipped onto the given bone.
	func make_equipment(type: Equipment.EquipmentType, bone: String) -> Equipment:
		var item = Equipment.new()
		item.equipment_type = type
		item.bone_attachment_bone_name = bone
		root.add_child(item)
		return item


class TestRadialMenuHold:
	extends InventoryTestBase

	func test_radial_menu_is_menu_held_returns_true_for_last_or_next_weapon():
		var radial_menu = player_instance.radial_menu
		Input.action_press("last_weapon")
		assert_true(radial_menu.is_menu_held(), "is_menu_held should return true when last_weapon is pressed")
		Input.action_release("last_weapon")
		Input.action_press("next_weapon")
		assert_true(radial_menu.is_menu_held(), "is_menu_held should return true when next_weapon is pressed")
		Input.action_release("next_weapon")

	func test_hold_timer_opens_menu_and_tap_cycles():
		var inventory: Inventory = player_instance.inventory
		var radial_menu = player_instance.radial_menu
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)

		sender.action_down("next_weapon")
		await wait_physics_frames(1)
		assert_false(inventory.hold_timer.is_stopped(), "Pressing next_weapon should start the hold timer")
		assert_false(radial_menu.visible, "Menu should stay closed before the hold timer elapses")

		await wait_for_signal(inventory.hold_timer.timeout, inventory.hold_timer.wait_time + 0.5)
		await wait_physics_frames(1)
		assert_true(radial_menu.visible, "Holding next_weapon past the timer should open the radial menu")

		sender.action_up("next_weapon")
		await wait_physics_frames(2)
		assert_false(radial_menu.visible, "Releasing should close the radial menu")


class TestCycleAndBackpack:
	extends InventoryTestBase

	## A sword and a shield are out together on two bones; forward used to step onto the shield, already out, and stop.
	func test_cycling_forward_from_a_sword_and_shield_moves_on():
		var inventory: Inventory = player_instance.inventory
		var bow = make_equipment(Equipment.EquipmentType.BOW, "LeftHand")
		var pistol = make_equipment(Equipment.EquipmentType.PISTOL, "RightHand")
		var sword = make_equipment(Equipment.EquipmentType.SWORD_1H, "RightHand")
		var shield = make_equipment(Equipment.EquipmentType.SWORD_AND_SHIELD, "LeftLowerArm")
		for item: Equipment in [bow, pistol, sword, shield]:
			inventory.equip_pickup(item)
		assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The sword is out")
		assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_AND_SHIELD), "and the shield with it")

		inventory.cycle_weapon(1)
		assert_true(inventory.is_unarmed(), "Forward past the last weapon is empty hands")
		inventory.cycle_weapon(1)
		assert_true(inventory.has_equipment(Equipment.EquipmentType.BOW), "then round to the first, the bow")
		inventory.cycle_weapon(1)
		assert_true(inventory.has_equipment(Equipment.EquipmentType.PISTOL), "then the pistol")

	func test_cycling_back_from_a_sword_and_shield_reaches_the_pistol():
		var inventory: Inventory = player_instance.inventory
		var pistol = make_equipment(Equipment.EquipmentType.PISTOL, "RightHand")
		var sword = make_equipment(Equipment.EquipmentType.SWORD_1H, "RightHand")
		var shield = make_equipment(Equipment.EquipmentType.SWORD_AND_SHIELD, "LeftLowerArm")
		for item: Equipment in [pistol, sword, shield]:
			inventory.equip_pickup(item)
		inventory.cycle_weapon(-1)
		assert_true(inventory.has_equipment(Equipment.EquipmentType.PISTOL), "Back from the sword and shield is the pistol")

	func test_cycle_weapon_and_equip_from_backpack_emit_equipment_changed():
		var inventory: Inventory = player_instance.inventory
		var sword = make_equipment(Equipment.EquipmentType.SWORD_1H, "RightHand")
		var axe = make_equipment(Equipment.EquipmentType.AXE_1H, "RightHand")
		inventory.equip_pickup(sword)
		inventory.equip_pickup(axe)

		# Same bone: the sword was stowed, the axe is equipped
		assert_true(inventory.has_equipment(Equipment.EquipmentType.AXE_1H), "Axe should be equipped")
		assert_false(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "Sword should be stowed")
		assert_eq(inventory.get_all_weapons().size(), 2, "Both items should be in the loadout")

		watch_signals(inventory)
		inventory.cycle_weapon(1)
		assert_signal_emitted(inventory, "equipment_changed", "cycle_weapon should emit equipment_changed")
		assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "Cycling should equip the stowed sword")
		assert_true(inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H) is Equipment, "Lookup returns a typed Equipment")

		inventory.unequip_all()
		assert_true(inventory.is_unarmed(), "unequip_all should leave the player unarmed")
		var attachment: BoneAttachment3D = inventory.get_all_weapons()[0].get_parent() as BoneAttachment3D
		assert_eq(attachment.get_parent(), inventory, "Stowed attachments live under the inventory")

		watch_signals(inventory)
		inventory.equip_from_backpack(attachment)
		assert_signal_emitted(inventory, "equipment_changed", "equip_from_backpack should emit equipment_changed")
		assert_eq(attachment.get_parent(), player_instance.skeleton, "Equipped attachments live under the skeleton")


class TestWheelCap:
	extends InventoryTestBase

	func test_the_wheel_shows_eight_items_at_most():
		var wheel: RadialMenu = player_instance.radial_menu
		assert_eq(wheel.max_items, 8)
		wheel.custom_item_provider = func() -> Array:
			var items: Array = []
			for i in 12:
				items.append({"display_name": "Station %d" % i, "icon": null})
			return items
		wheel.update_items()
		assert_eq(wheel.weapons.size(), 8, "Twelve stations offered, eight wedges drawn")
		wheel.custom_item_provider = Callable()
		for i in 10:
			player_instance.inventory.equip_pickup(make_equipment(Equipment.EquipmentType.values()[i], "RightHand"))
		assert_eq(player_instance.inventory.get_all_weapons().size(), 8, "The inventory itself stops at eight weapons")
		wheel.update_items()
		assert_eq(wheel.weapons.size(), 9, "Eight weapons plus the Unarmed wedge")



class TestPuppetEquipment:
	extends InventoryTestBase

	const SWORD_SCENE: String = "res://addons/3d_player_controller/inventory/scenes/demo/wooden_sword.tscn"

	## A peer's copy of the Player has no save and walks over nothing; the authority's list, rebuilt from scene
	## paths, puts the same pieces on its skeleton so its stances read there.
	func test_a_puppet_rebuilds_the_authoritys_equipment_from_scene_paths() -> void:
		var puppet: Player = PlayerScene.instantiate() as Player
		puppet.set_multiplayer_authority(2)
		root.add_child(puppet)
		await wait_physics_frames(1)
		puppet.inventory.synced_equipment = {SWORD_SCENE: true} # as the PlayerSynchronizer sets it
		assert_true(puppet.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The sword is on the puppet's skeleton")
		assert_true(puppet.equipped_sword_1h, "so the AnimationTree's equipped_* edges hold the stance")
		var sword: Equipment = puppet.inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H)
		assert_eq(sword.get_parent().get_parent(), puppet.skeleton)
		puppet.inventory.synced_equipment = {SWORD_SCENE: false}
		assert_false(puppet.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "Stowed on the authority, stowed here")
		assert_eq(puppet.inventory.get_all_weapons().size(), 1, "but still carried")
		puppet.inventory.synced_equipment = {}
		assert_eq(puppet.inventory.get_all_weapons().size(), 0, "Dropped there, gone here")

	func test_the_authority_keeps_its_own_equipment() -> void:
		player_instance.inventory.synced_equipment = {SWORD_SCENE: true}
		assert_false(player_instance.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "A sync is for puppets; the authority's list is its own")
		player_instance.inventory._publish_equipment()
		assert_eq(player_instance.inventory.synced_equipment, {}, "and what it publishes is what it actually carries")


class TestCyclingGuards:
	extends InventoryTestBase

	func test_no_cycling_while_paused_or_typing() -> void:
		var inventory: Inventory = player_instance.inventory
		var press := InputEventAction.new()
		press.action = "next_weapon"
		press.pressed = true
		player_instance.is_paused = true
		inventory._unhandled_input(press)
		assert_true(inventory.hold_timer.is_stopped(), "Paused, the hold timer never starts")
		player_instance.is_paused = false
		player_instance.is_typing = true
		inventory._unhandled_input(press)
		assert_true(inventory.hold_timer.is_stopped(), "Typing in the chat, neither")
		player_instance.is_typing = false
		inventory._unhandled_input(press)
		assert_false(inventory.hold_timer.is_stopped(), "Back in the game the press counts")
		inventory.hold_timer.stop()

	func test_an_empty_wheel_neither_opens_nor_divides_by_zero() -> void:
		var wheel: RadialMenu = player_instance.radial_menu
		wheel.custom_item_provider = func() -> Array: return []
		Input.action_press("next_weapon")
		wheel._on_hold_timer_timeout()
		assert_false(wheel.visible, "Nothing to offer, nothing to show")
		wheel.visible = true # forced open, as a provider emptied under it would leave it
		wheel._process(0.016)
		assert_eq(wheel.hovered_index, -1, "and the direction code copes with no wedges")
		Input.action_release("next_weapon")
		wheel.hide()
		wheel.custom_item_provider = Callable()

	## The action names are exported, defaulting to this addon's, so a game maps them in the inspector.
	func test_the_cycling_and_stick_actions_are_exported_with_the_defaults() -> void:
		assert_eq(player_instance.inventory.next_weapon_action, &"next_weapon")
		assert_eq(player_instance.inventory.last_weapon_action, &"last_weapon")
		var wheel: RadialMenu = player_instance.radial_menu
		assert_eq([wheel.look_left_action, wheel.look_right_action, wheel.look_up_action, wheel.look_down_action], [&"look_left", &"look_right", &"look_up", &"look_down"])
