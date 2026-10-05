@tool
class_name ControlScheme
extends Resource

## One pad layout: which action each of the four face buttons carries, and what Focus does.
##
## The keyboard keys behind the buttons ([constant PlayerControls.PLAYER_ACTIONS]), the shoulders, the
## triggers, the sticks and the d-pad are the same in every scheme, so a scheme is only the four faces plus
## [member locks_on]. The ones that ship are in [code]resources/control_schemes/[/code]; a game that wants its
## own writes another [code].tres[/code] beside them and assigns it to [member Player.control_scheme], with
## nothing in this addon to edit.

@export var scheme_name: String = "" ## What the settings menu calls this layout.

@export_group("Face buttons")
## The action the bottom face button carries: A on an Xbox pad, Cross on a PlayStation one.
@export var action_button_0: StringName = &""
## The action the right face button carries: B on an Xbox pad, Circle on a PlayStation one.
@export var action_button_1: StringName = &""
## The action the left face button carries: X on an Xbox pad, Square on a PlayStation one.
@export var action_button_2: StringName = &""
## The action the top face button carries: Y on an Xbox pad, Triangle on a PlayStation one.
@export var action_button_3: StringName = &""

@export_group("Beyond the face buttons")
## Every pad slot beyond the four faces that the game this layout is named after actually had, by the slot's
## name on the HUD ("button_9" is the left shoulder, "button_10" the right, "axis_4_plus" the left trigger,
## "axis_5_plus" the right, "button_7" and "button_8" the stick clicks, "button_11" to "button_14" the d-pad).
## Most games put verbs out here that this addon keeps on the faces: Dark Souls attacks on the right trigger,
## Half-Life 2 sprints on the left shoulder.
##
## This is the whole of that game's pad, not a patch on top of the scene's, so [b]a slot left out is cleared[/b]:
## the button comes off screen and its label empties. Metal Gear had nothing on the stick clicks and Resident
## Evil nothing to throw, and neither should be left showing Tears of the Kingdom's binding because no layout
## said otherwise. [constant PlayerControls.SYSTEM_SLOTS] is what no layout reaches - the sticks, Start,
## Screenshot and Perspective are this addon's, not the game's.
@export var extra_slots: Dictionary[String, StringName] = {}

## What each slot reads on the HUD, by the slot's name, in the words the game itself uses: Metal Gear's left
## shoulder says Change Item rather than Last Weapon, Dark Souls' says Guard rather than Scope, and a
## skateboarding game's right trigger says Revert rather than Shoot. The four faces are named here too
## ("button_0" to "button_3").
##
## The action underneath keeps whatever this addon calls it, because that is what the scripts read; only the
## word on the button changes. A slot left out falls back to [constant PlayerControls.ACTION_LABELS] and then
## to the action's own name, which is how every layout used to read before it was given its own words.
@export var slot_labels: Dictionary[String, String] = {}

@export_group("Movement")
## A tap of Sprint rolls, Souls style: a dive roll along the direction moved, a backstep when still, and in the air a
## forward dive; a hold sprints. [member Player.enable_dodge] turns the same on under any scheme.
@export var rolls: bool = false

@export_group("Focus")
## Focus locks on to a target, Breath of the Wild style. Off, Focus is a free over-the-shoulder aim, Grand
## Theft Auto style. [method Player.lock_on_enabled] is this flag, and [Camera] and [Focus] follow it.
@export var locks_on: bool = true
## The cursor stays visible, World of Warcraft style: a click on a body makes it the Target, a Focus tap selects the
## nearest and then cycles, the cancel action or a click on nothing clears it, and right-drag turns the camera. Off,
## the cursor is captured and Focus is held ([Focus]). [method Player.cursor_mode] is this flag.
@export var frees_cursor: bool = false


## The slot-to-action mapping [method PlayerControls.apply_control_scheme] applies, keyed by the slot's export
## name on the HUD.
func slots() -> Dictionary[String, StringName]:
	return {
		"action_button_0": action_button_0,
		"action_button_1": action_button_1,
		"action_button_2": action_button_2,
		"action_button_3": action_button_3,
	}
