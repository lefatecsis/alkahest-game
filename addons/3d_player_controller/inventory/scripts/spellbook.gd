class_name Spellbook
extends Node
## The Player's spells: which [Ability]s the Player has unlocked from the [SpellTree], the skill points left to unlock
## more, and the loadout of up to [member max_active] spells that fills the Player's ability wheel. A child of the
## [Inventory], which saves it alongside the items.
##
## The spells listed on the Player's [member Abilities.abilities] when the game starts count as unlocked and
## fill the first wheel slots, so a Player without a tree keeps working as before.

signal skill_points_changed(points: int)
signal spell_unlocked(ability: Ability)
signal loadout_changed ## The wheel slots changed.

const MAX_ACTIVE: int = 8 ## The wheel holds this many spells at most.

@export var tree: SpellTree ## What can be unlocked; empty, nothing can.
@export var skill_points: int = 0: ## Spent on [method unlock]; the game grants them however it likes.
	set(value):
		skill_points = maxi(value, 0)
		skill_points_changed.emit(skill_points)
		if is_inside_tree():
			_request_save()
@export_range(1, MAX_ACTIVE) var max_active: int = MAX_ACTIVE ## Wheel slots.

var unlocked: Array[Ability] = []
var active: Array[Ability] = [] ## The wheel slots, [member max_active] long, null where empty.
var _seeded: bool = false

@onready var inventory: Inventory = get_parent() as Inventory


func _ready() -> void:
	active.resize(max_active)
	if inventory and inventory.player:
		if inventory.player.is_node_ready():
			_seed()
		else:
			inventory.player.ready.connect(_seed, CONNECT_ONE_SHOT)


## The spells the Player started with are theirs: unlocked and on the wheel.
func _seed() -> void:
	if _seeded:
		return
	var abilities: Abilities = _abilities()
	if abilities == null:
		return
	_seeded = true
	if unlocked.is_empty() and active.all(func(slot: Ability) -> bool: return slot == null):
		for ability: Ability in abilities.abilities:
			if ability and not unlocked.has(ability):
				unlocked.append(ability)
				var slot: int = active.find(null)
				if slot != -1:
					active[slot] = ability
	_apply()


# --- Unlocking --------------------------------------------------------------------------------------------------

func is_unlocked(ability: Ability) -> bool:
	return ability != null and unlocked.has(ability)


## Whether every prerequisite of [param ability]'s node is unlocked.
func has_prerequisites(ability: Ability) -> bool:
	var node: SpellNode = tree.get_node_for(ability) if tree else null
	if node == null:
		return false
	return node.requires.all(is_unlocked)


## Unlockable now: on the tree, not yet unlocked, prerequisites met and points enough.
func can_unlock(ability: Ability) -> bool:
	if is_unlocked(ability) or not has_prerequisites(ability):
		return false
	return skill_points >= tree.get_node_for(ability).cost


## Spends the points and unlocks; the spell also takes the first free wheel slot. False when it cannot.
func unlock(ability: Ability) -> bool:
	if not can_unlock(ability):
		return false
	skill_points -= tree.get_node_for(ability).cost
	unlocked.append(ability)
	spell_unlocked.emit(ability)
	var slot: int = active.find(null)
	if slot != -1:
		active[slot] = ability
	_apply()
	loadout_changed.emit()
	_request_save()
	return true


# --- Loadout ---------------------------------------------------------------------------------------------------

## Puts an unlocked [param ability] (or null to clear) in wheel slot [param slot]; a spell already on the wheel
## moves to the new slot.
func set_active(slot: int, ability: Ability) -> void:
	if slot < 0 or slot >= active.size() or (ability != null and not is_unlocked(ability)):
		return
	var old: int = active.find(ability) if ability else -1
	if old != -1 and old != slot:
		active[old] = null
	active[slot] = ability
	_apply()
	loadout_changed.emit()
	_request_save()


func clear_active(slot: int) -> void:
	set_active(slot, null)


func is_active(ability: Ability) -> bool:
	return ability != null and active.has(ability)


## The wheel, in slot order, without the gaps.
func get_active_spells() -> Array[Ability]:
	var spells: Array[Ability] = []
	for ability: Ability in active:
		if ability:
			spells.append(ability)
	return spells


# --- Saving ----------------------------------------------------------------------------------------------------

func write_save(data: InventorySave) -> void:
	data.spells_saved = true
	data.skill_points = skill_points
	data.unlocked_spells = unlocked.duplicate()
	data.active_spells = active.duplicate()


func read_save(data: InventorySave) -> void:
	if not data.spells_saved:
		return
	_seeded = true
	skill_points = data.skill_points
	unlocked.clear()
	for ability: Ability in data.unlocked_spells:
		if ability and not unlocked.has(ability):
			unlocked.append(ability)
	active.clear()
	active.resize(max_active)
	for i: int in mini(data.active_spells.size(), max_active):
		var ability: Ability = data.active_spells[i]
		active[i] = ability if is_unlocked(ability) else null
	_apply()
	loadout_changed.emit()


# --- Helpers ---------------------------------------------------------------------------------------------------

func _abilities() -> Abilities:
	if inventory == null or inventory.player == null:
		return null
	return inventory.player.abilities


## Hands the wheel its spells and keeps the picked one valid.
func _apply() -> void:
	var abilities: Abilities = _abilities()
	if abilities == null:
		return
	var spells: Array[Ability] = get_active_spells()
	abilities.abilities = spells
	if not spells.has(abilities.active_ability):
		abilities.active_ability = spells[0] if not spells.is_empty() else null


func _request_save() -> void:
	if inventory:
		inventory.request_save()
