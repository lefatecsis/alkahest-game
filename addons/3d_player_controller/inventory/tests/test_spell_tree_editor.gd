extends GutTest

## Purpose: the Spell Tree editor panel lays a SpellTree out like the AnimationTree editor, moves spells by
## dragging, draws requirements by dragging spell to spell with Connect on, selects spells and lines for Cost and
## Remove, adds abilities from its palette and saves the .tres.

const EDITOR_SCRIPT: GDScript = preload("res://addons/3d_player_controller/inventory/editor/spell_tree_editor.gd")
const STEALTH_PATH: String = "res://addons/3d_player_controller/resources/abilities/stealth.tres"
const HEAL_PATH: String = "res://addons/3d_player_controller/resources/abilities/heal.tres"
const STEALTH: Ability = preload(STEALTH_PATH)
const HEAL: Ability = preload(HEAL_PATH)
const TEST_SAVE: String = "user://test_spell_tree.tres"
const CELL: Vector2 = SpellTree.CELL

var editor: SpellTreeEditor
var tree: SpellTree


func before_each() -> void:
	editor = EDITOR_SCRIPT.new()
	editor.ability_scanner = func() -> PackedStringArray: return PackedStringArray([STEALTH_PATH, HEAL_PATH])
	add_child_autofree(editor)
	tree = SpellTree.new()
	tree.display_name = "Test Spells"


func after_each() -> void:
	# The canvas frees its buttons deferred, since it rebuilds from their own input
	await wait_process_frames(1)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


## Stealth at (column 0, row 0) and Heal at (column 1, row 1); Heal requires Stealth when [param linked].
func _two_spell_tree(linked: bool = true) -> SpellTree:
	var stealth: SpellNode = SpellNode.new()
	stealth.ability = STEALTH
	var heal: SpellNode = SpellNode.new()
	heal.ability = HEAL
	heal.cost = 2
	heal.row = 1
	heal.column = 1
	if linked:
		heal.requires = [STEALTH]
	tree.nodes = [stealth, heal]
	return tree


func _centre(index: int) -> Vector2:
	var button: SpellNodeButton = editor.get_node_button(index)
	return button.position + button.size * 0.5


## How many spell buttons the canvas holds right now.
func _button_count() -> int:
	var count: int = 0
	for child: Node in editor.canvas.get_children():
		if child is SpellNodeButton:
			count += 1
	return count


func _press(at: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	editor.canvas.gui_input.emit(event)


func _move(to: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = to
	editor.canvas.gui_input.emit(event)


func _release(at: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	editor.canvas.gui_input.emit(event)


func _drag(from: Vector2, to: Vector2) -> void:
	_press(from)
	_move(to)
	_release(to)


func test_draws_the_screens_button_per_spell_at_its_cell_and_a_line_per_prerequisite() -> void:
	editor.tree = _two_spell_tree()
	var stealth: SpellNodeButton = editor.get_node_button(0)
	var heal: SpellNodeButton = editor.get_node_button(1)
	assert_not_null(stealth, "Stealth has a button")
	assert_not_null(heal, "Heal has a button")
	assert_eq(stealth.name_label.text, "Stealth", "It is the Spells screen's own button")
	assert_eq(stealth.cost_label.text, "1 pt")
	assert_eq(heal.position, Vector2(1, 1) * CELL, "Column and row map to cells")
	assert_eq(heal.position, SpellTree.cell_position(tree.nodes[1]), "the same cells the Spells screen uses")
	assert_eq(editor.get_links(), [Vector2i(0, 1)] as Array[Vector2i], "One line, from the prerequisite to the dependent")
	assert_eq(editor.name_edit.text, "Test Spells")
	assert_eq(editor.canvas.custom_minimum_size, (tree.pixel_size() + CELL), "The canvas spans the grid plus a spare cell")


func test_with_connect_on_dragging_spell_to_spell_adds_a_prerequisite_and_a_loop_is_refused() -> void:
	editor.tree = _two_spell_tree(false)
	_drag(_centre(0), _centre(1))
	assert_true(tree.nodes[1].requires.is_empty(), "Without Connect a drag moves rather than links")
	editor.connect_button.button_pressed = true
	assert_true(editor.connect_mode)
	_drag(_centre(0), _centre(1))
	assert_eq(tree.nodes[1].requires, [STEALTH] as Array[Ability], "Heal now requires Stealth")
	assert_eq(editor.get_links(), [Vector2i(0, 1)] as Array[Vector2i])
	assert_eq(editor.selected_link, Vector2i(0, 1), "The new line is selected")
	assert_true(editor.dirty)
	_drag(_centre(1), _centre(0))
	assert_true(tree.nodes[0].requires.is_empty(), "Stealth requiring Heal would loop, so it is refused")
	_drag(_centre(0), _centre(0) + Vector2(5, 5))
	assert_true(tree.nodes[0].requires.is_empty(), "A spell cannot require itself")
	_drag(_centre(0), Vector2(600, 600))
	assert_eq(editor.get_links().size(), 1, "Letting go on nothing adds nothing")


func test_clicking_a_line_selects_it_and_remove_drops_the_prerequisite() -> void:
	editor.tree = _two_spell_tree()
	var segment: PackedVector2Array = SpellTree.connection_segment(Rect2(Vector2.ZERO, editor.get_node_button(0).size), Rect2(CELL, editor.get_node_button(1).size))
	_press((segment[0] + segment[1]) * 0.5)
	_release((segment[0] + segment[1]) * 0.5)
	assert_eq(editor.selected_link, Vector2i(0, 1), "The line under the mouse is selected")
	assert_eq(editor.selected_index, -1)
	assert_false(editor.remove_button.disabled)
	editor.remove_button.pressed.emit()
	assert_true(tree.nodes[1].requires.is_empty())
	assert_eq(editor.get_links().size(), 0)
	assert_eq(editor.selected_link, SpellTreeEditor.NO_LINK)


func test_clicking_a_spell_selects_it_and_delete_removes_it_with_the_links_into_it() -> void:
	editor.tree = _two_spell_tree()
	_press(_centre(0))
	_release(_centre(0))
	assert_eq(editor.selected_index, 0, "Stealth is selected")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_DELETE
	key.pressed = true
	editor.canvas.gui_input.emit(key)
	assert_eq(tree.nodes.size(), 1)
	assert_eq(tree.nodes[0].ability, HEAL)
	assert_true(tree.nodes[0].requires.is_empty(), "Heal no longer requires the removed Stealth")
	assert_null(editor.get_node_button(1), "Only one button is left")
	assert_eq(_button_count(), 1, "The edit rebuilt the canvas")
	assert_eq(editor.selected_index, -1)
	_press(Vector2(500, 500))
	_release(Vector2(500, 500))
	assert_eq(editor.selected_index, -1, "Clicking empty canvas selects nothing")


func test_a_dragged_spell_snaps_to_the_nearest_free_cell_and_back_from_a_taken_one() -> void:
	editor.tree = _two_spell_tree()
	_drag(_centre(1), _centre(1) + CELL * Vector2(1.2, -0.1))
	assert_eq(tree.nodes[1].column, 2, "Nearest column")
	assert_eq(tree.nodes[1].row, 1, "Nearest row")
	assert_eq(editor.get_node_button(1).position, Vector2(2, 1) * CELL, "Snapped onto the cell")
	assert_eq(editor.selected_index, 1, "The dragged spell is selected")
	_drag(_centre(1), _centre(0))
	assert_eq(Vector2i(tree.nodes[1].column, tree.nodes[1].row), Vector2i(2, 1), "Stealth's cell is taken, so Heal stays put")
	assert_eq(editor.get_node_button(1).position, Vector2(2, 1) * CELL, "and slides back")


func test_the_palette_lists_the_scanned_abilities_and_adds_one_at_a_free_cell() -> void:
	var stealth: SpellNode = SpellNode.new()
	stealth.ability = STEALTH
	tree.nodes = [stealth]
	editor.tree = tree
	assert_eq(editor.palette.item_count, 2)
	assert_eq(editor.palette.get_item_text(0), "Heal", "Sorted by path")
	assert_true(editor.add_ability_path(HEAL_PATH))
	assert_eq(tree.nodes.size(), 2)
	assert_eq(tree.nodes[1].ability, HEAL)
	assert_eq(_button_count(), 2, "The edit rebuilt the canvas through the tree's changed signal")
	assert_not_null(editor.get_node_button(1))
	assert_eq(Vector2i(tree.nodes[1].column, tree.nodes[1].row), Vector2i(0, 1), "The first free cell under Stealth")
	assert_eq(editor.selected_index, 1, "The new spell is selected")
	assert_false(editor.add_ability_path(HEAL_PATH), "A spell already on the tree is not added twice")
	assert_eq(tree.nodes.size(), 2)
	assert_false(editor.add_ability_path(STEALTH_PATH, Vector2i(3, 0)), "Stealth is on the tree too")


func test_a_drop_lands_on_the_cell_under_the_cursor() -> void:
	editor.tree = tree
	editor.canvas.drop_handler.call(HEAL_PATH, CELL * Vector2(3.6, 2.2))
	assert_eq(tree.nodes.size(), 1)
	assert_eq(Vector2i(tree.nodes[0].column, tree.nodes[0].row), Vector2i(3, 2))


func test_the_cost_spinner_and_the_name_field_write_through() -> void:
	editor.tree = _two_spell_tree()
	assert_false(editor.cost_spin.editable, "Nothing selected, nothing to cost")
	editor.select_only(1)
	assert_eq(editor.cost_spin.value, 2.0, "The toolbar shows the selected spell's cost")
	editor.cost_spin.value = 5
	assert_eq(tree.nodes[1].cost, 5)
	assert_eq(tree.nodes[0].cost, 1, "Only the selected spell changed")
	assert_eq(editor.selected_index, 1, "and it stays selected after the redraw")
	assert_eq(editor.get_node_button(1).cost_label.text, "5 pt", "The button shows it, as the screen would")
	editor.name_edit.text = "Renamed"
	editor.name_edit.text_submitted.emit("Renamed")
	assert_eq(tree.display_name, "Renamed")


func test_save_writes_the_tres_and_a_tree_without_a_file_asks_for_one() -> void:
	editor.tree = _two_spell_tree()
	watch_signals(editor)
	assert_false(editor.save(), "No path yet")
	assert_signal_emitted(editor, "save_as_requested")
	assert_true(editor.save_to(TEST_SAVE))
	assert_false(editor.dirty)
	assert_eq(tree.resource_path, TEST_SAVE, "The tree takes the path it was saved to")
	var loaded: SpellTree = ResourceLoader.load(TEST_SAVE, "", ResourceLoader.CACHE_MODE_IGNORE) as SpellTree
	assert_not_null(loaded)
	assert_eq(loaded.nodes.size(), 2)
	assert_eq(loaded.nodes[1].requires.size(), 1)
	assert_eq(loaded.nodes[1].cost, 2)


func test_a_tree_built_into_another_resource_takes_the_file_it_is_saved_to() -> void:
	editor.tree = _two_spell_tree()
	tree.resource_path = "res://addons/3d_player_controller/inventory/tests/host_scene.tscn::SpellTree_test"
	editor.set_cost(1, 3)
	assert_true(editor.dirty)
	watch_signals(editor)
	assert_false(editor.save(), "A built-in tree has no file of its own")
	assert_signal_emitted(editor, "save_as_requested")
	assert_true(editor.save_to(TEST_SAVE))
	assert_eq(tree.resource_path, TEST_SAVE, "The tree takes the path it was saved to")
	assert_false(editor.dirty)
	assert_true(editor.save(), "Save now writes to that file without asking")
	assert_signal_emit_count(editor, "save_as_requested", 1)


func test_outside_the_editor_the_scan_is_empty_and_the_palette_says_so() -> void:
	assert_false(Engine.is_editor_hint(), "GUT runs without the editor's file index")
	editor.ability_scanner = editor.scan_ability_paths
	editor.refresh_palette()
	assert_eq(editor.scan_ability_paths().size(), 0)
	assert_eq(editor.palette.item_count, 0)
	assert_string_contains(editor.status_label.text, "No Ability resources found")


func test_the_class_chain_and_the_header_tell_an_ability_tres_from_the_rest() -> void:
	editor._load_class_bases()
	assert_true(editor._extends_ability("Ability"))
	assert_true(editor._extends_ability("StealthAbility"), "StealthAbility extends Ability")
	assert_true(editor._extends_ability("HealAbility"), "HealAbility extends Ability")
	assert_false(editor._extends_ability("SpellTree"), "A SpellTree is not an Ability")
	assert_false(editor._extends_ability(""), "A .tres without a script class is not one either")
	assert_false(editor._extends_ability("NoSuchClass"))
	assert_eq(SpellTreeEditor._header_script_class(STEALTH_PATH), "StealthAbility")
	assert_eq(SpellTreeEditor._header_script_class("res://addons/3d_player_controller/inventory/resources/spell_tree_demo.tres"), "SpellTree")
	assert_eq(SpellTreeEditor._header_script_class("res://no_such_file.tres"), "")


func test_a_spell_without_a_button_is_skipped_by_the_lines_and_dropped_by_a_drag() -> void:
	editor.tree = _two_spell_tree()
	var ghost: SpellNode = SpellNode.new()
	ghost.row = 2
	ghost.requires = [STEALTH]
	tree.nodes.append(ghost) # In place, so nothing rebuilds and Spell2 has no button
	assert_null(editor.get_node_button(2))
	assert_eq(editor.get_links().size(), 2, "The tree links Stealth to the ghost")
	assert_eq(editor._node_rect(2), Rect2(), "No button, no rect")
	var segment: PackedVector2Array = SpellTree.connection_segment(Rect2(Vector2.ZERO, editor.get_node_button(0).size), Rect2(CELL, editor.get_node_button(1).size))
	assert_eq(editor._link_at_point((segment[0] + segment[1]) * 0.5), Vector2i(0, 1), "The line between two buttons is still picked")
	assert_eq(editor._link_at_point(Vector2(CELL.x * 0.4, CELL.y * 1.6)), SpellTreeEditor.NO_LINK, "The ghost's line is not there to pick")
	editor.select_only(2)
	editor.canvas.queue_redraw()
	await wait_process_frames(1)
	assert_eq(editor.selected_index, 2, "Drawing the links and the frame of a spell with no button raised nothing")
	editor._drag_index = 2
	_move(Vector2(40.0, 40.0))
	assert_eq(editor._drag_index, -1, "A drag whose button is gone is dropped")
	editor._drag_index = 2
	_release(Vector2(40.0, 40.0))
	assert_eq(tree.nodes.size(), 3, "and letting go moves nothing")
	assert_eq(Vector2i(tree.nodes[2].column, tree.nodes[2].row), Vector2i(0, 2))


func test_edits_go_through_the_editors_undo_history_and_undo_puts_the_old_nodes_back() -> void:
	var history: FakeUndoRedo = FakeUndoRedo.new()
	editor.undo_redo = history
	editor.tree = _two_spell_tree(false)
	editor.add_requirement(0, 1)
	assert_eq(history.actions, ["Require spell"])
	assert_eq(tree.nodes[1].requires.size(), 1, "The do step ran")
	history.undo()
	assert_true(tree.nodes[1].requires.is_empty(), "Undo restores the earlier nodes")
	assert_eq(editor.get_links().size(), 0, "and the canvas follows")
	history.redo()
	assert_eq(tree.nodes[1].requires.size(), 1)
	editor.name_edit.text_submitted.emit("Renamed")
	assert_eq(history.actions, ["Require spell", "Rename spell tree"])
	assert_eq(tree.display_name, "Renamed")
	history.undo()
	assert_eq(tree.display_name, "Test Spells")


## Stands in for EditorUndoRedoManager: records each action's do and undo calls and can play them back.
class FakeUndoRedo:
	var actions: Array[String] = []
	var _do: Array[Callable] = []
	var _undo: Array[Callable] = []
	var _current: Array = []

	func create_action(action_name: String, _merge: int, _context: Object) -> void:
		actions.append(action_name)
		_current = [[], []]

	func add_do_method(object: Object, method: StringName, ...args: Array) -> void:
		_current[0].append(Callable(object, method).bindv(args))

	func add_undo_method(object: Object, method: StringName, ...args: Array) -> void:
		_current[1].append(Callable(object, method).bindv(args))

	func add_do_property(object: Object, property: StringName, value: Variant) -> void:
		_current[0].append(func() -> void: object.set(property, value))

	func add_undo_property(object: Object, property: StringName, value: Variant) -> void:
		_current[1].append(func() -> void: object.set(property, value))

	func commit_action() -> void:
		_do.append(func() -> void: for step: Callable in _current[0]: step.call())
		_undo.append(func() -> void: for step: Callable in _current[1]: step.call())
		_do.back().call()

	func undo() -> void:
		_undo.back().call()

	func redo() -> void:
		_do.back().call()


func test_clearing_the_tree_empties_the_canvas() -> void:
	editor.tree = _two_spell_tree()
	editor.tree = null
	assert_null(editor.get_node_button(0))
	assert_false(editor.scroll.visible)
	assert_true(editor.save_button.disabled)
	assert_true(editor.connect_button.disabled)
