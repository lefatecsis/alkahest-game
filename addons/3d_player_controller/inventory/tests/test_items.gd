extends GutTest

## Purpose: The inventory keeps stacks of Items in fixed tabs: they stack to their limit, move, merge and swap, using only
## signals, dropping puts a pickup in the world, equipment items go onto the skeleton, and the whole inventory
## survives a save and a load.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const APPLE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/apple.tres")
const ORE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/iron_ore.tres")
const KEY: Item = preload("res://addons/3d_player_controller/inventory/resources/items/old_key.tres")
const SWORD: Item = preload("res://addons/3d_player_controller/inventory/resources/items/wooden_sword.tres")
const HEAL: Ability = preload("res://addons/3d_player_controller/resources/abilities/heal.tres")
const TEST_SAVE: String = "user://test_inventory.json"
const MODEL: String = "res://addons/3d_player_controller/assets/quaternius/paraglider/Paraglider.glb" ## A model file, no script of its own.
const EQUIPMENT_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/equipment.gd")
const ContractActions: GDScript = preload("res://addons/3d_player_controller/inventory/tests/contract_actions.gd")

var root: Node3D
var player: Player
var inventory: Inventory
var actions: RefCounted = ContractActions.new()
var _persistence_was_enabled: bool


func before_all() -> void:
	actions.add_missing()


func after_all() -> void:
	actions.remove_added()


func before_each() -> void:
	_persistence_was_enabled = Inventory.persistence_enabled
	Inventory.persistence_enabled = true # the suite's pre-run hook turns it off; these tests write a file of their own
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(20.0, 1.0, 20.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = _spawn_player()
	inventory = player.inventory
	await wait_physics_frames(3)


func after_each() -> void:
	Inventory.persistence_enabled = _persistence_was_enabled
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)
	await wait_process_frames(1) # forgotten equipment was queued for freeing (Inventory.forget_equipment)


func _spawn_player() -> Player:
	var spawned: Player = PLAYER_SCENE.instantiate()
	spawned.get_node("Hud/Inventory").save_path = TEST_SAVE
	root.add_child(spawned)
	return spawned


func test_items_stack_to_their_limit_and_spill_into_new_slots() -> void:
	assert_eq(inventory.add_item(APPLE, 5), 0, "Five apples fit")
	assert_eq(inventory.count_of(APPLE), 5)
	assert_eq(inventory.get_slot(Item.Category.FOOD, 0).count, 5, "One stack in the first food slot")
	assert_eq(inventory.add_item(ORE, 2000), 0, "Ore stacks to 999, so 2000 spread over three slots")
	assert_eq(inventory.get_slot(Item.Category.MATERIALS, 0).count, 999)
	assert_eq(inventory.get_slot(Item.Category.MATERIALS, 1).count, 999)
	assert_eq(inventory.get_slot(Item.Category.MATERIALS, 2).count, 2)
	assert_null(inventory.get_slot(Item.Category.MATERIALS, 3))


func test_a_full_tab_reports_what_did_not_fit() -> void:
	var left: int = inventory.add_item(KEY, inventory.slots_per_tab + 3)
	assert_eq(left, 3, "Key items do not stack, so three are left over once every slot holds one")
	assert_eq(inventory.count_of(KEY), inventory.slots_per_tab)


func test_remove_takes_from_the_last_stacks_first() -> void:
	inventory.add_item(ORE, 1500)
	assert_eq(inventory.remove_item(ORE, 600), 600)
	assert_eq(inventory.count_of(ORE), 900)
	assert_null(inventory.get_slot(Item.Category.MATERIALS, 1), "The partial second stack went first")
	assert_eq(inventory.get_slot(Item.Category.MATERIALS, 0).count, 900)
	assert_eq(inventory.remove_item(ORE, 5000), 900, "Asking for more than there is takes what there is")
	assert_false(inventory.has_item(ORE))


func test_move_swaps_merges_and_moves() -> void:
	inventory.add_item(APPLE, 5)
	var mushroom: Item = load("res://addons/3d_player_controller/inventory/resources/items/mushroom.tres")
	inventory.add_item(mushroom, 2)
	watch_signals(inventory)
	inventory.move_slot(Item.Category.FOOD, 0, 1)
	assert_eq(inventory.get_slot(Item.Category.FOOD, 0).item, mushroom, "Different items swap")
	assert_eq(inventory.get_slot(Item.Category.FOOD, 1).item, APPLE)
	inventory.move_slot(Item.Category.FOOD, 1, 4)
	assert_null(inventory.get_slot(Item.Category.FOOD, 1), "Onto an empty slot it moves")
	assert_eq(inventory.get_slot(Item.Category.FOOD, 4).count, 5)
	inventory.get_slots(Item.Category.FOOD)[2] = ItemSlot.make(APPLE, 96)
	inventory.move_slot(Item.Category.FOOD, 4, 2)
	assert_eq(inventory.get_slot(Item.Category.FOOD, 2).count, 99, "Onto the same item it merges up to the limit")
	assert_eq(inventory.get_slot(Item.Category.FOOD, 4).count, 2, "And the rest stays behind")
	assert_signal_emit_count(inventory, "items_changed", 3, "Swap, move and merge each signal once; the direct slot write does not")


func test_use_only_signals_and_consumes_consumables() -> void:
	inventory.add_item(APPLE, 3)
	inventory.add_item(ORE, 3)
	watch_signals(inventory)
	inventory.use_slot(Item.Category.FOOD, 0)
	assert_signal_emitted_with_parameters(inventory, "item_used", [APPLE, 1])
	assert_eq(inventory.count_of(APPLE), 2, "Food is consumable")
	inventory.use_slot(Item.Category.MATERIALS, 0)
	assert_signal_emit_count(inventory, "item_used", 2)
	assert_eq(inventory.count_of(ORE), 3, "Ore is not")


func test_drop_puts_a_pickup_in_front_of_the_player() -> void:
	inventory.add_item(APPLE, 3)
	watch_signals(inventory)
	var pickup: Node3D = inventory.drop_slot(Item.Category.FOOD, 0)
	assert_true(pickup is ItemPickup, "A pickup is spawned")
	assert_eq(pickup.get_parent(), root, "Beside the Player in the world")
	assert_lt(pickup.global_position.distance_to(player.global_position), 2.0)
	assert_eq(pickup.item, APPLE)
	assert_eq(pickup.count, 1, "One at a time")
	assert_eq(inventory.count_of(APPLE), 2)
	assert_signal_emitted_with_parameters(inventory, "item_dropped", [APPLE, 1, pickup])


func test_an_equipment_item_goes_onto_the_skeleton() -> void:
	assert_eq(inventory.add_item(SWORD), 0)
	assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The sword is in hand")
	assert_eq(inventory.add_item(SWORD), 1, "A second of the same type on the same bone is refused")
	var sword: Equipment = inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H)
	assert_eq(sword.scene_file_path, "res://addons/3d_player_controller/inventory/scenes/demo/wooden_sword.tscn", "The copy remembers its scene")
	assert_eq(sword.player, player, "and its Player")
	var attachment: BoneAttachment3D = sword.get_parent() as BoneAttachment3D
	assert_not_null(attachment, "The copy hangs off a BoneAttachment3D")
	assert_eq(attachment.bone_name, "RightHand", "on the bone the scene names")
	assert_eq(attachment.get_parent(), player.skeleton, "under the Player's skeleton")
	assert_eq(sword.position, sword.position_offset, "It was in the tree while it equipped, so the hand offsets reached the copy")
	assert_almost_eq(sword.rotation_degrees.y, sword.rotation_offset_degrees.y, 0.01, "rotation included")
	assert_eq(sword.scale, sword.scale_offset, "and scale")
	assert_true((sword.get_node("PlayerDetection/CollisionShape3D") as CollisionShape3D).disabled, "The copy is no pickup")
	assert_false((sword.get_node("Hitbox/CollisionShape3D") as CollisionShape3D).disabled, "but its hitbox still counts")
	assert_false((sword.get_node("WeaponBody/CollisionShape3D") as CollisionShape3D).disabled, "and its weapon body still shoves")
	var dropped: Node3D = inventory.drop_equipment(sword)
	assert_true(dropped is Equipment, "Dropping equipment puts its scene back in the world")
	assert_false(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H))
	await wait_physics_frames(2)
	assert_eq(inventory.get_all_weapons().size(), 0, "Standing on the dropped sword does not take it straight back")
	assert_eq(dropped.get_meta("dropped_by"), player, "Until the Player steps away")
	player.warp_to(Transform3D(Basis(), player.global_position + Vector3(6.0, 0.0, 0.0)))
	await wait_physics_frames(2)
	assert_false(dropped.has_meta("dropped_by"), "Stepping away re-arms the pickup; walking back over it is the real addon's pickup, see tests/integration")


func test_save_and_load_round_trip() -> void:
	inventory.add_item(APPLE, 5)
	inventory.add_item(ORE, 1200)
	inventory.add_item(KEY)
	inventory.add_item(SWORD)
	inventory.move_slot(Item.Category.FOOD, 0, 3)
	assert_eq(inventory.save(), OK)
	assert_true(FileAccess.file_exists(TEST_SAVE))

	var loaded: Player = _spawn_player()
	await wait_physics_frames(2)
	assert_true(loaded.inventory.load_save(), "The save is read")
	assert_eq(loaded.inventory.count_of(APPLE), 5)
	assert_eq(loaded.inventory.get_slot(Item.Category.FOOD, 3).count, 5, "In the slot it was moved to")
	assert_eq(loaded.inventory.get_slot(Item.Category.MATERIALS, 0).count, 999)
	assert_eq(loaded.inventory.get_slot(Item.Category.MATERIALS, 1).count, 201)
	assert_true(loaded.inventory.has_item(KEY))
	assert_true(loaded.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The sword is back in hand")

	inventory.unequip_all()
	inventory.save()
	var stowed: Player = _spawn_player()
	await wait_physics_frames(2)
	stowed.inventory.load_save()
	assert_false(stowed.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "Stowed on save, stowed on load")
	assert_eq(stowed.inventory.get_all_weapons().size(), 1, "But still owned")



## A save names each item by its res:// path, so an item the game has since renamed or removed is left out and
## everything else loads. As a .tres the one missing file failed the whole load, and the player lost every item.
func test_an_item_the_game_no_longer_has_is_skipped_and_the_rest_loads() -> void:
	inventory.add_item(APPLE, 5)
	inventory.add_item(KEY)
	inventory.add_item(SWORD)
	assert_eq(inventory.save(), OK)
	var text: String = FileAccess.get_file_as_string(TEST_SAVE)
	assert_true(text.contains(APPLE.resource_path), "Items are named by path, not embedded")
	var file: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(text.replace(APPLE.resource_path, "res://items/renamed_since.tres"))
	file.close()

	var loaded: Player = _spawn_player()
	await wait_physics_frames(2)
	assert_true(loaded.inventory.load_save(), "The save still loads")
	assert_eq(loaded.inventory.count_of(APPLE), 0, "without the item that is gone")
	assert_true(loaded.inventory.has_item(KEY), "and with everything else")
	assert_true(loaded.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H))


## A file that is not a save of this version, an old .tres or anything else, is left alone rather than guessed at.
func test_a_file_that_is_not_an_inventory_save_is_refused() -> void:
	var file: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string('[gd_resource type="Resource" format=3]')
	file.close()
	inventory.add_item(APPLE, 2)
	assert_false(inventory.load_save(), "Refused")
	assert_eq(inventory.count_of(APPLE), 2, "and what the Player carries is untouched")
	file = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(JSON.from_native({"version": Inventory.SAVE_VERSION + 1, "inventory": {}})))
	file.close()
	assert_false(inventory.load_save(), "A save of another version is refused too")
	assert_eq(inventory.count_of(APPLE), 2)


func test_persist_writes_the_file_on_every_change_and_reads_it_on_ready() -> void:
	inventory.persist = true
	inventory.add_item(APPLE, 2)
	await wait_process_frames(1) # the write is deferred to the end of the frame
	assert_true(FileAccess.file_exists(TEST_SAVE), "Adding saved")
	var reloaded: Player = PLAYER_SCENE.instantiate()
	reloaded.get_node("Hud/Inventory").save_path = TEST_SAVE
	reloaded.get_node("Hud/Inventory").persist = true
	root.add_child(reloaded)
	await wait_physics_frames(2)
	assert_eq(reloaded.inventory.count_of(APPLE), 2, "Loaded on ready")


func test_persist_is_off_by_default_so_bare_players_leave_the_disk_alone() -> void:
	assert_false(inventory.persist)
	inventory.add_item(APPLE)
	assert_false(FileAccess.file_exists(TEST_SAVE))


func test_persistence_can_be_switched_off_for_every_inventory() -> void:
	Inventory.persistence_enabled = false
	inventory.persist = true
	inventory.add_item(APPLE)
	assert_false(FileAccess.file_exists(TEST_SAVE), "The test suite's hook keeps every inventory off the disk")
	Inventory.persistence_enabled = true
	inventory.add_item(APPLE)
	await wait_process_frames(1)
	assert_true(FileAccess.file_exists(TEST_SAVE))


func test_throwables_are_listed_and_use_item_uses_the_first_stack() -> void:
	assert_false(Item.new().throwable, "Nothing is throwable unless the resource says so")
	assert_eq(Item.new().throw_damage, 0.0)
	var stone: Item = Item.new()
	stone.id = &"stone"
	stone.throwable = true
	inventory.add_item(APPLE, 3)
	inventory.add_item(ORE, 5)
	inventory.add_item(stone, 4)
	assert_eq(inventory.get_throwable_items(), [stone] as Array[Item], "Only the flagged kind, once")
	watch_signals(inventory)
	inventory.use_item(APPLE)
	assert_signal_emitted_with_parameters(inventory, "item_used", [APPLE, 1]) # use_item finds the stack and uses it as use_slot does
	assert_eq(inventory.count_of(APPLE), 2)
	inventory.use_item(Item.new())
	assert_signal_emit_count(inventory, "item_used", 1, "An item that is not carried uses nothing")


func test_forget_equipment_drops_nothing_and_add_equipment_scene_brings_it_back() -> void:
	assert_eq(inventory.add_item(SWORD), 0)
	var sword: Equipment = inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H)
	var bare: Equipment = Equipment.new()
	bare.equipment_type = Equipment.EquipmentType.DAGGER
	bare.bone_attachment_bone_name = "LeftHand"
	root.add_child(bare)
	var dagger: Equipment = inventory.equip_pickup(bare)
	assert_eq(inventory.forget_equipment(dagger), String(bare.get_path()), "Equipment from a pickup standing in the world comes back from that pickup, by its path")
	assert_false(inventory.equipment.has(dagger), "so it goes")
	watch_signals(inventory)
	var children_before: int = root.get_child_count()
	assert_eq(inventory.forget_equipment(sword), "res://addons/3d_player_controller/inventory/scenes/demo/wooden_sword.tscn", "The scene path the sword can come back from")
	assert_false(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H))
	assert_eq(inventory.get_all_weapons().filter(func(item: Equipment) -> bool: return item.equipment_type == Equipment.EquipmentType.SWORD_1H).size(), 0, "Out of the backpack")
	assert_eq(root.get_child_count(), children_before, "and no pickup in the world")
	assert_signal_emitted(inventory, "items_changed")
	var copy: Equipment = inventory.add_equipment_scene(SWORD.equipment_scene)
	assert_not_null(copy, "add_equipment_scene equips a fresh copy from the scene")
	assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H))
	assert_eq(copy.scene_file_path, "res://addons/3d_player_controller/inventory/scenes/demo/wooden_sword.tscn")
	assert_eq(copy.position, copy.position_offset, "with the hand offsets, as a walk-over pickup gets them")


func test_the_ninth_weapon_is_refused() -> void:
	assert_eq(inventory.max_equipment, 8, "BOTW's eight weapon slots by default")
	inventory.max_equipment = 2
	assert_eq(inventory.add_item(SWORD), 0)
	var dagger: Equipment = Equipment.new()
	dagger.equipment_type = Equipment.EquipmentType.DAGGER
	dagger.bone_attachment_bone_name = "RightHand"
	root.add_child(dagger)
	assert_not_null(inventory.equip_pickup(dagger), "The second weapon fits")
	assert_false(inventory.can_carry_equipment(), "Two carried, none to spare")
	var axe: Equipment = Equipment.new()
	axe.equipment_type = Equipment.EquipmentType.AXE_1H
	axe.bone_attachment_bone_name = "RightHand"
	root.add_child(axe)
	assert_null(inventory.equip_pickup(axe), "A third is refused until one is dropped")
	assert_eq(inventory.get_all_weapons().size(), 2)
	var sword: Equipment = inventory.get_all_weapons().filter(func(weapon: Equipment) -> bool: return weapon.equipment_type == Equipment.EquipmentType.SWORD_1H)[0]
	assert_not_null(inventory.drop_equipment(sword), "The sword came from a scene, so it can be dropped")
	await wait_physics_frames(1)
	assert_true(inventory.can_carry_equipment())
	assert_not_null(inventory.equip_pickup(axe), "Dropping one makes room")


## The Inventory is ready before the Player's skeleton and abilities are, so a persisted save has to wait for the
## Player's own ready: the sword goes back on the skeleton and the wheel loadout onto the abilities node.
func test_a_persisted_save_is_applied_once_the_player_is_ready() -> void:
	inventory.persist = true
	inventory.add_item(SWORD)
	inventory.spellbook.clear_active(0)
	inventory.spellbook.set_active(3, HEAL)
	await wait_process_frames(1)
	var reloaded: Player = PLAYER_SCENE.instantiate()
	reloaded.get_node("Hud/Inventory").save_path = TEST_SAVE
	reloaded.get_node("Hud/Inventory").persist = true
	root.add_child(reloaded)
	await wait_physics_frames(2)
	assert_true(reloaded.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The sword is back on a skeleton that did not exist when the Inventory was ready")
	assert_eq(reloaded.inventory.spellbook.active[3], HEAL, "The wheel slot came back")
	assert_eq(reloaded.abilities.abilities, [HEAL] as Array[Ability], "and onto the abilities node, over the scene's own spells")


## Equipment comes back as [instance, equipped] pairs, so an entry that is skipped does not hand its flag to the
## next one.
func test_a_saved_piece_that_cannot_be_recreated_does_not_shift_the_equipped_flags() -> void:
	var data: InventorySave = InventorySave.new()
	var gone: EquipmentEntry = EquipmentEntry.new()
	gone.scene_path = "res://gone.tres" # not a scene, so it is skipped
	gone.equipped = false
	var sword: EquipmentEntry = EquipmentEntry.new()
	sword.scene_path = SWORD.equipment_scene.resource_path
	sword.equipped = true
	data.equipment = [gone, sword]
	inventory.apply_save(data)
	assert_eq(inventory.get_all_weapons().size(), 1, "The unloadable piece is skipped")
	assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "and the sword keeps its own flag, not the skipped entry's")


## A piece that was added without a bone attachment (a bare fixture) leaves the set when forgotten, through the
## same stow as everything else.
func test_forgetting_a_bare_equipped_fixture_leaves_the_set() -> void:
	var bare: Equipment = Equipment.new()
	bare.equipment_type = Equipment.EquipmentType.DAGGER
	bare.scene_file_path = SWORD.equipment_scene.resource_path
	root.add_child(bare)
	inventory.add_equipment(bare)
	assert_true(inventory.has_equipment(Equipment.EquipmentType.DAGGER))
	assert_eq(inventory.forget_equipment(bare), bare.scene_file_path, "Forgotten by scene path")
	assert_false(inventory.has_equipment(Equipment.EquipmentType.DAGGER), "It left the set with no attachment to stow")


func test_autosave_writes_once_per_frame_however_many_changes() -> void:
	inventory.persist = true
	inventory.add_item(APPLE)
	inventory.add_item(ORE)
	inventory.add_item(KEY)
	assert_false(FileAccess.file_exists(TEST_SAVE), "Nothing is written in the middle of the changes")
	assert_true(inventory._save_queued, "one write is queued")
	await wait_process_frames(1)
	assert_true(FileAccess.file_exists(TEST_SAVE), "and it lands at the end of the frame")
	assert_false(inventory._save_queued)
	var loaded: Player = _spawn_player()
	await wait_physics_frames(2)
	loaded.inventory.load_save()
	assert_true(loaded.inventory.has_item(KEY), "with the last change in it")


## Without a ProjectileSpawner a drop lands in every peer's world under one name, "Dropped_<peer>_<n>", so a later
## take vanishes it everywhere; only the dropping Player's own peer, the Inventory's authority, may send it.
func test_drops_are_named_per_peer_and_travel_by_rpc() -> void:
	inventory.add_item(APPLE, 2)
	var first: Node3D = inventory.drop_slot(Item.Category.FOOD, 0, 1)
	var second: Node3D = inventory.drop_slot(Item.Category.FOOD, 0, 1)
	assert_eq(first.name, "Dropped_1_1", "Offline this peer is 1; its first drop")
	assert_eq(second.name, "Dropped_1_2")
	assert_eq(first.get_parent(), root, "In the world beside the Player")
	assert_eq(first.get("item"), APPLE)
	assert_eq(first.get("count"), 1)
	var config: Dictionary = (inventory.get_script() as Script).get_rpc_config()
	assert_eq(config["_spawn_dropped"]["rpc_mode"], MultiplayerAPI.RPC_MODE_AUTHORITY, "Only the Player's own peer drops into every world")
	assert_true(config["_spawn_dropped"]["call_local"])
	assert_false(config.has("_sync_equipment"), "Equipment is no RPC: it rides the PlayerSynchronizer as synced_equipment")
	var player_state: SceneState = (load("res://addons/3d_player_controller/scenes/player.tscn") as PackedScene).get_state()
	var synced: bool = false
	for i: int in player_state.get_node_count():
		if player_state.get_node_name(i) != "PlayerSynchronizer":
			continue
		for j: int in player_state.get_node_property_count(i):
			if player_state.get_node_property_name(i, j) == "replication_config":
				var config_resource: SceneReplicationConfig = player_state.get_node_property_value(i, j)
				synced = config_resource.get_properties().has(NodePath("Hud/Inventory:synced_equipment"))
	assert_true(synced, "and player.tscn's PlayerSynchronizer carries it")


## A peer re-creates equipment from any scene the loader knows, not only a .tscn: the sword in a game is often
## the imported model itself, and skipping it left the puppet unarmed while the stance said otherwise.
func test_any_loadable_scene_can_travel_to_a_peer() -> void:
	assert_true(Inventory._is_scene_path("res://addons/3d_player_controller/scenes/player.tscn"), "a scene file")
	assert_false(Inventory._is_scene_path(""), "a node placed inline in a level has no path")
	assert_false(Inventory._is_scene_path("res://addons/3d_player_controller/scripts/player.gd"), "a script is not a scene")
	assert_false(Inventory._is_scene_path("res://nowhere/missing.tscn"), "nor is a file that is not there")
	var models: Array[String] = []
	for dir_path: String in ["res://addons/3d_player_controller/assets", "res://addons/3d_player_controller/scenes"]:
		for file_name: String in ResourceLoader.list_directory(dir_path):
			if file_name.get_extension() in ["fbx", "glb", "gltf"]:
				models.append(dir_path.path_join(file_name))
	if models.is_empty():
		pass_test("no imported model in the addon to try; the loader check covers it")
		return
	assert_true(Inventory._is_scene_path(models[0]), "an imported model is a scene too: %s" % models[0])


## A weapon standing in a level as the model file with the Equipment script put on there, the way v3's axes and
## swords are: as the pickup it came from, as the save names it.
func _model_weapon(weapon_name: String) -> Equipment:
	var model: Node = (load(MODEL) as PackedScene).instantiate()
	model.set_script(EQUIPMENT_SCRIPT)
	var weapon: Equipment = model as Equipment
	weapon.name = weapon_name
	weapon.equipment_type = Equipment.EquipmentType.AXE_1H
	weapon.bone_attachment_bone_name = "RightHand"
	root.add_child(weapon)
	return weapon


## The model file alone re-creates nothing, so the save names the world pickup the axe came from and a load
## duplicates that pickup, as a peer does; before, the save held the model file and the axe was gone after a restart.
func test_a_weapon_whose_scene_is_a_model_file_survives_a_save_and_a_load() -> void:
	var axe: Equipment = _model_weapon("WorldAxe")
	assert_true(axe.equip(player), "The Player picks the axe up")
	var entries: Array[EquipmentEntry] = inventory.make_save().equipment
	assert_eq(entries.size(), 1)
	assert_eq(entries[0].scene_path, String(axe.get_path()), "The save names the pickup it came from, not the model file")
	assert_true(entries[0].equipped)
	assert_eq(inventory.save(), OK)
	var loaded: Player = _spawn_player()
	await wait_physics_frames(2)
	assert_true(loaded.inventory.load_save())
	assert_true(loaded.inventory.has_equipment(Equipment.EquipmentType.AXE_1H), "The axe is back in hand after a restart")
	assert_eq(loaded.inventory.origin_of(loaded.inventory.get_equipment_by_type(Equipment.EquipmentType.AXE_1H)), String(axe.get_path()))


## A taken weapon stays in the level hidden, and its shapes used to stay too: a sword's blade or a bow's template
## arrow went on stopping rounds where it had lain. A copy made from it for a drop or a peer is whole again.
func test_a_taken_weapon_leaves_no_collider_behind_and_a_copy_of_it_is_whole() -> void:
	var axe: Equipment = _model_weapon("WorldAxe")
	var body: AnimatableBody3D = AnimatableBody3D.new()
	body.name = "WeaponBody"
	var blade: CollisionShape3D = CollisionShape3D.new()
	blade.shape = BoxShape3D.new()
	body.add_child(blade)
	axe.add_child(body)
	assert_true(axe.equip(player), "The Player picks the axe up")
	axe._vanish()
	await wait_physics_frames(2)
	assert_true(blade.disabled, "The blade of the spent pickup no longer collides")
	var copy: Equipment = Inventory.pickup_from(String(axe.get_path()), root)
	var copied: CollisionShape3D = copy.get_node("WeaponBody").get_child(0) as CollisionShape3D
	assert_false(copied.disabled, "while a copy of it can be walked over and swung again")
	copy.free()


## An instance of a scene that turns out to be no Equipment (a bare model file) is freed, not left lying about.
func test_a_scene_that_is_no_equipment_is_freed_rather_than_leaked() -> void:
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	assert_null(Inventory.pickup_from(MODEL, root), "A model file alone is no Equipment")
	assert_null(inventory.add_equipment_scene(load(MODEL) as PackedScene), "and cannot be equipped")
	assert_eq(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), orphans, "The instances it made were freed")


## An equipment item puts one piece in hand, however many the stack says; the rest are left over.
func test_adding_an_equipment_item_takes_one_piece_of_the_stack() -> void:
	assert_eq(inventory.add_item(SWORD, 3), 2, "One sword goes in hand, two are left")
	assert_eq(inventory.get_all_weapons().size(), 1)
	assert_eq(inventory.add_item(SWORD, 3), 3, "A second of the same type on the same bone is refused, all three left")


## What an ItemPickup asks the server for: the room on the item's stacks and in the empty slots of its tab.
func test_room_for_counts_the_space_an_item_would_take() -> void:
	assert_eq(inventory.room_for(APPLE), APPLE.max_stack * inventory.slots_per_tab, "An empty tab takes a full stack per slot")
	inventory.add_item(APPLE, APPLE.max_stack * inventory.slots_per_tab - 3)
	assert_eq(inventory.room_for(APPLE), 3, "A nearly full tab has three places left")
	assert_eq(inventory.room_for(KEY), inventory.slots_per_tab, "Other tabs are untouched")
	assert_eq(inventory.room_for(SWORD), 1, "An equipment item fits once while it could be equipped")
	inventory.add_item(SWORD)
	assert_eq(inventory.room_for(SWORD), 0, "and not while one of its type is on that bone")
	assert_eq(inventory.room_for(null), 0)
