class_name AmmoReadout
extends HudReadout

## The equipped firearm's magazine and reserve, under the crosshair.
##
## [Firearm] drives it, so the readout ships with the guns rather than with the button HUD: a project that takes
## this addon for its firearms gets the count with them. See [HudReadout] for why it is its own scene.

const NO_RESERVE: int = -1 ## Passed as the reserve by a firearm that does not carry one, which then shows alone.

@onready var label: Label = %Label


## Shows [param rounds] in the magazine against [param reserve] in reserve. The layer itself is what shows: the
## Player's HUD hides this instance until a firearm is in hand.
func set_ammo(rounds: int, reserve: int) -> void:
	label.text = "%d" % rounds if reserve == NO_RESERVE else "%d / %d" % [rounds, reserve]
	show()


## Nothing is in hand to count.
func hide_ammo() -> void:
	hide()
