class_name StatusBars3D
extends Node3D
## Health and energy bars floating over a character's head. Wire a [Health] node's `health_changed` and
## `energy_changed` (or the Player's `Stamina.stamina_changed`) to [method set_health] and [method set_energy].

@onready var health_bar: ProgressBar3D = $HealthBar
@onready var energy_bar: ProgressBar3D = $EnergyBar


func set_health(value: float, max_value: float) -> void:
	# A sibling Health readies (and emits) before these bars exist; full health shows nothing anyway
	if is_node_ready():
		health_bar.set_progress(value, max_value)


func set_energy(value: float, max_value: float) -> void:
	if is_node_ready():
		energy_bar.set_progress(value, max_value)
