@icon("res://addons/3d_player_controller/inventory/assets/icons/materials.svg")
class_name Inventory
extends CanvasLayer
## Everything the Player carries.
##
## Equipment is the live [Equipment] attached to the Player's skeleton plus the stowed "backpack" attachments;
## each [BoneAttachment3D] holds exactly one [Equipment], stowed attachments live hidden under this node until
## re-equipped, tapping next/last weapon cycles and holding opens the [RadialMenu]. Everything else is stacks
## of [Item] in fixed-size tabs (materials, food, key items) that the [InventoryScreen] shows as a grid.
##
## Spells live here too: the child [Spellbook] holds the unlocked spells, the skill points and the wheel loadout,
## and is saved with the items. Equipment is capped at [member max_equipment] pieces, BOTW style.
##
## The inventory only signals when an item is used; the game applies the effect. With [member persist] on, the whole
## inventory is written to [member save_path] after every change and read back once the Player is ready.
##
## The Player's inventory is the [code]Hud/Inventory[/code] node of player.tscn. Over the network the equipment is
## the authority's alone; every other peer's copy of the Player carries the same pieces through
## [member synced_equipment], so its stances read there. A drop goes through the world's [ProjectileSpawner], so
## every peer, a later joiner included, gets it (without one it lands in every present world under one name,
## [method _spawn_dropped]). Items themselves never leave the owning peer.

signal equipment_changed ## Emitted after the set of equipped items changes.
signal items_changed ## Emitted after a stack is added, removed, moved, used or dropped.
signal item_used(item: Item, count: int) ## Use on a stack; consumables lose the count, the effect is the game's.
signal item_dropped(item: Item, count: int, pickup: Node3D) ## A stack (or part of one) is back in the world.

const ITEM_PICKUP_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/item_pickup.tscn")
const ITEM_TABS: Array[Item.Category] = [Item.Category.MATERIALS, Item.Category.FOOD, Item.Category.KEY_ITEMS]
const SAVE_VERSION: int = 1 ## The format [method save] writes, plain JSON. The .tres saves before it are not read.
const HEAVY_TYPES: Array[Equipment.EquipmentType] = [
	Equipment.EquipmentType.AXE_2H,
	Equipment.EquipmentType.FISHING_ROD,
	Equipment.EquipmentType.STAFF,
	Equipment.EquipmentType.SWORD_2H,
]
const ONE_HANDED_TYPES: Array[Equipment.EquipmentType] = [
	Equipment.EquipmentType.AXE_1H,
	Equipment.EquipmentType.DAGGER,
	Equipment.EquipmentType.SWORD_1H,
	Equipment.EquipmentType.SWORD_AND_SHIELD,
]

@export var player: Player
@export_range(1, 100) var slots_per_tab: int = 20 ## Slots on each item tab; the grid shows them all.
@export_range(1, 100) var max_equipment: int = 8 ## Weapons and tools carried at once, equipped and stowed together; more are refused.
@export var persist: bool = false ## Load [member save_path] on ready and write it after every change.
@export var save_path: String = "user://inventory.json"
@export var next_weapon_action: StringName = &"next_weapon" ## Tap cycles forward; holding either opens the [RadialMenu].
@export var last_weapon_action: StringName = &"last_weapon" ## Tap cycles back.

static var persistence_enabled: bool = true ## Off, no inventory loads or saves whatever [member persist] says; the test suite's pre-run hook turns it off so tests never touch a real save.

var equipment: Array[Equipment] = [] ## Items currently attached to the skeleton.
var equipment_by_type: Dictionary[Equipment.EquipmentType, Equipment] = {}
var can_player_attack: bool = true ## Does the currently equipped item allow the Player to attack?
var can_player_shoot: bool = false ## Does the currently equipped item allow the Player to shoot?
var custom_cycle_handler: Callable = Callable() ## Replaces weapon cycling (e.g. radio stations while driving).
var _tabs: Dictionary[int, Array] = {} ## Category to its slots: [ItemSlot] or null per index.
var _loading: bool = false ## True while a save is applied, so the changes it makes are not written back.
var _save_queued: bool = false ## A write is waiting for the end of the frame, so a burst of changes costs one.
var _drop_counter: int = 0 ## Numbers this peer's drops, so every peer names the pickup the same.

@onready var radial_menu: RadialMenu = $RadialMenu
@onready var hold_timer: Timer = $HoldTimer ## Runs while next/last weapon is held; its timeout opens the radial menu.
@onready var spellbook: Spellbook = get_node_or_null("Spellbook") as Spellbook ## The spells; optional.


func _ready() -> void:
	set_process_unhandled_input(is_multiplayer_authority())
	for category: Item.Category in ITEM_TABS:
		_tabs[category] = _empty_tab()
	if not is_multiplayer_authority():
		# A puppet's pieces come through synced_equipment, which the spawn sync sets before the skeleton is ready
		if player and not player.is_node_ready():
			player.ready.connect(_apply_synced_equipment, CONNECT_ONE_SHOT)
		else:
			_apply_synced_equipment()
		return
	if persist and persistence_enabled:
		# The Player's skeleton and abilities are @onready, so a save applied before its ready has nowhere to go
		if player and not player.is_node_ready():
			player.ready.connect(load_save, CONNECT_ONE_SHOT)
		else:
			load_save()


func _unhandled_input(event: InputEvent) -> void:
	if player == null or player.is_paused or player.is_typing or player.held_object.is_holding_object():
		hold_timer.stop()
		return

	if event.is_action_pressed(next_weapon_action) or event.is_action_pressed(last_weapon_action):
		hold_timer.start()
	elif event.is_action_released(next_weapon_action) or event.is_action_released(last_weapon_action):
		# A release while the timer still runs is a tap; a timeout already opened the radial menu.
		if hold_timer.is_stopped():
			return
		hold_timer.stop()
		cycle_weapon(1 if event.is_action_released(next_weapon_action) else -1)


# --- Items -----------------------------------------------------------------------------------------------------

## The slots of an item tab: [ItemSlot] or null per index, [member slots_per_tab] long. Not for equipment, see
## [method get_all_weapons].
func get_slots(category: Item.Category) -> Array:
	return _tabs.get(category, [])


## The stack at [param index] of [param category], or null.
func get_slot(category: Item.Category, index: int) -> ItemSlot:
	var slots: Array = get_slots(category)
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## Adds [param count] of [param item]: onto stacks of the same item first, then into empty slots. Equipment items
## are picked up through their [member Item.equipment_scene] instead, one piece at a time. Returns how many did not
## fit.
func add_item(item: Item, count: int = 1) -> int:
	if item == null or count <= 0:
		return count
	if item.category == Item.Category.EQUIPMENT:
		return count if add_equipment_scene(item.equipment_scene) == null else count - 1
	var slots: Array = get_slots(item.category)
	var left: int = count
	for slot: ItemSlot in slots:
		if left == 0:
			break
		if slot and slot.item.is_same(item) and slot.count < item.max_stack:
			var room: int = item.max_stack - slot.count
			var taken: int = mini(room, left)
			slot.count += taken
			left -= taken
	for i: int in slots.size():
		if left == 0:
			break
		if slots[i] == null:
			var taken: int = mini(item.max_stack, left)
			slots[i] = ItemSlot.make(item, taken)
			left -= taken
	if left != count:
		_items_changed()
	return left


## Takes [param count] of [param item] from the stacks that hold it. Returns how many were taken.
func remove_item(item: Item, count: int = 1) -> int:
	if item == null or count <= 0:
		return 0
	var slots: Array = get_slots(item.category)
	var left: int = count
	for i: int in range(slots.size() - 1, -1, -1):
		if left == 0:
			break
		var slot: ItemSlot = slots[i]
		if slot and slot.item.is_same(item):
			var taken: int = mini(slot.count, left)
			slot.count -= taken
			left -= taken
			if slot.count == 0:
				slots[i] = null
	if left != count:
		_items_changed()
	return count - left


## How many of [param item] [method add_item] would take now: the room on its stacks and in the empty slots of its
## tab, or, for an equipment item, 1 while its scene could be equipped. An [ItemPickup] asks the server for no more.
func room_for(item: Item) -> int:
	if item == null:
		return 0
	if item.category == Item.Category.EQUIPMENT:
		var piece: Node = item.equipment_scene.instantiate() if item.equipment_scene else null
		var fits: bool = can_equip(piece as Equipment)
		if piece:
			piece.free()
		return 1 if fits else 0
	var room: int = 0
	for slot: ItemSlot in get_slots(item.category):
		if slot == null:
			room += item.max_stack
		elif slot.item.is_same(item):
			room += maxi(item.max_stack - slot.count, 0)
	return room


## How many of [param item] are carried.
func count_of(item: Item) -> int:
	if item == null:
		return 0
	var total: int = 0
	for slot: ItemSlot in get_slots(item.category):
		if slot and slot.item.is_same(item):
			total += slot.count
	return total


func has_item(item: Item, count: int = 1) -> bool:
	return count_of(item) >= count


## Moves the stack at [param from_index] onto [param to_index] of the same tab: onto an empty slot it moves, onto
## the same item it merges up to the stack limit, onto anything else it swaps.
func move_slot(category: Item.Category, from_index: int, to_index: int) -> void:
	var slots: Array = get_slots(category)
	if from_index == to_index or from_index < 0 or to_index < 0 or from_index >= slots.size() or to_index >= slots.size():
		return
	var moving: ItemSlot = slots[from_index]
	if moving == null:
		return
	var target: ItemSlot = slots[to_index]
	if target and target.item.is_same(moving.item) and target.count < moving.item.max_stack:
		var taken: int = mini(moving.item.max_stack - target.count, moving.count)
		target.count += taken
		moving.count -= taken
		if moving.count == 0:
			slots[from_index] = null
	else:
		slots[to_index] = moving
		slots[from_index] = target
	_items_changed()


## Uses [param count] from the stack at [param index]: emits [signal item_used] and, for a consumable, takes them.
func use_slot(category: Item.Category, index: int, count: int = 1) -> void:
	var slot: ItemSlot = get_slot(category, index)
	if slot == null:
		return
	var used: int = mini(count, slot.count)
	var item: Item = slot.item
	if item.consumable:
		slot.count -= used
		if slot.count == 0:
			get_slots(category)[index] = null
		_items_changed()
	item_used.emit(item, used)


## Uses [param count] of [param item] from the first stack that holds it, as [method use_slot] does.
func use_item(item: Item, count: int = 1) -> void:
	if item == null:
		return
	var slots: Array = get_slots(item.category)
	for i: int in slots.size():
		if slots[i] and slots[i].item.is_same(item):
			use_slot(item.category, i, count)
			return


## Every carried [Item] with [member Item.throwable] set, in tab and slot order, each kind once.
func get_throwable_items() -> Array[Item]:
	var found: Array[Item] = []
	for category: Item.Category in ITEM_TABS:
		for slot: ItemSlot in get_slots(category):
			if slot and slot.item.throwable and not found.any(func(item: Item) -> bool: return item.is_same(slot.item)):
				found.append(slot.item)
	return found


## Drops [param count] from the stack at [param index] on the ground in front of the Player as an [ItemPickup].
## Returns the pickup in this world: null on a client whose drop comes back through the [ProjectileSpawner].
func drop_slot(category: Item.Category, index: int, count: int = 1) -> Node3D:
	var slot: ItemSlot = get_slot(category, index)
	if slot == null or player == null:
		return null
	var dropped: int = mini(count, slot.count)
	var item: Item = slot.item
	slot.count -= dropped
	if slot.count == 0:
		get_slots(category)[index] = null
	var pickup: Node3D = _drop(ITEM_PICKUP_SCENE.resource_path, item, dropped)
	_items_changed()
	item_dropped.emit(item, dropped, pickup)
	return pickup


## Drops an equipped or stowed [Equipment] back into the world (its scene, or a copy of the world pickup it came
## from, in front of the Player) and forgets it. Equipment that neither can re-create cannot be dropped; it stays.
## Returns the pickup in this world, null on a client as for [method drop_slot].
func drop_equipment(item: Equipment) -> Node3D:
	if player == null:
		return null
	var scene_path: String = forget_equipment(item)
	if scene_path.is_empty():
		return null
	return _drop(scene_path, null, 0)


## Forgets an equipped or stowed [Equipment] without putting anything in the world (it was thrown, it broke) and
## returns the scene path it can be re-created from. Empty, and nothing happens, for equipment that was not
## instanced from a scene.
func forget_equipment(item: Equipment) -> String:
	var scene_path: String = origin_of(item)
	if scene_path.is_empty():
		return ""
	var attachment: BoneAttachment3D = item.get_parent() as BoneAttachment3D
	if equipment.has(item):
		_stow(item)
	var gone: Node = attachment if attachment else item
	if gone.get_parent():
		gone.get_parent().remove_child(gone) # out of the backpack now, freed at the end of the frame
	gone.queue_free()
	_items_changed()
	_publish_equipment()
	return scene_path


## Equips a fresh instance of [param scene] (an [Equipment] scene) as walking over it would; returns the copy on
## the skeleton, or null when the equip was refused. An equipment [Item] comes through here when it is added.
func add_equipment_scene(scene: PackedScene) -> Equipment:
	if scene == null or player == null:
		return null
	var pickup: Node = scene.instantiate()
	if pickup is Equipment:
		return _equip_instance(pickup)
	pickup.free()
	return null


## Puts [param item] back in the backpack without dropping it.
func stow_equipment(item: Equipment) -> void:
	if item == null or not equipment.has(item):
		return
	_stow(item)


# --- Saving ----------------------------------------------------------------------------------------------------

## Writes every stack and every piece of equipment to [member save_path] as JSON, in the plain form [SaveGame]
## writes: an item, a weapon's scene and a spell are named by their res:// path, never embedded.
func save() -> Error:
	_save_queued = false
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var data: Dictionary = {"version": SAVE_VERSION, "inventory": SaveGame.to_plain(make_save())}
	file.store_string(JSON.stringify(JSON.from_native(data), "	"))
	var error: Error = file.get_error()
	file.close()
	return error


## Every stack and every piece of equipment as an [InventorySave], for [method save] and for a [SaveGame] that
## keeps the inventory inside the game's own file.
func make_save() -> InventorySave:
	var data: InventorySave = InventorySave.new()
	for category: Item.Category in ITEM_TABS:
		var slots: Array = get_slots(category)
		for i: int in slots.size():
			var slot: ItemSlot = slots[i]
			if slot == null:
				continue
			var saved: ItemSlot = ItemSlot.make(slot.item, slot.count)
			saved.category = category
			saved.index = i
			data.slots.append(saved)
	for item: Equipment in get_all_weapons():
		# Its own scene, or the world pickup it came from: a model file with the script put on in the level
		# re-creates nothing by itself.
		var origin: String = origin_of(item)
		if origin.is_empty():
			continue # placed inline in a level and never a pickup; nothing can re-create it, so it is not saved
		var entry: EquipmentEntry = EquipmentEntry.new()
		entry.scene_path = origin
		entry.equipped = equipment.has(item)
		data.equipment.append(entry)
	if spellbook:
		spellbook.write_save(data)
	return data


## Replaces the inventory with what [member save_path] holds; false, and nothing changes, when there is no file or it
## is not a save of this version. An item, weapon or spell the game no longer has is left out and the rest loads:
## the file names each by path, so one renamed item cannot take the whole inventory with it.
func load_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var json: JSON = JSON.new()
	var parsed: Variant = JSON.to_native(json.data) if json.parse(FileAccess.get_file_as_string(save_path)) == OK else null
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) != SAVE_VERSION:
		push_warning("Inventory: %s is not a version %d inventory save, so it is not loaded and the next save replaces it" % [save_path, SAVE_VERSION])
		return false
	var data: InventorySave = SaveGame.from_plain((parsed as Dictionary).get("inventory")) as InventorySave
	if data == null:
		return false
	apply_save(data)
	return true


## Replaces the inventory with [param data].
func apply_save(data: InventorySave) -> void:
	_loading = true
	for category: Item.Category in ITEM_TABS:
		_tabs[category] = _empty_tab()
	for saved: ItemSlot in data.slots:
		if saved.item == null or saved.index < 0 or saved.index >= slots_per_tab:
			continue
		get_slots(saved.category)[saved.index] = ItemSlot.make(saved.item, saved.count)
	var scene_paths: PackedStringArray = []
	var equipped: PackedByteArray = []
	for entry: EquipmentEntry in data.equipment:
		scene_paths.append(entry.scene_path)
		equipped.append(1 if entry.equipped else 0)
	_rebuild_equipment(scene_paths, equipped)
	if spellbook:
		spellbook.read_save(data)
	_loading = false
	_items_changed()
	_publish_equipment()


## Replaces every piece of equipment with fresh instances of [param scene_paths], equipping those flagged in
## [param equipped]. An entry whose scene is gone is skipped, and its flag with it.
func _rebuild_equipment(scene_paths: PackedStringArray, equipped: PackedByteArray) -> void:
	if player == null or player.skeleton == null:
		return
	for item: Equipment in get_all_weapons():
		_free_piece(item)
	var instances: Array[Array] = [] # [Equipment, equipped] pairs; only the entries that came back
	for i: int in scene_paths.size():
		var pickup: Equipment = pickup_from(scene_paths[i], self)
		if pickup == null:
			continue
		var instance: Equipment = _equip_instance(pickup)
		if instance:
			instances.append([instance, i < equipped.size() and equipped[i] == 1])
	unequip_all()
	for pair: Array in instances:
		if pair[1]:
			equip_weapon(pair[0])


## Writes the save if [member persist] is on; the [Spellbook] calls it after its own changes.
func request_save() -> void:
	_autosave()


func _autosave() -> void:
	if persist and persistence_enabled and not _loading and not _save_queued and is_inside_tree() and is_multiplayer_authority():
		_save_queued = true
		save.call_deferred()


func _items_changed() -> void:
	items_changed.emit()
	_autosave()


# --- Equipment -------------------------------------------------------------------------------------------------

## Equips the next (+1) or previous (-1) item; the slot before the first item is "unarmed".
func cycle_weapon(direction: int) -> void:
	if custom_cycle_handler.is_valid():
		custom_cycle_handler.call(direction)
		return

	var all_weapons: Array[Equipment] = get_all_weapons()
	if all_weapons.is_empty():
		return
	# With two pieces out at once (a sword and a shield) the step starts past the last of them going forward, or
	# before the first going back. Starting at the first either way stepped onto the shield, already out, and
	# forward never got any further.
	var current_index: int = -1
	for i: int in all_weapons.size():
		if equipment.has(all_weapons[i]):
			current_index = i
			if direction < 0:
				break
	var new_index: int = posmod(current_index + 1 + direction, all_weapons.size() + 1) - 1
	if new_index == -1:
		unequip_all()
	else:
		equip_weapon(all_weapons[new_index])


func add_equipment(item: Equipment) -> void:
	if item == null or equipment.has(item):
		return
	equipment.append(item)
	rebuild_equipment_cache()


func remove_equipment(item: Equipment) -> void:
	if item == null or not equipment.has(item):
		return
	equipment.erase(item)
	rebuild_equipment_cache()


func rebuild_equipment_cache() -> void:
	equipment_by_type.clear()
	can_player_attack = equipment.is_empty()
	can_player_shoot = false
	for item: Equipment in equipment:
		equipment_by_type[item.equipment_type] = item
		can_player_attack = can_player_attack or item.can_attack
		can_player_shoot = can_player_shoot or item.can_shoot
	if player and player.controls:
		player.controls.reset_labels()
	equipment_changed.emit()
	_autosave()
	_publish_equipment()


func set_equipment_visibility(is_visible: bool) -> void:
	for item: Equipment in equipment:
		item.visible = is_visible


func get_equipment_by_type(type: Equipment.EquipmentType) -> Equipment:
	return equipment_by_type.get(type)


func has_equipment(type: Equipment.EquipmentType) -> bool:
	return equipment_by_type.has(type)


## Returns true if the player has a firearm equipped (Pistol, Rifle).
func has_firearm_equipped() -> bool:
	return has_equipment(Equipment.EquipmentType.PISTOL) or has_equipment(Equipment.EquipmentType.RIFLE)


## Room for one more weapon or tool under [member max_equipment].
func can_carry_equipment() -> bool:
	return get_all_weapons().size() < max_equipment


## Whether [method equip_pickup] would take [param pickup]: it names a bone, nothing of its type is carried on that
## bone, and there is room under [member max_equipment].
func can_equip(pickup: Equipment) -> bool:
	return pickup != null and not pickup.bone_attachment_bone_name.is_empty() and can_carry_equipment() \
			and not has_equipment_in_backpack(pickup.equipment_type, pickup.bone_attachment_bone_name)


## True if an item of this type on this bone is already equipped or stowed.
func has_equipment_in_backpack(type: Equipment.EquipmentType, bone_name: String) -> bool:
	for item: Equipment in get_all_weapons():
		if item.equipment_type == type and item.bone_attachment_bone_name == bone_name:
			return true
	return false


func has_any_equipment(types: Array[Equipment.EquipmentType]) -> bool:
	for type: Equipment.EquipmentType in types:
		if equipment_by_type.has(type):
			return true
	return false


## True if any equipped item has the given boolean capability (e.g. &"can_log").
func has_equipment_with_capability(capability: StringName) -> bool:
	for item: Equipment in equipment:
		if item.get(capability):
			return true
	return false


func has_heavy_weapon_equipped() -> bool:
	return has_any_equipment(HEAVY_TYPES)


func has_one_handed_or_shield_equipped() -> bool:
	return has_any_equipment(ONE_HANDED_TYPES)


func is_unarmed() -> bool:
	return equipment.is_empty()


## Equipped and stowed items, sorted by type then bone.
func get_all_weapons() -> Array[Equipment]:
	var all_weapons: Array[Equipment] = []
	all_weapons.assign(equipment)
	for child: Node in get_children():
		if child is BoneAttachment3D and child.get_child_count() > 0:
			all_weapons.append(child.get_child(0) as Equipment)
	all_weapons.sort_custom(func(a: Equipment, b: Equipment) -> bool:
		if a.equipment_type != b.equipment_type:
			return a.equipment_type < b.equipment_type
		return a.bone_attachment_bone_name < b.bone_attachment_bone_name
	)
	return all_weapons


func equip_weapon(target_item: Equipment) -> void:
	if equipment.has(target_item):
		return
	var attachment: BoneAttachment3D = target_item.get_parent() as BoneAttachment3D
	if attachment:
		equip_from_backpack(attachment)


## Equips [param pickup], an [Equipment] in the world, on the Player: a duplicate goes onto a new
## [BoneAttachment3D] on the skeleton, on the bone the item names and with the item's offsets, and joins
## [member equipment]; whatever conflicts with it is stowed first. Returns the copy on the skeleton, or null when
## the item names no bone, the Player already carries one of this type on this bone, or the backpack is full.
## [method Equipment.equip] and the walk-over pickups come through here.
func equip_pickup(pickup: Equipment) -> Equipment:
	if player == null or not can_equip(pickup):
		return null

	stow_conflicting(pickup.bone_attachment_bone_name, pickup.is_exclusive)

	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.bone_name = pickup.bone_attachment_bone_name
	player.skeleton.add_child(attachment)

	var copy: Equipment = pickup.duplicate() as Equipment
	copy.player = player
	# A node added at runtime keeps the engine's default authority, the server's, whatever it hangs under; a piece
	# on a client's own skeleton has to answer to that client, or its own _ready takes it for a puppet's.
	attachment.set_multiplayer_authority(player.get_multiplayer_authority())
	copy.set_multiplayer_authority(player.get_multiplayer_authority())
	copy.scene_file_path = pickup.scene_file_path # so the inventory can save and drop it as its scene
	# Where a peer finds the same piece when it has no scene of its own: the world pickup it first came from, by path,
	# since a model file alone carries no script. A drop is a copy of that pickup and names it again rather than
	# itself, so the drop can go once it is taken.
	if pickup.has_meta("origin"):
		copy.set_meta("origin", pickup.get_meta("origin"))
	elif pickup.is_inside_tree() and not player.is_ancestor_of(pickup):
		copy.set_meta("origin", String(pickup.get_path()))
	attachment.add_child(copy)
	# Disable world collision but keep the "Hitbox" and "WeaponBody" shapes so HitDetection can use them.
	for shape: Node in copy.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = shape.get_parent().name not in ["Hitbox", "WeaponBody"]
	for tree: Node in copy.find_children("*", "AnimationTree", true, false):
		(tree as AnimationTree).active = true
		(tree as AnimationTree).advance_expression_base_node = tree.get_path_to(copy)
	if pickup.is_inside_tree(): # The scene's hand offsets reach the copy from a pickup in the tree, as they always have
		copy.position = pickup.position_offset
		copy.rotation_degrees = pickup.rotation_offset_degrees
		copy.scale = pickup.scale_offset

	add_equipment(copy)
	return copy


## Moves a stowed attachment back onto the skeleton, stowing whatever conflicts with it.
func equip_from_backpack(attachment: BoneAttachment3D) -> void:
	var item: Equipment = attachment.get_child(0) as Equipment
	stow_conflicting(item.bone_attachment_bone_name, item.is_exclusive)
	attachment.reparent(player.skeleton, false)
	attachment.show()
	add_equipment(item)


## Stows every equipped item that conflicts with an incoming one: same bone, or either side exclusive.
func stow_conflicting(bone_name: String, is_exclusive: bool) -> void:
	for item: Equipment in equipment.duplicate():
		if item.bone_attachment_bone_name == bone_name or is_exclusive or item.is_exclusive:
			_stow(item)


## Takes [param item] off the skeleton into the backpack; one added without a bone attachment (a bare test fixture)
## just leaves the set.
func _stow(item: Equipment) -> void:
	var attachment: BoneAttachment3D = item.get_parent() as BoneAttachment3D
	if attachment:
		_stow_attachment(attachment)
	else:
		remove_equipment(item)


func unequip_all() -> void:
	stow_conflicting("", true)


## Moves an equipped attachment (and its item) off the skeleton into the hidden backpack. The move happens before
## [signal equipment_changed] fires, so listeners never see the item between the skeleton and the backpack.
func _stow_attachment(attachment: BoneAttachment3D) -> void:
	var item: Equipment = attachment.get_child(0) as Equipment
	attachment.reparent(self, false)
	attachment.hide()
	remove_equipment(item)


# --- Helpers ---------------------------------------------------------------------------------------------------

func _empty_tab() -> Array:
	var tab: Array = []
	tab.resize(slots_per_tab)
	return tab


## Equips a freshly instanced [param pickup] the way walking over it would: on the Player for the moment it
## equips, since [method equip_pickup] applies the scene's hand offsets only while the pickup is in the tree,
## then freed. Returns the copy on the skeleton, or null when the equip was refused.
func _equip_instance(pickup: Equipment) -> Equipment:
	player.add_child(pickup)
	var instance: Equipment = equip_pickup(pickup)
	player.remove_child(pickup)
	pickup.free()
	return instance


## Takes [param item] off the Player for good: out of the equipped set, and freed with its attachment.
func _free_piece(item: Equipment) -> void:
	var attachment: BoneAttachment3D = item.get_parent() as BoneAttachment3D
	if equipment.has(item):
		_stow(item)
	if attachment:
		attachment.free()


## Puts a pickup on the ground a metre in front of the Player: [param scene_path]'s scene, or for a path starting
## with "/" a copy of the world pickup there, holding [param count] of [param item] when it is an [ItemPickup].
## Through the world's [ProjectileSpawner] when there is one, so every peer and every later joiner gets it; without
## one it lands in every present world under one name ([method _spawn_dropped]). An item made at run time has no
## path to send and lands on this peer alone. Returns the copy in this world, null on a client whose drop comes
## back through the spawner.
func _drop(scene_path: String, item: Item, count: int) -> Node3D:
	var facing: Vector3 = player.get_facing_direction()
	if facing == Vector3.ZERO:
		facing = Vector3.FORWARD
	var at: Vector3 = player.global_position + facing.normalized() * 1.0 + player.up_direction * 0.2
	if item and item.resource_path.is_empty():
		var local: ItemPickup = ITEM_PICKUP_SCENE.instantiate()
		local.item = item
		local.count = count
		local.local_only = true
		player.get_parent().add_child(local)
		local.global_position = at
		return local
	var item_path: String = item.resource_path if item else ""
	var spawner: ProjectileSpawner = ProjectileSpawner.find_for(self)
	if spawner:
		var extra: Dictionary = {"shooter": String(player.get_path())} # the dropper, who must be the sender's own
		if item:
			extra["item"] = item_path
			extra["count"] = count
		if scene_path.begins_with("/"):
			extra["world_pickup"] = scene_path
			return spawner.place(null, at, extra)
		return spawner.place(load(scene_path) as PackedScene, at, extra)
	_drop_counter += 1
	var node_name: String = "Dropped_%d_%d" % [multiplayer.get_unique_id(), _drop_counter]
	_spawn_dropped.rpc(scene_path, at, node_name, item_path, count)
	return player.get_parent().get_node_or_null(node_name)


## Every peer puts the dropped [param scene_path] (an [ItemPickup], or an [Equipment] by [method pickup_from]) in its
## world as [param node_name] at [param at], for a world without a [ProjectileSpawner]; see [method _drop]. Only the
## Player's own peer, the Inventory's authority, sends it.
@rpc("authority", "call_local", "reliable")
func _spawn_dropped(scene_path: String, at: Vector3, node_name: String, item_path: String, count: int) -> void:
	var pickup: Node3D = null
	if scene_path == ITEM_PICKUP_SCENE.resource_path:
		pickup = ITEM_PICKUP_SCENE.instantiate()
	else:
		pickup = pickup_from(scene_path, self)
	if pickup == null:
		return
	pickup.name = node_name
	if pickup is ItemPickup:
		(pickup as ItemPickup).item = load(item_path) as Item if not item_path.is_empty() else null
		(pickup as ItemPickup).count = count
	player.get_parent().add_child(pickup)
	pickup.global_position = at
	if pickup is Equipment:
		(pickup as Equipment).set_dropped_by(player) # it lands inside its own reach, on the Player who dropped it


## What the authority carries, for the Player's synchronizer to carry to every peer's copy
## ([code]Hud/Inventory:synced_equipment[/code] in player.tscn, sent at spawn and on change): what names each weapon
## ([method origin_of]), true while it is equipped. The authority writes it after every change
## ([method _publish_equipment]); a puppet's copy follows it on its skeleton ([method _apply_synced_equipment]),
## visual only, registering no actions and writing no save.
var synced_equipment: Dictionary = {} :
	set(value):
		synced_equipment = value
		if is_inside_tree() and not is_multiplayer_authority() and player and player.is_node_ready():
			_apply_synced_equipment()


## The authority writes what it carries into [member synced_equipment]. A piece placed inline in a level and never a
## pickup has no scene path, so a peer could not re-create it, and it is left out.
func _publish_equipment() -> void:
	if _loading or not is_inside_tree() or not is_multiplayer_authority():
		return
	var carried: Dictionary = {}
	for item: Equipment in get_all_weapons():
		var origin: String = origin_of(item)
		if not origin.is_empty():
			carried[origin] = equipment.has(item)
	synced_equipment = carried


## A puppet's copy follows [member synced_equipment]: a piece it already carries stays and is stowed or equipped to
## match, only a new one is instanced and only one that is gone is freed. A tap that swaps weapons moves two pieces
## rather than rebuilding them all, and a stow is heard as a stow alone.
func _apply_synced_equipment() -> void:
	if is_multiplayer_authority() or player == null or player.skeleton == null:
		return
	_loading = true
	var carried: Dictionary[String, Equipment] = {}
	for item: Equipment in get_all_weapons():
		var origin: String = origin_of(item)
		if synced_equipment.has(origin) and not carried.has(origin):
			carried[origin] = item
		else:
			_free_piece(item)
	for origin: String in synced_equipment:
		if not carried.has(origin):
			var pickup: Equipment = pickup_from(origin, self)
			var instance: Equipment = _equip_instance(pickup) if pickup else null
			if instance:
				carried[origin] = instance
	for origin: String in carried: # stows first, so an equip never pushes aside a piece that is leaving anyway
		if not synced_equipment[origin]:
			stow_equipment(carried[origin])
	for origin: String in carried:
		if synced_equipment[origin]:
			equip_weapon(carried[origin])
	_loading = false


## What names [param item] to a peer and in a save: the scene it was instanced from when that scene is its own (a
## .tscn carries the script and the settings), else the world pickup it came from, by path, which is what a model
## file with the script put on in the level needs. Empty for a piece placed inline that was never a pickup.
func origin_of(item: Equipment) -> String:
	if item == null:
		return ""
	if has_own_scene(item):
		return item.scene_file_path
	return item.get_meta("origin") if item.has_meta("origin") else ""


## Whether [param item] can be re-created from its scene alone: a .tscn or .scn, which carries its script and
## settings, unlike an imported model that only gets them in the level. A throw needs this, since what lands
## is an instance of that scene.
static func has_own_scene(item: Equipment) -> bool:
	return item != null and (item.scene_file_path.ends_with(".tscn") or item.scene_file_path.ends_with(".scn"))


## A fresh pickup for [param origin] ([method origin_of]): a copy of the world pickup at that path, looked up from
## [param from] (any node in the tree), or an instance of that scene. Null when neither is there or the scene is no
## [Equipment] (a bare model file, whose instance is freed). A copy of a spent pickup is made whole again, so it
## can be worn or walked over.
static func pickup_from(origin: String, from: Node) -> Equipment:
	if origin.begins_with("/"):
		var source: Equipment = from.get_node_or_null(origin) as Equipment
		if source == null:
			return null
		var pickup: Equipment = source.duplicate() as Equipment
		pickup.equipment_instance = null
		pickup.visible = true
		var detection: Area3D = pickup.get_node_or_null("PlayerDetection") as Area3D
		if detection:
			detection.monitoring = true
		for shape: Node in pickup.find_children("*", "CollisionShape3D", true, false):
			(shape as CollisionShape3D).disabled = false
		pickup.set_meta("origin", origin)
		return pickup
	var node: Node = (load(origin) as PackedScene).instantiate() if _is_scene_path(origin) else null
	if node is Equipment:
		return node
	if node:
		node.free()
	return null


## Whether a peer can re-create a piece from [param path]: any scene the loader knows, which is a .tscn as much
## as an imported .fbx or .glb, since a project's weapons are often the model file itself. A node placed inline
## in a level has no path.
static func _is_scene_path(path: String) -> bool:
	return ResourceLoader.exists(path, "PackedScene")
