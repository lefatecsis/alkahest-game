extends GutTest

const LOBBY_EXPLORER_SCENE = preload("res://addons/3d_player_controller/scenes/ui/lobby_explorer.tscn")
const LOBBY_EXPLORER_ENTRY_SCENE = preload("res://addons/3d_player_controller/scenes/ui/lobby_explorer_entry.tscn")


func test_lobby_explorer_initial_nodes() -> void:
	var explorer = LOBBY_EXPLORER_SCENE.instantiate()
	add_child_autofree(explorer)

	assert_not_null(explorer.host_button, "Host button should exist")
	assert_not_null(explorer.refresh_button, "Refresh button should exist")
	assert_not_null(explorer.back_button, "Back button should exist")
	assert_not_null(explorer.status_label, "StatusLabel should exist")
	assert_not_null(explorer.lobby_list, "LobbyList should exist")
	assert_not_null(explorer.distance_option, "DistanceOption should exist")
	assert_not_null(explorer.label_version, "Label_Version should exist")
	assert_not_null(explorer.label_copyright, "Label_Copyright should exist")
	assert_eq(explorer.distance_option.item_count, 4, "Distance options come from the scene")
	assert_eq(explorer.world_scene, "", "The addon scene should not hard-code a project world scene")
	assert_eq(explorer.title_scene, "", "The addon scene should not hard-code a project title scene")


func test_lobby_explorer_version_and_footer_format() -> void:
	var explorer = LOBBY_EXPLORER_SCENE.instantiate()
	explorer.footer_text = "© Test"
	add_child_autofree(explorer)

	var version: String = ProjectSettings.get_setting("application/config/version", "")
	var expected_version: String = version if version.begins_with("v") else "v" + version
	assert_eq(explorer.label_version.text, expected_version, "Version label should match app config")

	var current_year: int = Time.get_date_dict_from_system().year
	assert_eq(explorer.label_copyright.text, "© Test %d" % current_year, "Footer label should append the current year")


func test_lobby_explorer_empty_footer_hides_text() -> void:
	var explorer = LOBBY_EXPLORER_SCENE.instantiate()
	add_child_autofree(explorer)
	assert_eq(explorer.label_copyright.text, "", "Empty footer_text should leave the label empty")


func test_lobby_explorer_entry_initial_state_and_signal() -> void:
	var entry = LOBBY_EXPLORER_ENTRY_SCENE.instantiate()
	add_child_autofree(entry)
	watch_signals(entry)

	entry.set_lobby_id(123456789)
	assert_eq(entry.lobby_id, 123456789, "Lobby ID should be stored")
	assert_eq(entry.name_label.text, "Lobby 123456789", "Without Steam the entry shows the lobby id")

	entry.join_button.pressed.emit()
	assert_signal_emitted_with_parameters(entry, "join_requested", [123456789], 0)


func test_the_entry_reads_nothing_from_steam_until_the_session_is_up() -> void:
	# CI loads the GodotSteam extension with no client behind it, and every lobby call errors there
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	var signed_in: int = steamworks.get("steam_id") if steamworks else 0
	if steamworks:
		steamworks.set("steam_id", 0)
	var entry = LOBBY_EXPLORER_ENTRY_SCENE.instantiate()
	add_child_autofree(entry)
	entry.set_lobby_id(5)
	assert_null(SteamPeer.session(entry), "The extension being loaded is not a session")
	assert_eq(entry.name_label.text, "Lobby 5", "so the entry shows the id and asks Steam nothing")
	if steamworks:
		steamworks.set("steam_id", signed_in)


func test_the_explorer_asks_steam_for_nothing_until_the_session_is_up() -> void:
	# The client running is not the session: headless and CI load the extension with Steamworks never initialised
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	var signed_in: int = steamworks.get("steam_id") if steamworks else 0
	if steamworks:
		steamworks.set("steam_id", 0)
	var explorer = LOBBY_EXPLORER_SCENE.instantiate()
	add_child_autofree(explorer)
	assert_null(SteamPeer.session(explorer))
	assert_true(explorer.host_button.disabled, "Hosting is off")
	assert_true(explorer.refresh_button.disabled, "and so is the list")
	assert_eq(explorer.status_label.text, "Steam is not running. Lobby features disabled.")
	explorer.refresh_lobbies()
	assert_eq(explorer.status_label.text, "Steam is not running. Lobby features disabled.", "A refresh asks nothing either")
	if steamworks:
		steamworks.set("steam_id", signed_in)
