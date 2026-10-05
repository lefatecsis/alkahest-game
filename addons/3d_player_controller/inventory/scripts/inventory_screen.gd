class_name InventoryScreen
extends PlayerMenuLayer
## The BOTW style inventory page: category tabs across the top, a grid of [InventorySlotButton]s, a details
## panel and Use / Drop / Back. Every control takes focus, so it works with a pad, the keyboard, the mouse and a
## finger the same way the pause menu does. Confirm on a stack lifts it onto the cursor and confirm on another slot
## drops it there (swap, or merge onto the same item); on the equipment tab confirm equips or stows the weapon.
## The [Pause] menu opens it when its inventory screen path is set, and Back returns there.

const SLOT_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/inventory_slot.tscn")
const TABS: Array[Item.Category] = [Item.Category.EQUIPMENT, Item.Category.MATERIALS, Item.Category.FOOD, Item.Category.KEY_ITEMS]

@export var columns: int = 5
@export var previous_tab_action: StringName = &"ability" ## Q / left bumper.
@export var next_tab_action: StringName = &"throw" ## T / right bumper.

var tab: Item.Category = Item.Category.EQUIPMENT
var held_index: int = -1 ## The slot whose stack rides on the cursor, -1 for none.
var focused_index: int = -1
var _slots: Array[InventorySlotButton] = []
var _weapons: Array[Equipment] = [] ## What the equipment tab shows, by slot.
var _inventory: Inventory

@onready var tab_buttons: Array[Button] = [%EquipmentTab, %MaterialsTab, %FoodTab, %KeyItemsTab]
@onready var grid_scroll: ScrollContainer = %GridScroll ## The grid's fixed area in the panel: the grid is centred in it when smaller and scrolls, following focus, when larger.
@onready var grid: GridContainer = %Grid
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_model: SubViewportContainer = %DetailModel ## The turning 3D preview shown instead of the icon when an item has a model.
@onready var model_pivot: Node3D = %ModelPivot
@onready var model_camera: Camera3D = %ModelCamera
@onready var detail_name: Label = %DetailName
@onready var detail_count: Label = %DetailCount
@onready var detail_scroll: ScrollContainer = %DetailScroll ## Holds the description at the panel's fixed height; a long one (a fish's ten lengths) scrolls inside it.
@onready var detail_description: Label = %DetailDescription
@onready var use_button: Button = %Use
@onready var drop_button: Button = %Drop
@onready var back_button: Button = %Back
@onready var held_icon: TextureRect = %HeldIcon


func _ready() -> void:
	super()
	grid.columns = columns
	for i: int in tab_buttons.size():
		tab_buttons[i].pressed.connect(_select_tab.bind(TABS[i]))
		tab_buttons[i].mouse_entered.connect(tab_buttons[i].grab_focus)
	if player:
		bind(player)


## Points the screen at [param target]'s inventory and builds the grid to its size.
func bind(target: Player) -> void:
	player = target
	if _inventory and _inventory.items_changed.is_connected(refresh):
		_inventory.items_changed.disconnect(refresh)
		_inventory.equipment_changed.disconnect(refresh)
	_inventory = target.inventory
	_inventory.items_changed.connect(refresh)
	_inventory.equipment_changed.connect(refresh)
	for slot: InventorySlotButton in _slots:
		slot.queue_free()
	_slots.clear()
	for i: int in _inventory.slots_per_tab:
		var slot: InventorySlotButton = SLOT_SCENE.instantiate()
		slot.index = i
		slot.name = "Slot%d" % i
		grid.add_child(slot)
		slot.slot_pressed.connect(_on_slot_pressed)
		slot.slot_focused.connect(_on_slot_focused)
		_slots.append(slot)


## A [TouchScreenButton] ignores the scroll area's clipping, so a slot scrolled out of view would still take taps over
## the tabs and the actions; hiding it turns its hit test off. Wired to the area's resized and the grid's
## item_rect_changed (a scroll moves the grid) and sort_children (the slots were laid out) in inventory_screen.tscn.
func _update_touch_visibility() -> void:
	if not is_instance_valid(grid_scroll):
		return
	var shown: Rect2 = grid_scroll.get_global_rect()
	for slot: InventorySlotButton in _slots:
		if is_instance_valid(slot) and is_instance_valid(slot.touch_button):
			slot.touch_button.visible = shown.intersects(slot.get_global_rect())


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("start"):
		_cancel_hold()
		hide_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if held_index != -1:
			_cancel_hold()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(previous_tab_action):
		_select_tab(TABS[posmod(TABS.find(tab) - 1, TABS.size())])
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(next_tab_action):
		_select_tab(TABS[posmod(TABS.find(tab) + 1, TABS.size())])
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if detail_model.visible:
		model_pivot.rotate_y(delta * 0.8)
	if held_index == -1 or not visible:
		return
	if player and player.controls and player.controls.current_input_type == Controls.InputType.KEYBOARD_MOUSE:
		held_icon.global_position = held_icon.get_viewport().get_mouse_position() + Vector2(12.0, 12.0)
	elif focused_index != -1:
		held_icon.global_position = _slots[focused_index].global_position + _slots[focused_index].size * 0.5


func show_menu() -> void:
	super()
	if _inventory == null and player:
		bind(player)
	refresh()
	if not _slots.is_empty():
		_slots[0].grab_focus()


func hide_menu() -> void:
	_cancel_hold()
	super()


## Redraws the current tab from the inventory.
func refresh() -> void:
	if _inventory == null:
		return
	for i: int in tab_buttons.size():
		tab_buttons[i].button_pressed = TABS[i] == tab
	if tab == Item.Category.EQUIPMENT:
		_weapons = _inventory.get_all_weapons()
		for i: int in _slots.size():
			var weapon: Equipment = _weapons[i] if i < _weapons.size() else null
			_slots[i].set_equipment(weapon, weapon != null and _inventory.equipment.has(weapon))
			_slots[i].disabled = i >= _inventory.max_equipment # BOTW: the weapon slots beyond the limit are not there
			# A rod's bait changes without the inventory moving; the equipment says so and the details follow
			if weapon and not weapon.details_changed.is_connected(_update_details):
				weapon.details_changed.connect(_update_details)
		use_button.text = "Equip"
	else:
		var slots: Array = _inventory.get_slots(tab)
		for i: int in _slots.size():
			_slots[i].set_stack(slots[i] if i < slots.size() else null, player)
			_slots[i].disabled = false
		use_button.text = "Use"
	for i: int in _slots.size():
		_slots[i].set_held(i == held_index)
	_update_details()


func _select_tab(category: Item.Category) -> void:
	if category == tab:
		return
	_cancel_hold()
	tab = category
	refresh()
	if focused_index == -1 and not _slots.is_empty():
		_slots[0].grab_focus()


func _on_slot_pressed(index: int) -> void:
	focused_index = index
	if tab == Item.Category.EQUIPMENT:
		_toggle_equipment(index)
		return
	if held_index == -1:
		if _slots[index].is_empty():
			return
		held_index = index
		held_icon.texture = _slots[index].icon
		held_icon.show()
		refresh()
	else:
		var from: int = held_index
		held_index = -1
		held_icon.hide()
		_inventory.move_slot(tab, from, index)
		refresh()


func _on_slot_focused(index: int) -> void:
	focused_index = index
	_update_details()


func _toggle_equipment(index: int) -> void:
	if index >= _weapons.size():
		return
	var weapon: Equipment = _weapons[index]
	if _inventory.equipment.has(weapon):
		_inventory.stow_equipment(weapon)
	else:
		_inventory.equip_weapon(weapon)


func _acting_index() -> int:
	return held_index if held_index != -1 else focused_index


func _on_use_pressed() -> void:
	var index: int = _acting_index()
	if index == -1 or _slots[index].is_empty():
		return
	if tab == Item.Category.EQUIPMENT:
		_toggle_equipment(index)
	else:
		_inventory.use_slot(tab, index)
		refresh() # a non-consumable changes no stack, but what it selected may badge the grid
	_cancel_hold()


func _on_use_touch_screen_button_pressed() -> void:
	_on_use_pressed()


func _on_drop_pressed() -> void:
	var index: int = _acting_index()
	if index == -1 or _slots[index].is_empty():
		return
	if tab == Item.Category.EQUIPMENT:
		_inventory.drop_equipment(_weapons[index])
	else:
		_inventory.drop_slot(tab, index)
	_cancel_hold()


func _on_drop_touch_screen_button_pressed() -> void:
	_on_drop_pressed()


## Return to the pause menu.
func _on_back_pressed() -> void:
	_cancel_hold()
	hide()
	if player and player.pause:
		player.pause.show_menu()


func _on_back_touch_screen_button_pressed() -> void:
	_on_back_pressed()


func _cancel_hold() -> void:
	if held_index == -1:
		return
	held_index = -1
	held_icon.hide()
	refresh()


func _update_details() -> void:
	var index: int = _acting_index()
	var slot: InventorySlotButton = _slots[index] if index >= 0 and index < _slots.size() else null
	if slot == null or slot.is_empty():
		detail_icon.texture = null
		detail_icon.modulate = Color.WHITE
		detail_name.text = ""
		detail_count.text = ""
		detail_description.text = ""
		_show_model(null, null)
		return
	detail_icon.texture = slot.icon
	detail_icon.modulate = slot.item.get_icon_color() if slot.item else Color.WHITE
	if slot.equipment:
		detail_name.text = InventorySlotButton.equipment_name(slot.equipment)
		detail_count.text = "Equipped" if _inventory.equipment.has(slot.equipment) else "Stowed"
		detail_description.text = _join_details(slot.equipment.description, slot.equipment.get_details())
		_show_model(slot.equipment.model_scene, null)
	else:
		var stack: ItemSlot = _inventory.get_slot(tab, index)
		detail_name.text = slot.item.get_display_name()
		detail_count.text = "x%d" % (stack.count if stack else 0)
		detail_description.text = _join_details(slot.item.description, slot.item.get_details(player))
		_show_model(slot.item.get_model_scene(), slot.item)


## The flavour text, then whatever the item adds, with a blank line between when both are there.
func _join_details(description: String, details: String) -> String:
	if description.is_empty() or details.is_empty():
		return description + details
	return description + "\n\n" + details


## Puts [param scene] turning in the preview viewport in place of the icon; null goes back to the icon.
func _show_model(scene: PackedScene, item: Item) -> void:
	for child: Node in model_pivot.get_children():
		child.queue_free()
	detail_model.visible = scene != null
	detail_icon.visible = scene == null
	if scene == null:
		return
	var model: Node3D = scene.instantiate() as Node3D
	model_pivot.add_child(model)
	if item:
		item.prepare_model(model) # once in the tree, so the model's own ready nodes exist
	# Centre the model under the camera and size the view to it
	var bounds: AABB = AABB()
	var first: bool = true
	for geometry: Node in model.find_children("*", "GeometryInstance3D", true, false):
		var visual: GeometryInstance3D = geometry as GeometryInstance3D
		var box: AABB = (model_pivot.global_transform.affine_inverse() * visual.global_transform) * visual.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if not first:
		model.position = -bounds.get_center()
		model_camera.size = maxf(bounds.get_longest_axis_size() * 1.4, 0.1)
