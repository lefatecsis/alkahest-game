@icon("res://addons/3d_player_controller/inventory/assets/icons/materials.svg")
class_name ItemPickup
extends Node3D
## An [Item] lying in the world, Zelda style: walk up and the [ActionPrompt] appears with the Action button read
## as "Pick Up"; Action puts [member count] of [member item] in the Player's [Inventory] and the pickup is gone.
## An item with a [member Item.model_scene] (what the inventory preview turns) lies here as that model, turning
## on the spot with its base on the ground; without one, or a mesh child of your own, its icon floats over the spot.
## The prompt and the label are up only while the Player is in the detection area and go down when they leave,
## when the pickup is taken, or when it vanishes (another peer took it).
##
## Over the network the server keeps the count: a take asks it for what fits in the taker's inventory
## ([method Inventory.room_for]), it grants what is left to the taker's peer and gives every peer the new count
## ([method _set_count]), so two peers pressing Action together never both get the stack. An emptied pickup saved in
## the level stays in the tree, hidden, and the server tells every peer that joins later how many are left (0 hides
## it), as it does for a drop that came through the world's [ProjectileSpawner]; any other emptied pickup is freed.

signal picked_up(player: Player, count: int) ## Emitted on the taker's peer with how many the Player took.

const TURN_SECONDS: float = 6.0 ## One full turn of the model.

@export var item: Item:
	set(value):
		item = value
		_refresh()
@export_range(1, 999) var count: int = 1
@export var show_icon: bool = true ## Float the item's icon as a billboard; turn off when the pickup has its own mesh.
@export var take_action: StringName = &"action" ## The action that takes the stack while the prompt is up.
@export var auto_take: bool = false ## Taken the moment the Player touches it, no prompt: a platformer's coin.

var player: Player ## The Player in range, shown the prompt.
var local_only: bool = false ## On this peer alone (a drop whose item has no resource path to send): taken here without asking the server.
var spawned: bool = false ## Put down by the world's [ProjectileSpawner] (a drop, what a throw left): the server's free takes every copy away, and a joiner gets it from the spawner.
var _turn: Tween

@onready var player_detection: Area3D = $PlayerDetection
@onready var action_prompt: ActionPrompt = $ActionPrompt
@onready var icon: Sprite3D = $Icon
@onready var model_pivot: Node3D = $ModelPivot ## Holds the item's model, turning.


func _ready() -> void:
	_refresh()


## Freed while a Player stands by it (someone else took it, the level changed): the prompt lets the label go.
func _exit_tree() -> void:
	if player:
		action_prompt.hide_for(player.controls)
		player = null


func _input(event: InputEvent) -> void:
	if player == null or item == null or player.is_paused or player.is_typing or not event.is_action_pressed(take_action):
		return
	take()
	get_viewport().set_input_as_handled()


## Asks the server for as many as fit in the Player's inventory; they go in once it grants them, and the pickup goes
## on every peer once it is empty.
func take() -> void:
	if player == null or item == null or count <= 0:
		return
	var wanted: int = mini(count, player.inventory.room_for(item))
	if wanted <= 0:
		return
	if local_only:
		_grant(get_path_to(player), wanted)
		_set_count(count - wanted)
	else:
		_request_take.rpc_id(1, get_path_to(player), wanted)


## The server's half of [method take]: grants the Player at [param taker_path] (from this node, the same on every
## peer), who must be the sender's own, up to [param wanted] of what is left, and gives every peer the new count.
@rpc("any_peer", "call_local", "reliable")
func _request_take(taker_path: NodePath, wanted: int) -> void:
	var taker: Player = get_node_or_null(taker_path) as Player
	var sender: int = multiplayer.get_remote_sender_id()
	var granted: int = mini(wanted, count)
	if not multiplayer.is_server() or taker == null or taker.get_multiplayer_authority() != sender or granted <= 0:
		return
	_grant.rpc_id(sender, taker_path, granted)
	_set_count.rpc(count - granted)


## The server's grant, on the taker's peer: [param granted] go into the Player's inventory. What no longer fits
## (the bag filled in the moment the request travelled) stays out.
@rpc("authority", "call_local", "reliable")
func _grant(taker_path: NodePath, granted: int) -> void:
	var taker: Player = get_node_or_null(taker_path) as Player
	if taker == null or not taker.is_multiplayer_authority():
		return
	var taken: int = granted - taker.inventory.add_item(item, granted)
	if taken > 0:
		picked_up.emit(taker, taken)


## How many are left, from the server, on every peer. An empty pickup goes: one saved in the level stays in the tree
## hidden, and so does a client's copy of a [member spawned] one, which the server's free removes everywhere; anything
## else is freed. The server tells every peer joining later the count of a pickup it will have too (a level's, or a
## spawned one, which it gets from the spawner).
@rpc("authority", "call_local", "reliable")
func _set_count(left: int) -> void:
	count = left
	if (owner != null or spawned) and multiplayer.is_server() and not multiplayer.peer_connected.is_connected(_tell_joiner):
		multiplayer.peer_connected.connect(_tell_joiner)
	if count > 0:
		return
	if player:
		action_prompt.hide_for(player.controls)
		player = null
	if owner != null or (spawned and not multiplayer.is_server()):
		hide()
		player_detection.set_deferred(&"monitoring", false)
		# Nor can it be hit: the Player's ProjectileRaycast collides with areas, and a spent stack's reach
		# would otherwise catch every round aimed through where it lay. A ray still hits an area that is
		# not monitorable, so the shape itself goes.
		for shape: Node in player_detection.find_children("*", "CollisionShape3D", true, false):
			shape.set_deferred(&"disabled", true)
	else:
		queue_free()


## Connected on the server once the count has changed: a peer joining later is told how many are left.
func _tell_joiner(peer_id: int) -> void:
	_set_count.rpc_id(peer_id, count)


## Wired to PlayerDetection.body_entered: the Player who walked up gets the prompt, with the Action button read as
## "Pick Up" (the scene sets the prompt's message_end; the prompt's own ready put it on the labels).
func _on_player_detection_body_entered(body: Node3D) -> void:
	if count > 0 and body is Player and body.is_multiplayer_authority() and not (body as Player).is_riding:
		player = body
		if auto_take:
			take()
			return
		action_prompt.show_for(player.controls, "Pick Up")


## Wired to PlayerDetection.body_exited: walking away takes the prompt and the label with it.
func _on_player_detection_body_exited(body: Node3D) -> void:
	if body == player:
		action_prompt.hide_for(player.controls)
		player = null


func _refresh() -> void:
	if not is_node_ready():
		return
	for child: Node in model_pivot.get_children():
		child.queue_free()
	if _turn:
		_turn.kill()
		_turn = null
	var scene: PackedScene = item.get_model_scene() if item else null
	icon.visible = show_icon and item != null and item.icon != null and scene == null
	icon.texture = item.icon if item else null
	if scene == null:
		return
	var model: Node3D = scene.instantiate() as Node3D
	if model == null:
		return
	_disable_collision(model)
	model_pivot.add_child(model)
	item.prepare_model(model) # once in the tree, so the model's own ready nodes exist
	# Stand the model on the ground under the prompt, wherever its scene put its origin
	var bounds: AABB = AABB()
	var first: bool = true
	var geometries: Array[Node] = model.find_children("*", "GeometryInstance3D", true, false)
	if model is GeometryInstance3D:
		geometries.push_front(model)
	for geometry: Node in geometries:
		var visual: GeometryInstance3D = geometry as GeometryInstance3D
		var box: AABB = (model_pivot.global_transform.affine_inverse() * visual.global_transform) * visual.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if not first:
		model.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
	_turn = create_tween().set_loops()
	_turn.tween_property(model_pivot, "rotation:y", TAU, TURN_SECONDS).as_relative()


## Switches off every collision shape and area under [param node], so the model on show neither blocks nor detects.
static func _disable_collision(node: Node) -> void:
	for shape: Node in node.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = true
	for area: Node in node.find_children("*", "Area3D", true, false):
		(area as Area3D).monitoring = false
		(area as Area3D).monitorable = false
