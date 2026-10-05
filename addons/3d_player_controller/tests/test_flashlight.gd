extends GutTest

## Purpose: the Flashlight holds a Stalker still while its beam is on it, without undoing a slow the enemy is under;
## only the Player's authority switches it; it runs its physics only while on; the battery runs it dark; and over ENet
## its on state reaches every peer, a player joining after it went on included.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/enemy_npc.tscn")
const FLASHLIGHT_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/equipment/flashlight.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")
const PORT: int = 47441

var player: Player
var enemy: EnemyNpc
var torch: Flashlight


func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(40.0, 1.0, 40.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	enemy = ENEMY_SCENE.instantiate()
	enemy.position = Vector3(0.0, 0.0, -8.0)
	enemy.add_to_group(&"Stalkers")
	root.add_child(enemy)
	torch = FLASHLIGHT_SCENE.instantiate()
	torch.player = player
	torch.spot_angle = 30.0
	torch.position = Vector3(0.0, 1.5, 0.0)
	player.add_child(torch)
	await wait_physics_frames(3)
	torch.look_at(Focus.get_focus_target_position(enemy))


func _press() -> void:
	var press := InputEventAction.new()
	press.action = torch.action
	press.pressed = true
	torch._input(press)


func test_the_beam_holds_a_stalker_still_and_a_slow_under_it_outlasts_the_beam() -> void:
	assert_false(torch.is_physics_processing(), "Off, the torch runs no physics")
	assert_false(torch.visible)
	torch.is_on = true
	assert_true(torch.is_on)
	assert_true(torch.visible)
	assert_true(torch.is_physics_processing(), "On, it drains and looks for what it lights")
	await wait_physics_frames(2)
	assert_true(torch.lights(enemy), "The enemy stands in the beam")
	assert_true(enemy.frozen, "so it is held still")
	assert_eq(enemy.movement_scale, 0.0)
	enemy.slow(0.5, 5.0) # a frostbolt lands meanwhile
	assert_eq(enemy.movement_scale, 0.0, "Still held while lit")
	torch.is_on = false
	assert_false(enemy.frozen, "Off, the beam lets go")
	assert_almost_eq(enemy.movement_scale, 0.5, 0.001, "and the frostbolt's slow is still there, not reset to full speed")
	assert_false(torch.is_physics_processing())


func test_only_the_owner_switches_it_and_the_battery_runs_it_dark() -> void:
	_press()
	assert_true(torch.is_on, "The owner's key turns it on")
	_press()
	assert_false(torch.is_on, "and off")
	torch.set_multiplayer_authority(7) # somebody else's torch, as a puppet's is
	_press()
	assert_false(torch.is_on, "A copy that is not the Player's authority ignores the key")
	torch.set_multiplayer_authority(1)
	watch_signals(torch)
	torch.battery = 0.05
	torch.is_on = true
	await wait_seconds(0.2)
	assert_false(torch.is_on, "An empty battery puts it out")
	assert_signal_emitted(torch, "went_dark")
	assert_false(enemy.frozen, "and lets go of what it held")


## Puts a PlayerSpawner in [param root] whose template Player carries a torch (a direct child of the template, which
## every copy takes with it), so each peer's Player has one.
func _add_players(root: Node3D) -> void:
	var players := Node3D.new()
	players.name = "Players"
	root.add_child(players)
	var spawner: PlayerSpawner = PLAYER_SPAWNER.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	var template: Player = PLAYER_SCENE.instantiate()
	template.add_child(FLASHLIGHT_SCENE.instantiate())
	spawner.add_child(template)
	root.add_child(spawner)


## The host switches its torch on before anybody else is there; a client joining afterwards sees it on, then sees it
## go off, and the client's own torch reaches the host the same way.
func test_a_player_joining_later_sees_a_torch_that_was_already_on() -> void:
	var server_root := Node3D.new()
	server_root.name = "ServerBranch"
	add_child(server_root)
	var server_api := SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PORT), OK)
	server_api.multiplayer_peer = server_peer
	_add_players(server_root)
	await wait_process_frames(5)
	var hosts_torch: Flashlight = server_root.get_node("Players/1/Flashlight")
	assert_true(hosts_torch.is_multiplayer_authority(), "The host's torch is the host's")
	hosts_torch.is_on = true
	await wait_process_frames(10)

	var client_root := Node3D.new()
	client_root.name = "ClientBranch"
	client_root.position = Vector3(0.0, 0.0, 300.0)
	add_child(client_root)
	var client_api := SceneMultiplayer.new()
	get_tree().set_multiplayer(client_api, client_root.get_path())
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PORT), OK)
	client_api.multiplayer_peer = client_peer
	_add_players(client_root)
	var on_client: Flashlight = null
	for i in 180:
		await wait_process_frames(1)
		on_client = client_root.get_node_or_null("Players/1/Flashlight") as Flashlight
		if on_client and on_client.is_on:
			break
	assert_not_null(on_client, "The host's Player reached the client with its torch")
	if on_client:
		assert_false(on_client.is_multiplayer_authority())
		assert_true(on_client.is_on, "A player joining after the torch went on sees it on")
		assert_true(on_client.visible)
		assert_false(on_client.is_physics_processing(), "and its copy drains no battery")
		hosts_torch.is_on = false
		for i in 60:
			await wait_process_frames(1)
			if not on_client.is_on:
				break
		assert_false(on_client.is_on, "Switched off, it goes off on the client too")
		var client_id: String = str(client_api.get_unique_id())
		var mine: Flashlight = client_root.get_node("Players/" + client_id + "/Flashlight")
		mine.is_on = true
		var mine_on_host: Flashlight = server_root.get_node("Players/" + client_id + "/Flashlight")
		for i in 60:
			await wait_process_frames(1)
			if mine_on_host.is_on:
				break
		assert_true(mine_on_host.is_on, "The client's own torch reaches the host")

	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	server_api.multiplayer_peer.close()
	client_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)
