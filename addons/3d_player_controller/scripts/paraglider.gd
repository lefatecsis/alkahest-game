extends Node3D
## Paraglider visuals and audio, shown while the Player is in the PARAGLIDING state. It is a node of
## [code]player.tscn[/code], saved hidden on the Player's right hand, and the Player's state_changed is wired to it
## there. The state replicates, so every peer opens the glider on every Player's copy.

@onready var opening: AudioStreamPlayer3D = $Opening
@onready var cloth_ruffling: AudioStreamPlayer3D = $ClothRuffling
@onready var left_wing: Contrail3D = $LeftWing
@onready var right_wing: Contrail3D = $RightWing
@onready var airflow_streaks: GPUParticles3D = $AirflowStreaks
@onready var opening_wind_burst: GPUParticles3D = $OpeningWindBurst


## Wired to Player.state_changed: opens the paraglider when paragliding starts and packs it away when it ends.
func _on_player_state_changed(from_state: int, to_state: int) -> void:
	if to_state == NodeStateMachine.States.PARAGLIDING:
		show()
		left_wing.emitting = true
		right_wing.emitting = true
		airflow_streaks.emitting = true
		opening_wind_burst.restart()
		opening_wind_burst.emitting = true
		opening.play()
		cloth_ruffling.play()
	elif from_state == NodeStateMachine.States.PARAGLIDING:
		hide()
		opening.stop()
		cloth_ruffling.stop()
		left_wing.emitting = false
		right_wing.emitting = false
		airflow_streaks.emitting = false
		opening_wind_burst.emitting = false
		left_wing.clear()
		right_wing.clear()
