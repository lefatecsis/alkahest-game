extends GutTest

## Purpose: Health clamps its pools, reports every change, dies once, refuses wasted heals and empty
## energy spends, regenerates energy on its timer, and the world-space bars only show while it matters.

const HEALTH_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/health.tscn")
const BARS_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/status_bars_3d.tscn")


func test_damage_heal_and_death() -> void:
	var health: Health = HEALTH_SCENE.instantiate()
	health.max_health = 50.0
	add_child_autofree(health)
	watch_signals(health)
	assert_eq(health.health, 50.0, "Starts full")
	assert_false(health.heal(10.0), "A full pool refuses a heal")
	health.damage(20.0, Vector3.ONE)
	assert_eq(health.health, 30.0)
	assert_signal_emitted_with_parameters(health, "damaged", [20.0, Vector3.ONE])
	assert_signal_emitted_with_parameters(health, "health_changed", [30.0, 50.0])
	assert_true(health.heal(10.0))
	assert_eq(health.health, 40.0)
	health.damage(100.0)
	assert_eq(health.health, 0.0, "Health never goes negative")
	assert_signal_emit_count(health, "died", 1)
	health.damage(5.0)
	assert_signal_emit_count(health, "died", 1, "The dead do not die twice")
	assert_false(health.heal(10.0), "The dead are not healed")


func test_energy_spends_and_regenerates() -> void:
	var health: Health = HEALTH_SCENE.instantiate()
	health.max_energy = 40.0
	health.energy_regen = 20.0
	add_child_autofree(health)
	assert_eq(health.energy, 40.0)
	assert_true(health.spend_energy(30.0))
	assert_false(health.spend_energy(30.0), "Not enough energy spends nothing")
	assert_eq(health.energy, 10.0)
	await wait_seconds(1.2)
	assert_gt(health.energy, 25.0, "The RegenTimer refills energy at energy_regen per second")
	assert_lte(health.energy, 40.0)


func test_status_bars_show_only_while_it_matters() -> void:
	var bars: StatusBars3D = BARS_SCENE.instantiate()
	add_child_autofree(bars)
	await wait_physics_frames(1)
	bars.set_health(100.0, 100.0)
	assert_false(bars.health_bar.visible, "Full health shows no bar")
	bars.set_health(60.0, 100.0)
	assert_true(bars.health_bar.visible, "Missing health shows the bar")
	bars.set_energy(0.0, 0.0)
	assert_false(bars.energy_bar.visible, "No energy pool, no bar")
	bars.set_energy(20.0, 50.0)
	assert_true(bars.energy_bar.visible)
