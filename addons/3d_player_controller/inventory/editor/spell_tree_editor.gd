@tool
class_name SpellTreeEditor
extends Control
## The Spell Tree bottom panel: a [SpellTree] laid out the way the AnimationTree editor lays out a state machine,
## and the same picture the [SpellsScreen] shows in game. Every [SpellNode] is the very [SpellNodeButton] the
## screen draws, at its [member SpellNode.column] and [member SpellNode.row] (one cell per [constant SpellTree.CELL]).
## Drag a spell to move it and it snaps to the nearest free cell. With Connect on, drag from the spell to unlock
## first onto the spell it unlocks and a line with an arrow joins them (a [member SpellNode.requires] entry).
## Click a spell or a line to select it; Remove (or Delete) takes it away and Cost sets the selected spell's price.
## The palette on the left lists every [Ability] resource the editor's file index knows; Refresh rescans it,
## double-click, Add or a drag onto the canvas puts one on the tree, and Save writes the [code].tres[/code].
##
## The plugin hands in the editor's undo/redo so every edit is undoable; without one (in tests) edits apply at once.

signal modified ## The tree changed through the panel.
signal saved(path: String) ## Save wrote the tree to [param path].
signal save_as_requested(tree: SpellTree) ## Save was pressed on a tree with no file; the plugin asks for one.

const CELL: Vector2 = SpellTree.CELL ## One grid cell in canvas pixels (before [member ui_scale]).
const MAX_INDEX: int = 32 ## The far edge of [SpellNode]'s row and column ranges.
const NODE_BUTTON_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/spell_node_button.tscn") ## What the screen draws; drawn here too.
const LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
const SELECTED_COLOR: Color = Color(0.93, 0.78, 0.35)
const LINE_WIDTH: float = 3.0
const LINK_PICK_DISTANCE: float = 8.0 ## Pixels from a line that still count as clicking it.
const NO_LINK: Vector2i = Vector2i(-1, -1)

var tree: SpellTree: ## The tree on the canvas; null clears it.
	set(value):
		if tree == value:
			return
		if tree and tree.changed.is_connected(rebuild):
			tree.changed.disconnect(rebuild)
		tree = value
		dirty = false
		selected_index = -1
		selected_link = NO_LINK
		if tree:
			tree.changed.connect(rebuild)
			ensure_palette()
		rebuild()
		if tree:
			_set_status("Drag a spell to move it. Turn on Connect and drag from the spell to unlock first onto the one it unlocks.")
var ability_scanner: Callable = scan_ability_paths ## Returns the res:// paths of every Ability .tres; tests hand in their own.
var undo_redo: Object ## The editor's EditorUndoRedoManager; null applies edits directly.
var ui_scale: float = 1.0 ## The editor's display scale; cells and buttons draw this many times larger so a HiDPI editor shows the same picture.
var ability_paths: PackedStringArray = [] ## What the palette lists, from the last Refresh.
var dirty: bool = false ## Edits since the last save.
var scanned: bool = false ## The palette has been filled once; it waits for the first tree or opening, since it loads every Ability.
var selected_index: int = -1 ## The selected spell's index in the tree, or -1.
var selected_link: Vector2i = NO_LINK ## The selected line as (prerequisite index, dependent index), or [constant NO_LINK].
var connect_mode: bool = false ## Dragging from a spell draws a requirement instead of moving it.

var scroll: ScrollContainer
var canvas: Control
var palette: ItemList
var name_edit: LineEdit
var cost_spin: SpinBox ## The selected spell's cost.
var remove_button: Button
var connect_button: Button
var refresh_button: Button
var add_button: Button
var save_button: Button
var status_label: Label
var _drag_index: int = -1 ## The spell riding the mouse.
var _drag_offset: Vector2 = Vector2.ZERO ## Where in the spell the mouse took hold.
var _link_from: int = -1 ## The spell a requirement is being dragged out of.
var _pointer: Vector2 = Vector2.ZERO ## The mouse on the canvas, for the rubber band.
var _class_bases: Dictionary[String, String] = {} ## Global class name -> base, from the project's class list.


func _init() -> void:
	name = "SpellTreeEditor"
	custom_minimum_size = Vector2(0.0, 320.0)
	_build_ui()


func _ready() -> void:
	_refresh_state()
	_refresh_selection()


# --- The tree --------------------------------------------------------------------------------------------------

## Shows [param value] on the canvas (null clears it); the same tree is left alone.
func set_tree(value: SpellTree) -> void:
	tree = value


## Fills the palette the first time it is needed.
func ensure_palette() -> void:
	if not scanned:
		refresh_palette()


## Redraws the canvas from [member tree]: one button per SpellNode at its cell; the lines come from the tree at draw time.
func rebuild() -> void:
	for child: Node in canvas.get_children():
		if child is SpellNodeButton:
			canvas.remove_child(child)
			child.queue_free()
	_drag_index = -1
	_link_from = -1
	if tree:
		name_edit.text = tree.display_name
		canvas.custom_minimum_size = (tree.pixel_size() + CELL) * ui_scale # A spare cell to drop into
		for i: int in tree.nodes.size():
			_add_button(i, tree.nodes[i])
		if selected_index >= tree.nodes.size():
			selected_index = -1
		if not get_links().has(selected_link):
			selected_link = NO_LINK
	else:
		canvas.custom_minimum_size = Vector2.ZERO
		selected_index = -1
		selected_link = NO_LINK
	canvas.queue_redraw()
	_refresh_state()
	_refresh_selection()
	_mark_palette()


func get_node_button(index: int) -> SpellNodeButton:
	return canvas.get_node_or_null(NodePath(_node_name(index))) as SpellNodeButton


## Every requirement as (prerequisite index, dependent index), skipping prerequisites that are not on the tree.
func get_links() -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	if tree == null:
		return links
	for j: int in tree.nodes.size():
		for required: Ability in tree.nodes[j].requires:
			var i: int = _index_of_ability(tree.nodes, required)
			if i != -1:
				links.append(Vector2i(i, j))
	return links


# --- Selection -------------------------------------------------------------------------------------------------

## Selects spell [param index] alone.
func select_only(index: int) -> void:
	selected_index = index
	selected_link = NO_LINK
	canvas.queue_redraw()
	_refresh_selection()


## Selects the line from spell [param link].x to spell [param link].y alone.
func select_link(link: Vector2i) -> void:
	selected_link = link
	selected_index = -1
	canvas.queue_redraw()
	_refresh_selection()


func clear_selection() -> void:
	selected_index = -1
	selected_link = NO_LINK
	canvas.queue_redraw()
	_refresh_selection()


## Takes the selected spell off the tree, or drops the selected requirement.
func remove_selection() -> void:
	if selected_index != -1:
		remove_nodes([selected_index])
	elif selected_link != NO_LINK:
		remove_requirement(selected_link.x, selected_link.y)


# --- Edits -----------------------------------------------------------------------------------------------------

## Puts the Ability at [param path] on the tree at [param cell] (column, row) when that cell is free, else at the
## first free cell, and selects it. A spell already on the tree is selected instead. False when nothing was added.
func add_ability_path(path: String, cell: Vector2i = Vector2i(-1, -1)) -> bool:
	var ability: Ability = load(path) as Ability
	if ability == null or tree == null:
		_set_status("Not an Ability: " + path)
		return false
	var existing: int = _index_of_ability(tree.nodes, ability)
	if existing != -1:
		select_only(existing)
		_set_status(ability.display_name + " is already on the tree")
		return false
	var nodes: Array[SpellNode] = tree.nodes.duplicate()
	var node: SpellNode = SpellNode.new()
	node.ability = ability
	if cell.x < 0 or _node_at(nodes, cell) != null:
		cell = _first_free_cell(nodes)
	node.column = cell.x
	node.row = cell.y
	nodes.append(node)
	selected_index = nodes.size() - 1
	selected_link = NO_LINK
	_commit("Add spell to tree", nodes)
	return true


func remove_nodes(indices: Array[int]) -> void:
	if tree == null or indices.is_empty():
		return
	var removed: Array[Ability] = []
	for i: int in indices:
		if tree.nodes[i].ability:
			removed.append(tree.nodes[i].ability)
	var nodes: Array[SpellNode] = []
	for i: int in tree.nodes.size():
		if indices.has(i):
			continue
		var node: SpellNode = tree.nodes[i]
		for ability: Ability in removed:
			if node.requires.has(ability):
				if node == tree.nodes[i]:
					node = _copy_node(node)
				node.requires.erase(ability)
		nodes.append(node)
	selected_index = -1
	selected_link = NO_LINK
	_commit("Remove spell from tree", nodes)


## Makes spell [param prerequisite] a requirement of spell [param dependent]; refused when it would loop.
func add_requirement(prerequisite: int, dependent: int) -> bool:
	if tree == null or prerequisite == dependent:
		return false
	var required: Ability = tree.nodes[prerequisite].ability
	var target: SpellNode = tree.nodes[dependent]
	if required == null or target.ability == null or target.requires.has(required):
		return false
	if _depends_on(tree.nodes, tree.nodes[prerequisite], target.ability, []):
		_set_status("%s already needs %s, so the link would loop" % [required.display_name, target.ability.display_name])
		return false
	var nodes: Array[SpellNode] = tree.nodes.duplicate()
	var copy: SpellNode = _copy_node(target)
	copy.requires.append(required)
	nodes[dependent] = copy
	selected_link = Vector2i(prerequisite, dependent)
	selected_index = -1
	_commit("Require spell", nodes)
	return true


func remove_requirement(prerequisite: int, dependent: int) -> void:
	if tree == null:
		return
	var required: Ability = tree.nodes[prerequisite].ability
	if required == null or not tree.nodes[dependent].requires.has(required):
		return
	var nodes: Array[SpellNode] = tree.nodes.duplicate()
	var copy: SpellNode = _copy_node(tree.nodes[dependent])
	copy.requires.erase(required)
	nodes[dependent] = copy
	selected_link = NO_LINK
	_commit("Drop spell requirement", nodes)


func set_cost(index: int, cost: int) -> void:
	if tree == null or tree.nodes[index].cost == cost:
		return
	var nodes: Array[SpellNode] = tree.nodes.duplicate()
	var copy: SpellNode = _copy_node(tree.nodes[index])
	copy.cost = cost
	nodes[index] = copy
	_commit("Set spell cost", nodes)


## Moves spell [param index] to [param cell] (column, row) when the cell is free; false when it is taken.
func move_node(index: int, cell: Vector2i) -> bool:
	if tree == null:
		return false
	var node: SpellNode = tree.nodes[index]
	if node.column == cell.x and node.row == cell.y:
		return true
	if _node_at(tree.nodes, cell) != null:
		return false
	var nodes: Array[SpellNode] = tree.nodes.duplicate()
	var copy: SpellNode = _copy_node(node)
	copy.column = cell.x
	copy.row = cell.y
	nodes[index] = copy
	_commit("Move spell", nodes)
	return true


func set_display_name(value: String) -> void:
	if tree == null or tree.display_name == value:
		return
	if undo_redo:
		undo_redo.create_action("Rename spell tree", UndoRedo.MERGE_DISABLE, tree)
		undo_redo.add_do_property(tree, &"display_name", value)
		undo_redo.add_undo_property(tree, &"display_name", tree.display_name)
		undo_redo.add_do_method(self, &"_after_edit", tree)
		undo_redo.add_undo_method(self, &"_after_edit", tree)
		undo_redo.commit_action()
	else:
		tree.display_name = value
		_after_edit(tree)


## Writes the tree to its file; a tree without one asks the plugin for a path through [signal save_as_requested].
func save() -> bool:
	if tree == null:
		return false
	if tree.resource_path.is_empty() or tree.resource_path.contains("::"):
		save_as_requested.emit(tree)
		return false
	return save_to(tree.resource_path)


func save_to(path: String) -> bool:
	if tree == null:
		return false
	var error: Error = ResourceSaver.save(tree, path)
	if error != OK:
		_set_status("Could not save %s: %s" % [path, error_string(error)])
		return false
	if tree.resource_path.is_empty() or tree.resource_path.contains("::"): # No file yet, or built into another one
		tree.take_over_path(path)
	dirty = false
	_refresh_state()
	_set_status("Saved " + path)
	saved.emit(path)
	return true


# --- The palette -----------------------------------------------------------------------------------------------

## Lists every Ability the scanner finds; the ones already on the tree are dimmed.
func refresh_palette() -> void:
	scanned = true
	ability_paths = ability_scanner.call()
	ability_paths.sort()
	palette.clear()
	for path: String in ability_paths:
		var ability: Ability = load(path) as Ability
		if ability == null:
			continue
		var label: String = ability.display_name if not ability.display_name.is_empty() else path.get_file().get_basename()
		var index: int = palette.add_item(label, ability.icon)
		palette.set_item_icon_modulate(index, ability.icon_color)
		palette.set_item_metadata(index, path)
		palette.set_item_tooltip(index, path)
	_mark_palette()
	if palette.item_count == 0:
		_set_status("No Ability resources found; the palette lists what the editor's file index knows")


## Every .tres whose script class is an Ability (or extends one), found through the editor's file index instead of
## walking the disk. The index knows a script-backed .tres only by its native type, Resource (materials, meshes and
## the like carry their own and are passed over), so just those few headers are read for their script_class; nothing
## loads. Outside the editor there is no index and the list is empty.
func scan_ability_paths() -> PackedStringArray:
	var found: PackedStringArray = []
	if not Engine.is_editor_hint():
		return found
	var filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if filesystem == null:
		return found
	_load_class_bases()
	_scan_index(filesystem.get_filesystem(), found)
	return found


func _scan_index(folder: EditorFileSystemDirectory, found: PackedStringArray) -> void:
	if folder == null:
		return
	for i: int in folder.get_file_count():
		var path: String = folder.get_file_path(i)
		if path.get_extension() == "tres" and folder.get_file_type(i) == "Resource" and _extends_ability(_header_script_class(path)):
			found.append(path)
	for i: int in folder.get_subdir_count():
		_scan_index(folder.get_subdir(i), found)


## Global class name -> base, from the project's class list, so [method _extends_ability] can follow a chain.
func _load_class_bases() -> void:
	_class_bases.clear()
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_class_bases[entry["class"]] = entry["base"]


## The script_class attribute of a .tres header, or "" when it has none.
static func _header_script_class(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var header: String = file.get_line()
	file.close()
	var start: int = header.find("script_class=\"")
	if start == -1:
		return ""
	start += "script_class=\"".length()
	return header.substr(start, header.find("\"", start) - start)


func _extends_ability(script_class: String) -> bool:
	var current: String = script_class
	var depth: int = 0
	while not current.is_empty() and depth < 32:
		if current == "Ability":
			return true
		current = _class_bases.get(current, "")
		depth += 1
	return false


# --- Building --------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	var split: HSplitContainer = HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	var side: VBoxContainer = VBoxContainer.new()
	side.custom_minimum_size.x = 220.0
	split.add_child(side)
	var side_bar: HBoxContainer = HBoxContainer.new()
	side.add_child(side_bar)
	var palette_label: Label = Label.new()
	palette_label.text = "Abilities"
	palette_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_bar.add_child(palette_label)
	refresh_button = Button.new()
	refresh_button.text = "Refresh"
	refresh_button.tooltip_text = "Scan the project for Ability resources again"
	refresh_button.pressed.connect(refresh_palette)
	side_bar.add_child(refresh_button)
	palette = AbilityList.new()
	palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette.fixed_icon_size = Vector2i(24, 24) # The ability icons are SVGs and would draw at full size
	palette.item_activated.connect(_on_palette_activated)
	palette.item_selected.connect(_on_palette_selected)
	side.add_child(palette)
	add_button = Button.new()
	add_button.text = "Add to tree"
	add_button.tooltip_text = "Put the selected ability on the tree (or double-click it, or drag it onto the canvas)"
	add_button.pressed.connect(_on_add_pressed)
	side.add_child(add_button)

	var main: VBoxContainer = VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(main)
	var bar: HBoxContainer = HBoxContainer.new()
	main.add_child(bar)
	var name_label: Label = Label.new()
	name_label.text = "Tree name"
	bar.add_child(name_label)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size.x = 180.0
	name_edit.text_submitted.connect(set_display_name)
	name_edit.focus_exited.connect(_on_name_focus_exited)
	bar.add_child(name_edit)
	connect_button = Button.new()
	connect_button.text = "Connect"
	connect_button.toggle_mode = true
	connect_button.tooltip_text = "Drag from the spell to unlock first onto the spell it unlocks"
	connect_button.toggled.connect(_on_connect_toggled)
	bar.add_child(connect_button)
	var cost_label: Label = Label.new()
	cost_label.text = "  Cost"
	bar.add_child(cost_label)
	cost_spin = SpinBox.new()
	cost_spin.name = "CostSpin"
	cost_spin.min_value = 0
	cost_spin.max_value = 99
	cost_spin.tooltip_text = "Skill points to unlock the selected spell; 0 is free"
	cost_spin.value_changed.connect(_on_cost_changed)
	bar.add_child(cost_spin)
	remove_button = Button.new()
	remove_button.text = "Remove"
	remove_button.tooltip_text = "Take the selected spell or line off the tree (Delete does too)"
	remove_button.pressed.connect(remove_selection)
	bar.add_child(remove_button)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(status_label)
	save_button = Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(save)
	bar.add_child(save_button)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(scroll)
	canvas = SpellCanvas.new()
	canvas.name = "Canvas"
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.focus_mode = Control.FOCUS_ALL
	canvas.drop_handler = _on_ability_dropped
	canvas.draw.connect(_draw_canvas)
	canvas.gui_input.connect(_on_canvas_input)
	scroll.add_child(canvas)


## The screen's own button at the node's cell, drawn at the editor's scale; the canvas handles its mouse.
func _add_button(index: int, node: SpellNode) -> void:
	var button: SpellNodeButton = NODE_BUTTON_SCENE.instantiate()
	button.name = _node_name(index)
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.focus_mode = Control.FOCUS_NONE
	button.scale = Vector2.ONE * ui_scale
	button.position = _offset_of(Vector2i(node.column, node.row))
	canvas.add_child(button)
	button.touch_button.visible = false
	button.set_node(node, false, true)


# --- The canvas ------------------------------------------------------------------------------------------------

## Lines under the buttons, the rubber band of a requirement being dragged, and a frame around the selected spell.
func _draw_canvas() -> void:
	if tree == null:
		return
	for link: Vector2i in get_links():
		var from: Rect2 = _node_rect(link.x)
		var to: Rect2 = _node_rect(link.y)
		if not from.has_area() or not to.has_area():
			continue
		var color: Color = SELECTED_COLOR if link == selected_link else LINE_COLOR
		SpellTree.draw_connection(canvas, from, to, color, LINE_WIDTH * ui_scale)
	if _link_from != -1 and _node_rect(_link_from).has_area():
		canvas.draw_line(_node_rect(_link_from).get_center(), _pointer, SELECTED_COLOR, LINE_WIDTH * ui_scale, true)
	if selected_index != -1 and _node_rect(selected_index).has_area():
		canvas.draw_rect(_node_rect(selected_index).grow(3.0 * ui_scale), SELECTED_COLOR, false, 2.0 * ui_scale)


func _on_canvas_input(event: InputEvent) -> void:
	if tree == null:
		return
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		if click.pressed:
			_press(click.position)
		else:
			_release(click.position)
		canvas.accept_event()
	elif event is InputEventMouseMotion:
		_pointer = (event as InputEventMouseMotion).position
		if _drag_index != -1:
			var dragged: SpellNodeButton = get_node_button(_drag_index)
			if dragged:
				dragged.position = _pointer - _drag_offset
			else:
				_drag_index = -1 # The button went away under the mouse; nothing to carry
			canvas.queue_redraw()
		elif _link_from != -1:
			canvas.queue_redraw()
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and (key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE):
			remove_selection()
			canvas.accept_event()


## A press on a spell takes hold of it (or, with Connect on, starts a requirement); on a line selects it; elsewhere clears.
func _press(at: Vector2) -> void:
	canvas.grab_focus()
	_pointer = at
	var index: int = _node_at_point(at)
	if index != -1:
		if connect_mode:
			_link_from = index
		else:
			_drag_index = index
			_drag_offset = at - get_node_button(index).position
		select_only(index)
		return
	var link: Vector2i = _link_at_point(at)
	if link != NO_LINK:
		select_link(link)
	else:
		clear_selection()


## Letting go settles a dragged spell on the nearest free cell (or back where it was) and lands a requirement on the spell under the mouse.
func _release(at: Vector2) -> void:
	if _drag_index != -1:
		var index: int = _drag_index
		_drag_index = -1
		var button: SpellNodeButton = get_node_button(index)
		if button == null:
			return
		if not move_node(index, _cell_of(button.position)):
			_set_status("That cell already has a spell")
		button = get_node_button(index) # A move rebuilt the canvas
		if button:
			button.position = _offset_of(Vector2i(tree.nodes[index].column, tree.nodes[index].row))
		canvas.queue_redraw()
	elif _link_from != -1:
		var prerequisite: int = _link_from
		_link_from = -1
		var dependent: int = _node_at_point(at)
		if dependent != -1 and dependent != prerequisite:
			add_requirement(prerequisite, dependent)
		canvas.queue_redraw()


## The spell's button on the canvas, or an empty [Rect2] (no area) when it has none, such as a node added without a rebuild.
func _node_rect(index: int) -> Rect2:
	var button: SpellNodeButton = get_node_button(index)
	if button == null:
		return Rect2()
	return Rect2(button.position, button.size * ui_scale)


## The topmost spell under [param at], or -1.
func _node_at_point(at: Vector2) -> int:
	if tree == null:
		return -1
	for i: int in range(tree.nodes.size() - 1, -1, -1):
		var button: SpellNodeButton = get_node_button(i)
		if button and _node_rect(i).has_point(at):
			return i
	return -1


## The line within [constant LINK_PICK_DISTANCE] of [param at], or [constant NO_LINK].
func _link_at_point(at: Vector2) -> Vector2i:
	for link: Vector2i in get_links():
		var from: Rect2 = _node_rect(link.x)
		var to: Rect2 = _node_rect(link.y)
		if not from.has_area() or not to.has_area():
			continue
		var segment: PackedVector2Array = SpellTree.connection_segment(from, to)
		if Geometry2D.get_closest_point_to_segment(at, segment[0], segment[1]).distance_to(at) <= LINK_PICK_DISTANCE * ui_scale:
			return link
	return NO_LINK


func _on_ability_dropped(path: String, at: Vector2) -> void:
	add_ability_path(path, _cell_under(at))


func _on_palette_activated(index: int) -> void:
	add_ability_path(palette.get_item_metadata(index))


func _on_palette_selected(_index: int) -> void:
	_refresh_state()


func _on_add_pressed() -> void:
	var selected: PackedInt32Array = palette.get_selected_items()
	if not selected.is_empty():
		add_ability_path(palette.get_item_metadata(selected[0]))


func _on_name_focus_exited() -> void:
	set_display_name(name_edit.text)


func _on_cost_changed(value: float) -> void:
	if selected_index != -1:
		set_cost(selected_index, int(value))


func _on_connect_toggled(pressed: bool) -> void:
	connect_mode = pressed
	_link_from = -1
	canvas.queue_redraw()
	if pressed:
		_set_status("Drag from the spell to unlock first onto the spell it unlocks")


# --- Helpers ---------------------------------------------------------------------------------------------------

## Replaces the tree's nodes with [param nodes], through undo/redo when the editor gave us one.
func _commit(action_name: String, nodes: Array[SpellNode]) -> void:
	if undo_redo:
		undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, tree)
		undo_redo.add_do_method(self, &"_apply_nodes", tree, nodes)
		undo_redo.add_undo_method(self, &"_apply_nodes", tree, tree.nodes.duplicate())
		undo_redo.commit_action()
	else:
		_apply_nodes(tree, nodes)


func _apply_nodes(target: SpellTree, nodes: Array[SpellNode]) -> void:
	target.nodes = nodes.duplicate()
	_after_edit(target)


## Marks the edit and tells the tree it changed; the tree setter wired [signal Resource.changed] to [method rebuild],
## so the canvas redraws right here, before this returns.
func _after_edit(target: SpellTree) -> void:
	if target == tree:
		dirty = true
	target.emit_changed()
	modified.emit()


## A SpellNode edited through the panel is copied first, so undo can put the untouched original back.
static func _copy_node(node: SpellNode) -> SpellNode:
	var copy: SpellNode = SpellNode.new()
	copy.ability = node.ability
	copy.cost = node.cost
	copy.requires = node.requires.duplicate()
	copy.row = node.row
	copy.column = node.column
	return copy


## Whether [param node] needs [param ability] somewhere up its chain of prerequisites.
static func _depends_on(nodes: Array[SpellNode], node: SpellNode, ability: Ability, seen: Array[SpellNode]) -> bool:
	if seen.has(node):
		return false
	seen.append(node)
	for required: Ability in node.requires:
		if required == ability:
			return true
		var i: int = _index_of_ability(nodes, required)
		if i != -1 and _depends_on(nodes, nodes[i], ability, seen):
			return true
	return false


static func _index_of_ability(nodes: Array[SpellNode], ability: Ability) -> int:
	for i: int in nodes.size():
		if nodes[i].ability == ability:
			return i
	return -1


static func _index_of_path(nodes: Array[SpellNode], path: String) -> int:
	for i: int in nodes.size():
		if nodes[i].ability and nodes[i].ability.resource_path == path:
			return i
	return -1


static func _node_at(nodes: Array[SpellNode], cell: Vector2i) -> SpellNode:
	for node: SpellNode in nodes:
		if node.column == cell.x and node.row == cell.y:
			return node
	return null


## The first empty cell reading each row left to right; (column, row).
static func _first_free_cell(nodes: Array[SpellNode]) -> Vector2i:
	var columns: int = 1
	for node: SpellNode in nodes:
		columns = maxi(columns, node.column + 1)
	for row: int in MAX_INDEX + 1:
		for column: int in columns:
			if _node_at(nodes, Vector2i(column, row)) == null:
				return Vector2i(column, row)
	return Vector2i(columns, 0)


## The cell (column, row) nearest a spell whose top-left corner sits at [param offset].
func _cell_of(offset: Vector2) -> Vector2i:
	var cell: Vector2 = offset / ui_scale / CELL
	return Vector2i(clampi(roundi(cell.x), 0, MAX_INDEX), clampi(roundi(cell.y), 0, MAX_INDEX))


## The cell (column, row) under a point on the canvas.
func _cell_under(at: Vector2) -> Vector2i:
	var cell: Vector2 = at / ui_scale / CELL
	return Vector2i(clampi(floori(cell.x), 0, MAX_INDEX), clampi(floori(cell.y), 0, MAX_INDEX))


## The canvas offset of a cell (column, row).
func _offset_of(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL * ui_scale


static func _node_name(index: int) -> StringName:
	return StringName("Spell%d" % index)


## Dims the palette entries already on the tree; a clear colour hands the rest back to the theme.
func _mark_palette() -> void:
	var dimmed: Color = palette.get_theme_color(&"font_color")
	dimmed.a *= 0.45
	for i: int in palette.item_count:
		var on_tree: bool = tree != null and _index_of_path(tree.nodes, palette.get_item_metadata(i)) != -1
		palette.set_item_custom_fg_color(i, dimmed if on_tree else Color(0.0, 0.0, 0.0, 0.0))


## The toolbar's Cost and Remove follow the selection.
func _refresh_selection() -> void:
	cost_spin.editable = selected_index != -1
	remove_button.disabled = selected_index == -1 and selected_link == NO_LINK
	if selected_index != -1 and tree:
		cost_spin.set_value_no_signal(tree.nodes[selected_index].cost)


func _refresh_state() -> void:
	var has_tree: bool = tree != null
	scroll.visible = has_tree
	name_edit.editable = has_tree
	connect_button.disabled = not has_tree
	save_button.disabled = not has_tree
	save_button.text = "Save*" if dirty else "Save"
	add_button.disabled = not has_tree or palette.get_selected_items().is_empty()
	if not has_tree:
		name_edit.text = ""
		_set_status("Select a SpellTree resource to edit it")


func _set_status(text: String) -> void:
	status_label.text = text


## The palette: its items can be dragged onto the canvas.
class AbilityList extends ItemList:
	func _get_drag_data(at_position: Vector2) -> Variant:
		var index: int = get_item_at_position(at_position, true)
		if index == -1:
			return null
		var preview: Label = Label.new()
		preview.text = get_item_text(index)
		set_drag_preview(preview)
		return {"type": "spell_ability", "path": get_item_metadata(index)}


## The canvas: takes a palette drop and hands the path and position to [member drop_handler].
class SpellCanvas extends Control:
	var drop_handler: Callable

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("type") == "spell_ability"

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		drop_handler.call(data["path"], at_position)
