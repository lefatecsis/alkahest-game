extends GutTest

## Needs the real player controller: the Abilities caster, its radial wheel and the ability label on the controls.
##
## Purpose: the ability wheel and the Q label follow the Spellbook's loadout: unlocked spells appear on the wheel,
## moving one off the wheel takes it off the wedges, and an empty loadout leaves the wheel and the label empty.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const DEMO_TREE: SpellTree = preload("res://addons/3d_player_controller/inventory/resources/spell_tree_demo.tres")
const STEALTH: Ability = preload("res://addons/3d_player_controller/resources/abilities/stealth.tres")
const HEAL: Ability = preload("res://addons/3d_player_controller/resources/abilities/heal.tres")

var root: Node3D
var player: Player
var spellbook: Spellbook


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate()
	var none: Array[Ability] = []
	player.get_node("Hud/Abilities").abilities = none
	player.get_node("Hud/Abilities").active_ability = null
	var book: Spellbook = player.get_node("Hud/Inventory/Spellbook")
	book.tree = DEMO_TREE
	book.skill_points = 3
	root.add_child(player)
	spellbook = player.inventory.spellbook
	await wait_physics_frames(3)


func _wheel_names() -> Array[String]:
	var wheel: RadialMenu = player.abilities.radial_menu
	wheel.update_items()
	var names: Array[String] = []
	for item: Dictionary in wheel.weapons:
		names.append(item["display_name"])
	return names


func test_the_ability_wheel_and_label_follow_the_loadout() -> void:
	var label: Label = player.controls.joypad_button_9_label
	assert_eq(_wheel_names(), [] as Array[String], "No spells, no wedges")
	spellbook.unlock(STEALTH)
	spellbook.unlock(HEAL)
	assert_eq(_wheel_names(), ["Stealth", "Heal"] as Array[String], "Unlocked spells fill the wheel in slot order")
	assert_eq(player.abilities.active_ability, STEALTH, "The first is picked")
	assert_eq(label.text, "Stealth", "and named on the Q label")
	spellbook.set_active(0, HEAL)
	assert_eq(_wheel_names(), ["Heal"] as Array[String], "Heal moved onto slot 0 and Stealth left the wheel")
	assert_eq(player.abilities.active_ability, HEAL, "The picked spell follows the wheel")
	assert_eq(label.text, "Heal")
	spellbook.clear_active(0)
	assert_eq(_wheel_names(), [] as Array[String], "An empty loadout empties the wheel")
	assert_null(player.abilities.active_ability)
	assert_eq(label.text, "Ability", "Nothing picked: the button keeps the layout's own word for it")
