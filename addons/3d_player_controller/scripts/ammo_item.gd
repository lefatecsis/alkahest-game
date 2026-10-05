class_name AmmoItem
extends Item
## Ammunition as an inventory item: an arrow, a magazine, a clip. The [Bow] and the [Firearm] draw it from the
## Player's [Inventory], the bow one arrow per shot and a gun one unit per reload. Use on a stack selects it for the
## weapon of [member weapon_type]; with nothing selected the weapon takes the plain kind (no [member projectile_scene]).
## The inventory grid badges the kind a weapon draws.

@export var weapon_type: Equipment.EquipmentType = Equipment.EquipmentType.BOW ## The weapon this loads (BOW, PISTOL, RIFLE).
@export var rounds_per_unit: int = 0 ## Rounds in one unit: 1 for an arrow; 0 means a full magazine of the weapon (its magazine_size).
@export var projectile_scene: PackedScene ## What flies instead of the weapon's own projectile; empty is the plain round.


## "Loaded" on the kind [param owner]'s weapon of this type has selected, "Default" on the plain kind it falls back
## to, nothing otherwise or without such a weapon.
func get_badge(owner: Node) -> String:
	var player: Player = owner as Player
	if player == null or player.inventory == null:
		return ""
	for weapon: Equipment in player.inventory.get_all_weapons():
		if weapon.equipment_type != weapon_type or not (weapon is Bow or weapon is Firearm):
			continue
		var selected: AmmoItem = weapon.get("selected_ammo") as AmmoItem
		if not self.is_same(weapon.call("get_ammo") as AmmoItem):
			return ""
		return "Loaded" if selected and self.is_same(selected) else "Default"
	return ""


## The ammunition a weapon of [param type] draws from [param inventory]: [param selected] while some is carried,
## else the plain kind (see [method find_default]), else null.
static func pick(inventory: Inventory, type: Equipment.EquipmentType, selected: AmmoItem) -> AmmoItem:
	if inventory == null:
		return null
	if selected and selected.weapon_type == type and inventory.count_of(selected) > 0:
		return selected
	return find_default(inventory, type)


## The first carried [AmmoItem] for [param type] with no [member projectile_scene] (regular arrows, a plain clip);
## with none of those, the first carried kind of the type at all, so a quiver of only fire arrows still shoots.
static func find_default(inventory: Inventory, type: Equipment.EquipmentType) -> AmmoItem:
	if inventory == null:
		return null
	var any_kind: AmmoItem = null
	for category: Item.Category in Inventory.ITEM_TABS:
		for slot: ItemSlot in inventory.get_slots(category):
			var ammo: AmmoItem = slot.item as AmmoItem if slot else null
			if ammo == null or ammo.weapon_type != type:
				continue
			if ammo.projectile_scene == null:
				return ammo
			if any_kind == null:
				any_kind = ammo
	return any_kind
