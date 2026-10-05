class_name PlayerView
extends SubViewportContainer
## One local player's view in a [SplitScreen]: a container whose SubViewport holds that Player, forwarding only
## the events of the Player's own pad ([member Player.input_device]). The keyboard and the mouse reach nobody,
## because two people cannot share one keyboard; a synthetic [InputEventAction] (a test, a script) reaches every view.

var player: Player


## Godot asks before handing an event to the SubViewport; false keeps it out.
func _propagate_input_event(event: InputEvent) -> bool:
	if player == null:
		return true
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device == player.input_device
	if event is InputEventAction:
		return true # synthetic (a test, a script, simulate_input): it names no pad, so every view answers
	return false
