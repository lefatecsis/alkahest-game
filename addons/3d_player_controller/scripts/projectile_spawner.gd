class_name ProjectileSpawner
extends MultiplayerSpawner
## Spawns projectiles on every peer from one launch description, and lands what they leave behind.
##
## [method fire] runs on the server (or offline) directly and asks the server over RPC otherwise; the
## server spawns through [member MultiplayerSpawner.spawn_function] with the same data on all peers,
## so each peer simulates an identical round, and the server's copy (the round's authority) decides what it hit.
## [method place] spawns a scene at a point on every peer (an ice block, what a thrown item leaves, a Player's
## drop), [method ignite] lights the grass on every peer. Add the node to the [code]ProjectileSpawner[/code] group
## so weapons and inventories can find it; without one, weapons fire and drops land locally. What it spawns lands
## under [member MultiplayerSpawner.spawn_path], the spawner itself unless the scene points it elsewhere, and a
## peer joining later is sent everything still standing there.
##
## A client's request is checked before anything spawns: the scene must be one of the spawner's spawnable scenes
## (its Auto Spawn List in the inspector, so list every scene a client fires or drops: bullets, arrows, thrown
## items, [code]item_pickup.tscn[/code] and droppable equipment), or for a drop, "world_pickup" must name a world
## [Equipment]; the shooter it names must be the sender's own; and an "item" must be an [Item] of this project, its
## "count" clamped to a stack. A client's throw does what the thrown item or equipment does, never the damage it sent
## ([method _request_spawn]). Lightning ([method strike_lightning], [method arc_lightning]) goes through here too, so
## a client's bolt reaches every peer.


func _init() -> void:
	if spawn_path.is_empty():
		spawn_path = ^"."


func _ready() -> void:
	spawn_function = _spawn_scene


## The spawner of [param node]'s multiplayer session (the one sharing its [member Node.multiplayer]), found
## through the ProjectileSpawner group; null without one, and things then happen locally.
static func find_for(node: Node) -> ProjectileSpawner:
	if node == null or not node.is_inside_tree():
		return null
	for candidate: Node in node.get_tree().get_nodes_in_group(&"ProjectileSpawner"):
		if candidate is ProjectileSpawner and candidate.multiplayer == node.multiplayer:
			return candidate
	return null


## Launches [param scene] from [param origin] along [param direction]; returns the local copy on the
## server and null on clients (their copy arrives through the spawner). [param extra] rides along in the launch
## data for scenes that read more than a [Projectile] does (a [ThrownItem] reads which item it is).
func fire(scene: PackedScene, origin: Transform3D, direction: Vector3, speed: float, shooter: Node3D, weapon: Node = null, extra: Dictionary = {}) -> Node:
	var data: Dictionary = {
		"scene": scene.resource_path,
		"origin": origin,
		"direction": direction,
		"speed": speed,
		"shooter": String(shooter.get_path()) if shooter else "",
		"weapon": String(weapon.get_path()) if weapon else "",
	}
	data.merge(extra)
	return _spawn_everywhere(data)


## Puts [param scene] down at world [param position] on every peer (an ice block where an arrow landed); returns the
## local copy on the server and null on clients. [param extra] may carry "item" (an [Item]'s res:// path) and
## "count", the stack a placed [ItemPickup] holds; "world_pickup", the node path of a world [Equipment] pickup
## whose copy is put down instead of a scene (pass a null [param scene]); and "shooter", the path of the Player who
## dropped it, whom a placed [Equipment] ignores until they step off it ([method Equipment.set_dropped_by]).
func place(scene: PackedScene, position: Vector3, extra: Dictionary = {}) -> Node3D:
	var data: Dictionary = {"scene": scene.resource_path if scene else "", "position": position}
	data.merge(extra)
	return _spawn_everywhere(data) as Node3D


## Lights the grass around [param position] on every peer, as a fire spell's impact does. Rounds belong to the
## server, so only the server's call does anything; the peers receive.
func ignite(position: Vector3, radius: float, duration: float) -> void:
	if multiplayer.is_server():
		_ignite.rpc(position, radius, duration)


## A bolt out of the sky onto [param position] on every peer, for a lightning spell cast by [param caster]: the
## weather's own bolt (weather_fx's [code]LightningFX[/code], the one in the "LightningFX" group sharing this
## spawner's multiplayer session, through its [code]strike_at(position, 0.0)[/code]), so it hurts nothing and the
## spell deals its own damage. A client asks the server, which strikes only for a caster that is the sender's own.
## Nothing happens in a scene without a LightningFX.
func strike_lightning(position: Vector3, caster: Node) -> void:
	_lightning.rpc_id(1, caster.get_path(), position, position, true)


## An arc from [param from] to [param to] on every peer, the jump of a chain of lightning, through the LightningFX's
## [code]arc(from, to)[/code]; as [method strike_lightning], a client asks the server.
func arc_lightning(from: Vector3, to: Vector3, caster: Node) -> void:
	_lightning.rpc_id(1, caster.get_path(), from, to, false)


func _spawn_everywhere(data: Dictionary) -> Node:
	if multiplayer.is_server():
		return spawn(data)
	_request_spawn.rpc_id(1, data)
	return null


## A client's spawn: refused unless the scene is on the spawnable list (or its "world_pickup" is a world
## [Equipment]), the shooter is the sender's own and any "item" is an [Item] of this project; its "count" is clamped
## to a stack. A fired item is a throw ([ThrownItem]), so it must be [member Item.throwable], and thrown "equipment"
## must be an [Equipment] scene on the list; the throw's "damage" is then that item's or that scene's
## [code]throw_damage[/code], whatever number the client sent.
@rpc("any_peer", "call_remote", "reliable")
func _request_spawn(data: Dictionary) -> void:
	var world_pickup: String = str(data.get("world_pickup", ""))
	var listed: bool = get_node_or_null(world_pickup) is Equipment if not world_pickup.is_empty() else _is_spawnable(str(data.get("scene", "")))
	if not multiplayer.is_server() or not listed or not _sent_by_owner(NodePath(str(data.get("shooter", "")))):
		return
	var damage: float = 0.0
	var item_path: String = str(data.get("item", ""))
	if not item_path.is_empty():
		var item: Item = load(item_path) as Item if item_path.begins_with("res://") and ResourceLoader.exists(item_path) else null
		if item == null or (data.has("origin") and not item.throwable):
			return
		var count: Variant = data.get("count", 1)
		data["count"] = clampi(count if count is int else 1, 1, item.max_stack)
		damage = item.throw_damage
	var equipment_path: String = str(data.get("equipment", ""))
	if not equipment_path.is_empty():
		var piece: Equipment = Inventory.pickup_from(equipment_path, self) if _is_spawnable(equipment_path) else null
		if piece == null:
			return
		damage = piece.throw_damage
		piece.free()
	if data.has("damage"):
		data["damage"] = damage
	spawn(data)


## Whether [param scene_path] is on the spawner's spawnable scenes (the inspector's Auto Spawn List).
func _is_spawnable(scene_path: String) -> bool:
	for i: int in get_spawnable_scene_count():
		if ResourceUID.ensure_path(get_spawnable_scene(i)) == scene_path:
			return true
	return false


## Whether the peer behind the request now running owns [param path], the shooter or caster it names; the
## server's own calls always pass.
func _sent_by_owner(path: NodePath) -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	var node: Node = null if path.is_empty() else get_node_or_null(path)
	return sender == multiplayer.get_unique_id() or (node != null and node.get_multiplayer_authority() == sender)


@rpc("authority", "call_local", "reliable")
func _ignite(position: Vector3, radius: float, duration: float) -> void:
	Ability.ignite_grass(get_tree(), position, radius, duration)


## The server's half of [method strike_lightning] and [method arc_lightning]: checks the caster, then has the
## LightningFX of its own session (which the server owns) play the bolt on every peer.
@rpc("any_peer", "call_local", "reliable")
func _lightning(caster_path: NodePath, from: Vector3, to: Vector3, strike: bool) -> void:
	if not multiplayer.is_server() or not _sent_by_owner(caster_path):
		return
	for lightning: Node in get_tree().get_nodes_in_group(&"LightningFX"):
		if lightning.multiplayer != multiplayer:
			continue
		if strike:
			lightning.rpc(&"strike_at", to, 0.0)
		else:
			lightning.rpc(&"arc", from, to)
		return


## Runs on every peer: builds the scene, or the copy of the world pickup "world_pickup" names. A projectile (or anything
## else with a [code]pending_launch[/code], a [ThrownItem]) launches itself once it enters the tree; anything else is
## put down at the data's position, relative to the spawn path's node: an [ItemPickup] holding the data's "item" and
## "count", an [Equipment] ignoring the Player who dropped it ("shooter") until they step off it, both marked
## [code]spawned[/code], so a take leaves the freeing to the server.
func _spawn_scene(data: Dictionary) -> Node:
	var world_pickup: String = str(data.get("world_pickup", ""))
	var node: Node = null
	if world_pickup.is_empty():
		node = (load(data["scene"]) as PackedScene).instantiate()
	else:
		node = Inventory.pickup_from(world_pickup, self)
	if "pending_launch" in node:
		node.set("pending_launch", data)
		return node
	if node is Node3D and data.has("position"):
		var parent: Node3D = get_node_or_null(spawn_path) as Node3D
		(node as Node3D).position = parent.to_local(data["position"]) if parent else data["position"]
	var dropper: Node3D = get_node_or_null(NodePath(str(data.get("shooter", "")))) as Node3D
	if node is ItemPickup:
		(node as ItemPickup).spawned = true
		if not str(data.get("item", "")).is_empty():
			(node as ItemPickup).item = load(data["item"]) as Item
			(node as ItemPickup).count = data.get("count", 1)
	elif node is Equipment:
		(node as Equipment).spawned = true
		if dropper:
			(node as Equipment).set_dropped_by(dropper)
	return node
