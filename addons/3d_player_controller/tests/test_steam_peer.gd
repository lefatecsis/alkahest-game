extends GutTest
## Purpose: SteamPeer has to tell a session it made from Godot's default peer. Every tree carries an
## OfflineMultiplayerPeer from the start, so "has a multiplayer peer" is always true and can never mean
## "already hosting or connected"; asking that made both the host and the client path return early, and no
## Steam session ever formed even with the lobby joined on both sides. Joiners connect to the host the lobby data
## names, not the lobby's owner; the session ends (lobby left, peer offline, session_ended) on Leave and when the host
## goes away; and the Steamworks autoload takes invites, from the overlay and from +connect_lobby.

const STEAM_PEER: Script = preload("res://addons/3d_player_controller/scripts/steam_peer.gd")


func test_the_default_offline_peer_is_not_a_session() -> void:
	var peer: SteamPeer = STEAM_PEER.new()
	add_child_autofree(peer)
	var was: MultiplayerPeer = peer.multiplayer.multiplayer_peer
	assert_true(peer.multiplayer.has_multiplayer_peer(), "Godot always answers yes here, which is the trap")
	assert_false(peer.has_session(), "so that is not what the guard asks")
	var enet: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	enet.create_server(47393)
	peer.multiplayer.multiplayer_peer = enet
	assert_true(peer.has_session(), "a real peer is a session")
	peer.multiplayer.multiplayer_peer = was
	enet.close()


func test_the_peer_is_unavailable_until_the_session_is_up() -> void:
	# The extension loaded and the client running are not the session; getLobbyOwner errors before it initialises
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	var signed_in: int = steamworks.get("steam_id") if steamworks else 0
	if steamworks:
		steamworks.set("steam_id", 0)
	var peer: Node = STEAM_PEER.new()
	add_child_autofree(peer)
	assert_false(peer.is_available(), "No session, no peer")
	peer.connect_to_lobby(123)
	assert_false(peer.has_session(), "and a lobby id is not acted on")
	if steamworks:
		steamworks.set("steam_id", signed_in)


const STEAMWORKS: Script = preload("res://addons/3d_player_controller/scripts/steamworks.gd")
const PORT: int = 47433


## Stands in for the Steam singleton: records what it is asked to do and answers the lobby reads from its fields.
class FakeSteam:
	extends RefCounted

	signal lobby_chat_update(lobby_id: int, changed_id: int, making_change_id: int, chat_state: int)

	var owner_id: int = 0
	var lobby_data: Dictionary = {}
	var left: Array[int] = []
	var joined: Array[int] = []

	func getLobbyData(_lobby_id: int, key: String) -> String:
		return str(lobby_data.get(key, ""))

	func getLobbyOwner(_lobby_id: int) -> int:
		return owner_id

	func leaveLobby(lobby_id: int) -> void:
		left.append(lobby_id)

	func joinLobby(lobby_id: int) -> void:
		joined.append(lobby_id)


## A Steamworks autoload of our own at /root/Steamworks, signed in and in [param lobby_id].
func _add_steamworks(lobby_id: int) -> Node:
	var steamworks: Node = STEAMWORKS.new()
	steamworks.name = "Steamworks"
	get_tree().root.add_child(steamworks)
	steamworks.set("steam_id", 42)
	steamworks.set("lobby_id", lobby_id)
	return steamworks


func after_each() -> void:
	SteamPeer.steam_override = null
	var steamworks: Node = get_tree().root.get_node_or_null("Steamworks")
	if steamworks:
		steamworks.free()


## Promote hands the lobby's ownership to somebody who is not hosting, so joiners look for the host in the lobby
## data, where the host wrote its own Steam id, and fall back on the owner only while nobody has.
func test_joiners_connect_to_the_host_written_in_the_lobby_not_its_owner() -> void:
	var steam: FakeSteam = FakeSteam.new()
	steam.owner_id = 999
	assert_eq(SteamPeer.host_of(steam, 5), 999, "Nothing written yet: the owner is the host")
	steam.lobby_data[SteamPeer.HOST_KEY] = "42"
	assert_eq(SteamPeer.host_of(steam, 5), 42, "Once written, the host it names, whoever owns the lobby")


## The lobby lookups go through one place: the Steamworks autoload's lobby, and its session only while signed in.
func test_the_session_and_the_lobby_come_from_the_steamworks_autoload() -> void:
	var peer: SteamPeer = STEAM_PEER.new()
	add_child_autofree(peer)
	assert_eq(SteamPeer.lobby_of(peer), 0, "No autoload, no lobby")
	var steamworks: Node = _add_steamworks(77)
	assert_eq(SteamPeer.lobby_of(peer), 77)
	steamworks.set("steam_id", 0)
	assert_null(SteamPeer.session(peer), "Signed out, no session")
	var steam: FakeSteam = FakeSteam.new()
	SteamPeer.steam_override = steam
	assert_same(SteamPeer.session(peer), steam, "A stand-in answers for Steam when set")


## Leave in the lobby menu ends here: the Steam lobby is left, the peer closed and replaced by an offline one, the
## autoload's lobby cleared, and session_ended fires for the world to go back to its title.
func test_ending_the_session_leaves_the_lobby_and_goes_offline() -> void:
	var steam: FakeSteam = FakeSteam.new()
	SteamPeer.steam_override = steam
	var steamworks: Node = _add_steamworks(77)
	var branch: Node = Node.new()
	branch.name = "Branch"
	add_child(branch)
	var api: SceneMultiplayer = SceneMultiplayer.new()
	get_tree().set_multiplayer(api, branch.get_path())
	var enet: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(enet.create_server(PORT), OK)
	api.multiplayer_peer = enet
	var peer: SteamPeer = STEAM_PEER.new()
	branch.add_child(peer)
	watch_signals(peer)

	peer.end_session()

	assert_eq(steam.left, [77] as Array[int], "The Steam lobby is left")
	assert_eq(steamworks.get("lobby_id"), 0, "and forgotten")
	assert_true(api.multiplayer_peer is OfflineMultiplayerPeer, "The game session is closed")
	assert_signal_emitted(peer, "session_ended", "and the world is told, to go back to its title")
	var path: NodePath = branch.get_path()
	branch.free()
	get_tree().set_multiplayer(null, path)


## The host quitting frees the client's own Player with everything on it; the client's SteamPeer ends the session
## instead of leaving it with nothing, and says so.
func test_the_host_going_away_ends_the_clients_session() -> void:
	var server_root: Node = Node.new()
	server_root.name = "ServerBranch"
	var client_root: Node = Node.new()
	client_root.name = "ClientBranch"
	add_child(server_root)
	add_child(client_root)
	var server_api: SceneMultiplayer = SceneMultiplayer.new()
	var client_api: SceneMultiplayer = SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	get_tree().set_multiplayer(client_api, client_root.get_path())
	var server_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PORT + 1), OK)
	server_api.multiplayer_peer = server_peer
	var client_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PORT + 1), OK)
	client_api.multiplayer_peer = client_peer
	var client_steam_peer: SteamPeer = STEAM_PEER.new()
	client_root.add_child(client_steam_peer)
	for i in 120:
		await wait_process_frames(1)
		if client_api.get_peers().size() > 0 and server_api.get_peers().size() > 0:
			break
	assert_gt(server_api.get_peers().size(), 0, "The client joined")
	watch_signals(client_steam_peer)

	server_peer.close()
	await wait_until(func() -> bool: return client_api.multiplayer_peer is OfflineMultiplayerPeer, 5.0)

	assert_true(client_api.multiplayer_peer is OfflineMultiplayerPeer, "The client is back offline")
	assert_signal_emitted(client_steam_peer, "session_ended", "and the world hears the session is over")
	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)


## A game launched by a Steam invite carries +connect_lobby and the lobby's id on its command line.
func test_a_launch_by_invite_names_its_lobby() -> void:
	assert_eq(STEAMWORKS.lobby_in_command_line(PackedStringArray(["--path", ".", "+connect_lobby", "109775242548404697"])), 109775242548404697)
	assert_eq(STEAMWORKS.lobby_in_command_line(PackedStringArray(["+connect_lobby"])), 0, "An id is needed")
	assert_eq(STEAMWORKS.lobby_in_command_line(PackedStringArray()), 0)


## An invite accepted in the overlay leaves the lobby we were in and joins the friend's; Steam's answer makes the
## new one the autoload's lobby, and a failed join leaves it as it was.
func test_an_accepted_invite_leaves_the_old_lobby_and_joins_the_new_one() -> void:
	var steam: FakeSteam = FakeSteam.new()
	var steamworks: Node = _add_steamworks(5)
	steamworks.set("_steam", steam)

	steamworks._on_join_requested(9, 1234)
	assert_eq(steam.left, [5] as Array[int], "The old lobby is left")
	assert_eq(steam.joined, [9] as Array[int], "and the friend's joined")

	steamworks._on_lobby_joined(9, 0, false, STEAMWORKS.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
	assert_eq(steamworks.get("lobby_id"), 9, "Steam's answer makes it the lobby")
	steamworks._on_lobby_joined(11, 0, false, 5)
	assert_eq(steamworks.get("lobby_id"), 9, "A failed join changes nothing")


## Records when the lobby is joined instead of joining it; this build has no SteamMultiplayerPeer to join with.
class JoinRecorder:
	extends SteamPeer

	var order: Array[String] = []

	func connect_to_lobby(lobby_id: int) -> void:
		order.append("joined %d" % lobby_id)


## A PlayerSpawner or SyncedBody placed above the SteamPeer readies after the session is joined, not before: from
## _ready, a joining client's spawner would ready offline and spawn a local Player "1" of its own.
func test_the_lobby_is_joined_before_any_node_above_it_readies() -> void:
	_add_steamworks(77)
	var world: Node = Node.new()
	var above: Node = Node.new()
	var peer: JoinRecorder = JoinRecorder.new()
	above.ready.connect(func() -> void: peer.order.append("ready above"))
	world.add_child(above)
	world.add_child(peer)
	add_child_autofree(world)
	assert_eq(peer.order, ["joined 77", "ready above"] as Array[String], "The session is in place before the node above it readies")
