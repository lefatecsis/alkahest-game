class_name BossBar
extends HudReadout

## The boss's name and health across the top of the screen, while the peer that owns this Player is fighting one.
##
## [Boss] drives it: the node sits on the NPC and finds this readout on the local Player, so what is shown is a
## readout of an enemy rather than anything to do with the pad. See [HudReadout] for why it is its own scene.

@onready var name_label: Label = %BossName
@onready var health_bar: ProgressBar = %BossHealth


## Puts [param boss_name] on screen with its health at [param ratio], 0 to 1. The layer itself is what shows: the
## Player's HUD hides this instance until a boss is engaged.
func show_boss(boss_name: String, ratio: float) -> void:
	name_label.text = boss_name
	health_bar.value = ratio
	show()


## Moves the health to [param ratio], 0 to 1.
func update_boss(ratio: float) -> void:
	health_bar.value = ratio


## The fight is over, or this peer is no longer the one having it.
func hide_boss() -> void:
	hide()
