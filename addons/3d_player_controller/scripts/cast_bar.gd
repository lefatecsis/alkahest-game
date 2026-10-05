class_name CastBar
extends HudReadout

## The ability being cast and how far through it is, under the crosshair.
##
## [Abilities] drives it while a spell with a cast time is going off. See [HudReadout] for why it is its own
## scene rather than a node on the button HUD.

@onready var bar: ProgressBar = %Bar ## Shown only while something is being cast.
@onready var label: Label = %Label


## Starts the bar empty under [param display_name].
func show_cast(display_name: String) -> void:
	label.text = display_name
	bar.value = 0.0
	bar.visible = true


## How far through the cast is, 0 to 1. Scaled onto the bar's own range, which is the ProgressBar default of
## 0 to 100 rather than 0 to 1, so a caller passing a ratio gets the fill it asked for.
func set_progress(ratio: float) -> void:
	bar.value = clampf(ratio, 0.0, 1.0) * bar.max_value


## The cast finished or was interrupted.
func hide_cast() -> void:
	bar.visible = false
