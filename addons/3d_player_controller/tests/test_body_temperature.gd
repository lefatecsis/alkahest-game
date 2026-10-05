extends GutTest

## Purpose: with enable_temperature, cold and heat cost health on Breath of the Wild's bands, a HeatSource (a campfire)
## warms the body out of the cold, and nothing happens with the feature off.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var player: Player


## A campfire as far as the body can tell: in the HeatSource group, [param degrees] warmer within [param radius].
class Fire:
	extends Node3D
	var degrees: float = 30.0
	var radius: float = 3.0
	func _ready() -> void:
		add_to_group(&"HeatSource")
	func warmth_at(position: Vector3) -> float:
		return degrees if position.distance_to(global_position) <= radius else 0.0


func before_each() -> void:
	player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.body_temperature.tick = 0.1
	await wait_physics_frames(2)


func test_the_bands_follow_breath_of_the_wild() -> void:
	var body: BodyTemperature = player.body_temperature
	assert_eq(body.damage_for(20.0), 0.0, "Mild air costs nothing")
	assert_eq(body.damage_for(-5.0), body.damage, "below freezing it costs slowly")
	assert_eq(body.damage_for(-15.0), body.severe_damage, "below -10, fast")
	assert_eq(body.damage_for(45.0), body.damage, "above 40, slowly")
	assert_eq(body.damage_for(55.0), body.severe_damage, "above 50, fast")
	body.cold_resistance = 10.0
	assert_eq(body.damage_for(-5.0), 0.0, "Warm clothes move the limit")


func test_the_cold_hurts_with_the_feature_on_and_not_off() -> void:
	player.body_temperature.default_temperature = -20.0
	var full: float = player.health.health
	await wait_seconds(0.5)
	assert_eq(player.health.health, full, "Off, the cold does nothing")
	player.enable_temperature = true
	await wait_seconds(0.5)
	assert_lt(player.health.health, full, "On, it costs health")


func test_a_fire_warms_the_body_out_of_the_cold() -> void:
	player.enable_temperature = true
	player.body_temperature.default_temperature = -5.0
	var fire := Fire.new()
	add_child_autofree(fire)
	fire.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
	await wait_physics_frames(2)
	assert_almost_eq(player.body_temperature.feel(), 25.0, 0.01, "By the fire it is warm")
	var full: float = player.health.health
	await wait_seconds(0.5)
	assert_eq(player.health.health, full, "and the cold costs nothing")
