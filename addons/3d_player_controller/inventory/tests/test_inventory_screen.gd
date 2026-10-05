extends GutTest

## Purpose: the inventory screen opens on a Player and pauses them, tabs switch with the bumper actions, confirm
## lifts and places stacks, Use and Drop act on the stack under the cursor, the equipment tab equips and stows, and
## Back hands over to the Player's pause menu. Contract tier: the screen is instanced here and bound to the Player
## directly; opening it from the real Pause menu is covered in tests/integration.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const SCREEN_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/inventory_screen.tscn")
const APPLE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/apple.tres")
const ORE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/iron_ore.tres")
const SWORD: Item = preload("res://addons/3d_player_controller/inventory/resources/items/wooden_sword.tres")
const ContractActions: GDScript = preload("res://addons/3d_player_controller/inventory/tests/contract_actions.gd")

## An item with a badge: the word the grid prints in the cell's corner for the Player that owns it.
class BadgedItem extends Item:
	func get_badge(owner: Node) -> String:
		return "Loaded" if owner is Player else ""


var root: Node3D
var player: Player
var inventory: Inventory
var screen: InventoryScreen
var sender
var actions: RefCounted = ContractActions.new()


func before_all() -> void:
	actions.add_missing()


func after_all() -> void:
	actions.remove_added()


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
	root.add_child(player)
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	inventory = player.inventory
	screen = SCREEN_SCENE.instantiate()
	screen.hide() # as Pause does when it instances one; the scene itself saves visible so it can be seen in the editor
	screen.player = player
	player.add_child(screen)
	sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	await wait_physics_frames(3)


func after_each() -> void:
	sender.release_all()
	sender.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _open() -> void:
	screen.show_menu()
	await wait_physics_frames(1)


func test_show_menu_pauses_the_player_and_back_hands_over_to_pause() -> void:
	assert_false(screen.visible, "Hidden until shown")
	assert_false(player.is_paused)
	await _open()
	assert_true(screen.visible)
	assert_true(player.is_paused, "The screen pauses the Player like every menu layer")
	assert_true(screen.get_viewport().gui_get_focus_owner() is InventorySlotButton, "A slot has focus for pad and keyboard")
	screen._on_back_pressed()
	await wait_physics_frames(1)
	assert_false(screen.visible)
	assert_true(player.pause.visible, "Back shows the Player's pause menu")
	assert_true(player.is_paused, "Still paused")
	player.pause.hide_menu()
	assert_false(player.is_paused)


func test_bumper_actions_switch_tabs() -> void:
	await _open()
	assert_eq(screen.tab, Item.Category.EQUIPMENT, "Opens on equipment")
	sender.action_down(screen.next_tab_action)
	await wait_physics_frames(1)
	sender.action_up(screen.next_tab_action)
	await wait_physics_frames(1)
	assert_eq(screen.tab, Item.Category.MATERIALS)
	assert_true(screen.tab_buttons[1].button_pressed, "The tab button shows it")
	sender.action_down(screen.previous_tab_action)
	await wait_physics_frames(1)
	sender.action_up(screen.previous_tab_action)
	await wait_physics_frames(1)
	assert_eq(screen.tab, Item.Category.EQUIPMENT)
	screen._select_tab(Item.Category.KEY_ITEMS)
	assert_true(screen.tab_buttons[3].button_pressed)
	screen.hide_menu()


func test_confirm_lifts_a_stack_and_places_it_on_another_slot() -> void:
	inventory.add_item(APPLE, 5)
	var mushroom: Item = load("res://addons/3d_player_controller/inventory/resources/items/mushroom.tres")
	inventory.add_item(mushroom, 2)
	await _open()
	screen._select_tab(Item.Category.FOOD)
	assert_eq(screen._slots[0].icon, APPLE.icon, "The grid shows the stacks")
	assert_eq(screen._slots[0].count_label.text, "5")
	screen._slots[0].grab_focus()
	sender.action_down("ui_accept")
	await wait_physics_frames(1)
	sender.action_up("ui_accept")
	await wait_physics_frames(1)
	assert_eq(screen.held_index, 0, "Confirm on a stack lifts it")
	assert_true(screen.held_icon.visible, "It rides on the cursor")
	assert_eq(screen.detail_name.text, "Apple", "The details follow the held stack")
	screen._slots[3].grab_focus()
	sender.action_down("ui_accept")
	await wait_physics_frames(1)
	sender.action_up("ui_accept")
	await wait_physics_frames(1)
	assert_eq(screen.held_index, -1, "Confirm on a slot drops it")
	assert_eq(inventory.get_slot(Item.Category.FOOD, 3).count, 5, "Into that slot")
	assert_null(inventory.get_slot(Item.Category.FOOD, 0))
	screen._on_slot_pressed(3)
	screen._on_slot_pressed(1)
	assert_eq(inventory.get_slot(Item.Category.FOOD, 1).item, APPLE, "Onto another item it swaps")
	assert_eq(inventory.get_slot(Item.Category.FOOD, 3).item, mushroom)
	screen._on_slot_pressed(1)
	sender.action_down("ui_cancel")
	await wait_physics_frames(1)
	sender.action_up("ui_cancel")
	await wait_physics_frames(1)
	assert_eq(screen.held_index, -1, "Cancel puts a held stack back")
	assert_true(screen.visible, "Without leaving the screen")
	screen.hide_menu()


func test_use_and_drop_act_on_the_focused_stack() -> void:
	inventory.add_item(APPLE, 3)
	await _open()
	screen._select_tab(Item.Category.FOOD)
	screen._slots[0].grab_focus()
	watch_signals(inventory)
	screen._on_use_pressed()
	assert_signal_emitted_with_parameters(inventory, "item_used", [APPLE, 1])
	assert_eq(inventory.count_of(APPLE), 2)
	screen._on_drop_pressed()
	assert_signal_emitted(inventory, "item_dropped")
	assert_eq(inventory.count_of(APPLE), 1)
	assert_eq(screen._slots[0].count_label.text, "", "A single apple shows no count")
	assert_eq(screen.detail_count.text, "x1")
	screen.hide_menu()


func test_the_equipment_tab_stows_and_equips() -> void:
	inventory.add_item(SWORD)
	await _open()
	assert_eq(screen.use_button.text, "Equip")
	assert_eq(screen._slots[0].equipment, inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H))
	assert_true(screen._slots[0].equipped_mark.visible, "Marked as in hand")
	screen._on_slot_pressed(0)
	assert_false(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "Confirm on an equipped weapon stows it")
	assert_false(screen._slots[0].equipped_mark.visible)
	assert_eq(screen.detail_count.text, "Stowed")
	screen._on_slot_pressed(0)
	assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "And again equips it")
	screen._on_drop_pressed()
	await wait_physics_frames(1)
	assert_eq(inventory.get_all_weapons().size(), 0, "Drop puts it back in the world")
	screen.hide_menu()


func test_the_grid_prints_an_items_badge_and_hides_it_without_one() -> void:
	var badged := BadgedItem.new()
	badged.id = &"badged"
	badged.category = Item.Category.MATERIALS
	inventory.add_item(badged, 1)
	inventory.add_item(ORE, 3)
	await _open()
	screen._select_tab(Item.Category.MATERIALS)
	var badged_slot: InventorySlotButton = screen._slots[0]
	var ore_slot: InventorySlotButton = screen._slots[1]
	assert_eq(badged.get_badge(player), "Loaded")
	assert_true(badged_slot.badge_label.visible, "A badge shows in the cell")
	assert_eq(badged_slot.badge_label.text, "Loaded")
	assert_false(ore_slot.badge_label.visible, "An item with no badge shows none")
	assert_eq(ore_slot.badge_label.text, "")
	assert_eq(ORE.get_badge(player), "", "Item's badge is empty by default")
	badged_slot.set_stack(null)
	assert_false(badged_slot.badge_label.visible, "Emptying the cell clears the badge")
	screen._select_tab(Item.Category.EQUIPMENT)
	assert_false(screen._slots[0].badge_label.visible, "Equipment cells carry no badge")
	screen.hide_menu()


## The grid keeps to a fixed area in the panel: a small one is centred in it, a large one scrolls there with the
## focus instead of spilling out of the 720x480 panel, and a slot scrolled out of view takes no taps.
func test_the_grid_is_centred_when_small_and_scrolls_inside_the_panel_when_large() -> void:
	await _open()
	await wait_process_frames(2)
	var panel: Control = screen.get_node("Panel")
	var area: ScrollContainer = screen.grid_scroll
	var area_size: Vector2 = area.size
	assert_eq(screen.grid.get_parent(), area, "The grid sits in a scroll area")
	assert_lt(screen.grid.size.y, area.size.y, "Twenty slots are smaller than the area")
	var centred: Vector2 = ((area.size - screen.grid.size) * 0.5).floor()
	assert_almost_eq(screen.grid.position.x, centred.x, 1.0, "and centred in it side to side")
	assert_almost_eq(screen.grid.position.y, centred.y, 1.0, "and top to bottom")
	screen.hide_menu()
	inventory.slots_per_tab = 60
	screen.bind(player)
	await _open()
	await wait_process_frames(2)
	assert_eq(screen._slots.size(), 60)
	assert_gt(screen.grid.size.y, area.size.y, "Sixty slots are taller than the area")
	assert_eq(area.size, area_size, "which did not grow to fit them")
	assert_eq(panel.size, Vector2(720.0, 480.0), "and neither did the panel")
	var top: InventorySlotButton = screen._slots[0]
	var bottom: InventorySlotButton = screen._slots[59]
	assert_true(top.touch_button.visible, "Unscrolled, the top slot can be tapped")
	assert_false(bottom.touch_button.visible, "and the bottom one, out of view, cannot")
	bottom.grab_focus()
	await wait_process_frames(3)
	assert_gt(area.scroll_vertical, 0, "Focus on the last slot scrolls it into view")
	assert_true(bottom.touch_button.visible, "where it can be tapped")
	assert_false(top.touch_button.visible, "and the top one, scrolled away, cannot")
	screen.hide_menu()


func test_a_long_description_scrolls_inside_the_panel_instead_of_growing_it() -> void:
	var logbook := Item.new()
	logbook.id = &"test_logbook"
	logbook.category = Item.Category.FOOD
	logbook.icon = APPLE.icon
	var lines: PackedStringArray = ["In the bag:"]
	for i: int in 40: # a fish with a bag full of lengths prints one line each
		lines.append("%d.0 cm" % (30 + i))
	logbook.description = "\n".join(lines)
	inventory.add_item(logbook, 1)
	await _open()
	screen._select_tab(Item.Category.FOOD)
	screen._slots[0].grab_focus()
	await wait_physics_frames(2)
	var panel: Control = screen.get_node("Panel")
	var column: Control = screen.get_node("Panel/VBoxContainer")
	assert_eq(panel.size, Vector2(720.0, 480.0), "The panel keeps the size the scene gives it")
	assert_lte(column.size.y, panel.size.y, "and its contents fit inside it")
	assert_gt(screen.detail_scroll.size.y, 40.0, "The description has a fixed area")
	assert_gt(screen.detail_description.size.y, screen.detail_scroll.size.y, "that the long text scrolls within instead of stretching")
	assert_eq(screen.detail_description.get_parent(), screen.detail_scroll)
	screen.hide_menu()
