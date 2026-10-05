class_name ThrownItem
extends RigidBody3D
## An inventory [Item] or a piece of [Equipment] in flight, thrown by [HeldObject].
##
## It carries the item's model (its icon when it has none) and flies as plain physics. On its first touch its
## multiplayer authority hurts what it hit by [member damage] (anything up the collider's ancestry with
## [code]take_hit[/code]) and puts the item back in the world where the body lies: an [ItemPickup] holding one of
## the item, or the equipment's own walk-over scene. Both go through the world's [ProjectileSpawner], so every peer
## gets the pickup and loses the body (a spawned node freed on the server is freed everywhere); without a spawner
## both happen locally. The spawner builds it on every peer with the launch data in [member pending_launch], like
## a [Projectile]; the extra keys are "item" (resource path), "equipment" (scene path) and "damage". For a client's
## throw the server sets "damage" from the item's or the equipment scene's [code]throw_damage[/code] and refuses an item
## that is not throwable or equipment off its spawnable list ([ProjectileSpawner]), so no client picks its own damage.

signal landed(collider: Node) ## Emitted on every peer the first time the body touches anything.

const ITEM_PICKUP_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/item_pickup.tscn")
const THROWER_EXCEPTION_SECONDS: float = 0.3 ## How long it ignores the body that threw it, so it leaves the hand cleanly.
const LOST_SECONDS: float = 30.0 ## A throw that never lands (off the world) frees itself after this.

@export var item: Item: ## The item in flight; the pickup it becomes holds one of these. Null for equipment.
	set(value):
		item = value
		_refresh()
@export var equipment_scene: PackedScene: ## Thrown equipment: the scene it was equipped from, and lands as.
	set(value):
		equipment_scene = value
		_refresh()
@export var damage: float = 0.0 ## Passed to the [code]take_hit[/code] of what it lands on; 0 hurts nothing.

var thrower: Node3D = null ## The body that threw it.
var pending_launch: Dictionary = {} ## Launch data from a [ProjectileSpawner], applied on ready.
var has_landed: bool = false ## True once the body has touched anything.

@onready var model_root: Node3D = $Model ## The item's model is instanced here.
@onready var icon: Sprite3D = $Icon ## Shown instead when the item has no model.


func _ready() -> void:
	if not pending_launch.is_empty():
		var data: Dictionary = pending_launch
		pending_launch = {}
		if not String(data.get("item", "")).is_empty():
			item = load(data["item"]) as Item
		if not String(data.get("equipment", "")).is_empty():
			equipment_scene = load(data["equipment"]) as PackedScene
		damage = data.get("damage", 0.0)
		launch(data["origin"], data["direction"], data["speed"], get_node_or_null(data["shooter"]) as Node3D)
	_refresh()
	get_tree().create_timer(LOST_SECONDS).timeout.connect(_on_lost_timeout)


## Places the body at [param origin] and sends it along [param direction] at [param speed].
func launch(origin: Transform3D, direction: Vector3, speed: float, from_thrower: Node3D) -> void:
	thrower = from_thrower
	global_transform = origin
	linear_velocity = direction.normalized() * speed
	if is_instance_valid(thrower) and thrower is PhysicsBody3D:
		add_collision_exception_with(thrower)
		get_tree().create_timer(THROWER_EXCEPTION_SECONDS).timeout.connect(_on_thrower_exception_timeout)


## Wired to body_entered: the first touch is the landing (another thrown item is not one, as rounds pass through
## rounds). Only the authority hurts and converts; the peers' copies wait for the spawner to replace them.
func _on_body_entered(body: Node) -> void:
	if has_landed or body is ThrownItem:
		return
	has_landed = true
	landed.emit(body)
	if not is_multiplayer_authority():
		return
	if damage > 0.0:
		var target: Node = _find_hit_target(body)
		if target:
			Ability.affect(target, &"take_hit", [damage, global_position], thrower)
	land.call_deferred() # out of the physics callback before nodes are added


## Leaves the item where the body lies as a pickup and removes the body: the equipment's scene, or an [ItemPickup]
## with one of the item. Through the world's [ProjectileSpawner] when there is one (and the item has a path to
## send), else locally beside this body.
func land() -> void:
	if not is_inside_tree():
		return
	var scene: PackedScene = equipment_scene if equipment_scene else ITEM_PICKUP_SCENE
	var spawner: ProjectileSpawner = ProjectileSpawner.find_for(self)
	if spawner and (equipment_scene or (item and not item.resource_path.is_empty())):
		var extra: Dictionary = {} if equipment_scene else {"item": item.resource_path, "count": 1}
		spawner.place(scene, global_position, extra)
	elif equipment_scene or item:
		var pickup: Node3D = scene.instantiate() as Node3D
		if equipment_scene == null:
			pickup.set("item", item)
			pickup.set("count", 1)
			pickup.set("local_only", true) # on this peer alone, so it is taken without asking the server
		get_parent().add_child(pickup)
		pickup.global_position = global_position
	queue_free()


## The thing to show in a hand or in flight: the equipment's scene, else the item's model dressed by the item, with
## every collision shape and area switched off so it hits and detects nothing itself. Null with no model.
static func build_model(of_item: Item, of_equipment: PackedScene) -> Node3D:
	var scene: PackedScene = of_equipment if of_equipment else (of_item.get_model_scene() if of_item else null)
	if scene == null:
		return null
	var model: Node3D = scene.instantiate() as Node3D
	if model == null:
		return null
	if of_item:
		of_item.prepare_model(model)
	disable_collision(model)
	return model


## Switches off every collision shape and area under [param node], the node included.
static func disable_collision(node: Node) -> void:
	for shape: Node in node.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = true
	for area: Node in node.find_children("*", "Area3D", true, false):
		(area as Area3D).monitoring = false
		(area as Area3D).monitorable = false


## The nearest ancestor (inclusive) of [param from] that takes hits.
func _find_hit_target(from: Node) -> Node:
	var node: Node = from
	while node:
		if node.has_method("take_hit"):
			return node
		node = node.get_parent()
	return null


func _refresh() -> void:
	if not is_node_ready():
		return
	for child: Node in model_root.get_children():
		child.queue_free()
	var model: Node3D = build_model(item, equipment_scene)
	if model:
		model_root.add_child(model)
	icon.visible = model == null and item != null and item.icon != null
	icon.texture = item.icon if item else null
	icon.modulate = item.get_icon_color() if item else Color.WHITE


func _on_thrower_exception_timeout() -> void:
	if is_instance_valid(thrower) and thrower is PhysicsBody3D:
		remove_collision_exception_with(thrower)


## Never landed: the item is lost with the body.
func _on_lost_timeout() -> void:
	if not has_landed and is_multiplayer_authority():
		queue_free()
