extends GutTest

## Purpose: The Player has hit points separate from stamina: hits cost health and show on the head bar,
## zero health ragdolls the Player and the RespawnTimer brings them back full at the spawn point, and the
## HUD boss bar shows what a Boss node tells it.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var player: Player


func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(20.0, 1.0, 20.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	player.position = Vector3(1.0, 0.0, 2.0)
	root.add_child(player)
	await wait_physics_frames(3)


func test_a_hit_costs_health_not_stamina() -> void:
	var stamina: float = player.stamina.stamina
	player.take_hit(30.0, player.global_position + Vector3.FORWARD)
	assert_eq(player.health.health, 70.0)
	assert_eq(player.stamina.stamina, stamina, "Stamina is energy, not hit points")
	assert_true(player.get_node("StatusBars3D/HealthBar").visible, "Missing health shows over the head")
	assert_gt(player.get_node("StatusBars3D/HealthBar").fill_color.g, 0.7, "The Player's health bar is green")
	assert_true(player.heal(10.0))
	assert_eq(player.health.health, 80.0)


## Amounts are clamped at zero: a negative hit heals nobody, a negative heal hurts nobody, and a negative slow
## lasts no time at all.
func test_negative_hits_heals_and_slows_do_nothing() -> void:
	player.health.health = 50.0
	player.take_hit(-40.0, player.global_position + Vector3.FORWARD)
	assert_eq(player.health.health, 50.0, "A negative hit heals nobody")
	player.heal(-40.0)
	assert_eq(player.health.health, 50.0, "and a negative heal hurts nobody")
	player.slow(0.5, -5.0)
	await wait_physics_frames(3)
	assert_eq(player.movement_scale, 1.0, "A slow for negative seconds is over at once")


func test_death_ragdolls_and_respawns_full_at_the_spawn_point() -> void:
	player.respawn_timer.wait_time = 0.3
	player.take_hit(500.0, player.global_position + Vector3.FORWARD)
	assert_eq(player.health.health, 0.0)
	await wait_physics_frames(2)
	assert_eq(player.current_state, NodeStateMachine.States.RAGDOLLING, "Zero health drops the Player")
	player.global_position += Vector3(3.0, 0.0, 0.0)
	await wait_seconds(0.6)
	assert_eq(player.health.health, player.health.max_health, "Respawned with full health")
	assert_eq(player.current_state, NodeStateMachine.States.STANDING)
	assert_almost_eq(player.global_position, Vector3(1.0, 0.0, 2.0), Vector3.ONE * 0.2, "Back at the spawn point")


func test_boss_bar_shows_name_and_health() -> void:
	var controls: Node = player.controls
	assert_false(player.boss_bar.visible)
	player.boss_bar.show_boss("Giant Duck", 0.75)
	assert_true(player.boss_bar.visible)
	assert_eq(player.boss_bar.name_label.text, "Giant Duck")
	assert_almost_eq(player.boss_bar.health_bar.value, 0.75, 0.001)
	player.boss_bar.update_boss(0.25)
	assert_almost_eq(player.boss_bar.health_bar.value, 0.25, 0.001)
	player.boss_bar.hide_boss()
	assert_false(player.boss_bar.visible)


func test_mana_only_regenerates_out_of_combat() -> void:
	player.health.energy = 50.0
	var hunter := Node.new()
	add_child_autofree(hunter)
	player.hunted_by(hunter.get_path(), true)
	assert_true(player.health.regen_paused)
	await wait_seconds(0.6)
	assert_eq(player.health.energy, 50.0, "Hunted: mana holds")
	player.hunted_by(hunter.get_path(), false)
	assert_false(player.health.regen_paused)
	await wait_seconds(0.6)
	assert_gt(player.health.energy, 50.0, "Alone again: mana trickles back")


func test_a_round_on_the_head_kills_the_player_outright() -> void:
	var bullet: Projectile = preload("res://addons/3d_player_controller/scenes/projectile/bullet.tscn").instantiate()
	add_child_autofree(bullet)
	bullet.shooter = null
	player.register_projectile_hit(bullet, player.global_position + Vector3(0.0, 1.0, 0.3), Vector3.FORWARD)
	assert_eq(player.health.health, 100.0 - bullet.damage, "A body hit costs the round's damage")
	bullet.hit_part = player.get_node("PlayerModel/Armature/GeneralSkeleton/HeadAttachment/Head")
	player.register_projectile_hit(bullet, bullet.hit_part.global_position, Vector3.FORWARD)
	assert_eq(player.health.health, 0.0, "A head hit is lethal")
