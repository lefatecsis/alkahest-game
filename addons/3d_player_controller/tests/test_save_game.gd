extends GutTest

## Purpose: A SaveGame node writes every Saveable's state to one file and reads it back: the Player's position,
## checkpoint, pools and inventory, plus whatever else joined the group. The file is plain JSON of one version,
## with no object in it, and anything else (an old .tres save, another version) is refused. The pause menu shows
## Save and Load only while a SaveGame is in the scene, checkpoints and the autosave timer write on their own, and
## a title screen's Continue request loads once the Player is in, including a Player spawned by a PlayerSpawner
## that sits before the SaveGame and spawns in its own _ready.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const SAVE_GAME_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/save_game.tscn")
const CHECKPOINT_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/prop/checkpoint.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")
const APPLE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/apple.tres")
const SWORD: Item = preload("res://addons/3d_player_controller/inventory/resources/items/wooden_sword.tres")
const TEST_PATH: String = "user://test_savegame.json"
const TEST_CLIENT_PATH: String = "user://test_savegame_client.json"

var root: Node3D
var player: Player
var saver: SaveGame


func before_each() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(60.0, 1.0, 60.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	root.add_child(player)
	saver = SAVE_GAME_SCENE.instantiate()
	saver.save_path = TEST_PATH
	root.add_child(saver)
	await wait_physics_frames(3)


func after_each() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	SaveGame.load_requested = false


func test_nothing_to_load_before_a_save() -> void:
	assert_false(saver.has_save())
	watch_signals(saver)
	assert_false(saver.load_game())
	assert_signal_emitted(saver, "load_failed")


func test_the_player_round_trips_through_the_file() -> void:
	player.warp_to(Transform3D(Basis(), Vector3(5.0, 0.0, -3.0)))
	player.set_checkpoint(Transform3D(Basis(), Vector3(9.0, 0.0, 9.0)))
	player.health.health = 42.0
	player.health.energy = 17.0
	player.enable_stamina = true # off, the bar refills itself every physics frame
	player.stamina.stamina = 33.0
	player.inventory.add_item(APPLE, 3)
	await wait_physics_frames(1)
	watch_signals(saver)
	assert_eq(saver.save_game(), OK)
	assert_signal_emitted(saver, "saved")
	assert_true(saver.has_save())
	var data: Dictionary = saver.read_save()
	assert_eq(data["version"], SaveGame.VERSION)
	assert_true(data["states"].has("Player"), "The Player is keyed by its path from the SaveGame's parent: %s" % data["states"].keys())
	assert_false(str(data["saved_at"]).is_empty())
	var text: String = FileAccess.get_file_as_string(TEST_PATH)
	assert_not_null(JSON.to_native(JSON.parse_string(text)), "Plain JSON that reads back with objects refused, so it holds none")
	assert_string_contains(text, "apple.tres", "The inventory's item is written as its res:// path")

	player.warp_to(Transform3D(Basis(), Vector3.ZERO))
	player.set_checkpoint(Transform3D(Basis(), Vector3.ZERO))
	player.health.health = player.health.max_health
	player.health.energy = player.health.max_energy
	player.stamina.stamina = player.stamina.max_value
	player.inventory.remove_item(APPLE, 3)
	assert_eq(player.inventory.count_of(APPLE), 0)
	assert_true(saver.load_game())
	assert_signal_emitted(saver, "loaded")
	assert_almost_eq(player.global_position, Vector3(5.0, 0.0, -3.0), Vector3.ONE * 0.01)
	assert_almost_eq(player.respawn_transform.origin, Vector3(9.0, 0.0, 9.0), Vector3.ONE * 0.01)
	assert_eq(player.health.health, 42.0)
	assert_eq(player.health.energy, 17.0)
	assert_almost_eq(player.stamina.stamina, 33.0, 2.0, "Stamina is back, give or take a frame of regen")
	assert_eq(player.inventory.count_of(APPLE), 3, "The inventory comes back inside the same file")


## The game's save carries the inventory's weapons as well as its stacks: one with a scene of its own by that scene,
## and one standing in the level as a model file with the Equipment script put on there by the pickup it came from,
## since the model file alone would load back as nothing.
func test_the_inventorys_weapons_round_trip_through_the_file() -> void:
	var model: Node = (load("res://addons/3d_player_controller/assets/quaternius/paraglider/Paraglider.glb") as PackedScene).instantiate()
	model.set_script(load("res://addons/3d_player_controller/scripts/equipment.gd"))
	var axe: Equipment = model as Equipment
	axe.name = "WorldAxe"
	axe.equipment_type = Equipment.EquipmentType.AXE_1H
	axe.bone_attachment_bone_name = "LeftHand"
	root.add_child(axe)
	assert_true(axe.equip(player), "The Player picks up the level's axe")
	player.inventory.add_item(SWORD)
	player.inventory.stow_equipment(player.inventory.get_equipment_by_type(Equipment.EquipmentType.AXE_1H))
	assert_eq(saver.save_game(), OK)
	assert_string_contains(FileAccess.get_file_as_string(TEST_PATH), String(axe.get_path()), "The axe is written as the pickup it came from")
	player.inventory.apply_save(InventorySave.new()) # everything gone
	assert_eq(player.inventory.get_all_weapons().size(), 0)
	assert_true(saver.load_game())
	assert_true(player.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The sword is back in hand")
	var weapons: Array[Equipment] = player.inventory.get_all_weapons()
	assert_eq(weapons.size(), 2, "and the axe is back too")
	var axes: Array[Equipment] = weapons.filter(func(w: Equipment) -> bool: return w.equipment_type == Equipment.EquipmentType.AXE_1H)
	assert_eq(axes.size(), 1)
	if axes.size() == 1:
		assert_false(player.inventory.equipment.has(axes[0]), "stowed, as it was saved")


func test_a_save_taken_dead_comes_back_alive() -> void:
	player.load_state({"health": 0.0})
	assert_eq(player.health.health, player.health.max_health)


func test_any_saveable_in_the_group_is_kept() -> void:
	var counter: SaveableCounter = SaveableCounter.new()
	counter.name = "Counter"
	root.add_child(counter)
	counter.count = 7
	saver.save_game()
	counter.count = 0
	saver.load_game()
	assert_eq(counter.count, 7)
	assert_true(saver.read_save()["states"].has("Counter"))


func test_a_saveable_that_is_gone_is_skipped() -> void:
	var counter: SaveableCounter = SaveableCounter.new()
	counter.name = "Counter"
	root.add_child(counter)
	counter.count = 3
	saver.save_game()
	counter.free()
	assert_true(saver.load_game(), "A missing node is no reason to fail")


func test_a_checkpoint_saves_the_game() -> void:
	var checkpoint: Checkpoint = CHECKPOINT_SCENE.instantiate()
	root.add_child(checkpoint)
	checkpoint.global_position = Vector3(10.0, 0.0, 0.0)
	watch_signals(saver)
	player.warp_to(Transform3D(Basis(), Vector3(10.0, 0.0, 0.0)))
	await wait_physics_frames(3)
	assert_signal_emitted(saver, "saved", "Taking a checkpoint writes the file")
	saver.delete_save()
	assert_false(saver.has_save())
	saver.save_on_checkpoint = false
	player.warp_to(Transform3D(Basis(), Vector3(20.0, 0.0, 0.0)))
	await wait_physics_frames(2)
	player.warp_to(Transform3D(Basis(), Vector3(10.0, 0.0, 0.0)))
	await wait_physics_frames(3)
	assert_false(saver.has_save(), "Turned off, a checkpoint writes nothing")


func test_autosave_writes_on_the_timer() -> void:
	saver.autosave_interval = 0.2
	assert_false(saver.autosave_timer.is_stopped())
	await wait_seconds(0.35)
	assert_true(saver.has_save())
	saver.autosave_interval = 0.0
	assert_true(saver.autosave_timer.is_stopped())


func test_the_pause_menu_offers_save_and_load() -> void:
	player.pause.show_menu()
	assert_true(player.pause.save_button.visible)
	assert_true(player.pause.load_button.visible)
	assert_true(player.pause.load_button.disabled, "Nothing to load yet")
	player.pause._on_save_pressed()
	assert_true(saver.has_save())
	assert_false(player.pause.visible, "Saving closes the menu")
	player.pause.show_menu()
	assert_false(player.pause.load_button.disabled)
	player.pause.hide_menu()


func test_the_pause_menu_hides_them_without_a_save_game() -> void:
	saver.free()
	player.pause.show_menu()
	assert_false(player.pause.save_button.visible)
	assert_false(player.pause.load_button.visible)
	player.pause.hide_menu()


## A host and a client each keep their own save. A client writes its own file, never the single-player one.
func test_a_client_writes_its_own_save_not_the_single_player_one() -> void:
	var branch: Node = Node.new()
	add_child(branch)
	var api: SceneMultiplayer = SceneMultiplayer.new()
	get_tree().set_multiplayer(api, branch.get_path())
	var enet: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(enet.create_client("127.0.0.1", 47435), OK)
	api.multiplayer_peer = enet
	var client_saver: SaveGame = SAVE_GAME_SCENE.instantiate()
	client_saver.save_path = TEST_PATH
	client_saver.client_save_path = TEST_CLIENT_PATH
	branch.add_child(client_saver)
	assert_eq(client_saver.current_path(), TEST_CLIENT_PATH)
	assert_eq(client_saver.save_game(), OK, "A client saves")
	assert_true(FileAccess.file_exists(TEST_CLIENT_PATH), "to its own file")
	assert_false(FileAccess.file_exists(TEST_PATH), "and leaves the single-player save alone")
	DirAccess.remove_absolute(TEST_CLIENT_PATH)
	enet.close()
	var path: NodePath = branch.get_path()
	branch.free()
	get_tree().set_multiplayer(null, path)


func test_a_requested_load_happens_on_ready() -> void:
	player.warp_to(Transform3D(Basis(), Vector3(4.0, 0.0, 4.0)))
	saver.save_game()
	player.warp_to(Transform3D(Basis(), Vector3.ZERO))
	saver.free()
	SaveGame.load_requested = true
	var late: SaveGame = SAVE_GAME_SCENE.instantiate()
	late.save_path = TEST_PATH
	watch_signals(late)
	root.add_child(late)
	await wait_physics_frames(2)
	assert_signal_emitted(late, "loaded")
	assert_false(SaveGame.load_requested, "The request is consumed")
	assert_almost_eq(player.global_position, Vector3(4.0, 0.0, 4.0), Vector3.ONE * 0.01)


## Continue on a world that spawns its Player: the PlayerSpawner sits before the SaveGame and spawns in its own
## _ready, before the SaveGame's, and its local_player_spawned is wired to load_for_player before anything readies,
## as a scene's connection is. The load still happens.
func test_a_requested_load_waits_for_a_spawner_that_comes_first() -> void:
	var first: Node3D = _spawner_world()
	root.add_child(first)
	await wait_physics_frames(2)
	var spawned: Player = first.get_node("PlayerSpawner").get_local_player()
	assert_not_null(spawned, "The spawner spawned this peer's Player")
	spawned.warp_to(Transform3D(Basis(), Vector3(6.0, 0.0, -2.0)))
	assert_eq((first.get_node("SaveGame") as SaveGame).save_game(), OK)
	first.free()

	SaveGame.load_requested = true
	var world: Node3D = _spawner_world()
	var late: SaveGame = world.get_node("SaveGame")
	watch_signals(late)
	root.add_child(world)
	await wait_physics_frames(2)
	assert_signal_emitted(late, "loaded", "The load happened although the spawn came before the SaveGame readied")
	assert_false(SaveGame.load_requested, "The request is consumed")
	var player_now: Player = world.get_node("PlayerSpawner").get_local_player()
	assert_almost_eq(player_now.global_position, Vector3(6.0, 0.0, -2.0), Vector3.ONE * 0.01)


## A world with the spawner ahead of the SaveGame, the spawner's local_player_spawned wired to it before either readies.
func _spawner_world() -> Node3D:
	var world: Node3D = Node3D.new()
	world.name = "World"
	var spawner: PlayerSpawner = PLAYER_SPAWNER.new()
	spawner.name = "PlayerSpawner"
	spawner.add_child(PLAYER_SCENE.instantiate())
	world.add_child(spawner)
	var world_saver: SaveGame = SAVE_GAME_SCENE.instantiate()
	world_saver.name = "SaveGame"
	world_saver.save_path = TEST_PATH
	world.add_child(world_saver)
	spawner.local_player_spawned.connect(world_saver.load_for_player)
	return world


## A save from before the format changed (a SaveGameData .tres) is refused, not loaded through ResourceLoader.
func test_an_old_resource_save_is_refused() -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string('[gd_resource type="Resource" format=3]

[resource]
version = 1
states = {}
')
	file.close()
	watch_signals(saver)
	assert_false(saver.load_game())
	assert_signal_emitted(saver, "load_failed")
	assert_true(saver.read_save().is_empty())


## A save of another version is left alone rather than guessed at.
func test_another_version_is_refused() -> void:
	player.warp_to(Transform3D(Basis(), Vector3(3.0, 0.0, 3.0)))
	saver.save_game()
	var data: Variant = JSON.to_native(JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH)))
	data["version"] = SaveGame.VERSION + 1
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(JSON.from_native(data)))
	file.close()
	player.warp_to(Transform3D(Basis(), Vector3.ZERO))
	assert_false(saver.load_game(), "A newer file is refused")
	assert_almost_eq(player.global_position, Vector3.ZERO, Vector3.ONE * 0.01, "and nothing of it applied")


## The default path is a static var a test run can point elsewhere; new SaveGames and has_save_at follow it.
func test_the_default_path_can_be_redirected() -> void:
	var was: String = SaveGame.DEFAULT_SAVE_PATH
	SaveGame.DEFAULT_SAVE_PATH = TEST_PATH
	var redirected: SaveGame = SAVE_GAME_SCENE.instantiate()
	assert_eq(redirected.save_path, TEST_PATH, "A new SaveGame takes the redirected default")
	redirected.free()
	saver.save_game()
	assert_true(SaveGame.has_save_at(), "and has_save_at looks there by default")
	SaveGame.DEFAULT_SAVE_PATH = was


class SaveableCounter extends Node:
	var count: int = 0

	func _ready() -> void:
		add_to_group(SaveGame.GROUP)

	func save_state() -> Dictionary:
		return {"count": count}

	func load_state(state: Dictionary) -> void:
		count = int(state.get("count", 0))


## A spawned Player is named after its peer id, which the next session will not repeat, so it is saved under
## PLAYER_KEY and loads back into whichever Player this peer owns then.
func test_a_spawned_player_is_saved_under_a_key_its_next_session_can_find() -> void:
	player.name = "1" # what a PlayerSpawner names the host's
	player.health.health = 40.0
	var states: Dictionary = saver.collect_states()
	assert_true(states.has(SaveGame.PLAYER_KEY), "Keyed by PLAYER_KEY, not by its path")
	player.health.health = player.health.max_health
	saver.apply_states(states)
	assert_eq(player.health.health, 40.0, "and applied to this peer's own Player")



## A save taken in another level brings the Player's health and inventory but not its place: it stays where this
## level put it.
func test_a_save_from_another_level_brings_the_things_not_the_place() -> void:
	player.name = "1" # spawned, as in a networked game
	player.warp_to(Transform3D(Basis(), Vector3(8.0, 0.0, 8.0)))
	player.health.health = 40.0
	player.inventory.add_item(APPLE, 3)
	assert_eq(saver.save_game(), OK)
	var data: Variant = JSON.to_native(JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH)))
	data["scene_path"] = "res://some/other_level.tscn"
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(JSON.from_native(data)))
	file.close()
	player.warp_to(Transform3D(Basis(), Vector3(-2.0, 0.0, 1.0)))
	player.health.health = player.health.max_health
	player.inventory.remove_item(APPLE, 3)
	assert_true(saver.load_game())
	assert_eq(player.health.health, 40.0, "The health comes along")
	assert_eq(player.inventory.count_of(APPLE), 3, "and the inventory")
	assert_almost_eq(player.global_position, Vector3(-2.0, 0.0, 1.0), Vector3.ONE * 0.01, "but the Player stays at this level's spawn")


## A friend joining a game brings their things with them: as a client's Player spawns, its own save loads without
## anyone picking Continue, and in the same level it puts them back where they were.
func test_a_client_loads_its_own_save_as_it_joins() -> void:
	var branch: Node3D = Node3D.new()
	add_child(branch)
	var api: SceneMultiplayer = SceneMultiplayer.new()
	get_tree().set_multiplayer(api, branch.get_path())
	var enet: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(enet.create_client("127.0.0.1", 47436), OK)
	api.multiplayer_peer = enet
	var client_player: Player = PLAYER_SCENE.instantiate()
	client_player.name = str(api.get_unique_id())
	client_player.set_multiplayer_authority(api.get_unique_id())
	branch.add_child(client_player)
	var client_saver: SaveGame = SAVE_GAME_SCENE.instantiate()
	client_saver.save_path = TEST_PATH
	client_saver.client_save_path = TEST_CLIENT_PATH
	branch.add_child(client_saver)
	await wait_physics_frames(2)
	client_player.warp_to(Transform3D(Basis(), Vector3(3.0, 0.0, -4.0)))
	client_player.health.health = 25.0
	assert_eq(client_saver.save_game(), OK)
	client_player.warp_to(Transform3D(Basis(), Vector3.ZERO))
	client_player.health.health = client_player.health.max_health
	watch_signals(client_saver)
	assert_false(SaveGame.load_requested, "Nobody picked Continue")
	client_saver.load_for_player(client_player)
	await wait_process_frames(2)
	assert_signal_emitted(client_saver, "loaded", "The client's own save loads as its Player comes in")
	assert_eq(client_player.health.health, 25.0, "with its health")
	assert_almost_eq(client_player.global_position.x, 3.0, 0.05, "and, in the same level, where it stood")
	DirAccess.remove_absolute(TEST_CLIENT_PATH)
	enet.close()
	var path: NodePath = branch.get_path()
	branch.free()
	get_tree().set_multiplayer(null, path)


## Single player waits for Continue: a New Game's Player does not pick up an old save on its own.
func test_single_player_does_not_load_without_continue() -> void:
	assert_eq(saver.save_game(), OK)
	watch_signals(saver)
	saver.load_for_player(player)
	await wait_process_frames(2)
	assert_signal_not_emitted(saver, "loaded")

#region Numbered saves

const TEST_SAVES_DIR: String = "user://test_saves"


func _with_slots() -> String:
	var was: String = SaveGame.SAVES_DIR
	SaveGame.SAVES_DIR = TEST_SAVES_DIR
	_clear_slots()
	return was


func _without_slots(was: String) -> void:
	_clear_slots()
	SaveGame.SAVES_DIR = was
	SaveGame.slot = 0


## Empties the test saves folder. A fresh machine (CI) has no such folder before the first save, and
## listing a folder that is not there logs an engine error, which GUT counts as a failure.
func _clear_slots() -> void:
	if not DirAccess.dir_exists_absolute(TEST_SAVES_DIR):
		return
	for file: String in DirAccess.get_files_at(TEST_SAVES_DIR):
		DirAccess.remove_absolute(TEST_SAVES_DIR.path_join(file))


func test_each_numbered_save_is_its_own_file_with_its_level() -> void:
	var was: String = _with_slots()
	SaveGame.slot = 2
	assert_eq(saver.current_path(), SaveGame.slot_path(2), "Save 2 writes its own file")
	assert_eq(saver.save_game(), OK)
	SaveGame.slot = 1
	assert_eq(saver.save_game(), OK)
	var saves: Array[Dictionary] = SaveGame.list_saves()
	assert_eq(saves.size(), 2, "Both are listed")
	assert_eq(int(saves[0]["slot"]), 1, "lowest first")
	assert_eq(saves[1]["path"], SaveGame.slot_path(2))
	assert_true(saves[0].has("saved_at") and saves[0].has("scene_path") and saves[0].has("level_name"), "each with when and where it was taken")
	assert_eq(SaveGame.next_free_slot(), 3, "A new game takes the next number free")
	_without_slots(was)


func test_a_save_keeps_its_preview_beside_it() -> void:
	var was: String = _with_slots()
	SaveGame.slot = 1
	var picture: Image = Image.create_empty(64, 36, false, Image.FORMAT_RGB8)
	picture.fill(Color.CORNFLOWER_BLUE)
	saver.set_preview(picture)
	assert_eq(saver.save_game(), OK)
	assert_true(FileAccess.file_exists(SaveGame.preview_path(1)), "The preview is written beside the save")
	var written: Image = Image.load_from_file(ProjectSettings.globalize_path(SaveGame.preview_path(1)))
	assert_eq(written.get_size(), SaveGame.PREVIEW_SIZE, "at the preview's size")
	saver.delete_save()
	assert_false(FileAccess.file_exists(SaveGame.preview_path(1)), "and goes with it")
	_without_slots(was)


func test_no_saves_folder_yet_lists_nothing_quietly() -> void:
	var was: String = SaveGame.SAVES_DIR
	SaveGame.SAVES_DIR = "user://no_such_saves_folder"
	assert_eq(SaveGame.list_saves().size(), 0, "Before the first save there is nothing to list")
	assert_eq(SaveGame.next_free_slot(), 1, "and a new game takes save 1")
	assert_engine_error_count(0, "without an error for the folder not being there")
	SaveGame.SAVES_DIR = was


func test_the_level_name_reads_well() -> void:
	assert_eq(SaveGame.level_name_of("res://scenes/snow_demo.tscn"), "Snow Demo")
	assert_eq(SaveGame.level_name_of("res://scenes/world.tscn"), "World")


func test_the_player_comes_back_facing_the_way_it_was() -> void:
	var facing: Basis = Basis(Vector3.UP, deg_to_rad(120.0))
	player.player_model.global_basis = facing
	player.orientation.basis = facing
	player.camera_mount.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(75.0), 0.0)
	assert_eq(saver.save_game(), OK)
	player.player_model.global_basis = Basis()
	player.camera_mount.rotation = Vector3.ZERO
	assert_true(saver.load_game())
	assert_almost_eq(player.player_model.global_basis.z.angle_to(facing.z), 0.0, 0.01, "The model faces the way it did")
	assert_almost_eq(player.camera_mount.rotation.y, deg_to_rad(75.0), 0.001, "and the camera looks where it did")
	assert_almost_eq(player.camera_mount.rotation.x, deg_to_rad(-20.0), 0.001)

#endregion
