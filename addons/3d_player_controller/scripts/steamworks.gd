extends Node
## The Steam session: initialises Steamworks and holds who you are and which lobby you are in.
##
## Register this as an autoload named [code]Steamworks[/code] and everything in the addon that wants
## Steam finds it at [code]/root/Steamworks[/code]. Nothing requires it: every caller looks it up with
## [method Node.get_node_or_null] and falls back to peer ids, so a project without Steam, or a web
## export, simply runs without it.
##
## Steam is only initialised on a desktop Forward+ build with the GodotSteam extension present and the
## client actually running. Where any of that is untrue the node stays in the tree with
## [member steam_id] at 0, which is what the callers read as "no Steam".
##
## Invites are accepted here. An invite taken in the Steam overlay ([code]join_requested[/code]) and a launch by
## one ([code]+connect_lobby <id>[/code] on the command line) both join that lobby, leaving the one we were in.
## Every lobby joined becomes [member lobby_id]. When the invite's lobby is joined while a world with a
## [SteamPeer] is up, that session closes and the scene loads again, joining the new lobby as it enters the tree;
## anywhere else (a title screen) a [LobbyExplorer] in the tree loads its world, as for a lobby from its list.

signal steam_ready ## Emitted once Steam is up and [member steam_id] and [member username] are filled.
signal steam_failed(reason: String) ## Steam is absent, not running, or refused to initialise.

const CHAT_ROOM_ENTER_RESPONSE_SUCCESS: int = 1 ## Steam's ChatRoomEnterResponse for a lobby joined.

var app_id: int = ProjectSettings.get_setting("steam/initialization/app_data/app_id", 480)
var steam_id: int = 0 ## The signed-in account, 0 when Steam is not running.
var username: String = "Player" ## The Steam persona name, unchanged when Steam is not running.
var lobby_id: int = 0 ## The lobby currently joined; set when Steam reports one joined, cleared by [method SteamPeer.end_session].

var _steam: Object = null ## The singleton, held once Steam is up, so the per-frame pump costs no lookup.
var _invited_lobby: int = 0 ## The lobby an invite asked to join, until Steam reports it joined.


func _ready() -> void:
	set_process(false)
	# The extension has no web library, and Steam wants a desktop renderer.
	if OS.has_feature("web") or ProjectSettings.get_setting("rendering/renderer/rendering_method") != "forward_plus":
		return
	initialize()


## Brings Steamworks up and reads the account off it. Safe to call when Steam is not there; it reports
## through [signal steam_failed] rather than failing.
func initialize() -> void:
	if not Engine.has_singleton("Steam"):
		steam_failed.emit("The GodotSteam extension is not installed.")
		return
	var steam: Object = Engine.get_singleton("Steam")
	if not steam.isSteamRunning():
		steam_failed.emit("The Steam client is not running.")
		return
	var result: Dictionary = steam.steamInitEx(app_id, true)
	if result.get("status", -1) != steam.get("STEAM_API_INIT_RESULT_OK"):
		steam_failed.emit("Steam refused to initialise: %s" % result.get("verbal", ""))
		return
	steam_id = steam.getSteamID()
	username = steam.getPersonaName()
	_steam = steam
	steam.connect(&"join_requested", _on_join_requested)
	steam.connect(&"lobby_joined", _on_lobby_joined)
	set_process(true)
	steam_ready.emit()
	var invited: int = lobby_in_command_line(OS.get_cmdline_args())
	if invited != 0:
		_on_join_requested(invited, 0)


## The lobby a Steam invite launched the game into: the id after [code]+connect_lobby[/code], or 0.
static func lobby_in_command_line(args: PackedStringArray) -> int:
	var at: int = args.find("+connect_lobby")
	return args[at + 1].to_int() if at >= 0 and at + 1 < args.size() else 0


## An invite accepted in the overlay, or the one the game was launched by: leaves the lobby we are in and joins it.
func _on_join_requested(lobby: int, _friend_id: int) -> void:
	if _steam == null or lobby == 0 or lobby == lobby_id:
		return
	if lobby_id != 0:
		_steam.leaveLobby(lobby_id)
		lobby_id = 0
	_invited_lobby = lobby
	_steam.joinLobby(lobby)


## Steam joined a lobby, whoever asked for it. The invite's lobby moves a world that is up into it: its session
## closes and the scene loads again, and its [SteamPeer] joins the new lobby as it readies.
func _on_lobby_joined(lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		return
	lobby_id = lobby
	if lobby != _invited_lobby:
		return
	_invited_lobby = 0
	var steam_peer: SteamPeer = SteamPeer.find_in(get_tree())
	if steam_peer == null:
		return
	if steam_peer.has_session():
		steam_peer.multiplayer.multiplayer_peer.close()
	steam_peer.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().reload_current_scene()


## Steamworks hands its answers back through callbacks, and nothing arrives until they are run. Without this
## the session comes up and then never advances: voice capture reports no data however long the talk key is
## held, and anything else that waits on a callback waits forever. Measured on the Mac, pumping this turned
## getAvailableVoice from 720 frames of NoData into 543 frames of OK with real audio behind it.
func _process(_delta: float) -> void:
	if _steam:
		_steam.run_callbacks()
