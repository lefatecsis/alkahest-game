extends GutTest

const LOBBY_MANAGER_SCENE = preload("res://addons/3d_player_controller/scenes/ui/lobby_manager.tscn")
const LOBBY_PLAYER_ITEM_SCENE = preload("res://addons/3d_player_controller/scenes/ui/lobby_player_item.tscn")
const STEAMWORKS: Script = preload("res://addons/3d_player_controller/scripts/steamworks.gd")
const STEAM_PEER: Script = preload("res://addons/3d_player_controller/scripts/steam_peer.gd")


## Stands in for the Steam singleton: the lobby signals the menus listen to, and the calls they make, recorded.
class FakeSteam:
	extends RefCounted

	signal lobby_chat_update(lobby_id: int, changed_id: int, making_change_id: int, chat_state: int)
	signal lobby_data_update(success: bool, lobby_id: int, member_id: int)
	signal lobby_message(lobby_id: int, user: int, message: String, chat_type: int)
	signal avatar_loaded(avatar_id: int, size: int, data: PackedByteArray)

	var local_id: int = 42
	var owner_id: int = 999
	var lobby_data: Dictionary = {}
	var messages: Array[String] = []
	var left: Array[int] = []

	func getLobbyData(_lobby_id: int, key: String) -> String:
		return str(lobby_data.get(key, ""))

	func getLobbyOwner(_lobby_id: int) -> int:
		return owner_id

	func getSteamID() -> int:
		return local_id

	func getFriendPersonaName(steam_id: int) -> String:
		return "Friend %d" % steam_id

	func getPlayerAvatar(_size: int, _steam_id: int) -> void:
		pass

	func getNumLobbyMembers(_lobby_id: int) -> int:
		return 0

	func getLobbyMemberLimit(_lobby_id: int) -> int:
		return 4

	func sendLobbyChatMsg(_lobby_id: int, message: String) -> bool:
		messages.append(message)
		return true

	func leaveLobby(lobby_id: int) -> void:
		left.append(lobby_id)


## A host's network peer, as far as a kick needs one: it maps a Steam id to a peer id and records who it drops.
class FakeHostPeer:
	extends MultiplayerPeerExtension

	var dropped: Array[int] = []

	func get_peer_id_for_steam_id(steam_id: int) -> int:
		return 7 if steam_id == 123 else 0

	func _disconnect_peer(peer: int, _force: bool) -> void:
		dropped.append(peer)

	func _get_unique_id() -> int:
		return 1

	func _is_server() -> bool:
		return true

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED

	func _poll() -> void:
		pass

	func _close() -> void:
		pass

	func _get_available_packet_count() -> int:
		return 0

	func _get_max_packet_size() -> int:
		return 1 << 16

	func _get_packet_script() -> PackedByteArray:
		return PackedByteArray()

	func _put_packet_script(_buffer: PackedByteArray) -> Error:
		return OK

	func _get_packet_channel() -> int:
		return 0

	func _get_packet_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE

	func _get_packet_peer() -> int:
		return 0

	func _set_transfer_channel(_channel: int) -> void:
		pass

	func _get_transfer_channel() -> int:
		return 0

	func _set_transfer_mode(_mode: MultiplayerPeer.TransferMode) -> void:
		pass

	func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE

	func _set_target_peer(_peer: int) -> void:
		pass

	func _is_server_relay_supported() -> bool:
		return false


func after_each() -> void:
	SteamPeer.steam_override = null
	var steamworks: Node = get_tree().root.get_node_or_null("Steamworks")
	if steamworks:
		steamworks.free()


## A Steamworks autoload of our own at /root/Steamworks, signed in and in lobby 5.
func _add_steamworks() -> Node:
	var steamworks: Node = STEAMWORKS.new()
	steamworks.name = "Steamworks"
	get_tree().root.add_child(steamworks)
	steamworks.set("steam_id", 42)
	steamworks.set("lobby_id", 5)
	return steamworks


func test_lobby_manager_initial_state() -> void:
	var lobby_manager = LOBBY_MANAGER_SCENE.instantiate()
	add_child_autofree(lobby_manager)

	assert_not_null(lobby_manager.panel, "Panel should exist")
	assert_not_null(lobby_manager.info_label, "InfoLabel should exist")
	assert_not_null(lobby_manager.player_list, "PlayerList container should exist")
	assert_not_null(lobby_manager.invite_button, "Invite button should exist")
	assert_not_null(lobby_manager.leave_button, "Leave button should exist")
	assert_not_null(lobby_manager.back_button, "BACK button should exist")


func test_lobby_manager_show_and_hide() -> void:
	var lobby_manager = LOBBY_MANAGER_SCENE.instantiate()
	add_child_autofree(lobby_manager)

	lobby_manager.show_menu()
	assert_true(lobby_manager.visible, "show_menu should make lobby manager visible")
	assert_true(lobby_manager.invite_button.disabled, "Invite should be disabled without an active lobby")

	lobby_manager.hide_menu()
	assert_false(lobby_manager.visible, "hide_menu should make lobby manager hidden")


func test_lobby_player_item_nodes_and_default_avatar() -> void:
	var item: LobbyPlayerItem = LOBBY_PLAYER_ITEM_SCENE.instantiate()
	add_child_autofree(item)

	assert_not_null(item.avatar, "Avatar node should exist")
	assert_not_null(item.host_icon, "HostIcon node should exist")
	assert_not_null(item.username_label, "Username label should exist")
	assert_not_null(item.actions_container, "ActionsContainer should exist")
	assert_not_null(item.options_button, "OptionsButton should exist")
	assert_not_null(item.profile_button, "ProfileButton should exist")
	assert_not_null(item.achievements_button, "AchievementsButton should exist")
	assert_not_null(item.promote_button, "PromoteButton should exist")
	assert_not_null(item.kick_button, "KickButton should exist")

	item.steam_id = 123
	assert_true(item.avatar.texture.resource_path.ends_with("profile.png"), "The avatar should show the default icon until Steam delivers one")
	assert_false(item.host_icon.visible, "Without a lobby nobody is host")
	assert_false(item.kick_button.visible, "Without a lobby nobody can be kicked")


func test_lobby_player_item_options_toggle() -> void:
	var item = LOBBY_PLAYER_ITEM_SCENE.instantiate()
	add_child_autofree(item)

	assert_false(item.actions_container.visible, "ActionsContainer should start hidden")
	assert_true(item.username_label.visible, "Username should start visible")

	item.options_button.button_pressed = true
	assert_true(item.actions_container.visible, "ActionsContainer should become visible when toggled")
	assert_false(item.username_label.visible, "Username should become hidden when options are toggled")

	item.options_button.button_pressed = false
	assert_false(item.actions_container.visible, "ActionsContainer should hide when untoggled")
	assert_true(item.username_label.visible, "Username should become visible when options are untoggled")


func test_the_item_reads_nothing_from_steam_until_the_session_is_up() -> void:
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	var signed_in: int = steamworks.get("steam_id") if steamworks else 0
	if steamworks:
		steamworks.set("steam_id", 0)
	var item: LobbyPlayerItem = LOBBY_PLAYER_ITEM_SCENE.instantiate()
	add_child_autofree(item)
	item.lobby_id = 7
	item.steam_id = 123
	assert_null(SteamPeer.session(item), "The extension being loaded is not a session")
	assert_false(item.host_icon.visible, "so nobody is host")
	assert_false(item.promote_button.visible, "and there is nobody to moderate")
	if steamworks:
		steamworks.set("steam_id", signed_in)


func test_the_manager_asks_steam_for_nothing_until_the_session_is_up() -> void:
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	var signed_in: int = steamworks.get("steam_id") if steamworks else 0
	if steamworks:
		steamworks.set("steam_id", 0)
	var lobby_manager = LOBBY_MANAGER_SCENE.instantiate()
	add_child_autofree(lobby_manager)
	lobby_manager.show_menu()
	assert_null(SteamPeer.session(lobby_manager))
	assert_eq(lobby_manager.info_label.text, "Steam unavailable")
	assert_true(lobby_manager.invite_button.disabled)
	assert_true(lobby_manager.leave_button.disabled)
	lobby_manager._on_lobby_message(1, 1, "/kick 0", 0) # a callback with no session behind it is ignored, not an error
	lobby_manager.hide_menu()
	if steamworks:
		steamworks.set("steam_id", signed_in)


## Every peer carries every Player's menus. Only the copy this peer owns listens to the lobby, or a /kick would run
## once per Player in the session.
func test_only_this_peers_own_lobby_menu_listens_to_steam() -> void:
	var steam: FakeSteam = FakeSteam.new()
	SteamPeer.steam_override = steam
	var mine = LOBBY_MANAGER_SCENE.instantiate()
	add_child_autofree(mine)
	var puppet = LOBBY_MANAGER_SCENE.instantiate()
	puppet.set_multiplayer_authority(2) # another peer's Player's copy
	add_child_autofree(puppet)
	assert_true(steam.is_connected("lobby_message", mine._on_lobby_message), "This peer's menu hears the lobby")
	assert_false(steam.is_connected("lobby_message", puppet._on_lobby_message), "a copy of somebody else's does not")
	assert_false(steam.is_connected("lobby_chat_update", puppet._on_lobby_chat_update))


## Leave ends the whole session, not just the Steam lobby: the world's SteamPeer leaves the lobby, goes offline and
## emits session_ended, which the game wires to its title.
func test_leave_ends_the_session_through_the_steam_peer() -> void:
	var steam: FakeSteam = FakeSteam.new()
	SteamPeer.steam_override = steam
	_add_steamworks()
	var steam_peer: SteamPeer = STEAM_PEER.new()
	add_child_autofree(steam_peer)
	var lobby_manager = LOBBY_MANAGER_SCENE.instantiate()
	add_child_autofree(lobby_manager)
	lobby_manager.show_menu()
	assert_false(lobby_manager.leave_button.disabled, "In a lobby, Leave is on")
	watch_signals(steam_peer)

	lobby_manager.leave_button.pressed.emit()

	assert_eq(steam.left, [5] as Array[int], "The lobby is left")
	assert_signal_emitted(steam_peer, "session_ended", "and the session ended, for the game to go to its title")
	assert_false(lobby_manager.visible, "The menu closes")


## The host's badge and the kick follow the host named in the lobby data, not the lobby's owner, who may not be
## hosting; Promote stays hidden, since there is no host migration to hand the session over.
func test_the_rows_follow_the_host_and_promote_stays_hidden() -> void:
	var steam: FakeSteam = FakeSteam.new()
	steam.lobby_data[SteamPeer.HOST_KEY] = "42" # we host; 999 owns the lobby
	SteamPeer.steam_override = steam
	var host_row: LobbyPlayerItem = LOBBY_PLAYER_ITEM_SCENE.instantiate()
	add_child_autofree(host_row)
	host_row.lobby_id = 5
	host_row.steam_id = 42
	var member_row: LobbyPlayerItem = LOBBY_PLAYER_ITEM_SCENE.instantiate()
	add_child_autofree(member_row)
	member_row.lobby_id = 5
	member_row.steam_id = 123
	assert_true(host_row.host_icon.visible, "The badge is on the host")
	assert_false(member_row.host_icon.visible)
	assert_true(member_row.kick_button.visible, "The host may kick a member")
	assert_false(host_row.kick_button.visible, "but not itself")
	assert_false(member_row.promote_button.visible, "Promote stays hidden")


## Kick tells the member's client to leave and, on the host, drops that member's peer as well.
func test_kick_drops_the_members_peer_on_the_host() -> void:
	var steam: FakeSteam = FakeSteam.new()
	steam.lobby_data[SteamPeer.HOST_KEY] = "42"
	SteamPeer.steam_override = steam
	var branch: Node = Node.new()
	branch.name = "HostBranch"
	add_child(branch)
	var api: SceneMultiplayer = SceneMultiplayer.new()
	get_tree().set_multiplayer(api, branch.get_path())
	var host_peer: FakeHostPeer = FakeHostPeer.new()
	api.multiplayer_peer = host_peer
	var row: LobbyPlayerItem = LOBBY_PLAYER_ITEM_SCENE.instantiate()
	branch.add_child(row)
	row.lobby_id = 5
	row.steam_id = 123

	row.kick_button.pressed.emit()

	assert_eq(steam.messages, ["/kick 123"] as Array[String], "The member's client is told")
	assert_eq(host_peer.dropped, [7] as Array[int], "and its peer is dropped here")
	var path: NodePath = branch.get_path()
	branch.free()
	get_tree().set_multiplayer(null, path)
