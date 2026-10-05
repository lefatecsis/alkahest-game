extends GutTest

## Purpose: the pause menu pauses the scene tree only when the Player plays alone: offline (no peer, Steam not
## loaded) and as a connected host nobody has joined. A client never pauses the world, a peer joining a paused
## host resumes it with the menu still up, a sub-menu opened from Pause keeps the pause until it closes, closing
## resumes, and a menu freed while paused resumes. Restart shows only while playing alone. Two branches over ENet on
## localhost stand in for the Steam session. The menus also cope with no "start" action (a title screen with no
## Player), and a Player freed in the frame it spawned takes its menu screens with it.

const PORT: int = 47397
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await wait_physics_frames(2)


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	PlayerMenuLayer._time_scale_before_freeze = -1.0
	if is_instance_valid(root):
		root.free()
		root = null


func test_offline_the_pause_menu_pauses_the_world_and_resume_runs_it_again() -> void:
	assert_true(player.pause.pauses_world, "pause.tscn pauses the world")
	assert_true(player.pause.is_single_player(), "No peer means playing alone")
	assert_eq(player.pause.process_mode, Node.PROCESS_MODE_ALWAYS, "The menu keeps working while the tree is paused")
	player.pause.show_menu()
	assert_true(player.pause.restart_button.visible, "Alone, Restart is offered")
	assert_true(get_tree().paused, "The world stands still")
	assert_true(player.is_paused)
	assert_eq(Engine.time_scale, 0.0, "and so does the engine clock, which stops shaders, particles and tweens")
	player.pause.hide_menu()
	assert_false(get_tree().paused, "Resume runs it again")
	assert_false(player.is_paused)
	assert_eq(Engine.time_scale, 1.0, "with the clock back")


func test_freezing_time_remembers_the_scale_it_found() -> void:
	Engine.time_scale = 0.5
	player.pause.show_menu()
	assert_eq(Engine.time_scale, 0.0)
	player.pause.hide_menu()
	assert_eq(Engine.time_scale, 0.5, "A slow-motion effect in force comes back as it was")
	PlayerMenuLayer.thaw_time()
	assert_eq(Engine.time_scale, 0.5, "A thaw with nothing frozen changes nothing")


func test_a_sub_menu_opened_from_pause_keeps_the_world_paused_until_it_closes() -> void:
	player.pause.show_menu()
	player.pause._on_settings_pressed()
	assert_false(player.pause.visible)
	assert_true(player.settings.visible)
	assert_true(get_tree().paused, "Settings opened from Pause keeps the pause")
	assert_eq(Engine.time_scale, 0.0, "and the frozen clock")
	assert_false(player.settings.pauses_world, "though Settings on its own would not pause")
	player.settings.hide_menu()
	assert_false(get_tree().paused, "Closing the sub-menu resumes")
	assert_eq(Engine.time_scale, 1.0, "clock included")


func test_a_menu_freed_while_paused_lets_the_world_go() -> void:
	player.pause.show_menu()
	assert_true(get_tree().paused)
	root.free()
	root = null
	assert_false(get_tree().paused, "The Player despawning (a scene change) never leaves the tree paused")
	assert_eq(Engine.time_scale, 1.0, "nor the clock frozen")


func test_only_a_connected_host_alone_pauses_and_a_joining_peer_resumes() -> void:
	var server_root := Node3D.new()
	server_root.name = "ServerBranch"
	var client_root := Node3D.new()
	client_root.name = "ClientBranch"
	add_child(server_root)
	add_child(client_root)
	var server_api := SceneMultiplayer.new()
	var client_api := SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	get_tree().set_multiplayer(client_api, client_root.get_path())
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PORT), OK, "ENet server should open on localhost")
	server_api.multiplayer_peer = server_peer
	var host: Player = PLAYER_SCENE.instantiate()
	server_root.add_child(host)
	var guest: Player = PLAYER_SCENE.instantiate() # the client's copy of the host's player, at the same path
	client_root.add_child(guest)
	await wait_physics_frames(2)
	assert_true(host.pause.is_single_player(), "A connected host with nobody joined plays alone")
	host.pause.show_menu()
	assert_true(get_tree().paused, "so the pause menu pauses the world")

	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PORT), OK)
	client_api.multiplayer_peer = client_peer
	for i in 120:
		await wait_process_frames(1)
		if client_api.get_peers().size() > 0 and server_api.get_peers().size() > 0:
			break
	assert_gt(server_api.get_peers().size(), 0, "The client joins")
	assert_false(get_tree().paused, "A peer joining resumes the world")
	assert_eq(Engine.time_scale, 1.0, "clock and all")
	assert_true(host.pause.visible, "with the menu still up")
	assert_false(host.pause.is_single_player(), "and the host is no longer alone")
	host.pause.hide_menu()
	host.pause.show_menu()
	assert_false(get_tree().paused, "Pausing again in company only pauses the Player")
	assert_true(host.is_paused)
	assert_false(host.pause.restart_button.visible, "Restart would reload the host's world under its clients, so it is gone")
	host.pause.hide_menu()

	assert_false(guest.pause.is_single_player(), "A client is never alone")
	guest.pause.show_menu()
	assert_false(get_tree().paused, "so its pause menu never pauses the world")
	assert_false(guest.pause.restart_button.visible, "and a client never restarts, which would leave it with no Player")
	guest.pause.hide_menu()

	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	server_api.multiplayer_peer.close()
	client_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)


## Unstuck is the Player's own warp home, the one respawn uses.
func test_unstuck_warps_the_player_back_to_where_it_started() -> void:
	var home: Transform3D = player.respawn_transform
	player.global_position += Vector3(5.0, 3.0, -2.0)
	player.velocity = Vector3(1.0, 2.0, 3.0)
	var pause: Node = player.pause
	pause._on_unstuck_pressed()
	assert_true(player.global_transform.is_equal_approx(home), "Back at the start")
	assert_eq(player.velocity, Vector3.ZERO, "and still")


## While a menu holds the engine clock at zero, a Player that still gets a physics frame (a client's, or one under an
## always-processing parent) must neither move nor divide its root motion by the zero delta.
func test_a_frozen_frame_moves_nothing_and_raises_no_error() -> void:
	await wait_physics_frames(2)
	var before: Transform3D = player.global_transform
	player._physics_process(0.0)
	assert_true(player.global_transform.is_finite(), "No NaN from dividing by a zero delta")
	assert_true(player.global_transform.is_equal_approx(before), "and nothing moved")


func test_a_tree_resumed_behind_the_menus_back_thaws_the_clock_next_frame() -> void:
	player.pause.show_menu()
	assert_eq(Engine.time_scale, 0.0)
	get_tree().paused = false # not through the menu
	await wait_process_frames(2)
	assert_eq(Engine.time_scale, 1.0, "A running tree never keeps a frozen clock")
	player.pause.hide_menu()



## A title screen shows the settings pages with no Player, where the controls addon may never have registered
## "start": the menus check for the action before asking about it, rather than erroring on every key.
func test_the_menus_ask_nothing_of_a_start_action_that_does_not_exist() -> void:
	var events: Array[InputEvent] = InputMap.action_get_events(&"start") if InputMap.has_action(&"start") else []
	if InputMap.has_action(&"start"):
		InputMap.erase_action(&"start")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	player.pause._input(key)
	player.settings.show_menu()
	player.settings._input(key)
	assert_true(player.settings.visible, "Nothing happened, and nothing errored")
	player.settings.hide_menu()
	InputMap.add_action(&"start")
	for event: InputEvent in events:
		InputMap.action_add_event(&"start", event)


## The pause menu's screens (inventory, spells, quests) join the Player as it readies. A deferred add was dropped
## for a Player freed before the frame ended, and its screens were left orphaned.
func test_a_player_freed_as_it_spawns_leaves_no_menu_screens_behind() -> void:
	await wait_process_frames(1)
	var before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var brief: Player = PLAYER_SCENE.instantiate()
	root.add_child(brief)
	assert_not_null(brief.pause.quests_screen, "The screens exist")
	assert_eq(brief.pause.quests_screen.get_parent(), brief, "and are the Player's already")
	brief.free()
	await wait_process_frames(1)
	assert_eq(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), before, "Nothing is left orphaned")
