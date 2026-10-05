extends Node3D
## Demo for the Controls addon: a HUD wired to actions this project made up, and a world prompt on the crate.
##
## Everything the HUD shows comes from the action names exported on the [Controls] node, set in
## [code]demo.tscn[/code]. The face buttons, shoulders, triggers and the right stick are mapped to
## [code]demo_*[/code] actions that appear nowhere in [code]project.godot[/code] - the addon registers them at
## runtime - while the d-pad and the left stick are left at their defaults, which are Godot's own
## [code]ui_up[/code], [code]ui_down[/code], [code]ui_left[/code] and [code]ui_right[/code]. Press any of them
## and the button lights up and the readout names the action.

## The keys and mouse buttons behind the made-up actions. A slot registers the pad button it stands for on its
## own, so this only has to add what the pad cannot describe. Handed to the HUD in [method _enter_tree],
## because a child is ready before its parent and [method Controls._ready] is where the registering happens.
const KEYBOARD_BINDINGS: Dictionary = {
	"demo_interact": {"keys": [KEY_E]},
	"demo_run": {"keys": [KEY_SHIFT]},
	"demo_attack": {"keys": [KEY_F]},
	"demo_jump": {"keys": [KEY_SPACE]},
	"demo_crouch": {"keys": [KEY_CTRL]},
	"demo_zoom": {"mouse": [MOUSE_BUTTON_MIDDLE]},
	"demo_ability": {"keys": [KEY_Q]},
	"demo_throw": {"keys": [KEY_T]},
	"demo_aim": {"mouse": [MOUSE_BUTTON_RIGHT]},
	"demo_shoot": {"mouse": [MOUSE_BUTTON_LEFT]},
	"demo_view": {"keys": [KEY_F5]},
	"demo_screenshot": {"keys": [KEY_PRINT]},
	"demo_menu": {"keys": [KEY_ESCAPE]},
}

## The actions the readout watches, paired with what to call them.
const WATCHED: Dictionary[StringName, String] = {
	&"demo_interact": "Interact",
	&"demo_run": "Run",
	&"demo_attack": "Attack",
	&"demo_jump": "Jump",
	&"demo_crouch": "Crouch",
	&"demo_zoom": "Zoom",
	&"demo_ability": "Ability",
	&"demo_throw": "Throw",
	&"demo_aim": "Aim",
	&"demo_shoot": "Shoot",
	&"demo_view": "View",
	&"demo_screenshot": "Screenshot",
	&"demo_menu": "Menu",
	&"ui_up": "Up",
	&"ui_down": "Down",
	&"ui_left": "Left",
	&"ui_right": "Right",
}

var _menu_open: bool = false ## Whether the demo is showing its "menu" label set instead of the default one.

@onready var controls: Controls = $Controls
@onready var action_prompt: ActionPrompt = $Crate/ActionPrompt
@onready var device_label: Label = %DeviceLabel
@onready var action_label: Label = %ActionLabel


## The HUD registers its actions in its own [method Node._ready], which runs before this node's, so the extra
## bindings have to be in place before that: a parent enters the tree ahead of its children.
func _enter_tree() -> void:
	($Controls as Controls).extra_actions = KEYBOARD_BINDINGS


func _ready() -> void:
	controls.input_type_changed.connect(_on_input_type_changed)
	_on_input_type_changed(controls.current_input_type)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"demo_menu"):
		_menu_open = not _menu_open
		_apply_menu_labels()
	for action_name: StringName in WATCHED:
		if InputMap.has_action(action_name) and event.is_action_pressed(action_name):
			action_label.text = "%s   (%s)" % [WATCHED[action_name], action_name]


## The world prompt follows the device being played on, and names the Interact button after what it opens.
func _on_input_type_changed(input_type: Controls.InputType) -> void:
	device_label.text = String(Controls.InputType.keys()[input_type]).capitalize()
	action_prompt.show_for(controls, "Open")


## Shows what one screen's worth of contextual labels looks like: [method Controls.set_labels] writes the ones
## given and clears the rest, and [method Controls.reset_labels] puts the scene's own text back.
func _apply_menu_labels() -> void:
	if not _menu_open:
		controls.reset_labels()
		return
	controls.set_labels({
		controls.joypad_button_0_label: "Select",
		controls.joypad_button_1_label: "Back",
		controls.joypad_button_6_label: "Close",
		controls.left_joystick_label: "Navigate",
	})
