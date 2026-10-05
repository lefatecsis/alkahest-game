class_name InventorySlotButton
extends Button
## One cell of the [InventoryScreen] grid: the item's icon, its stack count, its [method Item.get_badge] in the top
## right corner, a held marker while it is being carried, and a [TouchScreenButton] so it works under a finger as well as under focus and the mouse.

signal slot_pressed(index: int)
signal slot_focused(index: int)

var index: int = 0
var item: Item ## What the cell shows, null when empty.
var equipment: Equipment ## For the equipment tab: the weapon shown.
var ability: Ability ## For the spell wheel slots: the spell shown.

@onready var count_label: Label = $Count
@onready var equipped_mark: Label = $Equipped
@onready var badge_label: Label = $Badge ## The item's badge; hidden when the item has none.
@onready var touch_button: TouchScreenButton = $TouchScreenButton


func _ready() -> void:
	pressed.connect(func() -> void: slot_pressed.emit(index))
	focus_entered.connect(func() -> void: slot_focused.emit(index))
	mouse_entered.connect(grab_focus)
	touch_button.pressed.connect(func() -> void:
		grab_focus()
		slot_pressed.emit(index))
	PlayerMenuLayer.fit_touch_buttons(self)


## Shows a stack, or empties the cell with null; [param holder] is the Player, handed to [method Item.get_badge].
func set_stack(slot: ItemSlot, holder: Node = null) -> void:
	equipment = null
	ability = null
	item = slot.item if slot else null
	icon = item.icon if item else null
	_tint(item.get_icon_color() if item else Color.WHITE)
	count_label.text = str(slot.count) if slot and slot.count > 1 else ""
	_set_badge(item.get_badge(holder) if item else "")
	equipped_mark.hide()
	tooltip_text = item.get_display_name() if item else ""


## Shows a weapon or tool, marked when it is on the skeleton.
func set_equipment(weapon: Equipment, is_equipped: bool) -> void:
	item = null
	ability = null
	equipment = weapon
	icon = weapon.icon if weapon else null
	_tint(Color.WHITE)
	count_label.text = ""
	_set_badge("")
	equipped_mark.visible = weapon != null and is_equipped
	tooltip_text = equipment_name(weapon) if weapon else ""


## Shows a spell (a wheel slot on the Spells screen), or empties the cell with null.
func set_ability(spell: Ability) -> void:
	item = null
	equipment = null
	ability = spell
	icon = spell.icon if spell else null
	_tint(spell.icon_color if spell else Color.WHITE)
	count_label.text = ""
	_set_badge("")
	equipped_mark.hide()
	tooltip_text = spell.display_name if spell else ""


## Dims the cell while its stack rides on the cursor.
func set_held(held: bool) -> void:
	modulate = Color(1.0, 1.0, 1.0, 0.4) if held else Color.WHITE


func is_empty() -> bool:
	return item == null and equipment == null and ability == null


## Prints [param text] in the corner, or hides the label when there is nothing to print.
func _set_badge(text: String) -> void:
	badge_label.text = text
	badge_label.visible = not text.is_empty()


## The icon's colour in every button state.
func _tint(color: Color) -> void:
	for state_name: String in ["icon_normal_color", "icon_pressed_color", "icon_hover_color", "icon_focus_color", "icon_hover_pressed_color", "icon_disabled_color"]:
		add_theme_color_override(state_name, color)


static func equipment_name(weapon: Equipment) -> String:
	if weapon == null:
		return ""
	if not weapon.display_name.is_empty():
		return weapon.display_name
	return String(Equipment.EquipmentType.keys()[weapon.equipment_type]).capitalize()
