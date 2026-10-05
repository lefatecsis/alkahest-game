class_name SaveGame
extends Node
## Saves and loads the game. Drop one in the world: every node in the [code]Saveable[/code] group that implements
## [code]save_state() -> Dictionary[/code] and [code]load_state(state: Dictionary)[/code] is written to
## [member save_path] under its path, and read back into whichever of those nodes are still there. The Player saves
## itself (position, checkpoint, health, the whole inventory); a world adds its clock, its weather, its enemies,
## whatever else it wants kept, by joining the group.
##
## The file is plain JSON text: a [constant VERSION], when and where it was taken, and the states. Nothing in it is
## an object. A Resource a state holds is written as its [code]res://[/code] path, or, for one made at run time (an
## inventory's save), as its script's path and its stored properties, so reading a save back only ever loads the
## game's own files and never runs anything the file brought with it. A file of another version, or one that is not
## this format (the [code].tres[/code] saves of old), is refused rather than guessed at.
##
## [method save_game] is the pause menu's Save, [member autosave_interval] writes on the AutosaveTimer, and with
## [member save_on_checkpoint] every [Checkpoint] writes as it is taken. A title screen's Continue sets
## [member load_requested] before the world loads; the SaveGame loads once this peer's Player is in. A world that
## spawns its Players wires its [PlayerSpawner]'s local_player_spawned to [method load_for_player] in the scene; a
## Player standing in the scene is there already. Over the network every peer keeps its own save of what it owns: the
## host (and single player) in [member save_path], a client in [member client_save_path], so joining a friend's game
## never writes over the single-player save. A spawned Player is keyed [constant PLAYER_KEY] rather than by its peer
## id, which the next session will not repeat. In a networked game every peer loads its own save as its Player comes
## in, no Continue needed, so a friend joining brings their inventory, health and quests along.
##
## A save taken in another level brings the Player's things but not its place: [constant PLACE_KEYS] are left out, so
## the Player stays where the level spawned it, and the other Saveables, which belong to that other level, are skipped.
##
## Several saves, Minecraft style: set [member slot] and the host writes [code]user://saves/slot_N.json[/code] instead of
## [member save_path], with a preview [code]slot_N.png[/code] beside it (the frame [method capture_preview] took, which the
## pause menu does as it opens so the preview never shows the menu). The file keeps the level it was taken in, so a
## title screen lists them with [method list_saves] and loads the one picked into its own level.

signal saved(path: String) ## The file was written.
signal loaded(path: String) ## The file was read and applied.
signal load_failed(path: String) ## There was no file, or it could not be read.

const GROUP: StringName = &"Saveable"
const VERSION: int = 2 ## The file format; 1 was the SaveGameData resource, which is no longer read.
const PLAYER_KEY: String = "@player" ## The key this peer's own spawned Player is saved under, whatever its peer id.
const PLACE_KEYS: PackedStringArray = ["transform", "respawn_transform", "facing", "camera_rotation"] ## A Player's state that only means something in the level it was saved in.

static var DEFAULT_SAVE_PATH: String = "user://savegame.json" ## Where a SaveGame writes unless told otherwise; a test run points it elsewhere.
static var DEFAULT_CLIENT_SAVE_PATH: String = "user://savegame_client.json" ## Where a client in somebody else's game writes.
static var load_requested: bool = false ## Continue was picked: the next SaveGame loads its file once this peer's Player is in.
static var SAVES_DIR: String = "user://saves" ## Where numbered saves live; a test run points it elsewhere.
static var slot: int = 0 ## The numbered save this game writes and reads; 0 keeps to [member save_path].
const PREVIEW_SIZE: Vector2i = Vector2i(480, 270) ## A save's preview, 16:9 like the window it is taken from.

@export var save_path: String = DEFAULT_SAVE_PATH ## The host's and single player's save.
@export var client_save_path: String = DEFAULT_CLIENT_SAVE_PATH ## This peer's save while it is a client in somebody else's game.
@export var autosave_interval: float = 0.0: ## Seconds between automatic writes; zero turns them off.
	set(value):
		autosave_interval = maxf(value, 0.0)
		if is_node_ready():
			_update_timer()
@export var save_on_checkpoint: bool = true ## Write whenever a [Checkpoint] is taken.

@onready var autosave_timer: Timer = $AutosaveTimer ## Its timeout is wired to [method save_game] in the scene.


func _ready() -> void:
	add_to_group(&"SaveGame")
	_update_timer()
	for checkpoint: Node in get_tree().get_nodes_in_group(&"Checkpoint"):
		if checkpoint is Checkpoint:
			watch_checkpoint(checkpoint as Checkpoint)
	# A Player standing in the scene is in already; a spawned one arrives through load_for_player
	for player: Node in get_tree().get_nodes_in_group(&"Player"):
		if player.is_multiplayer_authority():
			load_for_player(player as Player)
			return


## True when a save exists at [param path].
static func has_save_at(path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## The SaveGame in [param tree], or null; the pause menu looks it up this way.
static func find_in(tree: SceneTree) -> SaveGame:
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"SaveGame") as SaveGame


## The file of save number [param number].
static func slot_path(number: int) -> String:
	return SAVES_DIR.path_join("slot_%d.json" % number)


## The preview picture beside save number [param number].
static func preview_path(number: int) -> String:
	return SAVES_DIR.path_join("slot_%d.png" % number)


## Every numbered save, lowest first, each as {slot, path, preview, scene_path, level_name, saved_at}: what a title
## screen needs to list them. A file that is not a save of this version is left out.
static func list_saves() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		return saves # Nothing saved yet; asking for the files of a folder that is not there logs an error
	for file: String in DirAccess.get_files_at(SAVES_DIR):
		if not (file.begins_with("slot_") and file.ends_with(".json")):
			continue
		var number: String = file.trim_prefix("slot_").trim_suffix(".json")
		if not number.is_valid_int():
			continue
		var json: JSON = JSON.new()
		if json.parse(FileAccess.get_file_as_string(SAVES_DIR.path_join(file))) != OK:
			continue
		var native: Variant = JSON.to_native(json.data) # written with from_native, so read back the same way
		if not native is Dictionary:
			continue
		var data: Dictionary = native
		if int(data.get("version", 0)) != VERSION:
			continue
		var scene_path: String = str(data.get("scene_path", ""))
		saves.append({
			"slot": int(number),
			"path": SAVES_DIR.path_join(file),
			"preview": preview_path(int(number)),
			"scene_path": scene_path,
			"level_name": str(data.get("level_name", level_name_of(scene_path))),
			"saved_at": str(data.get("saved_at", "")),
		})
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	return saves


## The lowest save number not yet taken, for a New Game.
static func next_free_slot() -> int:
	var taken: Array[int] = []
	for save: Dictionary in list_saves():
		taken.append(int(save["slot"]))
	var number: int = 1
	while number in taken:
		number += 1
	return number


## A readable name for the level at [param scene_path]: its file name, words capitalised ("snow_demo" is "Snow Demo").
static func level_name_of(scene_path: String) -> String:
	return scene_path.get_file().get_basename().capitalize()


## [member save_path] on the host and in single player, or save number [member slot] when one is set;
## [member client_save_path] on a client.
func current_path() -> String:
	if not multiplayer.is_server():
		return client_save_path
	return slot_path(slot) if slot > 0 else save_path


func has_save() -> bool:
	return has_save_at(current_path())


## Wire a [PlayerSpawner]'s local_player_spawned here in the scene: a Continue waiting on [member load_requested]
## loads once this peer's Player is in, and in a networked game so does any peer that has a save. A connection made in
## the scene exists before any node readies, so it hears the spawn even when the spawner sits earlier in the tree and
## spawns in its own _ready, before this one's.
func load_for_player(_player: Player) -> void:
	if load_requested or (is_networked() and has_save()):
		load_requested = false
		load_game.call_deferred()


## True in a game with other peers in it or on the way: hosting or joining, not single player.
func is_networked() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


## Writes every Saveable this peer owns to [method current_path].
func save_game() -> Error:
	var path: String = current_path()
	var scene: Node = get_tree().current_scene
	var data: Dictionary = {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"scene_path": scene.scene_file_path if scene else "",
		"level_name": level_name_of(scene.scene_file_path) if scene else "",
		"states": to_plain(collect_states()),
	}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var error: Error = FileAccess.get_open_error() if file == null else OK
	if file:
		file.store_string(JSON.stringify(JSON.from_native(data), "\t"))
		error = file.get_error()
		file.close()
	if error == OK:
		_write_preview(path.get_basename() + ".png")
		saved.emit(path)
	else:
		push_error("SaveGame: could not write %s (%s)" % [path, error_string(error)])
	return error


## Takes the frame on screen now as the next save's preview. The pause menu calls it as it opens, before it is drawn,
## so the preview is the game and not the menu. Returns false where there is no frame to take (headless).
func capture_preview() -> bool:
	if DisplayServer.get_name() == "headless":
		return false # Nothing is drawn, and reading the texture only logs an error.
	var viewport: Viewport = get_viewport()
	var texture: ViewportTexture = viewport.get_texture() if viewport else null
	var image: Image = texture.get_image() if texture else null
	if image == null or image.is_empty():
		return false
	set_preview(image)
	return true


## Uses [param image] as the next save's preview, scaled to [constant PREVIEW_SIZE].
func set_preview(image: Image) -> void:
	_preview = image.duplicate() as Image
	_preview.resize(PREVIEW_SIZE.x, PREVIEW_SIZE.y, Image.INTERPOLATE_LANCZOS)


var _preview: Image = null


## Writes the preview beside the save: the one [method capture_preview] took, or the frame on screen now.
func _write_preview(path: String) -> void:
	if _preview == null and not capture_preview():
		return
	_preview.save_png(path)
	_preview = null


## What [method current_path] holds (version, saved_at, scene_path and states), or an empty Dictionary when there is
## no file, it is not this format, or it is another version.
func read_save() -> Dictionary:
	if not has_save():
		return {}
	var path: String = current_path()
	var json: JSON = JSON.new()
	var parsed: bool = json.parse(FileAccess.get_file_as_string(path)) == OK
	var data: Variant = JSON.to_native(json.data) if parsed else null # objects stay out: allow_objects is off
	if not data is Dictionary or int((data as Dictionary).get("version", 0)) != VERSION or not (data as Dictionary).get("states") is Dictionary:
		push_warning("SaveGame: %s is not a version %d save; it is left alone" % [path, VERSION])
		return {}
	data["states"] = from_plain(data["states"])
	return data


## Reads [method current_path] back into the Saveables that are there; false when there is nothing to read. A save
## from another level brings only the Player's things, not its place.
func load_game() -> bool:
	var data: Dictionary = read_save()
	if data.is_empty():
		load_failed.emit(current_path())
		return false
	var states: Dictionary = data["states"]
	var scene: Node = get_tree().current_scene
	if str(data.get("scene_path", "")) != (scene.scene_file_path if scene else ""):
		states = carried_states(states)
	apply_states(states)
	loaded.emit(current_path())
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(current_path())
		var preview: String = current_path().get_basename() + ".png"
		if FileAccess.file_exists(preview):
			DirAccess.remove_absolute(preview)


## Every Saveable this peer owns, keyed by its path from this node's parent; a spawned Player, named after its peer
## id, by [constant PLAYER_KEY].
func collect_states() -> Dictionary:
	var states: Dictionary = {}
	var base: Node = get_parent() if get_parent() else self
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if not node.has_method("save_state") or not node.is_multiplayer_authority():
			continue
		var key: String = PLAYER_KEY if node is Player and str(node.name).is_valid_int() else String(base.get_path_to(node))
		states[key] = node.save_state()
	return states


## What of [param states] a Player carries into another level: its own state without [constant PLACE_KEYS].
static func carried_states(states: Dictionary) -> Dictionary:
	if not states.get(PLAYER_KEY) is Dictionary:
		return {}
	var carried: Dictionary = (states[PLAYER_KEY] as Dictionary).duplicate()
	for place: String in PLACE_KEYS:
		carried.erase(place)
	return {PLAYER_KEY: carried}


## Hands each state to the Saveable at its path, if it is still there and this peer owns it; [constant PLAYER_KEY]
## goes to this peer's spawned Player, whatever its peer id is this session.
func apply_states(states: Dictionary) -> void:
	var base: Node = get_parent() if get_parent() else self
	var own_player: Node = null
	for player: Node in get_tree().get_nodes_in_group(&"Player"):
		if player.is_multiplayer_authority() and str(player.name).is_valid_int():
			own_player = player
	for path: String in states:
		var node: Node = own_player if path == PLAYER_KEY else base.get_node_or_null(NodePath(path))
		if node == null or not node.is_in_group(GROUP) or not node.has_method("load_state") or not node.is_multiplayer_authority():
			continue
		node.load_state(states[path])


## Saves when [param checkpoint] is taken, if [member save_on_checkpoint] asks for it.
func watch_checkpoint(checkpoint: Checkpoint) -> void:
	if not checkpoint.activated.is_connected(_on_checkpoint_activated):
		checkpoint.activated.connect(_on_checkpoint_activated)


func _on_checkpoint_activated(_player: Player) -> void:
	if save_on_checkpoint:
		save_game()


func _update_timer() -> void:
	if autosave_timer == null:
		return
	if autosave_interval > 0.0:
		autosave_timer.start(autosave_interval)
	else:
		autosave_timer.stop()


## [param value] with every Resource in it made plain: one saved under res:// becomes {"@path": its path}, one made
## at run time {"@script": its script's res:// path} plus its stored properties. Any other object is dropped.
static func to_plain(value: Variant) -> Variant:
	if value is Resource:
		var resource: Resource = value
		if resource.resource_path.begins_with("res://") and not resource.resource_path.contains("::"):
			return {"@path": resource.resource_path}
		var script: Script = resource.get_script() as Script
		if script == null or not script.resource_path.begins_with("res://"):
			return null
		var plain: Dictionary = {"@script": script.resource_path}
		for property: Dictionary in resource.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
				plain[property.name] = to_plain(resource.get(property.name))
		return plain
	if value is Object:
		return null
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(to_plain(item))
		return items
	if value is Dictionary:
		var entries: Dictionary = {}
		for key: Variant in value:
			entries[key] = to_plain(value[key])
		return entries
	return value


## Undoes [method to_plain]. Only res:// files are loaded, and only Resource scripts from res:// are instanced, so a
## save can name nothing but the game's own content.
static func from_plain(value: Variant) -> Variant:
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(from_plain(item))
		return items
	if not value is Dictionary:
		return value
	var plain: Dictionary = value
	if plain.has("@path"):
		var path: String = str(plain["@path"])
		return load(path) if path.begins_with("res://") and ResourceLoader.exists(path) else null
	if plain.has("@script"):
		var script_path: String = str(plain["@script"])
		var script: Script = load(script_path) as Script if script_path.begins_with("res://") and ResourceLoader.exists(script_path) else null
		if script == null or not script.can_instantiate() or not ClassDB.is_parent_class(script.get_instance_base_type(), &"Resource"):
			return null
		var resource: Resource = script.new()
		for key: Variant in plain:
			if key == "@script":
				continue
			var restored: Variant = from_plain(plain[key])
			var current: Variant = resource.get(key)
			if current is Array and restored is Array:
				(current as Array).assign(restored) # a typed array property takes the elements, not a plain Array
			else:
				resource.set(key, restored)
		return resource
	var entries: Dictionary = {}
	for key: Variant in plain:
		entries[key] = from_plain(plain[key])
	return entries
