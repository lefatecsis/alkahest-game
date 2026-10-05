extends GutTest

## Needs the real player controller: the Pause menu with its Inventory and Spells buttons and the screens it
## instances beside itself on the Player.
##
## Purpose: Pause shows the Inventory and Spells buttons only when their screen paths are set, the screens open
## from the buttons and Back returns to Pause, and the start action closes everything and unpauses.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const PAUSE_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/pause.tscn")
const DEMO_TREE: SpellTree = preload("res://addons/3d_player_controller/inventory/resources/spell_tree_demo.tres")

var root: Node3D
var player: Player
var pause: Node
var inventory_screen: InventoryScreen
var spells_screen: SpellsScreen
var sender


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(20.0, 1.0, 20.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	var book: Spellbook = player.get_node("Hud/Inventory/Spellbook")
	book.tree = DEMO_TREE
	book.skill_points = 3
	root.add_child(player)
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	pause = player.pause
	sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	await wait_physics_frames(3)
	inventory_screen = pause.inventory_screen as InventoryScreen
	spells_screen = pause.spells_screen as SpellsScreen


func after_each() -> void:
	sender.release_all()
	sender.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_pause_shows_the_inventory_and_spells_buttons_when_their_screens_are_set() -> void:
	assert_true(pause.inventory_button.visible, "player.tscn sets the inventory screen path")
	assert_true(pause.spells_button.visible, "and the spells screen path")
	assert_not_null(inventory_screen, "The inventory screen is instanced")
	assert_eq(inventory_screen.get_parent(), player, "As a sibling menu on the Player")
	assert_false(inventory_screen.visible)
	assert_not_null(spells_screen, "So is the spells screen")
	assert_eq(spells_screen.get_parent(), player)
	assert_false(spells_screen.visible)


func test_pause_hides_the_buttons_when_no_screen_is_set() -> void:
	var bare: Node = PAUSE_SCENE.instantiate()
	bare.inventory_screen_scene = ""
	bare.spells_screen_scene = ""
	bare.player = player
	root.add_child(bare)
	await wait_physics_frames(1)
	assert_false(bare.inventory_button.visible, "No path, no button")
	assert_null(bare.inventory_screen)
	assert_false(bare.spells_button.visible)
	assert_null(bare.spells_screen)
	bare.queue_free()


func test_inventory_opens_from_pause_and_back_returns_to_it() -> void:
	pause.show_menu()
	pause._on_inventory_pressed()
	await wait_physics_frames(1)
	assert_true(inventory_screen.visible, "The inventory screen is up")
	assert_false(pause.visible, "In place of the pause menu")
	assert_true(player.is_paused, "Still paused")
	assert_true(inventory_screen.get_viewport().gui_get_focus_owner() is InventorySlotButton, "A slot has focus for pad and keyboard")
	inventory_screen._on_back_pressed()
	await wait_physics_frames(1)
	assert_false(inventory_screen.visible)
	assert_true(pause.visible, "Back returns to the pause menu")
	assert_true(player.is_paused)
	pause.hide_menu()
	assert_false(player.is_paused)


func test_spells_open_from_pause_on_the_tree_page_and_back_returns_to_it() -> void:
	pause.show_menu()
	pause._on_spells_pressed()
	await wait_physics_frames(1)
	assert_true(spells_screen.visible)
	assert_false(pause.visible)
	assert_eq(spells_screen.page, SpellsScreen.Page.TREE, "Opens on the tree")
	assert_eq(spells_screen.points_label.text, "Skill points: 3")
	assert_true(spells_screen.get_viewport().gui_get_focus_owner() is SpellNodeButton, "A tree node has focus")
	spells_screen._on_back_pressed()
	await wait_physics_frames(1)
	assert_true(pause.visible, "Back returns to Pause")
	pause.hide_menu()


func test_the_start_action_closes_the_inventory_and_unpauses() -> void:
	pause.show_menu()
	pause._on_inventory_pressed()
	await wait_physics_frames(1)
	sender.action_down("start")
	await wait_physics_frames(1)
	sender.action_up("start")
	await wait_physics_frames(1)
	assert_false(inventory_screen.visible)
	assert_false(pause.visible)
	assert_false(player.is_paused, "Start closes everything, like the other menus")


func test_the_spells_button_hides_without_a_spellbook() -> void:
	var bare: Player = PLAYER_SCENE.instantiate()
	bare.get_node("Hud/Inventory/Spellbook").free()
	root.add_child(bare)
	await wait_physics_frames(3)
	var bare_pause: Node = bare.pause
	bare_pause.show_menu()
	assert_false(bare_pause.spells_button.visible, "No spellbook, no Spells button")
	assert_true(bare_pause.inventory_button.visible, "The Inventory one stays")
	bare_pause.hide_menu()
