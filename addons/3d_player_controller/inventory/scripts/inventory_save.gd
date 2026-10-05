class_name InventorySave
extends Resource
## What [method Inventory.save] writes to [member Inventory.save_path]: every stack with its tab and slot, and every
## piece of equipment with whether it was equipped. Written as plain JSON through [method SaveGame.to_plain], so it
## can be read and edited by hand.

@export var slots: Array[ItemSlot] = []
@export var equipment: Array[EquipmentEntry] = []
@export var spells_saved: bool = false ## True once a [Spellbook] wrote the three fields below.
@export var skill_points: int = 0
@export var unlocked_spells: Array[Ability] = []
@export var active_spells: Array[Ability] = [] ## The wheel slots in order; null where empty.
