extends GutTest

const PLAYER_SCENE = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CONTROLS_SCENE = preload("res://addons/3d_player_controller/scenes/ui/player_controls.tscn")
const AUDIO_SETTINGS_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/audio_settings.tscn")


func test_broadcast_action_in_input_map() -> void:
	var controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(controls)

	assert_true(InputMap.has_action("broadcast"), "InputMap should have 'broadcast' action")

	var events = InputMap.action_get_events("broadcast")
	var has_key_v: bool = false
	var has_key_t: bool = false
	for event in events:
		if event is InputEventKey and event.physical_keycode == KEY_V:
			has_key_v = true
		if event is InputEventKey and event.physical_keycode == KEY_T:
			has_key_t = true
	assert_true(has_key_v, "'broadcast' action should be mapped to physical key V")
	assert_false(has_key_t, "T belongs to throw, not push-to-talk")


func test_player_voice_chat_nodes_and_default_state() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	assert_not_null(player.voice_chat.indicator, "VoiceChatIndicator should exist on Player")
	assert_false(player.voice_chat.indicator.visible, "VoiceChatIndicator should be hidden by default")
	assert_not_null(player.voice_chat.audio_player, "VoiceAudioPlayer should exist on Player")
	assert_eq(player.voice_chat.audio_player.playback_type, AudioServer.PLAYBACK_TYPE_STREAM, "Voice is streamed, so the web build can play it too")
	assert_false(player.voice_chat.is_broadcasting, "is_broadcasting should be false by default")


func test_player_broadcasting_indicator_toggle() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	player.voice_chat.start_broadcasting()
	assert_true(player.voice_chat.is_broadcasting, "Player is_broadcasting should be true after start_broadcasting()")
	assert_true(player.voice_chat.indicator.visible, "VoiceChatIndicator should be visible when broadcasting")

	player.voice_chat.stop_broadcasting()
	assert_false(player.voice_chat.is_broadcasting, "Player is_broadcasting should be false after stop_broadcasting()")
	assert_false(player.voice_chat.indicator.visible, "VoiceChatIndicator should be hidden when not broadcasting")


func test_voice_bus_exists_and_the_voice_player_uses_it() -> void:
	assert_ne(AudioServer.get_bus_index(&"Voice"), -1, "The Voice bus comes from default_bus_layout.tres (and Audio.BUSES creates it for projects without one)")
	assert_true(Audio.BUSES.has(&"Voice"), "Audio creates the Voice bus when a project's layout lacks it")
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	assert_eq(player.voice_chat.audio_player.bus, &"Voice", "Voice playback runs on its own bus so it has its own volume and mute")


func test_voice_settings_show_with_steam_and_hide_without() -> void:
	var with_steam: PlayerMenuLayer = partial_double(AUDIO_SETTINGS_SCENE).instantiate()
	stub(with_steam, "is_steam_loaded").to_return(true)
	add_child_autofree(with_steam)
	assert_true(with_steam.voice_settings.visible, "With Steam the Voice row and mute toggle show")
	assert_not_null(with_steam.get_node_or_null("Panel/VBoxContainer/VoiceSettings/Voice/VolumeSlider"), "The Voice row has a slider like the other rows")
	assert_not_null(with_steam.get_node_or_null("Panel/VBoxContainer/VoiceSettings/MuteVoice/TouchScreenButton"), "The mute toggle has a touch button")

	var without_steam: PlayerMenuLayer = partial_double(AUDIO_SETTINGS_SCENE).instantiate()
	stub(without_steam, "is_steam_loaded").to_return(false)
	add_child_autofree(without_steam)
	assert_false(without_steam.voice_settings.visible, "Without Steam there is no voice chat, so the rows hide")


## Only the owning peer ever sends its voice and its speaking indicator, so the RPCs are the authority's.
func test_voice_rpcs_are_sent_by_the_authority_alone() -> void:
	var config: Dictionary = (load("res://addons/3d_player_controller/scripts/voice_chat.gd") as Script).get_rpc_config()
	assert_eq(config["_receive_voice_packet"]["rpc_mode"], MultiplayerAPI.RPC_MODE_AUTHORITY)
	assert_eq(config["_receive_voice_packet"]["transfer_mode"], MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, "The other flags are as they were")
	assert_eq(config["_set_voice_indicator"]["rpc_mode"], MultiplayerAPI.RPC_MODE_AUTHORITY)
	assert_false(config["_set_voice_indicator"]["call_local"])


func test_voice_reaches_steam_only_while_the_session_is_up() -> void:
	# The client running is not the session: getVoiceOptimalSampleRate errors until Steamworks has initialised
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	var signed_in: int = steamworks.get("steam_id") if steamworks else 0
	if steamworks:
		steamworks.set("steam_id", 0)
	var player: Player = preload("res://addons/3d_player_controller/scenes/player.tscn").instantiate()
	add_child_autofree(player)
	assert_null(SteamPeer.session(player.voice_chat), "No session, no Steam for the voice code")
	if steamworks:
		steamworks.set("steam_id", signed_in)


## Stands in for GodotSteam's voice calls: records whether the capture is on.
class FakeVoiceSteam:
	extends RefCounted

	var recording: bool = false
	var stops: int = 0

	func startVoiceRecording() -> void:
		recording = true

	func stopVoiceRecording() -> void:
		recording = false
		stops += 1

	func getAvailableVoice() -> Dictionary:
		return {"result": VoiceChat.STEAM_VOICE_RESULT_OK, "size": 0}

	func getSteamID() -> int:
		return 0


func after_each() -> void:
	SteamPeer.steam_override = null


func test_letting_go_of_the_talk_key_behind_a_menu_closes_the_channel() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.voice_chat.start_broadcasting()
	player.is_paused = true
	var release: InputEventAction = InputEventAction.new()
	release.action = &"broadcast"
	release.pressed = false
	player.voice_chat._unhandled_input(release)
	assert_false(player.voice_chat.is_broadcasting, "The release gets past the pause gate; only a press is held back")
	var press: InputEventAction = release.duplicate()
	press.pressed = true
	player.voice_chat._unhandled_input(press)
	assert_false(player.voice_chat.is_broadcasting, "A press behind the menu still opens nothing")
	player.is_paused = false


func test_opening_the_chat_row_closes_the_channel() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var chat: Node = player.get_node("Hud/Chat")
	player.voice_chat.start_broadcasting()
	chat.typing_changed.emit(true)
	assert_false(player.voice_chat.is_broadcasting, "The chat row is a Window of its own, so the talk key's release never arrives; opening it closes the channel")
	chat.typing_changed.emit(false)


func test_steam_capture_stops_when_push_to_talk_ends() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	var was: bool = settings.voice_activation
	settings.voice_activation = false
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var steam: FakeVoiceSteam = FakeVoiceSteam.new()
	SteamPeer.steam_override = steam # after the Player is in, so its _ready does not ask this fake for a persona
	player.voice_chat.start_broadcasting()
	player.voice_chat._process(0.0)
	assert_true(steam.recording, "Holding the talk key captures")
	player.voice_chat.stop_broadcasting()
	player.voice_chat._process(0.0)
	assert_false(steam.recording, "Letting go stops Steam's capture, or it buffers whatever is said next and sends it on the next press")
	assert_eq(steam.stops, 1)
	settings.voice_activation = was
