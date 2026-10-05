class_name RadialMenu
extends Control
## Circular item picker opened by holding [member hold_actions]; releasing equips the hovered wedge.
##
## Items are Dictionaries with "display_name", "icon" and (for equipment) "item". A
## [member custom_item_provider] can supply its own Dictionaries (e.g. radio stations).

const PUNCH_ICON: Texture2D = preload("res://addons/3d_player_controller/assets/game_icons/punch.svg")
const ICON_SIZE: Vector2 = Vector2(64, 64)

@export var inner_radius: float = 64.0
@export var outer_radius: float = 200.0
@export var line_width: float = 4.0
@export var line_color: Color = Color.WHITE
@export var bg_color: Color = Color(0, 0, 0, 0.5)
@export var highlight_color: Color = Color(1, 1, 1, 0.3)
@export var equipped_color: Color = Color(1, 1, 1, 0.6)
@export var hold_actions: Array[StringName] = [&"last_weapon", &"next_weapon"] ## Actions that keep the wheel open.
@export var look_left_action: StringName = &"look_left" ## The right stick picks a wedge on a pad; these four read it.
@export var look_right_action: StringName = &"look_right"
@export var look_up_action: StringName = &"look_up"
@export var look_down_action: StringName = &"look_down"
@export_range(1, 16) var max_items: int = 8 ## Wedges at most (the weapon wheel's Unarmed wedge is on top of them).

var weapons: Array[Dictionary] = []
var hovered_index: int = -1

var custom_item_provider: Callable = Callable() ## Returns an Array of item Dictionaries.
var custom_item_selected: Callable = Callable() ## Called with (item, index) when a wedge is picked.
var custom_item_is_equipped: Callable = Callable() ## Returns true when (item, index) should draw as equipped.

@onready var player: Player = get_parent().player ## The Inventory or Abilities owning the wheel points at the Player.
@onready var inventory: Inventory = get_parent() as Inventory ## Null under the ability wheel, whose custom callbacks take over.
@onready var tooltip_label: Label = $TooltipLabel


func _ready() -> void:
	set_process(is_multiplayer_authority())


func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_menu_held():
		_close()
		return
	if weapons.is_empty():
		return
	var segment_angle: float = 360.0 / weapons.size()
	if _is_keyboard_mouse():
		var offset: Vector2 = get_local_mouse_position() - size / 2.0
		var distance: float = offset.length()
		if distance < inner_radius or distance > outer_radius:
			_set_hovered(-1)
		else:
			_set_hovered(int(fposmod(rad_to_deg(offset.angle()) + 90.0, 360.0) / segment_angle) % weapons.size())
	else:
		var stick: Vector2 = player.get_vector(look_left_action, look_right_action, look_up_action, look_down_action)
		if stick.length() > 0.3:
			_set_hovered(int(fposmod(rad_to_deg(stick.angle()) + 90.0, 360.0) / segment_angle) % weapons.size())


func is_menu_held() -> bool:
	return hold_actions.any(func(action: StringName) -> bool: return player.is_action_pressed(action))


func is_open() -> bool:
	return visible


## Opens the menu; wired to the inventory's hold timer.
func _on_hold_timer_timeout() -> void:
	if not is_menu_held():
		return
	update_items()
	if weapons.is_empty(): # a custom provider with nothing to offer
		return
	show()
	if player.uses_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _is_keyboard_mouse() else Input.MOUSE_MODE_HIDDEN
	player.crosshair.hide()


func _close() -> void:
	hide()
	if player.uses_mouse:
		Input.mouse_mode = player.cursor_mode()
	player.crosshair.show()
	if hovered_index != -1:
		equip_item(hovered_index)
	_set_hovered(-1)
	weapons.clear()


func _is_keyboard_mouse() -> bool:
	return player.controls.current_input_type == player.controls.InputType.KEYBOARD_MOUSE


func _set_hovered(index: int) -> void:
	if index == hovered_index:
		return
	hovered_index = index
	tooltip_label.text = "" if index == -1 else weapons[index].get("display_name", "")
	queue_redraw()


func update_items() -> void:
	if custom_item_provider.is_valid():
		weapons.assign(custom_item_provider.call())
		if weapons.size() > max_items:
			weapons.resize(max_items)
	else:
		weapons = [{"display_name": "Unarmed", "icon": PUNCH_ICON}]
		var owned: Array[Equipment] = inventory.get_all_weapons()
		for item: Equipment in owned.slice(0, max_items):
			var display_name: String = item.display_name
			if display_name.is_empty():
				display_name = Equipment.EquipmentType.keys()[item.equipment_type].capitalize()
			weapons.append({"item": item, "display_name": display_name, "icon": item.icon})
	queue_redraw()


func equip_item(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return
	if custom_item_selected.is_valid():
		custom_item_selected.call(weapons[index], index)
		return
	var item: Equipment = weapons[index].get("item")
	if item:
		inventory.equip_weapon(item)
	else:
		inventory.unequip_all()


func _is_equipped(index: int) -> bool:
	if custom_item_is_equipped.is_valid():
		return custom_item_is_equipped.call(weapons[index], index)
	var item: Equipment = weapons[index].get("item")
	return inventory.equipment.has(item) if item else inventory.equipment.is_empty()


func _draw() -> void:
	if weapons.is_empty():
		return

	var center: Vector2 = size / 2.0
	var segment_angle: float = TAU / weapons.size()
	var start_angle: float = -PI / 2.0
	var num_points: int = maxi(16, int(64.0 / weapons.size()))

	for i: int in weapons.size():
		var wedge_start: float = start_angle + i * segment_angle
		draw_polygon(_arc_band(center, wedge_start, segment_angle, num_points, inner_radius, outer_radius), PackedColorArray([highlight_color if i == hovered_index else bg_color]))
		if _is_equipped(i):
			var split_radius: float = inner_radius + (outer_radius - inner_radius) * 0.9
			draw_polygon(_arc_band(center, wedge_start, segment_angle, num_points, split_radius, outer_radius), PackedColorArray([equipped_color]))

		if weapons.size() > 1:
			var edge: Vector2 = Vector2(cos(wedge_start), sin(wedge_start))
			draw_line(center + edge * inner_radius, center + edge * outer_radius, line_color, line_width, true)

		var icon: Texture2D = weapons[i].get("icon")
		if icon:
			var mid_angle: float = wedge_start + segment_angle * 0.5
			var icon_pos: Vector2 = center + Vector2(cos(mid_angle), sin(mid_angle)) * (inner_radius + outer_radius) / 2.0
			draw_texture_rect(icon, Rect2(icon_pos - ICON_SIZE / 2.0, ICON_SIZE), false, weapons[i].get("icon_color", Color.WHITE))

	draw_arc(center, outer_radius, 0, TAU, 64, line_color, line_width, true)
	draw_arc(center, inner_radius, 0, TAU, 32, line_color, line_width, true)


## Polygon covering one wedge between two radii.
func _arc_band(center: Vector2, from_angle: float, sweep: float, num_points: int, radius_a: float, radius_b: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for j: int in num_points + 1:
		var a: float = from_angle + j * sweep / num_points
		points.append(center + Vector2(cos(a), sin(a)) * radius_a)
	for j: int in range(num_points, -1, -1):
		var a: float = from_angle + j * sweep / num_points
		points.append(center + Vector2(cos(a), sin(a)) * radius_b)
	return points
