class_name Flashlight
extends SpotLight3D
## A torch in the Player's hand, pointed where the camera looks: sit it under the CameraMount. [member action]
## turns it on and off, it runs on [member battery] (seconds of light) that drains while on and refills from a
## battery item (the game adds to [member battery] on use), and anything in [member freezes_group] caught in the
## beam stands still while lit ([member FollowerNpc.frozen], so a frostbolt's slow on it outlasts the beam), the
## way a thing that only moves in the dark does. [signal toggled] and [signal battery_changed] are for the HUD.
##
## Multiplayer: instance [code]scenes/equipment/flashlight.tscn[/code], whose [code]StateSynchronizer[/code] carries
## [member is_on] from the Player's authority to every peer's copy of the torch, a player joining later included. Only
## the authority reads the key and drains the battery. The beam is aimed by the owner's camera, which no other peer has,
## so the owner works out what it lights and tells the server ([method _hold]), which holds those still; the owner's
## copy runs its physics only while the torch is on.

signal toggled(on: bool)
signal battery_changed(seconds_left: float, capacity: float)
signal went_dark ## The battery ran out with the light on.

@export var player: Player ## Whose torch; the CameraMount's Player when empty.
@export var action: StringName = &"flashlight"
@export var capacity: float = 90.0 ## Seconds of light on a full battery.
@export var battery: float = 90.0: ## Seconds of light left.
	set(value):
		battery = clampf(value, 0.0, capacity)
		battery_changed.emit(battery, capacity)
@export var freezes_group: StringName = &"Stalkers" ## Enemies in this group stand still while the beam is on them.
@export var freeze_range: float = 14.0
@export var starts_on: bool = false

var is_on: bool = false: ## On every peer; the owner switches it and the StateSynchronizer carries it to the rest.
	set(value):
		is_on = value and battery > 0.0
		visible = is_on
		set_physics_process(is_on and is_multiplayer_authority())
		if not is_on:
			_report_lit([])
		toggled.emit(is_on)

var _lit: Array[EnemyNpc] = [] ## What the owner last told the server it lights.
var _frozen: Array[EnemyNpc] = [] ## What the server holds still for this torch.


func _ready() -> void:
	if player == null:
		player = get_parent().get_parent() as Player if get_parent() else null
	is_on = starts_on


## Lets go of whatever this torch held still, on the server, when it leaves (its Player left the game).
func _exit_tree() -> void:
	for enemy: EnemyNpc in _frozen:
		if is_instance_valid(enemy):
			enemy.frozen = false
	_frozen.clear()


func _input(event: InputEvent) -> void:
	if player and is_multiplayer_authority() and not player.is_paused and not player.is_typing and InputMap.has_action(action) \
			and event.is_action_pressed(action) and not event.is_echo():
		is_on = not is_on
		get_viewport().set_input_as_handled()


## The owner's copy, while on: the battery drains and what the beam lights goes to the server.
func _physics_process(delta: float) -> void:
	battery -= delta
	if battery <= 0.0:
		is_on = false
		went_dark.emit()
		return
	var lit: Array[EnemyNpc] = []
	if not freezes_group.is_empty():
		for node: Node in get_tree().get_nodes_in_group(freezes_group):
			if node is EnemyNpc and not (node as EnemyNpc).is_dead and lights(node):
				lit.append(node)
	_report_lit(lit)


## Whether [param target] stands in the beam: within [member freeze_range], inside the cone, with nothing between.
func lights(target: Node3D) -> bool:
	if not is_on or not is_instance_valid(target):
		return false
	var to_target: Vector3 = Focus.get_focus_target_position(target) - global_position
	if to_target.length() > freeze_range:
		return false
	if (-global_basis.z).angle_to(to_target) > deg_to_rad(spot_angle):
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position, global_position + to_target)
	if player:
		query.exclude = [player.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == target or target.is_ancestor_of(hit["collider"])


## The owner tells the server what the beam lights, when that changes.
func _report_lit(lit: Array[EnemyNpc]) -> void:
	if lit == _lit or not is_inside_tree() or not is_multiplayer_authority():
		return
	_lit = lit
	var paths: Array[NodePath] = []
	for enemy: EnemyNpc in lit:
		paths.append(get_path_to(enemy))
	_hold.rpc_id(1, paths)


## The server holds still what this torch lights ([param paths], from this node, sent by the torch's owner alone) and
## lets go of what it no longer does; a slow on it carries on underneath.
@rpc("any_peer", "call_local", "reliable")
func _hold(paths: Array) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	var lit: Array[EnemyNpc] = []
	for path: Variant in paths:
		var enemy: EnemyNpc = get_node_or_null(path as NodePath) as EnemyNpc
		if enemy and enemy.is_in_group(freezes_group):
			lit.append(enemy)
	for enemy: EnemyNpc in _frozen:
		if is_instance_valid(enemy) and not lit.has(enemy):
			enemy.frozen = false
	for enemy: EnemyNpc in lit:
		enemy.frozen = true
	_frozen = lit
