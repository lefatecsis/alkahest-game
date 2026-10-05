extends GutTest

## Purpose: a FoodItem eaten from the inventory restores what its .tres says: health, mana, and, with Vitals on the
## Player, hunger and thirst. The example apple and mushroom are food.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const APPLE: FoodItem = preload("res://addons/3d_player_controller/inventory/resources/items/apple.tres")
const MUSHROOM: FoodItem = preload("res://addons/3d_player_controller/inventory/resources/items/mushroom.tres")

var player: Player


func before_each() -> void:
	player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)


func test_eating_an_apple_heals_and_takes_one() -> void:
	player.health.health = 50.0
	player.inventory.add_item(APPLE, 3)
	player.inventory.use_item(APPLE)
	assert_eq(player.health.health, 50.0 + APPLE.health, "An apple heals what its resource says")
	assert_eq(player.inventory.count_of(APPLE), 2, "and one is eaten")


func test_a_mushroom_gives_back_mana() -> void:
	player.health.max_energy = 100.0
	player.health.energy = 20.0
	player.inventory.add_item(MUSHROOM)
	player.inventory.use_item(MUSHROOM)
	assert_eq(player.health.energy, 20.0 + MUSHROOM.mana, "A mushroom restores mana")


func test_food_eases_hunger_and_thirst_with_vitals() -> void:
	var vitals: Vitals = Vitals.new()
	vitals.enabled = false
	player.add_child(vitals)
	vitals.hunger = 10.0
	vitals.thirst = 10.0
	var drink: FoodItem = FoodItem.new()
	drink.id = &"test_waterskin"
	drink.thirst = 30.0
	player.inventory.add_item(APPLE)
	player.inventory.add_item(drink)
	player.inventory.use_item(APPLE)
	player.inventory.use_item(drink)
	assert_eq(vitals.hunger, 10.0 + APPLE.hunger, "Food eases hunger")
	assert_eq(vitals.thirst, 40.0, "and a drink, thirst")


func test_food_says_what_it_restores() -> void:
	assert_eq(APPLE.get_details(player), "Restores 10 HP, 15 hunger")
	assert_eq(APPLE.category, Item.Category.FOOD, "on the Food tab")
