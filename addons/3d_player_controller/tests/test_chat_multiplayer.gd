extends GutTest

## Purpose: a chat message sent on the host reaches the client's own chat window, and one from the client reaches
## the host. Chat travels by RPC on the sender's ChatWindow, which lives on every peer's copy of that Player, and
## relays to the chat that peer owns. Two scene branches with their own MultiplayerAPI talk over ENet on
## localhost, as test_enemy_multiplayer does.

const PORT: int = 47396
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")

var server_root: Node3D
var client_root: Node3D
var server_api: SceneMultiplayer
var client_api: SceneMultiplayer


func _build_branch(root: Node3D) -> void:
	var players: Node3D = Node3D.new()
	players.name = "Players"
	root.add_child(players)
	var player_spawner: PlayerSpawner = PLAYER_SPAWNER.new()
	player_spawner.name = "PlayerSpawner"
	player_spawner.spawn_path = NodePath("../Players")
	player_spawner.add_child(PLAYER_SCENE.instantiate()) # the template every peer's player is a copy of
	root.add_child(player_spawner)


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
	var server_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PORT), OK, "ENet server should open on localhost")
	server_api.multiplayer_peer = server_peer
	var client_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PORT), OK)
	client_api.multiplayer_peer = client_peer
	_build_branch(server_root)
	_build_branch(client_root)
	for i: int in 120:
		await wait_process_frames(1)
		if client_api.get_peers().size() > 0 and server_api.get_peers().size() > 0:
			break
	assert_gt(client_api.get_peers().size(), 0, "Client should connect to the loopback server")


func after_each() -> void:
	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	server_api.multiplayer_peer.close()
	client_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)


func test_a_host_message_arrives_in_the_clients_chat_and_back() -> void:
	await wait_process_frames(30)
	var client_id: String = str(client_api.get_unique_id()) # ENet hands clients a random id
	var host_chat: ChatWindow = server_root.get_node("Players/1/Hud/Chat")
	var client_chat: ChatWindow = client_root.get_node("Players/" + client_id + "/Hud/Chat")
	var host_copy_on_client: ChatWindow = client_root.get_node("Players/1/Hud/Chat")
	assert_true(host_chat.visible, "The host sees its own chat")
	assert_true(client_chat.visible, "The client sees its own chat")
	assert_false(host_copy_on_client.visible, "The host's copy on the client stays hidden")
	assert_false(server_root.get_node("Players/" + client_id + "/Hud/Chat").visible, "as does the client's copy on the host")

	var host_name: String = host_chat.get_display_name() # The Steam persona when Steam runs, else "Player 1"
	var client_name: String = client_chat.get_display_name()
	# The addon's own Steamworks autoload supplies /root/Steamworks, which need not be registered.
	var steamworks: Node = host_chat.get_node_or_null("/root/Steamworks")
	if not Engine.has_singleton("Steam") or steamworks == null or steamworks.get("steam_id") == 0:
		assert_eq(host_name, "Player 1", "Without Steam the host is named by its peer id")
		assert_eq(client_name, "Player " + client_id, "and so is the client")
	host_chat.send("hello from the host")
	await wait_process_frames(10)
	assert_string_contains(client_chat.history.get_parsed_text(), host_name + ": hello from the host", "The client's chat shows the host's line")
	assert_string_contains(host_chat.history.get_parsed_text(), host_name + ": hello from the host", "call_local echoes it on the host")
	assert_eq(host_copy_on_client.history.get_parsed_text(), "", "The hidden copy only relays, it keeps no history")

	client_chat.send("hi back")
	await wait_process_frames(10)
	assert_string_contains(host_chat.history.get_parsed_text(), client_name + ": hi back", "The host's chat shows the client's line")
	assert_string_contains(client_chat.history.get_parsed_text(), client_name + ": hi back", "and the client sees its own")
	assert_eq(client_chat.history.get_parsed_text().count("hello from the host"), 1, "Each message lands once")
