class_name BodyTemperature
extends Node
## Breath of the Wild's temperature: the air the Player stands in hurts once it is cold or hot enough. Below
## [member cold_threshold] it costs [member cold_damage] a second and below [member severe_cold_threshold] the
## severe rate; above [member heat_threshold] and [member severe_heat_threshold] the same for heat. Clothing and food
## would shift where the body feels those limits ([member cold_resistance], [member heat_resistance]); the Mixamo
## body wears nothing, so both start at 0.
##
## The air is the WeatherFX's [code]current_temperature[/code] when the addon is in the game (found through its
## "WeatherFX" group, so the player controller needs nothing from it), else [member default_temperature]. Anything in
## the "HeatSource" group with a [code]warmth_at(position)[/code] method adds its warmth, a campfire the way Link warms
## himself at one. Off unless [member Player.enable_temperature]; it runs on the Player's own peer, where the health it
## costs is kept.

signal felt_temperature_changed(celsius: float) ## The temperature the body feels, whenever it changes by a tenth of a degree.

@export var player: Player
@export var cold_threshold: float = 0.0 ## °C below which the cold hurts, slowly.
@export var severe_cold_threshold: float = -10.0 ## °C below which it hurts fast.
@export var heat_threshold: float = 40.0 ## °C above which the heat hurts, slowly.
@export var severe_heat_threshold: float = 50.0 ## °C above which it hurts fast.
@export var damage: float = 1.5 ## Health a second, slowly.
@export var severe_damage: float = 5.0 ## Health a second, fast.
@export var cold_resistance: float = 0.0 ## °C the body shrugs off in the cold (warm clothes, spicy food); lowers the cold limits.
@export var heat_resistance: float = 0.0 ## °C the body shrugs off in the heat (light clothes, chilly food); raises the heat limits.
@export var default_temperature: float = 20.0 ## The air without a WeatherFX in the game.
@export var tick: float = 1.0 ## Seconds between the costs.

var felt_temperature: float = 20.0 ## What the body feels now: the air plus any fire near it.
var _clock: float = 0.0
var _weather_fx: Node = null


func _physics_process(delta: float) -> void:
	if player == null or not player.is_multiplayer_authority() or not player.enable_temperature:
		return
	var felt: float = feel()
	if absf(felt - felt_temperature) >= 0.1:
		felt_temperature = felt
		felt_temperature_changed.emit(felt)
	_clock += delta
	if _clock < tick:
		return
	_clock = 0.0
	var cost: float = damage_for(felt) * tick
	if cost > 0.0 and player.health.is_alive() and not player.is_ragdolling:
		player.health.damage(cost, player.global_position)


## The temperature the body feels where it stands: the air, and the warmth of any fire in reach.
func feel() -> float:
	var celsius: float = air_temperature()
	for source: Node in player.get_tree().get_nodes_in_group(&"HeatSource"):
		if source.has_method("warmth_at"):
			celsius += float(source.call("warmth_at", player.global_position))
	return celsius


## The air's temperature: the WeatherFX's, or [member default_temperature] without one.
func air_temperature() -> float:
	if not is_instance_valid(_weather_fx):
		_weather_fx = player.get_tree().get_first_node_in_group(&"WeatherFX")
	if is_instance_valid(_weather_fx) and "current_temperature" in _weather_fx:
		return float(_weather_fx.get("current_temperature"))
	return default_temperature


## Health a second a body feeling [param celsius] loses: none between the limits, [member damage] past them,
## [member severe_damage] past the severe ones.
func damage_for(celsius: float) -> float:
	if celsius < severe_cold_threshold - cold_resistance or celsius > severe_heat_threshold + heat_resistance:
		return severe_damage
	if celsius < cold_threshold - cold_resistance or celsius > heat_threshold + heat_resistance:
		return damage
	return 0.0
