@tool
class_name PlayerSpawner
extends MultiplayerSpawner
## Spawns one copy of its Player child per peer, named by peer id, under [member MultiplayerSpawner.spawn_path],
## which is the spawner itself unless the scene points it elsewhere, so a world carries no empty container for them.
##
## The Player child is the template: an instance of [code]player.tscn[/code] placed in the world scene, so in the
## editor it is a real node. Select it, override its properties, add children to it, drag it to where players should
## appear; its transform is the spawn point. In the game the spawner takes it out of the tree before it readies (no
## camera, no HUD, no physics from the template itself) and every peer gets a duplicate of it, overrides and added
## children included. The server (also the case offline, where the local id is 1) spawns itself on ready and every
## peer that connects; each copy reaches the other peers through the spawner's custom spawn, so a client duplicates
## its own template. [Player] reads its authority from its node name in [code]_enter_tree[/code], so each copy runs
## input only on the peer that owns it.

signal local_player_spawned(player: Player) ## The player this peer controls has entered the tree.

var template: Player ## The Player child this spawner copies; out of the tree once the game runs.


func _init() -> void:
	if spawn_path.is_empty():
		spawn_path = ^"."


func _enter_tree() -> void:
	if Engine.is_editor_hint() or template:
		return
	# The children are built but not yet in the tree, so the template leaves before its _ready ever runs
	for child: Node in get_children():
		if child is Player:
			template = child
			remove_child(child)
			break


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	spawn_function = _spawn_copy
	spawned.connect(_on_spawned)
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(despawn_player)
	if multiplayer.is_server():
		spawn_player(multiplayer.get_unique_id())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(template) and not template.is_inside_tree():
		template.free()


func _get_configuration_warnings() -> PackedStringArray:
	for child: Node in get_children():
		if child is Player:
			return []
	return ["No Player child: add an instance of player.tscn under this spawner. It is the template every peer's player is a copy of, and where it stands is the spawn point."]


## Server only: adds the player node for [param peer_id]; the spawner replicates it.
func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server() or template == null:
		return
	var container: Node = get_node(spawn_path)
	if container.has_node(str(peer_id)):
		return
	var player: Player = spawn(peer_id) as Player
	if player:
		_on_spawned(player)


## Frees the player of [param peer_id], who has left. A body it carries hangs under its hands and would be freed with
## it on every peer, so it goes back into the world, and to the server, first; the peer that left can send nothing.
func despawn_player(peer_id: int) -> void:
	var player: Player = get_node(spawn_path).get_node_or_null(str(peer_id)) as Player
	if player == null:
		return
	if player.held_object and player.held_object.is_holding_rigidbody():
		player.held_object._release_held_rigidbody().set_multiplayer_authority(1)
	player.queue_free()


## The player controlled by this peer, or null before it spawns.
func get_local_player() -> Player:
	return get_node(spawn_path).get_node_or_null(str(multiplayer.get_unique_id())) as Player


## A copy of the template named for [param peer_id], the same on every peer (this is the spawner's spawn_function).
func _spawn_copy(peer_id: Variant) -> Node:
	# duplicate() copies every SubViewport's size onto the copy after its stretching container already owns that
	# size, which the engine warns about. Stretching pauses on the template around the copy and resumes on both.
	var stretching: Array[Node] = template.find_children("*", "SubViewportContainer", true, false).filter(func(c: Node) -> bool: return (c as SubViewportContainer).stretch)
	for container: Node in stretching:
		(container as SubViewportContainer).stretch = false
	var player: Player = template.duplicate() as Player
	for container: Node in stretching:
		(container as SubViewportContainer).stretch = true
		(player.get_node(template.get_path_to(container)) as SubViewportContainer).stretch = true
	player.name = str(peer_id)
	return player


func _on_spawned(node: Node) -> void:
	if node is Player and node.is_multiplayer_authority():
		local_player_spawned.emit(node)
