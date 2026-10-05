@tool
class_name ControlsInputCatalog
extends Resource
## The list of inputs a game will actually answer to, so the HUD's slots become a dropdown of them
## instead of free text.
##
## A game that reads the InputMap rather than raw events - an emulator wrapped as a GDExtension, say -
## knows exactly which actions it listens for and nothing else will reach it. Shipping that list as a
## resource lets [Controls] offer it: set [member Controls.input_catalog] and every
## [code]action_*[/code] slot turns into a picker of these names, so a slot cannot quietly name an
## action the game has never heard of.
##
## It is entirely optional. With no catalog set the slots stay plain text and behave exactly as they
## did, which is what a game that defines its own actions wants.
##
## The resource is a snapshot of what the game listens for, so whatever produces it should be checked
## against the game itself rather than kept in step by hand.

## The action names, in the order they should appear in the picker. A blank entry is ignored; the
## picker always offers an empty choice of its own, because a slot left blank is a button the game
## does not use and the HUD hides it.
@export var actions: Array[StringName] = []


## The picker's choices, as a [constant PROPERTY_HINT_ENUM] hint string: an empty choice first, then
## every action, with anything blank or repeated dropped.
func hint_string() -> String:
	var choices: PackedStringArray = [""]
	for action: StringName in actions:
		var name: String = String(action)
		if name != "" and not choices.has(name):
			choices.append(name)
	return ",".join(choices)


## Whether [param action] is one of the names in this catalog. A blank name is always allowed, since
## that is how a slot is turned off.
func has_action(action: StringName) -> bool:
	return action == &"" or actions.has(action)
