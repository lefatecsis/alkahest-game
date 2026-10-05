class_name EquipmentEntry
extends Resource
## A saved weapon or tool: what re-creates it ([method Inventory.origin_of]) and whether it was on the skeleton or stowed.

@export var scene_path: String = "" ## The [Equipment] scene to instance, or the node path of the world pickup it came from (a model file with the script put on in the level).
@export var equipped: bool = false
