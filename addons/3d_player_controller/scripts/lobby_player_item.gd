class_name LobbyPlayerItem
extends PanelContainer
## One row of the lobby member list; the avatar and name come from the Steam singleton when it is present.

const AVATAR_MEDIUM: int = 2 ## Mirrors Steam.AvatarSizes.AVATAR_MEDIUM (the Steam class is absent on web exports).

signal player_promoted(steam_id: int) ## Emitted after this member is made lobby owner.

var steam_id: int = 0 : set = set_steam_id
var lobby_id: int = 0 ## Set by the lobby manager before [member steam_id].

@onready var avatar: TextureRect = %Avatar
@onready var host_icon: TextureRect = %HostIcon
@onready var username_label: Label = %Username
@onready var options_button: Button = %OptionsButton
@onready var actions_container: HBoxContainer = %ActionsContainer
@onready var profile_button: Button = %ProfileButton
@onready var achievements_button: Button = %AchievementsButton
@onready var promote_button: Button = %PromoteButton
@onready var kick_button: Button = %KickButton


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var steam: Object = SteamPeer.session(self)
	if steam:
		steam.connect("avatar_loaded", _on_avatar_loaded)


func set_steam_id(new_steam_id: int) -> void:
	steam_id = new_steam_id
	if not is_node_ready():
		await ready
	var steam: Object = SteamPeer.session(self)
	if steam:
		username_label.text = steam.getFriendPersonaName(steam_id)
		steam.getPlayerAvatar(AVATAR_MEDIUM, steam_id)
	_update_player_state()


## Shows the host badge and, when the local user hosts, the kick action for other members. Promote stays hidden:
## the session has no host migration, so a new lobby owner would not be hosting anything.
func _update_player_state() -> void:
	var steam: Object = SteamPeer.session(self)
	var host_id: int = SteamPeer.host_of(steam, lobby_id) if steam and lobby_id > 0 else 0
	var local_id: int = steam.getSteamID() if steam else 0
	host_icon.visible = host_id > 0 and steam_id == host_id
	kick_button.visible = host_id > 0 and local_id == host_id and steam_id != local_id


func _on_avatar_loaded(avatar_id: int, size: int, data: PackedByteArray) -> void:
	if avatar_id == steam_id:
		avatar.texture = ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data))


func _on_options_toggled(toggled_on: bool) -> void:
	actions_container.visible = toggled_on
	username_label.visible = not toggled_on


func _on_profile_pressed() -> void:
	var steam: Object = SteamPeer.session(self)
	if steam and steam_id > 0:
		steam.activateGameOverlayToUser("steamid", steam_id)


func _on_achievements_pressed() -> void:
	var steam: Object = SteamPeer.session(self)
	if steam and steam_id > 0:
		steam.activateGameOverlayToUser("achievements", steam_id)


func _on_promote_pressed() -> void:
	var steam: Object = SteamPeer.session(self)
	if steam and lobby_id > 0 and steam_id > 0:
		steam.setLobbyOwner(lobby_id, steam_id)
		player_promoted.emit(steam_id)
		_update_player_state()


## Tells this member's client to leave, and drops them from the session here on the host as well, so a client that
## never acts on the message is gone all the same. The list refreshes from Steam's lobby_chat_update.
func _on_kick_pressed() -> void:
	var steam: Object = SteamPeer.session(self)
	if steam == null or lobby_id <= 0 or steam_id <= 0:
		return
	steam.sendLobbyChatMsg(lobby_id, "/kick %s" % steam_id)
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if multiplayer.is_server() and peer.has_method(&"get_peer_id_for_steam_id"):
		var peer_id: int = peer.call(&"get_peer_id_for_steam_id", steam_id)
		if peer_id > 1:
			peer.disconnect_peer(peer_id)

