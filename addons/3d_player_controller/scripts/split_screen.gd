class_name SplitScreen
extends Control
## Local multiplayer on one screen, one pad per player. Give it a [member player_scene] and a [member player_count]
## and it splits the window into that many views ([PlayerView], a SubViewport on the same world), each with a Player
## of its own inside it, so the camera, the HUD, the menus and the audio listener of each belong to their own view.
## Player one reads the first pad, player two the second, and so on ([member Player.input_device]): each view forwards
## only its pad's events, and the Player's polled reads ask that pad. The action names are the ordinary ones; nothing
## is renamed or rebound. The keyboard and the mouse drive nobody, since two people cannot share them. Put it under a
## world (a sibling of the level, over the whole window) rather than a [PlayerSpawner]: it is for players on one
## machine, not for a networked session.
##
## The world it renders is the one this node is in: the views share the parent viewport's World3D, so physics,
## navigation and the level are the same for everyone. A rideable or a prop of the game's that polls the whole
## input ([method Input.is_action_pressed]) answers to every pad at once; read through
## [method Player.is_action_pressed] to serve one view.

signal players_spawned(players: Array[Player]) ## Every view has its Player.

enum Layout {
	AUTO, ## Two players stack top and bottom; three or four make a grid.
	HORIZONTAL, ## Side by side.
	VERTICAL, ## Stacked.
	GRID, ## A square-ish grid.
}

@export var player_scene: PackedScene ## The Player scene (or one inheriting it), one per view.
@export_range(1, 4) var player_count: int = 2 ## One pad each: the first pad is player one's.
@export var layout: Layout = Layout.AUTO
@export var spawn_points: Array[Node3D] = [] ## Where each Player starts, in order; the rest start at the world origin.
@export var spawn_on_ready: bool = true

var players: Array[Player] = []
var views: Array[PlayerView] = []

@onready var grid: GridContainer = $Grid


func _ready() -> void:
	if spawn_on_ready and not Engine.is_editor_hint():
		spawn()


## Builds the views and their Players; a second call rebuilds from scratch.
func spawn() -> void:
	clear()
	if player_scene == null:
		push_error("SplitScreen: no player_scene to spawn")
		return
	grid.columns = _columns()
	var world: World3D = get_viewport().find_world_3d()
	for i: int in player_count:
		var view: PlayerView = PlayerView.new()
		view.name = "View%d" % (i + 1)
		view.stretch = true
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var viewport: SubViewport = SubViewport.new()
		viewport.name = "SubViewport"
		viewport.world_3d = world
		viewport.audio_listener_enable_3d = true
		viewport.handle_input_locally = true
		view.add_child(viewport)
		grid.add_child(view)
		views.append(view)
		var player: Player = player_scene.instantiate()
		player.name = "Player%d" % (i + 1)
		player.input_device = i
		view.player = player
		if i < spawn_points.size() and spawn_points[i]:
			player.transform = spawn_points[i].global_transform
		viewport.add_child(player)
		players.append(player)
	players_spawned.emit(players)


## Frees every view and Player.
func clear() -> void:
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.free()
	players.clear()
	views.clear()


## The Player in view [param index], or null.
func get_player(index: int) -> Player:
	return players[index] if index >= 0 and index < players.size() else null


func _columns() -> int:
	match layout:
		Layout.HORIZONTAL:
			return player_count
		Layout.VERTICAL:
			return 1
		Layout.GRID:
			return ceili(sqrt(float(player_count)))
	return 1 if player_count <= 2 else 2
