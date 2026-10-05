@tool
class_name SpellNodeButton
extends Button
## One node of the tree on the [SpellsScreen]: the spell's icon, name and cost, drawn dim while locked and marked
## once unlocked, with a [TouchScreenButton] for fingers. A tool script, so the editor's Spell Tree panel can draw
## the same button inside its graph nodes.

signal node_pressed(ability: Ability)
signal node_focused(ability: Ability)

var ability: Ability

@onready var icon_rect: TextureRect = %Icon
@onready var name_label: Label = %Name
@onready var cost_label: Label = %Cost
@onready var touch_button: TouchScreenButton = $TouchScreenButton


func _ready() -> void:
	PlayerMenuLayer.fit_touch_buttons(self) # The signals are wired in spell_node_button.tscn


## Shows [param node]'s spell in one of three looks: unlocked, unlockable now, or locked.
func set_node(node: SpellNode, is_unlocked: bool, is_unlockable: bool) -> void:
	ability = node.ability
	icon_rect.texture = ability.icon if ability else null
	icon_rect.modulate = ability.icon_color if ability else Color.WHITE
	name_label.text = ability.display_name if ability else ""
	cost_label.text = "Unlocked" if is_unlocked else ("%d pt" % node.cost if node.cost != 1 else "1 pt")
	modulate = Color.WHITE if is_unlocked or is_unlockable else Color(1.0, 1.0, 1.0, 0.45)
	tooltip_text = name_label.text


func _on_pressed() -> void:
	node_pressed.emit(ability)


func _on_focus_entered() -> void:
	node_focused.emit(ability)


func _on_touch_pressed() -> void:
	grab_focus()
	node_pressed.emit(ability)
