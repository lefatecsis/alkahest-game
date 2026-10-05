@icon("res://addons/3d_player_controller/inventory/assets/icons/materials.svg")
class_name FoodItem
extends Item
## Something to eat or drink: Use on a stack eats one, and it restores what it says, on the Player's own peer. Make
## one [code].tres[/code] per food, as with any [Item]: an apple heals a little and eases hunger, a waterskin quenches
## thirst, a mushroom gives back some mana. Hunger and thirst go to the Player's [Vitals] when it has one, and are
## ignored when it does not. The inventory prints what it restores under its description.

@export var health: float = 0.0 ## Health it restores (HP).
@export var mana: float = 0.0 ## Mana it restores (MP, the Player's energy pool).
@export var hunger: float = 0.0 ## Hunger it takes away, in the [Vitals] pool's points.
@export var thirst: float = 0.0 ## Thirst it takes away, in the [Vitals] pool's points.


func _init() -> void:
	category = Category.FOOD
	consumable = true


## "Restores 10 HP, 5 MP", and so on, for whatever it restores.
func get_details(_owner: Node) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for pair: Array in [[health, "HP"], [mana, "MP"], [hunger, "hunger"], [thirst, "thirst"]]:
		if pair[0] > 0.0:
			parts.append("%s %s" % [String.num(pair[0], 1).trim_suffix(".0"), pair[1]])
	return ("Restores " + ", ".join(parts)) if not parts.is_empty() else ""
