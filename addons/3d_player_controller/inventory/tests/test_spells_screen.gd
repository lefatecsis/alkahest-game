extends GutTest

## Purpose: the Spells screen opens on the Tree page and pauses the Player; the Tree page draws the tree and
## unlocks on Confirm, the Loadout page lifts an unlocked spell onto a wheel slot and clears slots, the pages switch
## with the bumper actions and Back hands over to the Player's pause menu. The tree area keeps its size: a small
## tree is centred in it, a large one scrolls, and nodes scrolled out of view lose their touch target. A node button
## wires its own signals in its scene and fits its touch target to its size. Contract tier: the screen is instanced
## here and bound to the Player directly; opening it from the real Pause menu is covered in tests/integration.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const SCREEN_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/spells_screen.tscn")
const DEMO_TREE: SpellTree = preload("res://addons/3d_player_controller/inventory/resources/spell_tree_demo.tres")
const STEALTH: Ability = preload("res://addons/3d_player_controller/resources/abilities/stealth.tres")
const HEAL: Ability = preload("res://addons/3d_player_controller/resources/abilities/heal.tres")
const ContractActions: GDScript = preload("res://addons/3d_player_controller/inventory/tests/contract_actions.gd")

var root: Node3D
var player: Player
var spellbook: Spellbook
var screen: SpellsScreen
var sender
var actions: RefCounted = ContractActions.new()


func before_all() -> void:
	actions.add_missing()


func after_all() -> void:
	actions.remove_added()


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
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	spellbook = player.inventory.spellbook
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


## A tree of [param count] spells in one row (or one column with [param down]), each a fresh Ability.
func _line_tree(count: int, down: bool) -> SpellTree:
	var line: SpellTree = SpellTree.new()
	for i: int in count:
		var spell: Ability = Ability.new()
		spell.display_name = "Spell %d" % i
		var node: SpellNode = SpellNode.new()
		node.ability = spell
		node.row = i if down else 0
		node.column = 0 if down else i
		line.nodes.append(node)
	return line


## Puts [param tree] on the screen in place of the demo tree and lets the holder lay it out.
func _show_tree(tree: SpellTree) -> void:
	spellbook.tree = tree
	screen.refresh()
	await wait_process_frames(2)


func test_show_menu_opens_on_the_tree_and_back_hands_over_to_pause() -> void:
	assert_false(screen.visible, "Hidden until shown")
	await _open()
	assert_true(screen.visible)
	assert_true(player.is_paused, "The screen pauses the Player like every menu layer")
	assert_eq(screen.page, SpellsScreen.Page.TREE, "Opens on the tree")
	assert_eq(screen.points_label.text, "Skill points: 3")
	assert_true(screen.get_viewport().gui_get_focus_owner() is SpellNodeButton, "A tree node has focus")
	screen._on_back_pressed()
	await wait_physics_frames(1)
	assert_false(screen.visible)
	assert_true(player.pause.visible, "Back shows the Player's pause menu")
	player.pause.hide_menu()
	assert_false(player.is_paused)


func test_the_tree_page_draws_the_nodes_and_unlocks_on_confirm() -> void:
	await _open()
	var stealth_button: SpellNodeButton = screen._node_buttons[STEALTH]
	var heal_button: SpellNodeButton = screen._node_buttons[HEAL]
	assert_eq(stealth_button.cost_label.text, "1 pt")
	assert_eq(heal_button.cost_label.text, "2 pt")
	assert_lt(heal_button.modulate.a, 1.0, "Heal is dim: Stealth comes first")
	assert_eq(stealth_button.modulate.a, 1.0, "Stealth is unlockable")
	stealth_button.grab_focus()
	assert_eq(screen.detail_name.text, "Stealth")
	assert_eq(screen.detail_status.text, "Costs 1 skill point")
	assert_false(screen.unlock_button.disabled)
	sender.action_down("ui_accept")
	await wait_physics_frames(1)
	sender.action_up("ui_accept")
	await wait_physics_frames(1)
	assert_true(spellbook.is_unlocked(STEALTH), "Confirm on the node unlocks it")
	assert_eq(stealth_button.cost_label.text, "Unlocked")
	assert_eq(screen.points_label.text, "Skill points: 2")
	assert_eq(heal_button.modulate.a, 1.0, "Heal is now unlockable")
	heal_button.grab_focus()
	assert_eq(screen.detail_requires.text, "Requires: Stealth")
	screen._on_unlock_pressed()
	assert_true(spellbook.is_unlocked(HEAL), "The Unlock button unlocks the focused node")
	assert_true(screen.unlock_button.disabled, "Nothing more to unlock here")
	screen.hide_menu()


func test_the_tree_page_lays_the_nodes_out_by_cell_like_the_editor_graph() -> void:
	await _open()
	assert_eq(screen._node_buttons.size(), DEMO_TREE.nodes.size(), "A button per node, no spacers")
	for node: SpellNode in DEMO_TREE.nodes:
		var expected: Vector2 = Vector2(node.column, node.row) * SpellTree.CELL
		assert_eq(screen._node_buttons[node.ability].position, expected, node.ability.display_name + " sits at its column and row")
		assert_eq(SpellTree.cell_position(node), expected)
	assert_eq(screen.tree_canvas.custom_minimum_size, DEMO_TREE.pixel_size(), "The canvas spans every column and row")
	assert_eq(DEMO_TREE.pixel_size(), Vector2(DEMO_TREE.column_count(), DEMO_TREE.row_count()) * SpellTree.CELL)
	var line: PackedVector2Array = SpellTree.connection_segment(Rect2(0, 0, 96, 80), Rect2(112, 120, 96, 80))
	assert_almost_eq(line[0].y, 80.0, 0.01, "A prerequisite line leaves the earlier spell's edge, aimed at the later one")
	assert_between(line[0].x, 48.0, 96.0)
	assert_almost_eq(line[1].y, 120.0, 0.01, "and reaches the later spell's edge")
	var sideways: PackedVector2Array = SpellTree.connection_segment(Rect2(0, 0, 96, 80), Rect2(224, 0, 96, 80))
	assert_eq(sideways[0], Vector2(96, 40), "Side by side, it runs edge to edge")
	assert_eq(sideways[1], Vector2(224, 40))
	screen.hide_menu()


func test_the_loadout_page_places_and_clears_wheel_slots() -> void:
	spellbook.unlock(STEALTH)
	spellbook.unlock(HEAL)
	await _open()
	sender.action_down(screen.next_page_action)
	await wait_physics_frames(1)
	sender.action_up(screen.next_page_action)
	await wait_physics_frames(1)
	assert_eq(screen.page, SpellsScreen.Page.LOADOUT, "The bumper action turns the page")
	assert_eq(screen._unlocked_buttons.size(), 2, "Both unlocked spells are listed")
	assert_eq(screen._slot_buttons.size(), Spellbook.MAX_ACTIVE, "Eight wheel slots")
	assert_eq(screen._slot_buttons[0].ability, STEALTH, "Unlocking put them on the wheel already")
	assert_eq(screen._slot_buttons[1].ability, HEAL)
	screen._on_unlocked_pressed(HEAL)
	assert_eq(screen.held_ability, HEAL, "Confirm on a spell lifts it")
	assert_true(screen.held_icon.visible)
	screen._on_wheel_slot_pressed(5)
	assert_null(screen.held_ability, "Confirm on a slot places it")
	assert_eq(spellbook.active[5], HEAL)
	assert_null(spellbook.active[1], "And it left its old slot")
	screen._on_wheel_slot_pressed(5)
	assert_null(spellbook.active[5], "Confirm on a filled slot with nothing held clears it")
	assert_eq(player.abilities.abilities, [STEALTH] as Array[Ability], "The wheel follows")
	screen._on_wheel_slot_focused(0)
	screen._on_clear_pressed()
	assert_null(spellbook.active[0], "Clear empties the focused slot")
	sender.action_down(screen.previous_page_action)
	await wait_physics_frames(1)
	sender.action_up(screen.previous_page_action)
	await wait_physics_frames(1)
	assert_eq(screen.page, SpellsScreen.Page.TREE)
	screen.hide_menu()


func test_the_tree_area_keeps_its_size_centring_a_small_tree_and_scrolling_a_wide_one() -> void:
	await _open()
	await wait_process_frames(1)
	var holder: ScrollContainer = screen.tree_holder
	var canvas: Control = screen.tree_canvas
	var holder_size: Vector2 = holder.size
	assert_eq(canvas.size, DEMO_TREE.pixel_size(), "The canvas is the tree's size, not stretched to the area")
	assert_lt(canvas.size.x, holder.size.x, "The demo tree is smaller than the area")
	assert_lt(canvas.size.y, holder.size.y)
	var centred: Vector2 = ((holder.size - canvas.size) * 0.5).floor()
	assert_almost_eq(canvas.position.x, centred.x, 1.0, "A small tree sits in the middle of the area, side to side")
	assert_almost_eq(canvas.position.y, centred.y, 1.0, "and top to bottom")
	var wide: SpellTree = _line_tree(16, false)
	await _show_tree(wide)
	assert_eq(screen._node_buttons.size(), 16)
	assert_eq(canvas.size.x, wide.pixel_size().x, "A wide tree keeps its full width")
	assert_gt(canvas.size.x, holder.size.x, "wider than the area")
	assert_eq(holder.size, holder_size, "and the area did not grow to fit it")
	assert_almost_eq(canvas.position.x, 0.0, 1.0, "It starts unscrolled at the left edge")
	var bar: ScrollBar = holder.get_h_scroll_bar()
	assert_true(bar.visible, "with a scrollbar along the bottom")
	assert_almost_eq(canvas.position.y, floorf((holder.size.y - bar.size.y - canvas.size.y) * 0.5), 1.0, "still centred top to bottom, above the scrollbar")
	holder.scroll_horizontal = int(canvas.size.x)
	await wait_process_frames(2)
	assert_lt(canvas.position.x, 0.0, "and it scrolls")
	assert_eq(holder.size, holder_size, "without the area changing size")
	screen.hide_menu()


func test_a_node_button_wires_its_signals_in_its_scene() -> void:
	var button: SpellNodeButton = SpellsScreen.NODE_BUTTON_SCENE.instantiate()
	add_child_autofree(button)
	assert_true(button.pressed.is_connected(button._on_pressed), "pressed emits node_pressed")
	assert_true(button.focus_entered.is_connected(button._on_focus_entered), "focus_entered emits node_focused")
	assert_true(button.mouse_entered.is_connected(button.grab_focus), "the mouse over it takes focus")
	assert_true(button.touch_button.pressed.is_connected(button._on_touch_pressed), "a tap presses it")
	watch_signals(button)
	button.touch_button.pressed.emit()
	assert_signal_emitted(button, "node_pressed")


func test_node_and_slot_buttons_fit_their_touch_targets_to_their_size() -> void:
	await _open()
	var stealth_button: SpellNodeButton = screen._node_buttons[STEALTH]
	var heal_button: SpellNodeButton = screen._node_buttons[HEAL]
	assert_eq((stealth_button.touch_button.shape as RectangleShape2D).size, stealth_button.size, "The touch target is the button's size")
	assert_eq(stealth_button.touch_button.position, stealth_button.size * 0.5, "on its centre")
	assert_ne(stealth_button.touch_button.shape, heal_button.touch_button.shape, "and each button owns its shape")
	stealth_button.size = Vector2(150.0, 110.0)
	await wait_process_frames(1)
	assert_eq((stealth_button.touch_button.shape as RectangleShape2D).size, Vector2(150.0, 110.0), "It follows a resize")
	assert_eq(stealth_button.touch_button.position, Vector2(75.0, 55.0))
	assert_eq((heal_button.touch_button.shape as RectangleShape2D).size, heal_button.size, "without touching the other button")
	var slot: InventorySlotButton = screen._slot_buttons[0]
	slot.size = Vector2(90.0, 90.0)
	await wait_process_frames(1)
	assert_eq((slot.touch_button.shape as RectangleShape2D).size, slot.size, "A wheel slot's touch target follows its size too")
	assert_eq(slot.touch_button.position, slot.size * 0.5)
	screen.hide_menu()


func test_nodes_scrolled_out_of_the_tree_area_lose_their_touch_target() -> void:
	await _open()
	var tall: SpellTree = _line_tree(16, true)
	await _show_tree(tall)
	var holder: ScrollContainer = screen.tree_holder
	var canvas: Control = screen.tree_canvas
	assert_gt(canvas.size.y, holder.size.y, "The tall tree overflows the area")
	var top: SpellNodeButton = screen._node_buttons[tall.nodes[0].ability]
	var bottom: SpellNodeButton = screen._node_buttons[tall.nodes[15].ability]
	assert_true(top.touch_button.visible, "Unscrolled, the top node can be tapped")
	assert_false(bottom.touch_button.visible, "and the bottom node, out of view, cannot")
	holder.scroll_vertical = int(canvas.size.y)
	await wait_process_frames(2)
	assert_false(top.touch_button.visible, "Scrolled to the bottom, the top node is out of view and cannot be tapped")
	assert_true(bottom.touch_button.visible, "and the bottom node can")
	screen.hide_menu()


## The unlocked list keeps to a fixed area on the Loadout page: a short one is centred in it, a long one scrolls
## there with the focus instead of spilling out of the panel, and a spell scrolled out of view takes no taps.
func test_the_unlocked_list_is_centred_when_short_and_scrolls_when_long() -> void:
	spellbook.unlock(STEALTH)
	await _open()
	screen._select_page(SpellsScreen.Page.LOADOUT)
	await wait_process_frames(2)
	var area: ScrollContainer = screen.unlocked_scroll
	var grid: GridContainer = screen.unlocked_grid
	var area_size: Vector2 = area.size
	assert_eq(grid.get_parent(), area, "The unlocked spells sit in a scroll area")
	var centred: Vector2 = ((area.size - grid.size) * 0.5).floor()
	assert_almost_eq(grid.position.x, centred.x, 1.0, "One spell is centred in it side to side")
	assert_almost_eq(grid.position.y, centred.y, 1.0, "and top to bottom")
	var panel_size: Vector2 = screen.get_node("Panel").size
	for i: int in 40:
		var spell: Ability = Ability.new()
		spell.display_name = "Spell %d" % i
		spellbook.unlocked.append(spell)
	screen.refresh()
	await wait_process_frames(3)
	assert_gt(grid.size.y, area.size.y, "Forty spells are taller than the area")
	assert_eq(area.size, area_size, "which did not grow to fit them")
	assert_eq(screen.get_node("Panel").size, panel_size, "and neither did the panel")
	var first: SpellNodeButton = screen._unlocked_buttons[0]
	var last: SpellNodeButton = screen._unlocked_buttons[-1]
	assert_true(first.touch_button.visible, "Unscrolled, the first spell can be tapped")
	assert_false(last.touch_button.visible, "and the last, out of view, cannot")
	last.grab_focus()
	await wait_process_frames(3)
	assert_gt(area.scroll_vertical, 0, "Focus on the last spell scrolls it into view")
	assert_true(last.touch_button.visible, "where it can be tapped")
	assert_false(first.touch_button.visible, "and the first, scrolled away, cannot")
	screen.hide_menu()


## The unlocked list is rebuilt from scratch on every refresh; a pad player's focus is put back on the same spell.
func test_a_refresh_keeps_the_focus_on_the_unlocked_list_for_pad_players() -> void:
	spellbook.unlock(STEALTH)
	spellbook.unlock(HEAL)
	await _open()
	screen._select_page(SpellsScreen.Page.LOADOUT)
	screen._unlocked_buttons[1].grab_focus()
	assert_eq(get_viewport().gui_get_focus_owner(), screen._unlocked_buttons[1])
	screen.refresh()
	var focus: Control = get_viewport().gui_get_focus_owner()
	assert_not_null(focus, "Something on the screen still has focus")
	assert_true(screen.is_ancestor_of(focus))
	assert_eq(focus, screen._unlocked_buttons[1], "the same spell's new button")


func test_binding_a_player_without_a_spellbook_is_harmless() -> void:
	var bare: Player = PLAYER_SCENE.instantiate()
	bare.get_node("Hud/Inventory/Spellbook").free()
	root.add_child(bare)
	var other: SpellsScreen = SCREEN_SCENE.instantiate()
	other.player = bare
	bare.add_child(other)
	assert_null(other._spellbook, "No spellbook, nothing bound and no crash")
	other.refresh()
