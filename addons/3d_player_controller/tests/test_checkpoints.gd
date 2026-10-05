extends GutTest

## Purpose: A Checkpoint walked through becomes where the Player respawns and heals them; dying shows the
## death screen with the respawn countdown and brings the Player back at that checkpoint, not the spawn point;
## a lethal KillZone kills through the same flow and a harmless one only puts the Player back.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CHECKPOINT_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/prop/checkpoint.tscn")
const KILL_ZONE_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/prop/kill_zone.tscn")

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(60.0, 1.0, 60.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	player.position = Vector3(0.0, 0.0, 0.0)
	root.add_child(player)
	player.respawn_timer.wait_time = 0.3
	await wait_physics_frames(3)


func _add_checkpoint(at: Vector3) -> Checkpoint:
	var checkpoint: Checkpoint = CHECKPOINT_SCENE.instantiate()
	root.add_child(checkpoint)
	checkpoint.global_position = at
	return checkpoint


func test_the_spawn_point_is_the_first_respawn_point() -> void:
	assert_almost_eq(player.respawn_transform.origin, Vector3.ZERO, Vector3.ONE * 0.01)
	assert_true(player.get_node("Hud/DeathScreen") is DeathScreen, "The Player carries its death screen")
	assert_false(player.get_node("Hud/DeathScreen").visible)


func test_walking_through_a_checkpoint_takes_it_and_heals() -> void:
	var checkpoint: Checkpoint = _add_checkpoint(Vector3(10.0, 0.0, 0.0))
	watch_signals(checkpoint)
	watch_signals(player)
	player.health.health = 40.0
	player.warp_to(Transform3D(Basis(), Vector3(10.0, 0.0, 0.0)))
	await wait_physics_frames(3)
	assert_signal_emitted(checkpoint, "activated")
	assert_signal_emitted(player, "checkpoint_changed")
	assert_almost_eq(player.respawn_transform.origin, Vector3(10.0, 0.0, 0.0), Vector3.ONE * 0.01, "The checkpoint is the respawn point")
	assert_eq(player.health.health, player.health.max_health, "Taking a checkpoint heals")


func test_a_one_shot_checkpoint_fires_once_per_player() -> void:
	var checkpoint: Checkpoint = _add_checkpoint(Vector3(10.0, 0.0, 0.0))
	checkpoint.one_shot = true
	watch_signals(checkpoint)
	player.warp_to(Transform3D(Basis(), Vector3(10.0, 0.0, 0.0)))
	await wait_physics_frames(3)
	player.warp_to(Transform3D(Basis(), Vector3(20.0, 0.0, 0.0)))
	await wait_physics_frames(3)
	player.warp_to(Transform3D(Basis(), Vector3(10.0, 0.0, 0.0)))
	await wait_physics_frames(3)
	assert_signal_emit_count(checkpoint, "activated", 1)


func test_dying_shows_the_screen_and_respawns_at_the_checkpoint() -> void:
	_add_checkpoint(Vector3(10.0, 0.0, 0.0))
	player.warp_to(Transform3D(Basis(), Vector3(10.0, 0.0, 0.0)))
	await wait_physics_frames(3)
	player.warp_to(Transform3D(Basis(), Vector3(20.0, 0.0, 5.0)))
	await wait_physics_frames(2)
	watch_signals(player)
	var screen: DeathScreen = player.get_node("Hud/DeathScreen")
	player.take_hit(500.0, player.global_position + Vector3.FORWARD)
	await wait_physics_frames(2)
	assert_true(screen.visible, "The death screen shows on death")
	assert_true(screen.subtitle_label.text.begins_with("Respawning in"), screen.subtitle_label.text)
	await wait_seconds(0.6)
	assert_signal_emitted(player, "respawned")
	assert_false(screen.visible, "The death screen hides on respawn")
	assert_almost_eq(player.global_position, Vector3(10.0, 0.0, 0.0), Vector3.ONE * 0.3, "Back at the checkpoint, not the spawn point")
	assert_eq(player.health.health, player.health.max_health)


func test_a_lethal_kill_zone_kills_and_a_harmless_one_teleports() -> void:
	_add_checkpoint(Vector3(10.0, 0.0, 0.0))
	player.warp_to(Transform3D(Basis(), Vector3(10.0, 0.0, 0.0)))
	await wait_physics_frames(3)
	var zone: KillZone = KILL_ZONE_SCENE.instantiate()
	root.add_child(zone)
	zone.global_position = Vector3(0.0, -30.0, 0.0)
	watch_signals(zone)
	player.warp_to(Transform3D(Basis(), Vector3(0.0, -30.0, 0.0)))
	await wait_physics_frames(3)
	assert_signal_emitted(zone, "killed")
	assert_eq(player.health.health, 0.0, "A lethal zone kills")
	await wait_seconds(0.6)
	assert_almost_eq(player.global_position, Vector3(10.0, 0.0, 0.0), Vector3.ONE * 0.3, "And the respawn lands on the checkpoint")
	zone.lethal = false
	player.warp_to(Transform3D(Basis(), Vector3(0.0, -30.0, 0.0)))
	await wait_physics_frames(3)
	assert_eq(player.health.health, player.health.max_health, "A harmless zone costs nothing")
	assert_almost_eq(player.global_position, Vector3(10.0, 0.0, 0.0), Vector3.ONE * 0.3, "It only puts the Player back")


func test_a_kill_zone_kills_anything_with_health() -> void:
	var zone: KillZone = KILL_ZONE_SCENE.instantiate()
	root.add_child(zone)
	zone.global_position = Vector3(0.0, -30.0, 0.0)
	var body: CharacterBody3D = CharacterBody3D.new()
	body.set_script(preload("res://addons/3d_player_controller/tests/test_checkpoints.gd").HealthyBody)
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	body.add_child(shape)
	var health: Health = preload("res://addons/3d_player_controller/scenes/ui/health.tscn").instantiate()
	body.add_child(health)
	body.health = health
	root.add_child(body)
	body.global_position = Vector3(0.0, -30.0, 0.0)
	await wait_physics_frames(3)
	assert_false(health.is_alive(), "An enemy that falls in dies")


## A roll's invulnerability frames dodge a sword, not lava: a lethal zone kills straight through them.
func test_a_kill_zone_kills_through_dodge_invulnerability() -> void:
	var zone: KillZone = KILL_ZONE_SCENE.instantiate()
	root.add_child(zone)
	zone.global_position = Vector3(0.0, -30.0, 0.0)
	player.dodge_invulnerable = true
	player.warp_to(Transform3D(Basis(), Vector3(0.0, -30.0, 0.0)))
	await wait_physics_frames(3)
	assert_eq(player.health.health, 0.0, "Rolling into lava still kills")
	player.dodge_invulnerable = false


func test_unstuck_goes_to_the_checkpoint() -> void:
	_add_checkpoint(Vector3(10.0, 0.0, 0.0))
	player.warp_to(Transform3D(Basis(), Vector3(10.0, 0.0, 0.0)))
	await wait_physics_frames(3)
	player.warp_to(Transform3D(Basis(), Vector3(20.0, 0.0, 5.0)))
	await wait_physics_frames(1)
	player.pause._on_unstuck_pressed()
	assert_almost_eq(player.global_position, Vector3(10.0, 0.0, 0.0), Vector3.ONE * 0.01)


class HealthyBody extends CharacterBody3D:
	var health: Health
