extends GutTest

## Purpose: what one peer does to or with a Player reaches the others the way it should, over a real host/client
## session: two scene branches with their own MultiplayerAPI talking ENet on localhost, as in
## test_multiplayer_spawning.gd. Effect RPCs (take_hit, heal, slow, hunted_by) land only from the server or from the
## peer that owns the named attacker or caster; the paraglider opens on every peer's copy; water is the owner's to
## enter, and the entry splash still shows on the other peer. An effect the server applies while it is handling a
## client's RPC (that client's hit on an enemy, its noise) is the server's own, and reaches its target.

const PORT: int = 47393
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")
const GLIDER_PATH: String = "PlayerModel/Armature/GeneralSkeleton/ParagliderBoneAttachment/Paraglider"

var server_root: Node3D
var client_root: Node3D
var server_api: SceneMultiplayer
var client_api: SceneMultiplayer


## Stands in for anything of the server's that a client's RPC sets off, like an enemy's _request_hit: the handler
## runs on the server, inside the client's call, and hits or hunts a Player from there.
class Relay:
	extends Node

	@rpc("any_peer", "reliable")
	func poke(target_path: NodePath, damage: float) -> void:
		var target: Player = get_node(target_path) as Player
		target.take_hit(damage, Vector3.ZERO)
		target.hunted_by(target.get_path_to(self), true)


func _build_branch(root: Node3D) -> void:
	var relay: Relay = Relay.new()
	relay.name = "Relay"
	root.add_child(relay)
	var players := Node3D.new()
	players.name = "Players"
	root.add_child(players)
	var spawner: PlayerSpawner = PLAYER_SPAWNER.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.add_child(PLAYER_SCENE.instantiate())
	root.add_child(spawner)


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
	await wait_process_frames(30)


func after_each() -> void:
	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	server_api.multiplayer_peer.close()
	client_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)


func _client_id() -> String:
	return str(client_api.get_unique_id())


## Waits up to [param frames] process frames for [param condition].
func _until(condition: Callable, frames: int = 60) -> void:
	for i in frames:
		if condition.call():
			return
		await wait_process_frames(1)


## A hit forwarded by the server lands; one a client sends straight to somebody else's Player does not, and nor
## does one it tries to route through the server's copy.
func test_a_hit_lands_from_the_server_but_not_from_another_client() -> void:
	var host_on_server: Player = server_root.get_node("Players/1")
	var client_on_client: Player = client_root.get_node("Players/" + _client_id())
	var client_on_server: Player = server_root.get_node("Players/" + _client_id())

	# The server's enemy hits the client's Player: the server's copy relays it to the owner
	client_on_server.take_hit(30.0, Vector3.ZERO)
	await _until(func() -> bool: return client_on_client.health.health < client_on_client.health.max_health)
	assert_eq(client_on_client.health.health, 70.0, "A hit the server sends lands on the owner")

	# A client that sends 9999 to the host's Player itself is ignored
	var host_on_client: Player = client_root.get_node("Players/1")
	host_on_client._take_hit.rpc_id(1, 9999.0, Vector3.ZERO, ^"")
	# ...and so is one sent to the server's copy of its own Player, which the server would otherwise relay
	client_on_client._heal.rpc_id(1, 50.0, ^"")
	await wait_process_frames(20)
	assert_eq(host_on_server.health.health, host_on_server.health.max_health, "A client cannot hurt somebody else's Player")
	assert_eq(client_on_client.health.health, 70.0, "nor launder a call through the server")


## A client's RPC to the server hits the client's own Player and the host's from the server's side. Inside that
## handler the engine still names the client as the remote sender, which once made the server's own calls look like
## the client's: the relay to the client's owner was held back and the host's Player refused the hit.
func test_a_hit_the_server_makes_inside_a_clients_rpc_is_the_servers_own() -> void:
	var host_on_server: Player = server_root.get_node("Players/1")
	var client_on_client: Player = client_root.get_node("Players/" + _client_id())
	var client_relay: Relay = client_root.get_node("Relay")
	var client_path: NodePath = NodePath("../Players/" + _client_id())

	client_relay.poke.rpc_id(1, client_path, 25.0) # on the server: hits the server's copy of the client's Player
	await _until(func() -> bool: return client_on_client.health.health < client_on_client.health.max_health)
	assert_eq(client_on_client.health.health, 75.0, "The hit reaches the client's own Player")
	await _until(func() -> bool: return not client_on_client.hunters.is_empty())
	assert_eq(client_on_client.hunters.size(), 1, "and so does the hunt, which pauses its mana regen")

	client_relay.poke.rpc_id(1, NodePath("../Players/1"), 10.0) # on the server: the host's own Player
	await _until(func() -> bool: return host_on_server.health.health < host_on_server.health.max_health)
	assert_eq(host_on_server.health.health, 90.0, "and the host's own Player takes it too")


## A heal from another player's peer lands when it names that player's own Player as the healer, not when it names
## somebody it does not own.
func test_a_heal_lands_only_from_the_peer_that_owns_the_healer() -> void:
	var host_on_server: Player = server_root.get_node("Players/1")
	var host_on_client: Player = client_root.get_node("Players/1")
	host_on_server.health.health = 20.0
	await wait_process_frames(10)

	# The paths are relative to the healed Player, so each branch resolves them to its own copies
	host_on_client.heal(30.0, NodePath(".")) # claims the host healed itself: not the client's to say
	await wait_process_frames(20)
	assert_eq(host_on_server.health.health, 20.0, "A heal naming a healer the sender does not own is refused")

	host_on_client.heal(30.0, NodePath("../" + _client_id()))
	await _until(func() -> bool: return host_on_server.health.health > 20.0)
	assert_eq(host_on_server.health.health, 50.0, "A heal from the healer's own peer lands")


## A client's glider opens on the host's copy of it too: the Paraglider is part of player.tscn and follows the
## replicated state on every peer.
func test_a_clients_paraglider_opens_on_the_host() -> void:
	var client_on_client: Player = client_root.get_node("Players/" + _client_id())
	var client_on_server: Player = server_root.get_node("Players/" + _client_id())
	var remote_glider: Node3D = client_on_server.get_node(GLIDER_PATH) as Node3D
	assert_false(remote_glider.visible, "Packed away until the Player glides")
	client_on_client.enable_paraglider = true
	client_on_client.state_machine.travel(client_on_client.current_state, NodeStateMachine.States.PARAGLIDING)
	assert_true((client_on_client.get_node(GLIDER_PATH) as Node3D).visible, "The glider opens on the owner's screen")
	await _until(func() -> bool: return remote_glider.visible)
	assert_true(remote_glider.visible, "and on the host's copy of that Player")


## Water is the owner's to enter: a copy on another peer that its water area reports stays as it is, while the
## owner's hard entry splashes on both peers.
func test_water_is_entered_by_the_owner_and_the_splash_reaches_the_other_peer() -> void:
	var client_on_client: Player = client_root.get_node("Players/" + _client_id())
	var client_on_server: Player = server_root.get_node("Players/" + _client_id())
	var server_water: Area3D = _add_water(server_root)
	var client_water: Area3D = _add_water(client_root)

	client_on_server.enter_water(server_water)
	assert_null(client_on_server.current_water_area, "A copy on another peer ignores the water")
	assert_ne(client_on_server.current_state, NodeStateMachine.States.SWIMMING, "and runs no state machine of its own")

	client_on_client.velocity = Vector3(0.0, -6.0, 0.0)
	client_on_client.enter_water(client_water)
	assert_eq(client_on_client.current_state, NodeStateMachine.States.SWIMMING, "The owner swims")
	assert_not_null(_find_splash(client_root.get_node("Players")), "and splashes on its own screen")
	await _until(func() -> bool: return _find_splash(server_root.get_node("Players")) != null)
	assert_not_null(_find_splash(server_root.get_node("Players")), "and on the host's")


func _add_water(root: Node3D) -> Area3D:
	var water: Area3D = Area3D.new()
	water.name = "Water"
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(100.0, 10.0, 100.0)
	shape.shape = box
	water.add_child(shape)
	root.add_child(water)
	water.global_position = Vector3(0.0, -5.0, 0.0)
	return water


func _find_splash(parent: Node) -> Node:
	for child: Node in parent.get_children():
		if child is WaterSplash:
			return child
	return null
