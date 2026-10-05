extends PlayerMenuLayer

@export var lobby_player_item_scene: PackedScene ## Assigned in the scene so it ships as a scene dependency.

@onready var panel: Panel = $Panel
@onready var info_label: Label = $Panel/VBoxContainer/InfoLabel
@onready var player_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/PlayerList
@onready var invite_button: Button = $Panel/VBoxContainer/HBoxContainer/Invite
@onready var leave_button: Button = $Panel/VBoxContainer/HBoxContainer/Leave
@onready var back_button: Button = $Panel/VBoxContainer/BACK


## Called when the node enters the scene tree for the first time. Every peer carries a copy of every Player's
## menus, so only the copy this peer owns listens to Steam; the others would run a kick once per Player.
func _ready() -> void:
	super()
	var steam: Object = SteamPeer.session(self)
	if steam == null or not is_multiplayer_authority():
		return
	steam.connect("lobby_chat_update", _on_lobby_chat_update)
	steam.connect("lobby_data_update", _on_lobby_data_update)
	steam.connect("lobby_message", _on_lobby_message)


func show_menu() -> void:
	_update_lobby_ui()
	focus_on_show = back_button if invite_button.disabled else invite_button
	super()


func _update_lobby_ui() -> void:
	for child: Node in player_list.get_children():
		child.queue_free()

	var active_lobby_id: int = SteamPeer.lobby_of(self)
	var steam: Object = SteamPeer.session(self)
	var has_lobby: bool = steam != null and active_lobby_id > 0
	invite_button.disabled = not has_lobby
	leave_button.disabled = not has_lobby
	if steam == null:
		info_label.text = "Steam unavailable"
		return
	if not has_lobby:
		info_label.text = "No active lobby"
		return

	var member_count: int = steam.getNumLobbyMembers(active_lobby_id)
	var max_members: int = steam.getLobbyMemberLimit(active_lobby_id)
	info_label.text = "Host: %s (%d/%d)" % [steam.getFriendPersonaName(SteamPeer.host_of(steam, active_lobby_id)), member_count, max_members if max_members > 0 else 4]

	if lobby_player_item_scene == null:
		return
	for i: int in range(member_count):
		var item: LobbyPlayerItem = lobby_player_item_scene.instantiate() as LobbyPlayerItem
		player_list.add_child(item)
		item.lobby_id = active_lobby_id
		item.steam_id = steam.getLobbyMemberByIndex(active_lobby_id, i)
		item.player_promoted.connect(_on_player_promoted)


func _on_player_promoted(_steam_id: int) -> void:
	_update_lobby_ui()


#region Steam Callbacks
func _on_lobby_chat_update(lobby_id: int, _changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	if SteamPeer.lobby_of(self) == lobby_id and visible:
		_update_lobby_ui()


func _on_lobby_data_update(_success: bool, lobby_id: int, _member_id: int) -> void:
	if SteamPeer.lobby_of(self) == lobby_id and visible:
		_update_lobby_ui()


## Leaves the lobby when the host sends "/kick <our steam id>".
func _on_lobby_message(lobby_id: int, sender: int, message: String, _chat_type: int) -> void:
	var steam: Object = SteamPeer.session(self)
	if steam == null or lobby_id != SteamPeer.lobby_of(self) or not message.begins_with("/kick ") or sender != SteamPeer.host_of(steam, lobby_id):
		return
	if int(message.get_slice(" ", 1)) == steam.getSteamID():
		_on_leave_pressed()
#endregion


func _on_invite_pressed() -> void:
	var active_lobby_id: int = SteamPeer.lobby_of(self)
	var steam: Object = SteamPeer.session(self)
	if steam != null and active_lobby_id > 0:
		steam.activateGameOverlayInviteDialog(active_lobby_id)


func _on_invite_touch_screen_button_pressed() -> void:
	_on_invite_pressed()


## Leaves the lobby and the game session with it: the world's [SteamPeer] ends the session, and the game goes back
## to its title on [signal SteamPeer.session_ended], wired in its world scene.
func _on_leave_pressed() -> void:
	var steam_peer: SteamPeer = SteamPeer.find_in(get_tree())
	if steam_peer == null:
		return
	hide_menu()
	steam_peer.end_session()


func _on_leave_touch_screen_button_pressed() -> void:
	_on_leave_pressed()


## Return to the pause menu.
func _on_back_pressed() -> void:
	if player == null:
		return
	hide()
	player.pause.show_menu()


func _on_back_touch_screen_button_pressed() -> void:
	_on_back_pressed()
