class_name SteamPeer
extends Node
## Turns the current Steam lobby into a high-level multiplayer session.
##
## Whoever hosts is peer 1 and writes their Steam id into the lobby data under [constant HOST_KEY]; everyone else
## connects to that id rather than to the lobby's owner, since ownership can move to somebody who is not hosting.
## Steam is reached only through [method session] and [code]/root/Steamworks[/code], so the node is inert on web
## exports and whenever no lobby is active. Call [method host] once a lobby has been created locally, or rely on
## [method _enter_tree] when the world loads after joining a lobby.
##
## The session ends through [method end_session]: the lobby menu's Leave calls it, and so does the host going away
## or a join that fails. The peer goes back to an [OfflineMultiplayerPeer] and [signal session_ended] fires, which
## a world wires in its scene to going back to its title.

signal network_ready(is_host: bool) ## Emitted once [member MultiplayerAPI.multiplayer_peer] is set.
signal session_ended ## The session is over: this peer left, the host went away, or the join failed.

const GROUP: StringName = &"SteamPeer"
const HOST_KEY: String = "host_steam_id" ## Lobby data naming the Steam id that hosts the session.

static var steam_override: Object = null ## Stands in for the Steam singleton when set; tests put a fake here.

@export var virtual_port: int = 0 ## Steam networking virtual port shared by host and clients.


## Joins the lobby's session on entering the tree rather than on ready. Every node in the world enters the tree
## before any of them readies, so a PlayerSpawner or SyncedBody readies with the session already in place wherever
## this node sits; from _ready, the ones above it would ready offline and spawn a local Player "1" on a client.
func _enter_tree() -> void:
	var lobby_id: int = lobby_of(self)
	if lobby_id != 0 and not has_session():
		connect_to_lobby(lobby_id)


func _ready() -> void:
	add_to_group(GROUP)
	# The MultiplayerAPI is no node, so these cannot be wired in a scene. Deferred, so the peer is replaced once the
	# poll that reported the loss has finished.
	multiplayer.server_disconnected.connect(end_session, CONNECT_DEFERRED)
	multiplayer.connection_failed.connect(end_session, CONNECT_DEFERRED)


## The Steam singleton while the Steamworks session is up, else null. The extension being loaded is not enough:
## the session only initialises on a desktop Forward+ build with the client running, and every lobby call errors
## before it has, so this waits for [code]/root/Steamworks[/code] to report a signed-in [code]steam_id[/code].
static func session(node: Node) -> Object:
	if steam_override:
		return steam_override
	var steamworks: Node = node.get_node_or_null(^"/root/Steamworks") if node.is_inside_tree() else null
	if steamworks == null or steamworks.get("steam_id") == 0 or not Engine.has_singleton("Steam"):
		return null
	return Engine.get_singleton("Steam")


## The lobby the Steamworks autoload has joined, or 0 with none (or no autoload at all).
static func lobby_of(node: Node) -> int:
	var steamworks: Node = node.get_node_or_null(^"/root/Steamworks") if node.is_inside_tree() else null
	return int(steamworks.get("lobby_id")) if steamworks else 0


## The Steam id hosting [param lobby_id]'s session: the one its host wrote into the lobby data, or the lobby's
## owner while nobody has.
static func host_of(steam: Object, lobby_id: int) -> int:
	var written: int = str(steam.getLobbyData(lobby_id, HOST_KEY)).to_int()
	return written if written != 0 else int(steam.getLobbyOwner(lobby_id))


## The SteamPeer in [param tree], or null (a world with no networking has none); the lobby menu's Leave finds it so.
static func find_in(tree: SceneTree) -> SteamPeer:
	return tree.get_first_node_in_group(GROUP) as SteamPeer if tree else null


## True when the Steamworks session is up and this build ships the Steam multiplayer peer.
func is_available() -> bool:
	return session(self) != null and ClassDB.class_exists(&"SteamMultiplayerPeer")


## Whether a session is already up. Godot gives every tree an [OfflineMultiplayerPeer] from the start, so
## [method MultiplayerAPI.has_multiplayer_peer] is always true and says nothing; only a peer that is not that
## one means we are hosting or connected. Asking the wrong question here meant neither ever happened.
func has_session() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


## Hosts the session and names this account its host in the lobby data; the caller has already created the lobby.
func host() -> void:
	if not is_available() or has_session():
		return
	var peer: MultiplayerPeer = ClassDB.instantiate(&"SteamMultiplayerPeer")
	peer.call("create_host", virtual_port)
	multiplayer.multiplayer_peer = peer
	var lobby_id: int = lobby_of(self)
	if lobby_id != 0:
		session(self).setLobbyData(lobby_id, HOST_KEY, str(_own_steam_id()))
	network_ready.emit(true)


## Hosts when we are [param lobby_id]'s host (see [method host_of]), otherwise connects to whoever is.
func connect_to_lobby(lobby_id: int) -> void:
	if not is_available() or has_session():
		return
	var host_id: int = host_of(session(self), lobby_id)
	if host_id == _own_steam_id():
		host()
		return
	var peer: MultiplayerPeer = ClassDB.instantiate(&"SteamMultiplayerPeer")
	peer.call("create_client", host_id, virtual_port)
	multiplayer.multiplayer_peer = peer
	network_ready.emit(false)


## Leaves the Steam lobby, closes the network peer and puts an [OfflineMultiplayerPeer] in its place, clears the
## Steamworks lobby and emits [signal session_ended]. Leave in the lobby menu, the host going away and a failed
## join all end here.
func end_session() -> void:
	var steam: Object = session(self)
	var lobby_id: int = lobby_of(self)
	if steam and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	var steamworks: Node = get_node_or_null(^"/root/Steamworks")
	if steamworks:
		steamworks.set("lobby_id", 0)
	if has_session():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	session_ended.emit()


func _own_steam_id() -> int:
	var steamworks: Node = get_node_or_null(^"/root/Steamworks")
	return int(steamworks.get("steam_id")) if steamworks else 0
