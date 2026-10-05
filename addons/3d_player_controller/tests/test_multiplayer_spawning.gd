extends GutTest

## Purpose: PlayerSpawner and ProjectileSpawner replicate across a real host/client session.
## Two scene branches each get their own MultiplayerAPI and talk over ENet on localhost, the same
## high-level API a SteamMultiplayerPeer session uses in the world.

const PORT: int = 47391
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const BULLET_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/bullet.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")
const PROJECTILE_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/projectile_spawner.gd")

var server_root: Node3D
var client_root: Node3D
var server_api: SceneMultiplayer
var client_api: SceneMultiplayer


## Builds one branch: Players + PlayerSpawner, Projectiles + ProjectileSpawner (same layout on both sides).
func _build_branch(root: Node3D) -> void:
	var players := Node3D.new()
	players.name = "Players"
	root.add_child(players)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	root.add_child(projectiles)
	var player_spawner: PlayerSpawner = PLAYER_SPAWNER.new()
	player_spawner.name = "PlayerSpawner"
	player_spawner.spawn_path = NodePath("../Players")
	player_spawner.add_child(PLAYER_SCENE.instantiate()) # the template every peer's player is a copy of
	root.add_child(player_spawner)
	var projectile_spawner: ProjectileSpawner = PROJECTILE_SPAWNER.new()
	projectile_spawner.name = "ProjectileSpawner"
	projectile_spawner.spawn_path = NodePath("../Projectiles")
	projectile_spawner.add_spawnable_scene(BULLET_SCENE.resource_path) # a client's request is only for a listed scene
	root.add_child(projectile_spawner)


func before_each() -> void:
	server_root = Node3D.new()
	server_root.name = "ServerBranch"
	client_root = Node3D.new()
	client_root.name = "ClientBranch"
	add_child(server_root)
	add_child(client_root)
	server_api = SceneMultiplayer.new()
	client_api = SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	get_tree().set_multiplayer(client_api, client_root.get_path())
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PORT), OK, "ENet server should open on localhost")
	server_api.multiplayer_peer = server_peer
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PORT), OK)
	client_api.multiplayer_peer = client_peer
	_build_branch(server_root)
	_build_branch(client_root)
	for i in 120:
		await wait_process_frames(1)
		if client_api.get_peers().size() > 0 and server_api.get_peers().size() > 0:
			break
	assert_gt(client_api.get_peers().size(), 0, "Client should connect to the loopback server")


func after_each() -> void:
	# Free the branches while their APIs still exist so synchronizers and spawners unregister cleanly
	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	server_api.multiplayer_peer.close()
	client_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)


func test_players_spawn_on_both_peers_with_the_right_authority() -> void:
	await wait_process_frames(30)
	var server_players: Node = server_root.get_node("Players")
	var client_players: Node = client_root.get_node("Players")
	var client_id: String = str(client_api.get_unique_id())
	assert_true(server_players.has_node("1"), "Host spawns its own player")
	assert_true(server_players.has_node(client_id), "Host spawns a player for the joined peer")
	assert_true(client_players.has_node("1"), "Client receives the host's player")
	assert_true(client_players.has_node(client_id), "Client receives its own player")
	assert_eq(client_players.get_node(client_id).get_multiplayer_authority(), client_api.get_unique_id(), "The client owns its player")
	assert_eq(client_players.get_node("1").get_multiplayer_authority(), 1, "The host's player stays host-owned on the client")
	assert_true((client_players.get_node(client_id) as Player).is_multiplayer_authority(), "Only the owner runs input on its copy")
	assert_false((client_players.get_node("1") as Player).is_multiplayer_authority())


func test_projectile_fired_on_the_host_appears_and_flies_on_the_client() -> void:
	await wait_process_frames(30)
	var host_spawner: ProjectileSpawner = server_root.get_node("ProjectileSpawner")
	var shooter: Node3D = server_root.get_node("Players/1")
	var bullet: Projectile = host_spawner.fire(BULLET_SCENE, Transform3D(Basis.IDENTITY, Vector3(200, 50, 0)), Vector3.FORWARD, 30.0, shooter)
	assert_not_null(bullet, "The host gets its projectile back immediately")
	await wait_process_frames(10)
	var client_projectiles: Node = client_root.get_node("Projectiles")
	assert_eq(client_projectiles.get_child_count(), 1, "The client spawns the same round")
	var remote: Projectile = client_projectiles.get_child(0)
	assert_lt(remote.linear_velocity.z, -20.0, "The client's copy launches itself from the spawn data")
	assert_true(String(remote.shooter.get_path()).ends_with("Players/1"), "Shooter resolves by path on the client")


func test_client_fire_request_is_spawned_by_the_host() -> void:
	await wait_process_frames(30)
	var client_spawner: ProjectileSpawner = client_root.get_node("ProjectileSpawner")
	var result: Projectile = client_spawner.fire(BULLET_SCENE, Transform3D(Basis.IDENTITY, Vector3(200, 50, 0)), Vector3.FORWARD, 30.0, client_root.get_node("Players/" + str(client_api.get_unique_id())))
	assert_null(result, "Clients do not spawn locally; they ask the host")
	await wait_process_frames(15)
	assert_eq(server_root.get_node("Projectiles").get_child_count(), 1, "The host spawns the requested round")
	assert_eq(client_root.get_node("Projectiles").get_child_count(), 1, "…and it replicates back to the client")


func test_a_shot_sound_sent_with_the_round_plays_at_the_muzzle_on_the_client() -> void:
	await wait_process_frames(30)
	var shot: AudioStreamRandomizer = AudioStreamRandomizer.new()
	shot.add_stream(0, AudioStreamGenerator.new())
	var path: String = "user://test_shot_sound.tres"
	assert_eq(ResourceSaver.save(shot, path), OK)
	var host_spawner: ProjectileSpawner = server_root.get_node("ProjectileSpawner")
	var shooter: Node3D = server_root.get_node("Players/1")
	var origin: Vector3 = Vector3(200, 50, 0)
	var bullet: Projectile = host_spawner.fire(BULLET_SCENE, Transform3D(Basis.IDENTITY, origin), Vector3.FORWARD, 30.0, shooter, null, {"fire_sfx": path})
	assert_not_null(bullet)
	var host_speaker: AudioStreamPlayer3D = server_root.get_node_or_null("Projectiles/LaunchSfx") as AudioStreamPlayer3D
	assert_not_null(host_speaker, "The host's copy plays the shot beside the round")
	assert_eq(host_speaker.stream.resource_path, path)
	assert_true(host_speaker.playing)
	assert_almost_eq(host_speaker.global_position, origin, Vector3.ONE * 0.01, "at the muzzle, not riding the round")
	await wait_process_frames(10)
	var remote_speaker: AudioStreamPlayer3D = client_root.get_node_or_null("Projectiles/LaunchSfx") as AudioStreamPlayer3D
	assert_not_null(remote_speaker, "The client's copy plays it too, from the same launch data")
	assert_eq(remote_speaker.stream.resource_path, path)
	assert_almost_eq(remote_speaker.global_position, origin, Vector3.ONE * 0.01)
	DirAccess.remove_absolute(path)
