extends GutTest

## Needs the real player controller: the demo is the yard with the real Player in it.
##
## Purpose: the inventory demo loads without errors, and its hint label is wired in the scene to the Player's
## Inventory where player.tscn keeps it now, under Hud, so using and dropping an item shows on the hint.

const DEMO_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/demo/demo.tscn")
const APPLE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/apple.tres")
const TEST_SAVE: String = "user://test_inventory_demo.json" ## The demo turns persist on; this keeps it off the real save.

var demo: Node3D


func before_each() -> void:
	demo = DEMO_SCENE.instantiate()
	demo.get_node("Player/Hud/Inventory").save_path = TEST_SAVE
	add_child_autofree(demo)
	await wait_physics_frames(3)


func after_each() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func test_the_demo_loads_with_its_hint_wired_to_the_players_inventory() -> void:
	var inventory: Inventory = demo.get_node("Player/Hud/Inventory") as Inventory
	assert_not_null(inventory, "The Player keeps its Inventory under Hud")
	assert_eq((demo.get_node("Player") as Player).inventory, inventory)
	assert_true(inventory.item_used.is_connected(demo._on_item_used), "item_used reaches the demo from the scene")
	assert_true(inventory.item_dropped.is_connected(demo._on_item_dropped), "and so does item_dropped")
	var hint: Label = demo.get_node("HUD/Hint") as Label
	inventory.add_item(APPLE, 2)
	inventory.use_item(APPLE)
	assert_string_contains(hint.text, "Used 1 x", "Using an apple shows on the hint")
	inventory.drop_slot(APPLE.category, 0)
	assert_string_contains(hint.text, "Dropped 1 x", "and so does dropping one")
