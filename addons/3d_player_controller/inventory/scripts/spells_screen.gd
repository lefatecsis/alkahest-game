class_name SpellsScreen
extends PlayerMenuLayer
## The Spells page from the Pause menu, in two pages. Tree: the [SpellTree] as a grid of [SpellNodeButton]s with
## lines to their prerequisites; Confirm (or Unlock) on an unlockable node spends skill points on it. Loadout: the
## unlocked spells on the left and the wheel's slots on the right; Confirm on a spell lifts it, Confirm on a slot
## puts it there, Confirm on a filled slot with nothing held clears it. Q and T (the bumpers) switch pages, and
## Back returns to Pause. Every control takes focus and pairs with a touch button, like the rest of the menus.

const NODE_BUTTON_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/spell_node_button.tscn")
const SLOT_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/inventory_slot.tscn")
const LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.35)
const LINE_UNLOCKED_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)

enum Page { TREE, LOADOUT }

@export var previous_page_action: StringName = &"ability" ## Q / left bumper.
@export var next_page_action: StringName = &"throw" ## T / right bumper.

var page: Page = Page.TREE
var focused_ability: Ability ## The spell under the cursor on either page.
var held_ability: Ability ## The unlocked spell riding on the cursor on the loadout page.
var focused_slot: int = -1
var _spellbook: Spellbook
var _built_tree: SpellTree ## The tree the node buttons were built for; a different one rebuilds them.
var _node_buttons: Dictionary[Ability, SpellNodeButton] = {}
var _unlocked_buttons: Array[SpellNodeButton] = []
var _slot_buttons: Array[InventorySlotButton] = []

@onready var page_buttons: Array[Button] = [%TreeTab, %LoadoutTab]
@onready var tree_page: Control = %TreePage
@onready var loadout_page: Control = %LoadoutPage
@onready var points_label: Label = %PointsLabel
@onready var tree_holder: ScrollContainer = %TreeHolder ## The fixed tree area: the canvas is centred inside it when smaller, scrolls when larger.
@onready var tree_canvas: Control = %TreeCanvas ## Spans the grid; the node buttons sit on it at their cells, like the editor graph.
@onready var tree_lines: Control = %TreeLines
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name: Label = %DetailName
@onready var detail_status: Label = %DetailStatus
@onready var detail_info: Label = %DetailInfo ## What the ability does in numbers (`Ability.get_details()`: damage, ticks, slows, fire).
@onready var detail_requires: Label = %DetailRequires
@onready var unlock_button: Button = %Unlock
@onready var unlocked_scroll: ScrollContainer = %UnlockedScroll ## The unlocked list's fixed area: the grid is centred in it when smaller and scrolls, following focus, when larger.
@onready var unlocked_grid: GridContainer = %UnlockedGrid
@onready var wheel_grid: GridContainer = %WheelGrid
@onready var clear_button: Button = %Clear
@onready var held_icon: TextureRect = %HeldIcon


func _ready() -> void:
	super()
	for i: int in page_buttons.size():
		page_buttons[i].pressed.connect(_select_page.bind(i as Page))
		page_buttons[i].mouse_entered.connect(page_buttons[i].grab_focus)
	tree_lines.draw.connect(_draw_tree_lines)
	if player:
		bind(player)


## Points the screen at [param target]'s spellbook and builds the tree and the wheel slots.
func bind(target: Player) -> void:
	player = target
	if _spellbook:
		_spellbook.loadout_changed.disconnect(refresh)
		_spellbook.skill_points_changed.disconnect(_on_points_changed)
	_spellbook = target.inventory.spellbook if target.inventory else null
	if _spellbook == null:
		return
	_spellbook.loadout_changed.connect(refresh)
	_spellbook.skill_points_changed.connect(_on_points_changed)
	_build_tree()
	for slot: InventorySlotButton in _slot_buttons:
		slot.queue_free()
	_slot_buttons.clear()
	for i: int in _spellbook.max_active:
		var slot: InventorySlotButton = SLOT_SCENE.instantiate()
		slot.index = i
		slot.name = "Wheel%d" % i
		wheel_grid.add_child(slot)
		slot.slot_pressed.connect(_on_wheel_slot_pressed)
		slot.slot_focused.connect(_on_wheel_slot_focused)
		_slot_buttons.append(slot)


## Puts a button for every node at its cell, the same picture the editor's Spell Tree panel draws.
func _build_tree() -> void:
	for button: SpellNodeButton in _node_buttons.values():
		tree_canvas.remove_child(button)
		button.queue_free()
	_node_buttons.clear()
	var tree: SpellTree = _spellbook.tree
	_built_tree = tree
	tree_canvas.custom_minimum_size = tree.pixel_size() if tree else Vector2.ZERO
	if tree == null:
		return
	for node: SpellNode in tree.nodes:
		if node.ability == null:
			continue
		var button: SpellNodeButton = NODE_BUTTON_SCENE.instantiate()
		button.name = node.ability.display_name.to_pascal_case()
		tree_canvas.add_child(button)
		button.position = SpellTree.cell_position(node)
		button.node_pressed.connect(_on_node_pressed)
		button.node_focused.connect(_on_node_focused)
		_node_buttons[node.ability] = button
	_update_touch_visibility()


## A [TouchScreenButton] ignores its scroll area's clipping, so a node or an unlocked spell scrolled out of view would
## still take taps over the tabs and the action row; hiding it turns its hit test off. Wired to each area's resized,
## the tree canvas's and the unlocked grid's item_rect_changed (a scroll moves them) and the grid's sort_children
## (its spells were laid out) in spells_screen.tscn, and called after every tree rebuild.
func _update_touch_visibility() -> void:
	if not is_instance_valid(tree_holder) or not is_instance_valid(unlocked_scroll):
		return
	var shown: Rect2 = tree_holder.get_global_rect()
	for button: SpellNodeButton in _node_buttons.values():
		if is_instance_valid(button) and is_instance_valid(button.touch_button):
			button.touch_button.visible = shown.intersects(button.get_global_rect())
	var listed: Rect2 = unlocked_scroll.get_global_rect()
	for button: SpellNodeButton in _unlocked_buttons:
		if is_instance_valid(button) and is_instance_valid(button.touch_button):
			button.touch_button.visible = listed.intersects(button.get_global_rect())


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("start"):
		_cancel_hold()
		hide_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if held_ability:
			_cancel_hold()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(previous_page_action):
		_select_page(Page.TREE)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(next_page_action):
		_select_page(Page.LOADOUT)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if held_ability == null or not visible:
		return
	if player and player.controls and player.controls.current_input_type == Controls.InputType.KEYBOARD_MOUSE:
		held_icon.global_position = held_icon.get_viewport().get_mouse_position() + Vector2(12.0, 12.0)
	else:
		var focus: Control = get_viewport().gui_get_focus_owner()
		if focus:
			held_icon.global_position = focus.global_position + focus.size * 0.5


func show_menu() -> void:
	super()
	if _spellbook == null and player:
		bind(player)
	refresh()
	_focus_first()


func hide_menu() -> void:
	_cancel_hold()
	super()


## Redraws both pages from the spellbook.
func refresh() -> void:
	if _spellbook == null:
		return
	for i: int in page_buttons.size():
		page_buttons[i].button_pressed = i == page
	tree_page.visible = page == Page.TREE
	loadout_page.visible = page == Page.LOADOUT
	_on_points_changed(_spellbook.skill_points)
	if _spellbook.tree != _built_tree:
		_build_tree()
	var tree: SpellTree = _spellbook.tree
	for ability: Ability in _node_buttons:
		var node: SpellNode = tree.get_node_for(ability) if tree else null
		if node:
			_node_buttons[ability].set_node(node, _spellbook.is_unlocked(ability), _spellbook.can_unlock(ability))
	tree_lines.queue_redraw()
	_rebuild_unlocked()
	for i: int in _slot_buttons.size():
		_slot_buttons[i].set_ability(_spellbook.active[i])
		_slot_buttons[i].equipped_mark.visible = _spellbook.active[i] != null and _spellbook.active[i] == player.abilities.active_ability
	_update_details()


## The buttons are rebuilt from scratch, so the focus a pad player had on one is put back on the same spell,
## or the first button when that spell is gone.
func _rebuild_unlocked() -> void:
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var refocus: Ability = null # the spell whose button had the focus, if one did
	for button: SpellNodeButton in _unlocked_buttons:
		if button == focused:
			refocus = button.ability
		button.queue_free()
	_unlocked_buttons.clear()
	for ability: Ability in _spellbook.unlocked:
		var button: SpellNodeButton = NODE_BUTTON_SCENE.instantiate()
		button.name = ability.display_name.to_pascal_case()
		unlocked_grid.add_child(button)
		var node: SpellNode = _spellbook.tree.get_node_for(ability) if _spellbook.tree else null
		button.set_node(node if node else _loose_node(ability), true, false)
		button.cost_label.text = "On wheel" if _spellbook.is_active(ability) else "Unlocked"
		button.modulate = Color(1.0, 1.0, 1.0, 0.4) if ability == held_ability else Color.WHITE
		button.node_pressed.connect(_on_unlocked_pressed)
		button.node_focused.connect(_on_node_focused)
		_unlocked_buttons.append(button)
	if refocus == null:
		return
	for button: SpellNodeButton in _unlocked_buttons:
		if button.ability == refocus:
			button.grab_focus()
			return
	if not _unlocked_buttons.is_empty():
		_unlocked_buttons[0].grab_focus()
	elif not _slot_buttons.is_empty():
		_slot_buttons[0].grab_focus()


## A node for a starting spell the tree does not list.
static func _loose_node(ability: Ability) -> SpellNode:
	var node: SpellNode = SpellNode.new()
	node.ability = ability
	node.cost = 0
	return node


func _select_page(target: Page) -> void:
	if target == page:
		return
	_cancel_hold()
	page = target
	refresh()
	_focus_first()


func _focus_first() -> void:
	if page == Page.TREE:
		for button: SpellNodeButton in _node_buttons.values():
			button.grab_focus()
			return
		unlock_button.grab_focus()
	else:
		if not _unlocked_buttons.is_empty():
			_unlocked_buttons[0].grab_focus()
		elif not _slot_buttons.is_empty():
			_slot_buttons[0].grab_focus()


# --- Tree page --------------------------------------------------------------------------------------------------

func _on_node_pressed(ability: Ability) -> void:
	focused_ability = ability
	if page == Page.TREE and _spellbook.unlock(ability):
		refresh()


func _on_node_focused(ability: Ability) -> void:
	focused_ability = ability
	focused_slot = -1
	_update_details()


func _on_unlock_pressed() -> void:
	if focused_ability and _spellbook.unlock(focused_ability):
		refresh()


func _on_unlock_touch_screen_button_pressed() -> void:
	_on_unlock_pressed()


func _on_points_changed(points: int) -> void:
	points_label.text = "Skill points: %d" % points


func _draw_tree_lines() -> void:
	if _spellbook == null or _spellbook.tree == null:
		return
	for ability: Ability in _node_buttons:
		var node: SpellNode = _spellbook.tree.get_node_for(ability)
		var to_button: SpellNodeButton = _node_buttons[ability]
		for required: Ability in node.requires:
			var from_button: SpellNodeButton = _node_buttons.get(required)
			if from_button == null:
				continue
			var color: Color = LINE_UNLOCKED_COLOR if _spellbook.is_unlocked(required) else LINE_COLOR
			SpellTree.draw_connection(tree_lines, Rect2(from_button.position, from_button.size), Rect2(to_button.position, to_button.size), color)


# --- Loadout page ----------------------------------------------------------------------------------------------

func _on_unlocked_pressed(ability: Ability) -> void:
	focused_ability = ability
	if held_ability == ability:
		_cancel_hold()
		return
	held_ability = ability
	held_icon.texture = ability.icon
	held_icon.show()
	refresh()


func _on_wheel_slot_pressed(index: int) -> void:
	focused_slot = index
	if held_ability:
		var placed: Ability = held_ability
		held_ability = null
		held_icon.hide()
		_spellbook.set_active(index, placed)
	elif _spellbook.active[index] != null:
		_spellbook.clear_active(index)
	refresh()


func _on_wheel_slot_focused(index: int) -> void:
	focused_slot = index
	focused_ability = _spellbook.active[index]
	_update_details()


func _on_clear_pressed() -> void:
	if focused_slot != -1:
		_spellbook.clear_active(focused_slot)
	elif focused_ability:
		var slot: int = _spellbook.active.find(focused_ability)
		if slot != -1:
			_spellbook.clear_active(slot)
	_cancel_hold()
	refresh()


func _on_clear_touch_screen_button_pressed() -> void:
	_on_clear_pressed()


# --- Shared ------------------------------------------------------------------------------------------------------

## Return to the pause menu.
func _on_back_pressed() -> void:
	_cancel_hold()
	hide()
	if player and player.pause:
		player.pause.show_menu()


func _on_back_touch_screen_button_pressed() -> void:
	_on_back_pressed()


func _cancel_hold() -> void:
	if held_ability == null:
		return
	held_ability = null
	held_icon.hide()
	refresh()


func _update_details() -> void:
	var ability: Ability = held_ability if held_ability else focused_ability
	if ability == null:
		detail_icon.texture = null
		detail_name.text = ""
		detail_status.text = "Empty slot" if focused_slot != -1 else ""
		detail_info.text = ""
		detail_requires.text = ""
		unlock_button.disabled = true
		return
	detail_icon.texture = ability.icon
	detail_icon.modulate = ability.icon_color
	detail_name.text = ability.display_name
	detail_info.text = str(ability.call("get_details")) if ability.has_method("get_details") else ""
	var node: SpellNode = _spellbook.tree.get_node_for(ability) if _spellbook.tree else null
	if _spellbook.is_unlocked(ability):
		detail_status.text = "On the wheel" if _spellbook.is_active(ability) else "Unlocked"
	elif node:
		detail_status.text = "Costs %d skill point%s" % [node.cost, "" if node.cost == 1 else "s"]
	else:
		detail_status.text = "Not on this tree"
	var names: PackedStringArray = PackedStringArray()
	if node:
		for required: Ability in node.requires:
			names.append(required.display_name + ("" if _spellbook.is_unlocked(required) else " (locked)"))
	detail_requires.text = "Requires: " + ", ".join(names) if not names.is_empty() else ""
	unlock_button.disabled = not _spellbook.can_unlock(ability)
