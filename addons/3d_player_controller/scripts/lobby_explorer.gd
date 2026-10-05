class_name LobbyExplorer
extends CanvasLayer
## Lists public Steam lobbies and hosts or joins one; the scenes it loads are set per project on the instance.

@export var lobby_explorer_entry_scene: PackedScene ## Assigned in the scene so it ships as a scene dependency.
@export_file("*.tscn") var world_scene: String = "" ## Loaded after hosting or joining a lobby.
@export_file("*.tscn") var title_scene: String = "" ## Loaded by BACK.
@export var footer_text: String = "" ## Shown bottom-right with the current year appended, e.g. a copyright line.

@onready var loading: Loading = $Loading
@onready var host_button: Button = %Button_Host
@onready var refresh_button: Button = %Button_Refresh
@onready var back_button: Button = %Button_Back
@onready var status_label: Label = %StatusLabel
@onready var lobby_list: VBoxContainer = %LobbyList
@onready var distance_option: OptionButton = %DistanceOption
@onready var label_version: Label = $Label_Version
@onready var label_copyright: Label = $Label_Copyright


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	label_version.text = version if version.begins_with("v") else "v" + version
	label_copyright.text = "%s %d" % [footer_text, Time.get_date_dict_from_system().year] if not footer_text.is_empty() else ""

	var steam: Object = SteamPeer.session(self)
	if steam == null:
		status_label.text = "Steam is not running. Lobby features disabled."
		host_button.disabled = true
		refresh_button.disabled = true
		return
	steam.connect("lobby_match_list", _on_lobby_match_list)
	steam.connect("lobby_joined", _on_lobby_joined)
	refresh_lobbies()


func refresh_lobbies() -> void:
	var steam: Object = SteamPeer.session(self)
	if steam == null:
		return
	_clear_lobby_list()
	status_label.text = "Searching for lobbies..."
	steam.addRequestLobbyListDistanceFilter(distance_option.selected)
	steam.addRequestLobbyListFilterSlotsAvailable(1)
	steam.addRequestLobbyListResultCountFilter(50)
	steam.requestLobbyList()


func _clear_lobby_list() -> void:
	for child: Node in lobby_list.get_children():
		child.queue_free()


func _on_distance_filter_changed(_index: int) -> void:
	refresh_lobbies()


func _on_host_pressed() -> void:
	if not world_scene.is_empty():
		loading.load_scene(world_scene)


func _on_back_pressed() -> void:
	if not title_scene.is_empty():
		loading.load_scene(title_scene)


func _on_touch_host_pressed() -> void:
	_on_host_pressed()


func _on_touch_refresh_pressed() -> void:
	refresh_lobbies()


func _on_touch_back_pressed() -> void:
	_on_back_pressed()


func _on_join_lobby_requested(lobby_id: int) -> void:
	status_label.text = "Joining lobby %d..." % lobby_id
	var steam: Object = SteamPeer.session(self)
	if steam != null:
		steam.joinLobby(lobby_id)


#region Steam Callbacks
func _on_lobby_match_list(lobbies: Array) -> void:
	_clear_lobby_list()
	if lobbies.is_empty():
		status_label.text = "No public lobbies found. Click 'Host Game' to create one!"
		return
	status_label.text = "Found %d active lobbies" % lobbies.size()
	if lobby_explorer_entry_scene == null:
		return
	for lobby_id: int in lobbies:
		var entry: LobbyExplorerEntry = lobby_explorer_entry_scene.instantiate() as LobbyExplorerEntry
		lobby_list.add_child(entry)
		entry.lobby_id = lobby_id
		entry.join_requested.connect(_on_join_lobby_requested)


## Any lobby joined, from the list or from a Steam invite; the Steamworks autoload has already made it its lobby_id.
func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_SUCCESS == 1
	if response != 1:
		status_label.text = "Failed to join lobby (Response code: %d)" % response
		return
	status_label.text = "Joined lobby %d! Loading world..." % lobby_id
	if not world_scene.is_empty():
		loading.load_scene(world_scene)
#endregion

