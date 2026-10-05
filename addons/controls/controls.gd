@tool
class_name Controls
extends CanvasLayer

## On-screen input hints: shows which button does what, swaps the button art to match the device being
## used, and registers the InputMap actions it needs so the addon is a drop-in with no [code]project.godot[/code] edits.
##
## Every button on the HUD is a slot with an [b]action name of its own[/b], exported so a project maps it
## without touching this script. The defaults are Godot's own built-in actions wherever the engine already
## binds that physical button, so the HUD does something sensible in a project that has never defined an
## action: the face buttons drive [code]ui_accept[/code], [code]ui_cancel[/code] and [code]ui_select[/code],
## the d-pad and the left stick drive [code]ui_up[/code], [code]ui_down[/code], [code]ui_left[/code] and
## [code]ui_right[/code]. A slot left blank is a button the game does not use, and it is hidden.
##
## Where a project wants richer bindings than the slot's own button - a keyboard key for a face button, say -
## it fills [member extra_actions] before calling [code]super()[/code] in its own [method Node._ready].

signal input_type_changed(input_type: InputType) ## The device being played on has changed.
signal contextual_labels_requested ## A world prompt gave its label back; whatever owns the labels should re-apply them.
signal screenshot_taken(path: String) ## A screenshot was saved. On the web this is the file name the browser was given.

const SCREENSHOT_DIR: String = "user://screenshots" ## Where [method take_screenshot] saves, off the web.
const BUTTON_SIZE: float = 64.0 ## How big a face button is drawn at a scale of one, in canvas pixels: the art is 64 square.

## What the bottom left offers a touchscreen player for movement. See [member touch_movement].
enum TouchMovement {
	JOYSTICK, ## The virtual stick.
	BUTTONS, ## The four movement buttons - the same nodes the keyboard set draws as its movement keys.
}

enum InputType {
	KEYBOARD_MOUSE,
	MICROSOFT,
	NINTENDO,
	SONY,
	TOUCH,
}

## The physical input each slot stands for, used to register an action the project has not defined and to
## extend Godot's own [code]ui_*[/code] actions. Keys are slot names; values are
## [code]keys[/code] (physical keycodes), [code]buttons[/code] (joypad buttons) and [code]axes[/code]
## ([code][axis, value][/code] pairs).
const SLOT_EVENTS: Dictionary = {
	"button_0": {"buttons": [JOY_BUTTON_A]},
	"button_1": {"buttons": [JOY_BUTTON_B]},
	"button_2": {"buttons": [JOY_BUTTON_X]},
	"button_3": {"buttons": [JOY_BUTTON_Y]},
	"button_4": {"buttons": [JOY_BUTTON_BACK], "keys": [KEY_F5]},
	"button_6": {"buttons": [JOY_BUTTON_START], "keys": [KEY_ESCAPE]},
	"button_7": {"buttons": [JOY_BUTTON_LEFT_STICK]},
	"button_8": {"buttons": [JOY_BUTTON_RIGHT_STICK]},
	"button_9": {"buttons": [JOY_BUTTON_LEFT_SHOULDER]},
	"button_10": {"buttons": [JOY_BUTTON_RIGHT_SHOULDER]},
	"button_11": {"buttons": [JOY_BUTTON_DPAD_UP], "keys": [KEY_I]},
	"button_12": {"buttons": [JOY_BUTTON_DPAD_DOWN], "keys": [KEY_K]},
	"button_13": {"buttons": [JOY_BUTTON_DPAD_LEFT], "keys": [KEY_J]},
	"button_14": {"buttons": [JOY_BUTTON_DPAD_RIGHT], "keys": [KEY_L]},
	"button_15": {"buttons": [JOY_BUTTON_MISC1], "keys": [KEY_PRINT]},
	"axis_4_plus": {"axes": [[JOY_AXIS_TRIGGER_LEFT, 1.0]]},
	"axis_5_plus": {"axes": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]},
	"move_up": {"keys": [KEY_W], "axes": [[JOY_AXIS_LEFT_Y, -1.0]]},
	"move_down": {"keys": [KEY_S], "axes": [[JOY_AXIS_LEFT_Y, 1.0]]},
	"move_left": {"keys": [KEY_A], "axes": [[JOY_AXIS_LEFT_X, -1.0]]},
	"move_right": {"keys": [KEY_D], "axes": [[JOY_AXIS_LEFT_X, 1.0]]},
	"look_up": {"keys": [KEY_UP], "axes": [[JOY_AXIS_RIGHT_Y, -1.0]]},
	"look_down": {"keys": [KEY_DOWN], "axes": [[JOY_AXIS_RIGHT_Y, 1.0]]},
	"look_left": {"keys": [KEY_LEFT], "axes": [[JOY_AXIS_RIGHT_X, -1.0]]},
	"look_right": {"keys": [KEY_RIGHT], "axes": [[JOY_AXIS_RIGHT_X, 1.0]]},
}

## The slots whose art swaps per input device. The button of each is [code]joypad_<slot>[/code] and its art
## is [code]<prefix>_<slot>_normal[/code] and [code]_pressed[/code], so this list is the only order there is.
const SWAPPABLE_SLOTS: PackedStringArray = [
	"button_0", "button_1", "button_2", "button_3", "button_4", "button_15", "button_6",
	"button_7", "button_8", "button_9", "button_10", "axis_4_plus", "axis_5_plus",
]

## The export prefix that holds each input type's art. Touch has none and borrows Microsoft's.
const VENDOR_PREFIXES: Dictionary[InputType, String] = {
	InputType.KEYBOARD_MOUSE: "keyboard_mouse",
	InputType.MICROSOFT: "microsoft",
	InputType.NINTENDO: "nintendo",
	InputType.SONY: "sony",
}

@export var input_deadzone: float = 0.05 ## Address joystick drift by setting a deadzone threshold for joystick motion inputs

## How big a face button is, as a fraction of the shorter side of the window in real pixels, a tenth by
## default. The HUD sizes itself to the window rather than to the project's stretch mode, and sizes itself
## again whenever the window changes, so it comes out the same on the glass whether the game stretches its
## canvas or draws pixel for pixel, and a thumb has something to hit. Zero turns the fit off and leaves the
## HUD at [member hud_scale] alone.
@export_range(0.0, 0.3, 0.005) var button_fraction: float = 0.1:
	set(value):
		button_fraction = value
		if is_node_ready():
			apply_scale()

## A multiplier on top of the fit, for a game that wants its HUD a little bigger or smaller than
## [member button_fraction] gives, or a fixed size with the fit turned off. Each corner's cluster of buttons
## scales about the corner it is anchored to, so the bottom right grows up and to the left and stays in the
## bottom right. It shows in the editor as it is typed.
@export_range(0.25, 4.0, 0.05) var hud_scale: float = 1.0:
	set(value):
		hud_scale = value
		if is_node_ready():
			apply_scale()

## What a touchscreen player gets for movement: the virtual stick, or the four movement buttons.
##
## A stick is analogue, and in a game that reads four directions and nothing in between that works against
## the player - a finger a fraction off the axis is a direction the game cannot express, so the stick feels
## finicky where a button would not. Such a game sets [constant TouchMovement.BUTTONS] and gets the four
## buttons of the movement slots instead, with the stick taken off the screen.
##
## Only touch. A pad player has a real stick in their hands and a keyboard player is drawn their own keys,
## so neither is affected.
@export var touch_movement: TouchMovement = TouchMovement.JOYSTICK:
	set(value):
		touch_movement = value
		if not is_node_ready():
			return
		if Engine.is_editor_hint():
			preview_in_editor()
		else:
			update_input_ui()
## Draw only the buttons that mean something right now: a button whose label differs from the resting text the
## scene gave it (a prompt's "Pick Up" on Action beside a pickup, a state's "Climb" on Jump at a wall, "Aim" on
## the trigger while a gun is held), and nothing else, the way Breath of the Wild shows a hint as it becomes
## relevant. The sticks and the d-pad stay off unless a label of theirs changed too. Off, the whole set is drawn.
## A game that keeps the HUD off the desktop screen turns this on instead of hiding the node, so the hints still
## pop in; the visibility follows every label write ([method set_labels], [method reset_labels], a prompt's claim).
@export var contextual_only: bool = false:
	set(value):
		contextual_only = value
		if is_node_ready() and not Engine.is_editor_hint():
			_apply_contextual_visibility()

## Whether the share button saves a PNG of the screen when it is pressed. It is the one button here the HUD
## acts on itself, because capturing the screen is not something a game has to be asked about; turn it off in a
## project that captures the screen its own way, or blank [member action_button_15] to drop the button entirely.
@export var takes_screenshots: bool = true

## The inputs the game will actually answer to. Set it and every [code]action_*[/code] slot below
## becomes a picker of those names instead of free text, so a slot cannot name an action the game has
## never heard of. Leave it unset and the slots stay plain text, which is what a game that defines its
## own actions wants. A wrapper around an engine or an emulator usually ships one.
@export var input_catalog: ControlsInputCatalog:
	set(value):
		input_catalog = value
		notify_property_list_changed()

@export_group("Face Button Actions", "action_")
@export var action_button_0: StringName = &"ui_accept" ## Bottom face button. Microsoft: Ⓐ, Nintendo: Ⓑ, Sony: ✕
@export var action_button_1: StringName = &"ui_cancel" ## Right face button. Microsoft: Ⓑ, Nintendo: Ⓐ, Sony: ○
@export var action_button_2: StringName = &"" ## Left face button; no Godot built-in binds it. Microsoft: Ⓧ, Nintendo: Ⓨ, Sony: □
@export var action_button_3: StringName = &"ui_select" ## Top face button. Microsoft: Ⓨ, Nintendo: Ⓧ, Sony: △

@export_group("Shoulder and Trigger Actions", "action_")
@export var action_button_9: StringName = &"" ## Microsoft: 🄻B, Nintendo: L, Sony: L1
@export var action_button_10: StringName = &"" ## Microsoft: 🅁B, Nintendo: R, Sony: R1
@export var action_axis_4_plus: StringName = &"" ## Microsoft: 🄻T, Nintendo: Z🄻, Sony: 🄻2
@export var action_axis_5_plus: StringName = &"" ## Microsoft: 🅁T, Nintendo: Z🅁, Sony: 🅁2

@export_group("Stick Actions", "action_")
@export var action_button_7: StringName = &"" ## Left stick click. Sony: L3
@export var action_button_8: StringName = &"" ## Right stick click. Sony: R3
@export var action_move_up: StringName = &"ui_up" ## Left stick forward, and the [W] key
@export var action_move_down: StringName = &"ui_down" ## Left stick back, and the [S] key
@export var action_move_left: StringName = &"ui_left" ## Left stick left, and the [A] key
@export var action_move_right: StringName = &"ui_right" ## Left stick right, and the [D] key
@export var action_look_up: StringName = &"" ## Right stick up, and the [Up] key
@export var action_look_down: StringName = &"" ## Right stick down, and the [Down] key
@export var action_look_left: StringName = &"" ## Right stick left, and the [Left] key
@export var action_look_right: StringName = &"" ## Right stick right, and the [Right] key

@export_group("D-Pad Actions", "action_")
@export var action_button_11: StringName = &"ui_up" ## D-pad up, and the [I] key
@export var action_button_12: StringName = &"ui_down" ## D-pad down, and the [K] key
@export var action_button_13: StringName = &"ui_left" ## D-pad left, and the [J] key
@export var action_button_14: StringName = &"ui_right" ## D-pad right, and the [L] key

@export_group("System Button Actions", "action_")
@export var action_button_4: StringName = &"" ## Microsoft: ⧉, Nintendo: ⊝, Sony: ⦀
@export var action_button_6: StringName = &"" ## Microsoft: ☰, Nintendo: ⊕, Sony: ☰
## The share button. Unlike every other slot this one is filled in by default, because the HUD has something
## to put on it: [method take_screenshot]. Microsoft: ⧉, Nintendo: ⧇, Sony: Create
@export var action_button_15: StringName = &"take_screenshot"

@export_category("Keyboard and Mouse Textures")
@export var keyboard_mouse_button_0_normal: Texture2D ## Keyboard [E] key (Normal)
@export var keyboard_mouse_button_0_pressed: Texture2D ## Keyboard [E] key (Pressed)
@export var keyboard_mouse_button_1_normal: Texture2D ## Keyboard [Shift] key (Normal)
@export var keyboard_mouse_button_1_pressed: Texture2D ## Keyboard [Shift] key (Pressed)
@export var keyboard_mouse_button_2_normal: Texture2D ## Keyboard [Alt] key (Normal)
@export var keyboard_mouse_button_2_pressed: Texture2D ## Keyboard [Alt] key (Pressed)
@export var keyboard_mouse_button_3_normal: Texture2D ## Keyboard [Space] key (Normal)
@export var keyboard_mouse_button_3_pressed: Texture2D ## Keyboard [Space] key (Pressed)
@export var keyboard_mouse_button_4_normal: Texture2D ## Keyboard [F5] key (Normal)
@export var keyboard_mouse_button_4_pressed: Texture2D ## Keyboard [F5] key (Pressed)
@export var keyboard_mouse_button_15_normal: Texture2D ## Keyboard [Print] key (Normal)
@export var keyboard_mouse_button_15_pressed: Texture2D ## Keyboard [Print] key (Pressed)
@export var keyboard_mouse_button_6_normal: Texture2D ## Keyboard [Esc] key (Normal)
@export var keyboard_mouse_button_6_pressed: Texture2D ## Keyboard [Esc] key (Pressed)
@export var keyboard_mouse_button_7_normal: Texture2D ## Keyboard [Ctrl] key (Normal)
@export var keyboard_mouse_button_7_pressed: Texture2D ## Keyboard [Ctrl] key (Pressed)
@export var keyboard_mouse_button_8_normal: Texture2D ## Keyboard [Mouse-Scroll] key (Normal)
@export var keyboard_mouse_button_8_pressed: Texture2D ## Keyboard [Mouse-Scroll] key (Pressed)
@export var keyboard_mouse_button_9_normal: Texture2D ## Keyboard [Q] key (Normal)
@export var keyboard_mouse_button_9_pressed: Texture2D ## Keyboard [Q] key (Pressed)
@export var keyboard_mouse_button_10_normal: Texture2D ## Keyboard [T] key (Normal)
@export var keyboard_mouse_button_10_pressed: Texture2D ## Keyboard [T] key (Pressed)
@export var keyboard_mouse_axis_4_plus_normal: Texture2D ## Keyboard [Mouse-Left] key (Normal)
@export var keyboard_mouse_axis_4_plus_pressed: Texture2D ## Keyboard [Mouse-Left] key (Pressed)
@export var keyboard_mouse_axis_5_plus_normal: Texture2D ## Keyboard [Mouse-Right] key (Normal)
@export var keyboard_mouse_axis_5_plus_pressed: Texture2D ## Keyboard [Mouse-Right] key (Pressed)
## The stick and d-pad halves of the keyboard set. These are never swapped per device - they are only ever
## shown for keyboard and mouse - so unlike the face buttons they carry no vendor pairs, and anything left
## blank keeps the key face the scene already has.
@export var keyboard_mouse_move_up_normal: Texture2D ## Left stick forward, [W] by default (Normal)
@export var keyboard_mouse_move_up_pressed: Texture2D ## Left stick forward, [W] by default (Pressed)
@export var keyboard_mouse_move_down_normal: Texture2D ## Left stick back, [S] by default (Normal)
@export var keyboard_mouse_move_down_pressed: Texture2D ## Left stick back, [S] by default (Pressed)
@export var keyboard_mouse_move_left_normal: Texture2D ## Left stick left, [A] by default (Normal)
@export var keyboard_mouse_move_left_pressed: Texture2D ## Left stick left, [A] by default (Pressed)
@export var keyboard_mouse_move_right_normal: Texture2D ## Left stick right, [D] by default (Normal)
@export var keyboard_mouse_move_right_pressed: Texture2D ## Left stick right, [D] by default (Pressed)
@export var keyboard_mouse_button_11_normal: Texture2D ## D-pad up, [I] by default (Normal)
@export var keyboard_mouse_button_11_pressed: Texture2D ## D-pad up, [I] by default (Pressed)
@export var keyboard_mouse_button_12_normal: Texture2D ## D-pad down, [K] by default (Normal)
@export var keyboard_mouse_button_12_pressed: Texture2D ## D-pad down, [K] by default (Pressed)
@export var keyboard_mouse_button_13_normal: Texture2D ## D-pad left, [J] by default (Normal)
@export var keyboard_mouse_button_13_pressed: Texture2D ## D-pad left, [J] by default (Pressed)
@export var keyboard_mouse_button_14_normal: Texture2D ## D-pad right, [L] by default (Normal)
@export var keyboard_mouse_button_14_pressed: Texture2D ## D-pad right, [L] by default (Pressed)
@export var keyboard_mouse_look_up_normal: Texture2D ## Right stick up, [Up] by default (Normal)
@export var keyboard_mouse_look_up_pressed: Texture2D ## Right stick up, [Up] by default (Pressed)
@export var keyboard_mouse_look_down_normal: Texture2D ## Right stick down, [Down] by default (Normal)
@export var keyboard_mouse_look_down_pressed: Texture2D ## Right stick down, [Down] by default (Pressed)
@export var keyboard_mouse_look_left_normal: Texture2D ## Right stick left, [Left] by default (Normal)
@export var keyboard_mouse_look_left_pressed: Texture2D ## Right stick left, [Left] by default (Pressed)
@export var keyboard_mouse_look_right_normal: Texture2D ## Right stick right, [Right] by default (Normal)
@export var keyboard_mouse_look_right_pressed: Texture2D ## Right stick right, [Right] by default (Pressed)
@export_category("Microsoft Textures")
@export var microsoft_button_0_normal: Texture2D ## XBox A (Normal)
@export var microsoft_button_0_pressed: Texture2D ## XBox A (Pressed)
@export var microsoft_button_1_normal: Texture2D ## XBox B (Normal)
@export var microsoft_button_1_pressed: Texture2D ## XBox B (Pressed)
@export var microsoft_button_2_normal: Texture2D ## XBox X (Normal)
@export var microsoft_button_2_pressed: Texture2D ## XBox X (Pressed)
@export var microsoft_button_3_normal: Texture2D ## XBox Y (Normal)
@export var microsoft_button_3_pressed: Texture2D ## XBox Y (Pressed)
@export var microsoft_button_4_normal: Texture2D ## XBox Back(Normal)
@export var microsoft_button_4_pressed: Texture2D ## XBox Back (Pressed)
@export var microsoft_button_15_normal: Texture2D ## XBox Share (Normal)
@export var microsoft_button_15_pressed: Texture2D ## XBox Share (Pressed)
@export var microsoft_button_6_normal: Texture2D ## XBox Forward (Normal)
@export var microsoft_button_6_pressed: Texture2D ## XBox Forward (Pressed)
@export var microsoft_button_7_normal: Texture2D ## XBox LS (Normal)
@export var microsoft_button_7_pressed: Texture2D ## XBox LS (Pressed)
@export var microsoft_button_8_normal: Texture2D ## XBox RS (Normal)
@export var microsoft_button_8_pressed: Texture2D ## XBox RS (Pressed)
@export var microsoft_button_9_normal: Texture2D ## XBox LB (Normal)
@export var microsoft_button_9_pressed: Texture2D ## XBox LB (Pressed)
@export var microsoft_button_10_normal: Texture2D ## XBox RB (Normal)
@export var microsoft_button_10_pressed: Texture2D ## XBox RB (Pressed)
@export var microsoft_axis_4_plus_normal: Texture2D ## XBox LT (Normal)
@export var microsoft_axis_4_plus_pressed: Texture2D ## XBox LT (Pressed)
@export var microsoft_axis_5_plus_normal: Texture2D ## XBox RT (Normal)
@export var microsoft_axis_5_plus_pressed: Texture2D ## XBox RT (Pressed)
@export_category("Nintendo Textures")
@export var nintendo_button_0_normal: Texture2D ## Nintendo B (Normal)
@export var nintendo_button_0_pressed: Texture2D ## Nintendo B (Pressed)
@export var nintendo_button_1_normal: Texture2D ## Nintendo A (Normal)
@export var nintendo_button_1_pressed: Texture2D ## Nintendo A (Pressed)
@export var nintendo_button_2_normal: Texture2D ## Nintendo Y (Normal)
@export var nintendo_button_2_pressed: Texture2D ## Nintendo Y (Pressed)
@export var nintendo_button_3_normal: Texture2D ## Nintendo X (Normal)
@export var nintendo_button_3_pressed: Texture2D ## Nintendo X (Pressed)
@export var nintendo_button_4_normal: Texture2D ## Nintendo - (Normal)
@export var nintendo_button_4_pressed: Texture2D ## Nintendo - (Pressed)
@export var nintendo_button_15_normal: Texture2D ## Nintendo Share (Normal)
@export var nintendo_button_15_pressed: Texture2D ## Nintendo Share (Pressed)
@export var nintendo_button_6_normal: Texture2D ## Nintendo + (Normal)
@export var nintendo_button_6_pressed: Texture2D ## Nintendo + (Pressed)
@export var nintendo_button_7_normal: Texture2D ## Nintendo LS (Normal)
@export var nintendo_button_7_pressed: Texture2D ## Nintendo LS (Pressed)
@export var nintendo_button_8_normal: Texture2D ## Nintendo RS (Normal)
@export var nintendo_button_8_pressed: Texture2D ## Nintendo RS (Pressed)
@export var nintendo_button_9_normal: Texture2D ## Nintendo L (Normal)
@export var nintendo_button_9_pressed: Texture2D ## Nintendo L (Pressed)
@export var nintendo_button_10_normal: Texture2D ## Nintendo R (Normal)
@export var nintendo_button_10_pressed: Texture2D ## Nintendo R (Pressed)
@export var nintendo_axis_4_plus_normal: Texture2D ## Nintendo ZL (Normal)
@export var nintendo_axis_4_plus_pressed: Texture2D ## Nintendo ZL (Pressed)
@export var nintendo_axis_5_plus_normal: Texture2D ## Nintendo ZR (Normal)
@export var nintendo_axis_5_plus_pressed: Texture2D ## Nintendo ZR (Pressed)
@export_category("Sony Textures")
@export var sony_button_0_normal: Texture2D ## Sony Cross (Normal)
@export var sony_button_0_pressed: Texture2D ## Sony Cross (Pressed)
@export var sony_button_1_normal: Texture2D ## Sony Circle (Normal)
@export var sony_button_1_pressed: Texture2D ## Sony Circle (Pressed)
@export var sony_button_2_normal: Texture2D ## Sony Square (Normal)
@export var sony_button_2_pressed: Texture2D ## Sony Square (Pressed)
@export var sony_button_3_normal: Texture2D ## Sony Triangle (Normal)
@export var sony_button_3_pressed: Texture2D ## Sony Triangle (Pressed)
@export var sony_button_4_normal: Texture2D ## Sony Select (Normal)
@export var sony_button_4_pressed: Texture2D ## Sony Select (Pressed)
@export var sony_button_15_normal: Texture2D ## Sony Share (Normal)
@export var sony_button_15_pressed: Texture2D ## Sony Share (Pressed)
@export var sony_button_6_normal: Texture2D ## Sony Options (Normal)
@export var sony_button_6_pressed: Texture2D ## Sony Options (Pressed)
@export var sony_button_7_normal: Texture2D ## Sony L3 (Normal)
@export var sony_button_7_pressed: Texture2D ## Sony L3 (Pressed)
@export var sony_button_8_normal: Texture2D ## Sony R3 (Normal)
@export var sony_button_8_pressed: Texture2D ## Sony R3 (Pressed)
@export var sony_button_9_normal: Texture2D ## Sony L1 (Normal)
@export var sony_button_9_pressed: Texture2D ## Sony L1 (Pressed)
@export var sony_button_10_normal: Texture2D ## Sony R1 (Normal)
@export var sony_button_10_pressed: Texture2D ## Sony R1 (Pressed)
@export var sony_axis_4_plus_normal: Texture2D ## Sony L2 (Normal)
@export var sony_axis_4_plus_pressed: Texture2D ## Sony L2 (Pressed)
@export var sony_axis_5_plus_normal: Texture2D ## Sony R2 (Normal)
@export var sony_axis_5_plus_pressed: Texture2D ## Sony R2 (Pressed)

## Extra InputMap actions to register, for bindings a slot's own button cannot describe: the keyboard key
## behind a face button, a mouse button behind a trigger, or an action with no on-screen button at all.
## Same shape as [constant SLOT_EVENTS], plus [code]keycodes[/code] (logical keycodes),
## [code]mouse[/code] (mouse buttons) and [code]deadzone[/code]. Fill it before calling
## [code]super()[/code] in an overriding [method Node._ready].
var extra_actions: Dictionary = {}

## What the bottom-action button reads while a world prompt is in range ("Pick Up"), kept through every label
## refresh. [method ActionPrompt.show_for] claims it and [method ActionPrompt.hide_for] gives it back.
var prompt_action_label: String = ""
## The action a world prompt names: its label is the one [method claim_action_label] writes. Empty means the
## bottom face button, whatever it carries. A game that moves its interact action about the pad (a control
## scheme) names it here so "Pick Up" lands on the button that picks up.
@export var prompt_action: StringName = &""

## The five corners the buttons are grouped in. Each is anchored to its corner of the screen and pivots there,
## which is what lets [member hud_scale] grow it into the screen rather than off it.
@onready var _clusters: Array[Control] = [$BottomLeft, $BottomRight, $TopLeft, $TopCenter, $TopRight]
@onready var dpad_base: TextureRect = $BottomLeft/DPadBase ## The d-pad cross the joypad d-pad buttons sit on
@onready var joypad_button_0: TouchScreenButton = $BottomRight/JoypadButton0 ## Joypad Button 0 (Bottom Action, Sony Cross, XBox A, Nintendo B)
@onready var joypad_button_0_label: Label = $BottomRight/JoypadButton0/Label
@onready var joypad_button_1: TouchScreenButton = $BottomRight/JoypadButton1 ## Joypad Button 1 (Right Action, Sony Circle, XBox B, Nintendo A)
@onready var joypad_button_1_label: Label = $BottomRight/JoypadButton1/Label
@onready var joypad_button_2: TouchScreenButton = $BottomRight/JoypadButton2 ## Joypad Button 2 (Left Action, Sony Square, XBox X, Nintendo Y)
@onready var joypad_button_2_label: Label = $BottomRight/JoypadButton2/Label
@onready var joypad_button_3: TouchScreenButton = $BottomRight/JoypadButton3 ## Joypad Button 3 (Top Action, Sony Triangle, XBox Y, Nintendo X)
@onready var joypad_button_3_label: Label = $BottomRight/JoypadButton3/Label
@onready var joypad_button_4: TouchScreenButton = $TopCenter/JoypadButton4 ## Joypad Button 4 (Back, Sony Select, XBox Back, Nintendo -)
@onready var joypad_button_4_label: Label = $TopCenter/JoypadButton4/Label
@onready var joypad_button_15: TouchScreenButton = $TopCenter/JoypadButton15 ## Joypad Button 15 (Share Action, Sony Share, XBox Share, Nintendo Share)
@onready var joypad_button_15_label: Label = $TopCenter/JoypadButton15/Label
@onready var joypad_button_6: TouchScreenButton = $TopCenter/JoypadButton6 ## Joypad Button 6 (Start, Sony Options, XBox Menu, Nintendo Plus)
@onready var joypad_button_6_label: Label = $TopCenter/JoypadButton6/Label
@onready var joypad_button_7: TouchScreenButton = $BottomLeft/JoypadButton7 ## Joypad Button 7 (Left Stick, Sony L3, XBox Left Stick, Nintendo Left Stick)
@onready var joypad_button_7_label: Label = $BottomLeft/JoypadButton7/Label
@onready var joypad_button_8: TouchScreenButton = $BottomRight/JoypadButton8 ## Joypad Button 8 (Right Stick, Sony R3, XBox Right Stick, Nintendo Right Stick)
@onready var joypad_button_8_label: Label = $BottomRight/JoypadButton8/Label
@onready var joypad_button_9: TouchScreenButton = $TopLeft/JoypadButton9 ## Joypad Button 9 (Left Shoulder, Sony L1, XBox L, Nintendo L)
@onready var joypad_button_9_label: Label = $TopLeft/JoypadButton9/Label
@onready var joypad_button_10: TouchScreenButton = $TopRight/JoypadButton10 ## Joypad Button 10 (Right Shoulder, Sony R1, XBox RB, Nintendo R)
@onready var joypad_button_10_label: Label = $TopRight/JoypadButton10/Label
@onready var joypad_axis_4_plus: TouchScreenButton = $TopLeft/JoypadAxis4Plus ## Joypad Axis 4 + (Left Trigger, Sony L2, XBox LT, Nintendo ZL)
@onready var joypad_axis_4_plus_label: Label = $TopLeft/JoypadAxis4Plus/Label
@onready var joypad_axis_5_plus: TouchScreenButton = $TopRight/JoypadAxis5Plus ## Joypad Axis 5 + (Right Trigger, Sony R2, XBox RT, Nintendo ZR)
@onready var joypad_axis_5_plus_label: Label = $TopRight/JoypadAxis5Plus/Label
@onready var joypad_button_11: TouchScreenButton = $BottomLeft/JoypadButton11 ## Joypad Button 11 (DPad Up)
@onready var joypad_button_11_label: Label = $BottomLeft/JoypadButton11/Label
@onready var joypad_button_12: TouchScreenButton = $BottomLeft/JoypadButton12 ## Joypad Button 12 (DPad Down)
@onready var joypad_button_12_label: Label = $BottomLeft/JoypadButton12/Label
@onready var joypad_button_13: TouchScreenButton = $BottomLeft/JoypadButton13 ## Joypad Button 13 (DPad Left)
@onready var joypad_button_13_label: Label = $BottomLeft/JoypadButton13/Label
@onready var joypad_button_14: TouchScreenButton = $BottomLeft/JoypadButton14 ## Joypad Button 14 (DPad Right)
@onready var joypad_button_14_label: Label = $BottomLeft/JoypadButton14/Label
@onready var key_w: TouchScreenButton = $BottomLeft/KeyW ## Keyboard [W] key
@onready var key_w_label: Label = $BottomLeft/KeyW/Label
@onready var key_a: TouchScreenButton = $BottomLeft/KeyA ## Keyboard [A] key
@onready var key_a_label: Label = $BottomLeft/KeyA/Label
@onready var key_s: TouchScreenButton = $BottomLeft/KeyS ## Keyboard [S] key
@onready var key_s_label: Label = $BottomLeft/KeyS/Label
@onready var key_d: TouchScreenButton = $BottomLeft/KeyD ## Keyboard [D] key
@onready var key_d_label: Label = $BottomLeft/KeyD/Label
@onready var key_i: TouchScreenButton = $BottomLeft/KeyI ## Keyboard [I] key
@onready var key_i_label: Label = $BottomLeft/KeyI/Label
@onready var key_j: TouchScreenButton = $BottomLeft/KeyJ ## Keyboard [J] key
@onready var key_j_label: Label = $BottomLeft/KeyJ/Label
@onready var key_k: TouchScreenButton = $BottomLeft/KeyK ## Keyboard [K] key
@onready var key_k_label: Label = $BottomLeft/KeyK/Label
@onready var key_l: TouchScreenButton = $BottomLeft/KeyL ## Keyboard [L] key
@onready var key_l_label: Label = $BottomLeft/KeyL/Label
@onready var left_joystick: VirtualJoystick = $BottomLeft/LeftJoystick ## Virtual Joystick (introduced in Godot 4.7) for player movement
@onready var left_joystick_label: Label = $BottomLeft/LeftJoystick/Label
@onready var right_joystick: VirtualJoystick = $BottomRight/RightJoystick ## Virtual Joystick (introduced in Godot 4.7) for camera movement
@onready var right_joystick_label: Label = $BottomRight/RightJoystick/Label
@onready var key_up: TouchScreenButton = $BottomRight/KeyUp ## Keyboard [Up] key
@onready var key_up_label: Label = $BottomRight/KeyUp/Label
@onready var key_left: TouchScreenButton = $BottomRight/KeyLeft ## Keyboard [Left] key
@onready var key_left_label: Label = $BottomRight/KeyLeft/Label
@onready var key_down: TouchScreenButton = $BottomRight/KeyDown ## Keyboard [Down] key
@onready var key_down_label: Label = $BottomRight/KeyDown/Label
@onready var key_right: TouchScreenButton = $BottomRight/KeyRight ## Keyboard [Right] key
@onready var key_right_label: Label = $BottomRight/KeyRight/Label

@onready var all_buttons: Array[TouchScreenButton] = [
	joypad_button_0, joypad_button_1, joypad_button_2, joypad_button_3,
	joypad_button_4, joypad_button_15, joypad_button_6, joypad_button_7,
	joypad_button_8, joypad_button_9, joypad_button_10, joypad_axis_4_plus,
	joypad_axis_5_plus, joypad_button_11, joypad_button_12, joypad_button_13,
	joypad_button_14, key_w, key_a, key_s, key_d, key_i, key_j, key_k,
	key_l, key_up, key_left, key_down, key_right,
]
@onready var all_labels: Array[Label] = [
	joypad_button_0_label, joypad_button_1_label, joypad_button_2_label, joypad_button_3_label,
	joypad_button_4_label, joypad_button_15_label, joypad_button_6_label, joypad_button_7_label,
	joypad_button_8_label, joypad_button_9_label, joypad_button_10_label, joypad_axis_4_plus_label,
	joypad_axis_5_plus_label, joypad_button_11_label, joypad_button_12_label, joypad_button_13_label,
	joypad_button_14_label, key_w_label, key_a_label, key_s_label, key_d_label, key_i_label, key_j_label, key_k_label,
	key_l_label, key_up_label, key_left_label, key_down_label, key_right_label,
	left_joystick_label, right_joystick_label,
]
## The buttons of [constant SWAPPABLE_SLOTS], in that order, filled in [method _ready].
var _swappable_buttons: Array[TouchScreenButton] = []
## Normal/pressed texture pairs per input type, in [member _swappable_buttons] order, filled in [method _ready].
var _vendor_textures: Dictionary[InputType, Array] = {}
## Controls shown only for controller/touch input (the keyboard set is shown instead for keyboard/mouse).
@onready var _joypad_only: Array[CanvasItem] = [dpad_base, joypad_button_11, joypad_button_12, joypad_button_13, joypad_button_14, left_joystick, right_joystick]
@onready var _keyboard_only: Array[CanvasItem] = [key_w, key_a, key_s, key_d, key_i, key_j, key_k, key_l, key_up, key_left, key_down, key_right]

## The four buttons of the movement slots, which the keyboard set draws as its movement keys and which a
## touchscreen player gets instead of the stick when [member touch_movement] asks for them.
@onready var _movement_buttons: Array[CanvasItem] = [key_w, key_a, key_s, key_d]

## A joypad label and the key label that does the same job, so [method set_labels] can name either and the
## other follows. The d-pad and [I], [J], [K], [L] are the pairs; the sticks mirror one way only, since a key
## is one of four and the stick is all of them.
@onready var _mirrored_labels: Array[Array] = [
	[joypad_button_11_label, key_i_label], [joypad_button_12_label, key_k_label],
	[joypad_button_13_label, key_j_label], [joypad_button_14_label, key_l_label],
]


var current_input_type: InputType = InputType.TOUCH:
	set(value):
		if current_input_type != value:
			current_input_type = value
			update_input_ui()
			input_type_changed.emit(value)

var _normal_textures: Dictionary[TouchScreenButton, Texture2D] = {} ## Unpressed texture per button for the current input type.
var _label_texts: Dictionary[Label, String] = {} ## Default label text per label (from the scene).
var _unbound: Array[CanvasItem] = [] ## Buttons and sticks whose slot was left blank, so the game does not use them.
var _prompt_owner: Object = null ## The [ActionPrompt] that claimed [member prompt_action_label]; only it may give it back.
var _foreign_actions: Dictionary = {} ## Actions the project had declared before this node registered any, which are its own to bind.
var _pad_device: int = 0 ## The pad the player last pressed, so a rumble reaches the one in their hands rather than the first enumerated.


## Turns every slot into a picker of the catalog's actions when one is set. Godot asks about each
## exported property in turn, so this only touches the ones named for a slot.
func _validate_property(property: Dictionary) -> void:
	if input_catalog == null or not String(property.name).begins_with("action_"):
		return
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = input_catalog.hint_string()


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Registering InputMap actions and swapping textures is no business of an edited scene, so none of the
	# rest of this runs in the editor. What does is the visibility, because a scene that shows buttons the
	# game never mapped is a scene that does not show what ships - which is the whole point of looking at it.
	if Engine.is_editor_hint():
		preview_in_editor()
		apply_scale()
		set_process(true)
		return
	# A remote player's HUD has no one to show it to: left alone it would sit on top of the local one with its
	# touch buttons live and register actions for a player who is not here. Its _input goes too, because it
	# would otherwise redraw a HUD that was never set up.
	if not is_multiplayer_authority():
		hide()
		set_process_input(false)
		return
	set_process(false)

	# A project's own key faces go on before anything is cached, so everything downstream - the held-state
	# swap and update_input_ui - sees them as though the scene had always had them.
	_apply_keyboard_textures()

	# The swappable buttons and their vendor art are read off the slot names, so the order of both comes from
	# the one list and nothing has to be kept in step by hand.
	for slot: String in SWAPPABLE_SLOTS:
		_swappable_buttons.append(get("joypad_%s" % slot))
	for input_type: InputType in VENDOR_PREFIXES:
		var textures: Array = []
		for slot: String in SWAPPABLE_SLOTS:
			textures.append(get("%s_%s_normal" % [VENDOR_PREFIXES[input_type], slot]))
			textures.append(get("%s_%s_pressed" % [VENDOR_PREFIXES[input_type], slot]))
		_vendor_textures[input_type] = textures

	# Cache the initial normal textures and label texts
	for button: TouchScreenButton in all_buttons:
		_normal_textures[button] = button.texture_normal
	for label: Label in all_labels:
		_label_texts[label] = label.text

	# Note what the project bound for itself before adding anything, so the two are told apart afterwards.
	for action_name: StringName in InputMap.get_actions():
		if not String(action_name).begins_with("ui_"):
			_foreign_actions[String(action_name)] = true

	_apply_slot_actions()
	register_actions(extra_actions)
	_register_slot_actions()
	update_input_ui()
	# The fit is measured against the window, so a resize or a turned phone measures again.
	get_viewport().size_changed.connect(apply_scale)


## The key face for each button of the keyboard set that is not a face button, as the exports have it.
## Keyed by the button itself, because the d-pad slots stand for two buttons each and only the keyboard one
## is a key.
func _keyboard_key_textures() -> Dictionary:
	return {
		key_w: [keyboard_mouse_move_up_normal, keyboard_mouse_move_up_pressed],
		key_s: [keyboard_mouse_move_down_normal, keyboard_mouse_move_down_pressed],
		key_a: [keyboard_mouse_move_left_normal, keyboard_mouse_move_left_pressed],
		key_d: [keyboard_mouse_move_right_normal, keyboard_mouse_move_right_pressed],
		key_i: [keyboard_mouse_button_11_normal, keyboard_mouse_button_11_pressed],
		key_k: [keyboard_mouse_button_12_normal, keyboard_mouse_button_12_pressed],
		key_j: [keyboard_mouse_button_13_normal, keyboard_mouse_button_13_pressed],
		key_l: [keyboard_mouse_button_14_normal, keyboard_mouse_button_14_pressed],
		key_up: [keyboard_mouse_look_up_normal, keyboard_mouse_look_up_pressed],
		key_down: [keyboard_mouse_look_down_normal, keyboard_mouse_look_down_pressed],
		key_left: [keyboard_mouse_look_left_normal, keyboard_mouse_look_left_pressed],
		key_right: [keyboard_mouse_look_right_normal, keyboard_mouse_look_right_pressed],
	}


## Puts a project's own key faces on the stick and d-pad keys. A pair left blank keeps the scene's art, so a
## project that binds WASD and the arrows like everyone else sets none of them.
func _apply_keyboard_textures() -> void:
	for button: TouchScreenButton in _keyboard_key_textures():
		var pair: Array = _keyboard_key_textures()[button]
		if pair[0] != null:
			button.texture_normal = pair[0]
		if pair[1] != null:
			button.texture_pressed = pair[1]


## Every slot's action name, in [constant SLOT_EVENTS] order, as the exports currently have it.
func get_slot_actions() -> Dictionary:
	return {
		"button_0": action_button_0, "button_1": action_button_1, "button_2": action_button_2,
		"button_3": action_button_3, "button_4": action_button_4, "button_6": action_button_6,
		"button_7": action_button_7, "button_8": action_button_8, "button_9": action_button_9,
		"button_10": action_button_10, "button_11": action_button_11, "button_12": action_button_12,
		"button_13": action_button_13, "button_14": action_button_14, "button_15": action_button_15,
		"axis_4_plus": action_axis_4_plus, "axis_5_plus": action_axis_5_plus,
		"move_up": action_move_up, "move_down": action_move_down,
		"move_left": action_move_left, "move_right": action_move_right,
		"look_up": action_look_up, "look_down": action_look_down,
		"look_left": action_look_left, "look_right": action_look_right,
	}


## The on-screen buttons each slot drives; a slot with more than one drives the joypad button and the key
## that stand for the same thing (the d-pad and [I], [J], [K], [L]).
func _get_slot_buttons() -> Dictionary:
	return {
		"button_0": [joypad_button_0], "button_1": [joypad_button_1], "button_2": [joypad_button_2],
		"button_3": [joypad_button_3], "button_4": [joypad_button_4], "button_6": [joypad_button_6],
		"button_7": [joypad_button_7], "button_8": [joypad_button_8], "button_9": [joypad_button_9],
		"button_10": [joypad_button_10], "button_15": [joypad_button_15],
		"button_11": [joypad_button_11, key_i], "button_12": [joypad_button_12, key_k],
		"button_13": [joypad_button_13, key_j], "button_14": [joypad_button_14, key_l],
		"axis_4_plus": [joypad_axis_4_plus], "axis_5_plus": [joypad_axis_5_plus],
		"move_up": [key_w], "move_down": [key_s], "move_left": [key_a], "move_right": [key_d],
		"look_up": [key_up], "look_down": [key_down], "look_left": [key_left], "look_right": [key_right],
	}


## Writes the exported action names onto the buttons and the two sticks, and collects the slots the game left
## blank so [method update_input_ui] can keep them hidden.
func _apply_slot_actions() -> void:
	var slot_actions: Dictionary = get_slot_actions()
	var slot_buttons: Dictionary = _get_slot_buttons()
	_unbound.clear()
	for slot: String in slot_buttons:
		var action_name: StringName = slot_actions[slot]
		for button: TouchScreenButton in slot_buttons[slot]:
			button.action = action_name
			if action_name.is_empty():
				_unbound.append(button)

	left_joystick.action_up = action_move_up
	left_joystick.action_down = action_move_down
	left_joystick.action_left = action_move_left
	left_joystick.action_right = action_move_right
	right_joystick.action_up = action_look_up
	right_joystick.action_down = action_look_down
	right_joystick.action_left = action_look_left
	right_joystick.action_right = action_look_right
	if action_move_up.is_empty() and action_move_down.is_empty():
		_unbound.append(left_joystick)
	if action_look_up.is_empty() and action_look_down.is_empty():
		_unbound.append(right_joystick)
	if action_button_11.is_empty() and action_button_12.is_empty() and action_button_13.is_empty() and action_button_14.is_empty():
		_unbound.append(dpad_base)


## Gives every mapped slot an InputMap action bound to the button it stands for, so the addon is a drop-in.
## An action the project already defines is left alone, except the engine's built-in [code]ui_*[/code]
## actions, which are extended rather than replaced.
func _register_slot_actions() -> void:
	var slot_actions: Dictionary = get_slot_actions()
	var table: Dictionary = {}
	for slot: String in slot_actions:
		var action_name: StringName = slot_actions[slot]
		if action_name.is_empty():
			continue
		# Two slots may name the same action on purpose - a face button that jumps and a stick pushed
		# up, say - so the table gathers both slots' events rather than the later one replacing the
		# earlier, which would silently unbind the button the player is looking at.
		var key: String = String(action_name)
		table[key] = merge_bindings(table.get(key, {}), SLOT_EVENTS[slot])
	register_actions(table)


## Folds [param addition] into [param base] and returns the result, leaving both alone. Bindings are the
## shape [method register_actions] takes - [code]keys[/code], [code]keycodes[/code], [code]buttons[/code],
## [code]axes[/code], [code]mouse[/code], [code]deadzone[/code] - and the lists are joined without repeats,
## so an action named by two slots answers to everything both slots stand for. Use it anywhere bindings are
## collected by action name, because a plain assignment there throws one slot's events away.
static func merge_bindings(base: Dictionary, addition: Dictionary) -> Dictionary:
	var merged: Dictionary = base.duplicate(true)
	for key: String in addition:
		if key == "deadzone":
			merged[key] = addition[key]
			continue
		var values: Array = merged.get(key, []).duplicate()
		for value: Variant in addition[key]:
			if not values.has(value):
				values.append(value)
		merged[key] = values
	return merged


## Registers [param table] into the InputMap. A missing action is created and bound. An action the project
## declared for itself is left exactly as it is, because its bindings are the project's business; anything else
## - one this node created a moment ago, or one of the engine's own [code]ui_*[/code] actions - is extended
## with the events it lacks. Values take [code]keys[/code], [code]keycodes[/code], [code]buttons[/code],
## [code]axes[/code], [code]mouse[/code] and [code]deadzone[/code].
func register_actions(table: Dictionary) -> void:
	for action_name: String in table:
		var binding: Dictionary = table[action_name]
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name, binding.get("deadzone", 0.2))
		elif _foreign_actions.has(action_name):
			continue
		for event: InputEvent in _events_for(binding):
			if not InputMap.action_has_event(action_name, event):
				InputMap.action_add_event(action_name, event)


## Turns one [method register_actions] binding into the input events it describes.
func _events_for(binding: Dictionary) -> Array[InputEvent]:
	var events: Array[InputEvent] = []
	for key: Key in binding.get("keys", []):
		var key_event: InputEventKey = InputEventKey.new()
		key_event.physical_keycode = key
		events.append(key_event)
	for keycode: Key in binding.get("keycodes", []):
		var key_event: InputEventKey = InputEventKey.new()
		key_event.keycode = keycode
		events.append(key_event)
	for button: JoyButton in binding.get("buttons", []):
		var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
		button_event.button_index = button
		events.append(button_event)
	for axis: Array in binding.get("axes", []):
		var motion_event: InputEventJoypadMotion = InputEventJoypadMotion.new()
		motion_event.axis = axis[0]
		motion_event.axis_value = axis[1]
		events.append(motion_event)
	for mouse_button: MouseButton in binding.get("mouse", []):
		var mouse_event: InputEventMouseButton = InputEventMouseButton.new()
		mouse_event.button_index = mouse_button
		events.append(mouse_event)
	# A new event is for device 0, and the InputMap only matches an event from the device it was registered
	# for, so without this a second pad could press every button on the HUD and fire nothing. Minus one is
	# what the editor's "All Devices" writes; the engine's name for it is not exposed to scripts.
	for event: InputEvent in events:
		event.device = -1
	return events


## The device [param event] came from, as [member current_input_type] would be set by it, or -1 for an event
## that says nothing about the device. A click is always someone at a mouse, but motion only counts while the
## mouse is captured, so nudging the desk does not take a pad player's HUD away. A touchscreen sends mouse
## events too where the project emulates them, and those carry DEVICE_ID_EMULATION. A pad is told by its name:
## Nintendo [Switch] and Sony [PlayStation]; anything else is drawn as an Xbox pad, because a pad the name gives
## nothing away about is still a pad, and that is the layout most of them copy. Something that reads an event
## before this HUD has seen it (a node earlier in the input order) asks here, so it reads the event for the
## device it came from rather than the one that was in hand a moment ago.
func input_type_of(event: InputEvent) -> int:
	if event is InputEventKey:
		return InputType.KEYBOARD_MOUSE
	if event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			return InputType.KEYBOARD_MOUSE
		return -1
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > input_deadzone):
		var joystick_name: String = Input.get_joy_name(event.device).to_lower()
		if joystick_name.contains("nintendo"):
			return InputType.NINTENDO
		if joystick_name.contains("playstation") or joystick_name.contains("dualshock") or joystick_name.contains("dualsense") or joystick_name.contains("sony"):
			return InputType.SONY
		return InputType.MICROSOFT
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return InputType.TOUCH
	return -1


## Called when there is an input event.
func _input(event: InputEvent) -> void:
	# Detect the input device from the event
	var device: int = input_type_of(event)
	if device >= 0:
		if device != InputType.KEYBOARD_MOUSE and device != InputType.TOUCH:
			_pad_device = event.device
		current_input_type = device as InputType

	# A text field with focus owns the keys: what is typed into a chat box is not a press of anything on the
	# HUD, and it is certainly not a screenshot.
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return

	# Motion events are never button presses; only press/release events update the pressed visuals
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		return
	if takes_screenshots and not action_button_15.is_empty() and event.is_action_pressed(action_button_15):
		take_screenshot()
	for button: TouchScreenButton in all_buttons:
		if button.action.is_empty() or not event.is_action(button.action):
			continue
		if event.is_action_pressed(button.action) and button.texture_pressed:
			button.texture_normal = button.texture_pressed
		elif event.is_action_released(button.action):
			button.texture_normal = _normal_textures[button]


## Puts every label back to the text the scene gave it, then re-applies whatever is contextual.
func reset_labels() -> void:
	for label: Label in _label_texts:
		label.text = _label_texts[label]
	_apply_contextual_labels()
	_apply_prompt_label()
	_apply_contextual_visibility()


## Hook for a subclass that has labels of its own to re-apply after a reset (what the shoulder button casts,
## what the d-pad opens). Does nothing here.
func _apply_contextual_labels() -> void:
	pass


## Hook called once [method set_labels] has written a state's labels. Does nothing here.
func _labels_applied() -> void:
	pass


## Names the bottom-action button after a world prompt in range ("Pick Up"), until [param owner] gives it back.
func claim_action_label(text: String, owner: Object) -> void:
	prompt_action_label = text
	_prompt_owner = owner
	_apply_prompt_label()


## Gives the label back, but only to whoever claimed it, so leaving one prompt while inside another keeps the
## other's label. Whatever owns the contextual labels is asked to re-apply them.
func release_action_label(owner: Object) -> void:
	if _prompt_owner == owner:
		prompt_action_label = ""
		_prompt_owner = null
		# The scene's own word goes back on the button; whatever owns the contextual labels may write over it
		var label: Label = prompt_label()
		if label != null and _label_texts.has(label):
			label.text = _label_texts[label]
		if is_node_ready():
			_apply_contextual_visibility()
	contextual_labels_requested.emit()


## The label a world prompt writes: the button bound to [member prompt_action], else the bottom face button.
func prompt_label() -> Label:
	if not prompt_action.is_empty():
		var label: Label = action_label(prompt_action)
		if label != null:
			return label
	return joypad_button_0_label


## The joypad label of the slot bound to [param action] ("Jump" on Y in one scheme, on X in another), so a state
## can write its word on whichever button carries the action; [param fallback] when no slot carries it.
func action_label(action: StringName, fallback: Label = null) -> Label:
	if action.is_empty():
		return fallback
	for slot: String in get_slot_actions():
		if get_slot_actions()[slot] == action:
			var label: Label = get("joypad_%s_label" % slot) as Label
			if label != null:
				return label
	return fallback


## The on-screen button of the slot bound to [param action], or [param fallback] when no slot carries it.
func action_button(action: StringName, fallback: TouchScreenButton = null) -> TouchScreenButton:
	if action.is_empty():
		return fallback
	for slot: String in get_slot_actions():
		if get_slot_actions()[slot] == action:
			var button: TouchScreenButton = get("joypad_%s" % slot) as TouchScreenButton
			if button != null:
				return button
	return fallback


## The art [param button] shows at rest for the current input type (the pad's glyph, or the key's), so a world
## prompt can draw the same button the HUD does.
func button_art(button: TouchScreenButton) -> Texture2D:
	return _normal_textures.get(button, button.texture_normal if button else null)


## The art [param slot] shows for [param input_type], normal then pressed: the pair the exports hold, as
## [method set_slot_art] last left it.
func slot_art(input_type: InputType, slot: String) -> Array[Texture2D]:
	if not VENDOR_PREFIXES.has(input_type) or not SWAPPABLE_SLOTS.has(slot):
		return []
	var prefix: String = VENDOR_PREFIXES[input_type]
	return [get("%s_%s_normal" % [prefix, slot]), get("%s_%s_pressed" % [prefix, slot])]


## Puts new art on one swappable [param slot] for one [param input_type], live: [param normal] and
## [param pressed] replace that device's export pair for the slot, and a HUD showing that device redraws the
## button at once. This is for a game whose keys move about at run time: a layout that swaps which action a
## face button carries also swaps which key stands behind it on the keyboard set, and the button should be
## drawn as the key that actually presses it. Touch borrows the Xbox art, so Xbox art set while on touch
## shows too.
func set_slot_art(input_type: InputType, slot: String, normal: Texture2D, pressed: Texture2D) -> void:
	var index: int = SWAPPABLE_SLOTS.find(slot)
	if index < 0 or not VENDOR_PREFIXES.has(input_type):
		push_warning("No swappable slot %s for input type %s" % [slot, input_type])
		return
	var prefix: String = VENDOR_PREFIXES[input_type]
	set("%s_%s_normal" % [prefix, slot], normal)
	set("%s_%s_pressed" % [prefix, slot], pressed)
	if not _vendor_textures.has(input_type):
		return # not ready yet: _ready reads the exports
	_vendor_textures[input_type][index * 2] = normal
	_vendor_textures[input_type][index * 2 + 1] = pressed
	var shown: InputType = InputType.MICROSOFT if current_input_type == InputType.TOUCH else current_input_type
	if shown != input_type or index >= _swappable_buttons.size():
		return
	var button: TouchScreenButton = _swappable_buttons[index]
	button.texture_pressed = pressed
	_normal_textures[button] = normal
	var is_held: bool = not button.action.is_empty() and InputMap.has_action(button.action) and Input.is_action_pressed(button.action)
	button.texture_normal = pressed if is_held and pressed else normal


## A world prompt in range keeps the bottom-action button reading what it does ("Pick Up", "Get In") through
## every label refresh, until the prompt gives the label back ([method ActionPrompt.hide_for]).
func _apply_prompt_label() -> void:
	var label: Label = prompt_label()
	if prompt_action_label != "" and label != null:
		label.text = prompt_action_label
	if is_node_ready():
		_apply_contextual_visibility()


## Writes one state's labels: [param label_texts] maps a label node to its text, and every other label is
## cleared. A joypad label with no keyboard counterpart given is mirrored onto the key that does the same job.
func set_labels(label_texts: Dictionary) -> void:
	var final_texts: Dictionary = label_texts.duplicate()
	if left_joystick_label in final_texts and not key_s_label in final_texts:
		final_texts[key_s_label] = final_texts[left_joystick_label]
	if right_joystick_label in final_texts and not key_down_label in final_texts:
		final_texts[key_down_label] = final_texts[right_joystick_label]
	for pair: Array in _mirrored_labels:
		if pair[0] in final_texts and not pair[1] in final_texts:
			final_texts[pair[1]] = final_texts[pair[0]]
		elif pair[1] in final_texts and not pair[0] in final_texts:
			final_texts[pair[0]] = final_texts[pair[1]]

	for label: Label in _label_texts:
		if label in final_texts:
			label.text = final_texts[label]
		# Don't clear joystick labels if they are not explicitly specified
		elif label != left_joystick_label and label != right_joystick_label:
			label.text = ""
	_apply_prompt_label()
	_labels_applied()


## Editor only, so a slot mapped or blanked in the inspector shows or hides as it is typed. The exported
## action names have no setters to hang this off - there are two dozen of them - so it is checked each frame.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		preview_in_editor()


## Whether [param item] belongs on screen for the device being played on. The keyboard set and the joypad
## set are shown one or the other, except for the movement buttons and the stick, which swap places on a
## touchscreen when the game has asked for buttons rather than a stick.
func _belongs_on_screen(item: CanvasItem) -> bool:
	var is_keyboard: bool = current_input_type == InputType.KEYBOARD_MOUSE
	var buttons_for_touch: bool = touch_movement == TouchMovement.BUTTONS and current_input_type == InputType.TOUCH
	if item == left_joystick:
		return not is_keyboard and not buttons_for_touch
	if _movement_buttons.has(item):
		return is_keyboard or buttons_for_touch
	if _joypad_only.has(item):
		return not is_keyboard
	if _keyboard_only.has(item):
		return is_keyboard
	return true


## Shows the editor what will actually be on screen: a slot the game has not mapped is hidden, and the
## keyboard or the joypad set is shown for [member current_input_type], exactly as [method update_input_ui]
## decides it at runtime. Nothing is registered, no texture is swapped and no action is written to a button,
## and a visibility that already matches is left alone, so an untouched scene is not marked modified.
func preview_in_editor() -> void:
	var unmapped: Array[CanvasItem] = unmapped_items()
	for item: CanvasItem in _previewable_items():
		var wanted: bool = not unmapped.has(item) and _belongs_on_screen(item)
		if item.visible != wanted:
			item.visible = wanted


## The buttons and sticks the game has left blank, worked out without writing an action to any of them, so
## the editor can hide them without touching the scene. [method _apply_slot_actions] does the same at runtime
## as a side effect of assigning the actions.
func unmapped_items() -> Array[CanvasItem]:
	var slot_actions: Dictionary = get_slot_actions()
	var slot_buttons: Dictionary = _get_slot_buttons()
	var unmapped: Array[CanvasItem] = []
	for slot: String in slot_buttons:
		if not String(slot_actions[slot]).is_empty():
			continue
		for button: TouchScreenButton in slot_buttons[slot]:
			unmapped.append(button)
	if action_move_up.is_empty() and action_move_down.is_empty():
		unmapped.append(left_joystick)
	if action_look_up.is_empty() and action_look_down.is_empty():
		unmapped.append(right_joystick)
	if action_button_11.is_empty() and action_button_12.is_empty() and action_button_13.is_empty() and action_button_14.is_empty():
		unmapped.append(dpad_base)
	return unmapped


## Everything [method preview_in_editor] is allowed to show or hide: every button, both sticks, and the
## d-pad cross behind the d-pad buttons.
func _previewable_items() -> Array[CanvasItem]:
	var items: Array[CanvasItem] = []
	for button: TouchScreenButton in all_buttons:
		items.append(button)
	items.append(left_joystick)
	items.append(right_joystick)
	items.append(dpad_base)
	return items


## Applies the current input type: device textures on the swappable buttons, keyboard vs joypad visibility,
## default labels, and held-button visuals. Slots the game left blank stay hidden throughout.
func update_input_ui() -> void:
	reset_labels()

	var textures: Array = _vendor_textures[InputType.MICROSOFT if current_input_type == InputType.TOUCH else current_input_type]
	for i: int in _swappable_buttons.size():
		_swappable_buttons[i].texture_pressed = textures[i * 2 + 1]
		_normal_textures[_swappable_buttons[i]] = textures[i * 2]

	for item: CanvasItem in _joypad_only:
		item.visible = _belongs_on_screen(item)
	for item: CanvasItem in _keyboard_only:
		item.visible = _belongs_on_screen(item)

	# Show each button pressed or normal to match the actions currently held
	for button: TouchScreenButton in all_buttons:
		var is_held: bool = not button.action.is_empty() and InputMap.has_action(button.action) and Input.is_action_pressed(button.action)
		button.texture_normal = button.texture_pressed if is_held and button.texture_pressed else _normal_textures[button]

	for item: CanvasItem in _unbound:
		item.hide()
	_apply_contextual_visibility()
	apply_scale()


## Whether [param label] reads something other than the text the scene gave it: a state's or a prompt's word.
func is_label_contextual(label: Label) -> bool:
	return label != null and label.text != "" and label.text != _label_texts.get(label, label.text)


## With [member contextual_only] on, shows only the buttons whose label is contextual and hides the rest; off,
## it does nothing, since [method update_input_ui] has already drawn the whole set for the device in hand.
func _apply_contextual_visibility() -> void:
	if not contextual_only:
		for i: int in all_buttons.size():
			var button: TouchScreenButton = all_buttons[i]
			var device_set: bool = _joypad_only.has(button) or _keyboard_only.has(button)
			button.visible = (_belongs_on_screen(button) if device_set else true) and not _unbound.has(button)
		left_joystick.visible = _belongs_on_screen(left_joystick) and not _unbound.has(left_joystick)
		right_joystick.visible = _belongs_on_screen(right_joystick) and not _unbound.has(right_joystick)
		dpad_base.visible = _belongs_on_screen(dpad_base) and not _unbound.has(dpad_base)
		return
	var dpad_shown: bool = false
	for i: int in all_buttons.size():
		var button: TouchScreenButton = all_buttons[i]
		var shown: bool = _belongs_on_screen(button) and not _unbound.has(button) and is_label_contextual(all_labels[i])
		button.visible = shown
		if shown and (button == joypad_button_11 or button == joypad_button_12 or button == joypad_button_13 or button == joypad_button_14):
			dpad_shown = true
	left_joystick.visible = _belongs_on_screen(left_joystick) and not _unbound.has(left_joystick) and is_label_contextual(left_joystick_label)
	right_joystick.visible = _belongs_on_screen(right_joystick) and not _unbound.has(right_joystick) and is_label_contextual(right_joystick_label)
	dpad_base.visible = dpad_shown and _belongs_on_screen(dpad_base)


## What the corners are drawn at right now: the fit to the window, times [member hud_scale].
func get_effective_scale() -> float:
	return hud_scale * window_fit()


## The scale that makes a face button [member button_fraction] of the window's shorter side. It measures the
## window in real pixels through whatever stretch the project applies, so the answer is the same fraction of
## the glass whether the game stretches its canvas or draws pixel for pixel, and it goes down as well as up.
## One with the fit turned off, and in the editor, where there is no player's window to measure.
func window_fit() -> float:
	if Engine.is_editor_hint() or button_fraction <= 0.0:
		return 1.0
	var window_size: Vector2 = Vector2(get_window().size)
	var canvas_to_window: float = get_viewport().get_final_transform().get_scale().x
	var drawn: float = BUTTON_SIZE * canvas_to_window
	if drawn <= 0.0:
		return 1.0
	return button_fraction * minf(window_size.x, window_size.y) / drawn


## Scales every corner's cluster about its own anchored corner - the pivot each has in the scene - so the
## buttons grow into the screen and the corners stay put. A scale that already matches is left alone, so an
## untouched scene is not marked modified in the editor.
func apply_scale() -> void:
	var value: Vector2 = Vector2.ONE * get_effective_scale()
	for cluster: Control in _clusters:
		if cluster.scale != value:
			cluster.scale = value


## Saves a PNG of what is on screen and returns where it went, with the HUD itself left out of the picture:
## a player sharing a screenshot wants the game in it, not the buttons they pressed to get there.
##
## Off the web the file lands in [constant SCREENSHOT_DIR]. On the web it cannot: [code]user://[/code] there is
## a browser storage sandbox with no folder behind it and nothing the player can open, so the bytes are handed
## to the page as a download instead, which is the one way a browser lets a file reach the machine.
func take_screenshot() -> String:
	var hud_was_visible: bool = visible
	visible = false
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	visible = hud_was_visible
	# Colons are legal in a path on none of the three desktops, and the browser strips them from a download.
	var file_name: String = "screenshot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(image.save_png_to_buffer(), file_name, "image/png")
		screenshot_taken.emit(file_name)
		return file_name
	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
	var path: String = SCREENSHOT_DIR.path_join(file_name)
	image.save_png(path)
	screenshot_taken.emit(path)
	return path


## Rumbles the pad for [param seconds] unless the player is on keyboard/mouse or touch; returns whether it did.
func rumble(weak: float, strong: float, seconds: float) -> bool:
	if current_input_type in [InputType.KEYBOARD_MOUSE, InputType.TOUCH]:
		return false
	Input.start_joy_vibration(_pad_device, weak, strong, seconds)
	return true
