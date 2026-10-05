class_name SeekerWheel
extends CanvasLayer
## Holding the "seeker" action (D-pad Up / I) opens a second [RadialMenu] beside the weapon wheel, and what it
## offers depends on what the Player is doing.
##
## Aiming (focus held) with a [Bow] or a [Firearm] equipped, the wedges are the kinds of ammunition carried for
## that weapon, with the kind it draws marked, and releasing on one selects it exactly as Use does
## ([method Inventory.use_item], so the grid's badges and the weapon follow). Otherwise the wedges are the
## throwable items carried ([member Item.throwable]), the one the next throw takes marked, and releasing on one
## makes it [member Player.selected_throwable]. With nothing to offer the wheel stays closed. Local to the owning
## peer; a carried object keeps the seeker action for its own controls.

@export var player: Player

var context_weapon: Equipment ## The Bow or Firearm the last wheel listed ammunition for; null for throwables.

@onready var hold_timer: Timer = $HoldTimer ## Runs while seeker is held; its timeout opens the wheel.
@onready var radial_menu: RadialMenu = $RadialMenu


func _ready() -> void:
	set_process_unhandled_input(is_multiplayer_authority())
	radial_menu.custom_item_provider = get_wheel_items
	radial_menu.custom_item_selected = _on_wheel_item_selected
	radial_menu.custom_item_is_equipped = _is_wheel_item_selected


func _unhandled_input(event: InputEvent) -> void:
	if player == null or player.is_paused or player.is_typing or player.held_object.is_holding_object():
		hold_timer.stop()
		return
	if event.is_action_pressed(&"seeker") and not event.is_echo():
		hold_timer.start()
	elif event.is_action_released(&"seeker"):
		hold_timer.stop()


## Wired to HoldTimer.timeout: opens the wheel when there is something to pick.
func _on_hold_timer_timeout() -> void:
	if get_wheel_items().is_empty():
		return
	radial_menu._on_hold_timer_timeout()


## The Bow or Firearm the Player is aiming with, else null: a firearm while focus is held, a bow while focus is
## held or the string is drawn (is_shooting, is_drawing_arrow, is_aiming_bow), so arrows can be swapped mid-draw.
func get_aimed_weapon() -> Equipment:
	if player == null:
		return null
	var bow_drawn: bool = player.is_shooting or player.is_drawing_arrow or player.is_aiming_bow
	for weapon: Equipment in player.inventory.equipment:
		if weapon is Bow and (player.is_focusing or bow_drawn):
			return weapon
		if weapon is Firearm and player.is_focusing:
			return weapon
	return null


## The wedges for the moment: ammunition kinds for the aimed weapon, else the throwable items carried.
func get_wheel_items() -> Array[Dictionary]:
	var wedges: Array[Dictionary] = []
	context_weapon = get_aimed_weapon()
	if context_weapon:
		for ammo: AmmoItem in get_ammo_kinds(context_weapon.equipment_type):
			wedges.append(_wedge(ammo))
	else:
		for item: Item in player.inventory.get_throwable_items():
			wedges.append(_wedge(item))
	return wedges


## The carried [AmmoItem] kinds for a weapon [param type], in tab and slot order, each kind once.
func get_ammo_kinds(type: Equipment.EquipmentType) -> Array[AmmoItem]:
	var kinds: Array[AmmoItem] = []
	for category: Item.Category in Inventory.ITEM_TABS:
		for slot: ItemSlot in player.inventory.get_slots(category):
			var ammo: AmmoItem = slot.item as AmmoItem if slot else null
			if ammo and ammo.weapon_type == type and not kinds.any(func(kind: AmmoItem) -> bool: return kind.is_same(ammo)):
				kinds.append(ammo)
	return kinds


func _wedge(item: Item) -> Dictionary:
	return {
		"item": item,
		"display_name": "%s x%d" % [item.get_display_name(), player.inventory.count_of(item)],
		"icon": item.icon,
		"icon_color": item.get_icon_color(),
	}


## Releasing on a wedge: ammunition is used (the weapon's own selection path), a throwable becomes the Player's pick.
func _on_wheel_item_selected(wedge: Dictionary, _index: int) -> void:
	var item: Item = wedge.get("item") as Item
	if item is AmmoItem:
		player.inventory.use_item(item)
	elif item:
		player.selected_throwable = item


## The wedge drawn as picked: the kind the aimed weapon draws, or the throwable the next throw takes.
func _is_wheel_item_selected(wedge: Dictionary, _index: int) -> bool:
	var item: Item = wedge.get("item") as Item
	if item == null:
		return false
	if context_weapon and context_weapon.has_method("get_ammo"):
		return item.is_same(context_weapon.call("get_ammo") as AmmoItem)
	return item.is_same(player.held_object.get_selected_throwable())
