@icon("res://addons/3d_player_controller/inventory/assets/icons/materials.svg")
class_name Item
extends Resource
## A thing the Player can carry: what it is called, what it looks like in the grid, which tab it sits on and how
## many fit in one stack. Make one [code].tres[/code] per item under [code]resources/items/[/code]; the world
## hands them out through [ItemPickup] and the [Inventory] keeps them.

enum Category {
	EQUIPMENT, ## Weapons and tools: the live [Equipment] on the Player's skeleton, not stacks.
	MATERIALS,
	FOOD,
	KEY_ITEMS,
}

@export var id: StringName = &"" ## Stable name used to match stacks and saves; the file name when empty.
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var icon_color: Color = Color.WHITE ## Tints the icon in the grid, so one icon can serve many variants (fish species, potions).
@export var category: Category = Category.MATERIALS
@export_range(1, 999) var max_stack: int = 99 ## Stacks of key items are 1; BOTW materials go to 999.
@export var consumable: bool = false ## Using it takes one from the stack (the effect is the game's, see [signal Inventory.item_used]).
@export var equipment_scene: PackedScene ## For [constant Category.EQUIPMENT]: the [Equipment] scene picked up when this item is added.
@export var model_scene: PackedScene ## A 3D model the inventory shows turning in place of the icon; empty keeps the icon.
@export var throwable: bool = false ## The Player can throw one from the stack; a thrown one lands in the world as an [ItemPickup] (the throw itself is the game's).
@export var throw_damage: float = 0.0 ## What a thrown one does to whatever it lands on that can take a hit; 0 hurts nothing.


## The name saves and stacks match on.
func get_id() -> StringName:
	if id != &"":
		return id
	return StringName(resource_path.get_file().get_basename())


## Whether two items are the same kind (the same resource, or the same id).
func is_same(other: Item) -> bool:
	if other == null:
		return false
	return other == self or (get_id() != &"" and get_id() == other.get_id())


## The name shown in the grid; the id when none is set.
func get_display_name() -> String:
	return display_name if not display_name.is_empty() else String(get_id()).capitalize()


## The tint for [member icon]; subclasses can derive it (a fish from its body colour).
func get_icon_color() -> Color:
	return icon_color


## Extra lines the inventory prints under [member description]; [param owner] is the Player, for state kept on
## it (a fish lists the lengths in the bag). Empty by default.
func get_details(_owner: Node) -> String:
	return ""


## A short word the grid prints in the cell's corner ("Loaded" on the ammunition a weapon draws); [param owner] is
## the Player. Empty by default, and an empty badge is not drawn.
func get_badge(_owner: Node) -> String:
	return ""


## Called on a freshly instanced [member model_scene] before it is shown, for a subclass to dress it (a fish
## tints the placeholder body).
func prepare_model(_model: Node3D) -> void:
	pass


## The scene the inventory turns in the preview; a subclass can fall back to a shared placeholder.
func get_model_scene() -> PackedScene:
	return model_scene
