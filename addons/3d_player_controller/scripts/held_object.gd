class_name HeldObject
extends Node
## Picks up, carries, charges, and throws [RigidBody3D] objects targeted by the crosshair, and throws inventory items.
##
## The "action" input picks up or drops the crosshair target; holding "shoot" charges a
## throw. Throw animations fire [method Player.execute_throw] via a "Call Method Track".
##
## With nothing in hand, pressing "throw" takes a throwable out of the inventory (the equipped [Equipment] if it
## [member Equipment.is_throwable], else [member Player.selected_throwable] or the first throwable [Item]) and puts
## its model in [member throw_hand] while the same charge runs; releasing (or a full charge) throws it as a
## [ThrownItem] with the same emote, on the spine blend, so the Player keeps moving. Only the Player's multiplayer
## authority throws; the body reaches every peer through the [ProjectileSpawner]. Pausing mid-charge puts the
## item back.
##
## A world body is the server's: picking it up, dropping it and throwing it are asked of the server, which puts it
## in the carrier's hands on every peer and hands it (and its [SyncedBody]) to the carrier's peer for the carry, so
## every peer sees the carry; a drop or a throw puts it back where it came from and gives it back to the server,
## which throws it.

const THROWN_ITEM_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/thrown_item.tscn")
const CHARGE_START_DELAY: float = 0.2 ## Seconds "shoot" must be held before a charged throw starts.
const CHARGE_DURATION: float = 0.6 ## Seconds from charge start to full throw power.
const MIN_THROW_POWER: float = 0.25 ## Throw power multiplier for a quick tap.
const MAX_THROW_POWER: float = 1.0 ## Throw power multiplier at full charge.
const RELEASE_GRACE: float = 0.3 ## Seconds a released body still passes through the Player, so it leaves cleanly instead of being shoved out by depenetration.
const HOLD_EMOTE: StringName = &"ReadyToCastSpell" ## Emote pose played while carrying.

@export var connector_scene: PackedScene ## Scene stretched from [member connector_origin] to the held object; instanced once on ready.
@export var player: Player
@export var connector_origin: Node3D
@export var throw_charge_bar: ProgressBar ## Charge indicator; hidden whenever a charge ends.
@export var throw_arm_mass: float = 2.4 ## Effective mass of the throwing arm (kg). A thrown [RigidBody3D] leaves at [method release_speed]: the arm puts about the same energy into any throw, so a heavier body leaves slower. 2.4 kg is what a casual 7.26 kg shot put at 7 m/s implies, near a real arm's 3.5 kg.
@export var throw_hand: Node3D ## Where a throwable item sits while its throw charges (a bone attachment on the throwing hand); the Player model when unset.
@export var throw_speed: float = 14.0 ## Speed (m/s) of the throwing hand at full charge, about 50 km/h, a casual adult throw: a thrown inventory item or piece of equipment leaves at it, and a held body at [method release_speed].
@export var connector_origin_height: float = 1.0 ## Fallback height when connector_origin is unset.
@export_group("Held Object Controls")
@export var held_move_speed: float = 1.5
@export var held_joypad_move_multiplier: float = 0.65
@export var held_depth_speed: float = 1.5
@export var held_rotation_speed: float = 90.0
@export var held_min_distance: float = 0.5
@export var held_max_distance: float = 5.0
@export var held_clearance: float = 0.7 ## Metres kept between the arm's origin and the middle of a held body beyond the body's own reach ([method held_extent]): the Player's half width and a little air, so a big body (a snowball grown past a metre) is held out past the Player rather than round them.
@export var held_max_offset: Vector2 = Vector2(1.5, 1.0)
@export var rotation_snap_angle: float = 45.0 ## Degrees to rotate per discrete D-pad press in rotation mode.
@export var use_discrete_rotation_snap: bool = true ## When true, D-pad presses snap rotation in discrete 45-degree increments.

var is_throw_queued: bool = false ## Is a throw waiting on the animation call track or charge timeout?
var is_throwing: bool = false ## Is the throw wind-up currently active?
var is_charging_throw: bool = false: ## Is the Player currently charging a throw?
	set(value):
		is_charging_throw = value
		if not value and throw_charge_bar:
			throw_charge_bar.hide()
var throw_charge_time: float = 0.0 ## Elapsed charge duration for the current throw.
var throw_power: float = 1.0 ## Throw power multiplier (MIN_THROW_POWER to MAX_THROW_POWER).
var queued_throw_direction: Vector3 = Vector3.ZERO ## Direction applied when executing a queued throw.
var held_rigidbody: RigidBody3D = null
var _last_held: RigidBody3D = null ## What the head was pointed at on pickup, so letting go clears only that.
var held_throwable: Node3D = null ## The model of the inventory item or equipment in the throwing hand while its throw charges.
var throwable_item: Item = null ## The item [member held_throwable] is one of; null for equipment.
var throwable_equipment: PackedScene = null ## The scene the equipment in hand was equipped from; null for items.
var throwable_damage: float = 0.0 ## What the throwable in hand does to what it lands on.
var _original_collision_layer: int = 0
var _original_freeze: bool = false
var _held_home: Node ## Where the held body lived before it was picked up; a drop puts it back there on every peer.
var _connector_node: Node3D
var _held_distance: float = 2.0
var _held_offset: Vector2 = Vector2.ZERO
var _is_held_rotation_mode: bool = false


func _ready() -> void:
	set_physics_process(is_multiplayer_authority())
	set_process_input(is_multiplayer_authority())
	if connector_scene == null:
		return
	_connector_node = connector_scene.instantiate() as Node3D
	if _connector_node:
		_connector_node.hide()
		add_child(_connector_node)


func _input(event: InputEvent) -> void:
	if player == null or player.is_paused or player.is_typing or player.is_ragdolling:
		return

	if is_holding_rigidbody() and _is_held_object_control_event(event):
		if event.is_action_pressed(&"focus") and not event.is_echo():
			_lay_held_rigidbody_flat()
		if event.is_action_pressed(&"throw") and not event.is_echo():
			_is_held_rotation_mode = true
			refresh_contextual_controls()
		elif event.is_action_released(&"throw"):
			_is_held_rotation_mode = false
			refresh_contextual_controls()

		# Discrete 45-degree rotation snapping on D-pad press in rotation mode
		if _is_held_rotation_mode and use_discrete_rotation_snap and event.is_pressed() and not event.is_echo():
			if event.is_action(&"last_weapon"):
				held_rigidbody.rotate_object_local(Vector3.UP, deg_to_rad(rotation_snap_angle))
			elif event.is_action(&"next_weapon"):
				held_rigidbody.rotate_object_local(Vector3.UP, deg_to_rad(-rotation_snap_angle))
			elif event.is_action(&"seeker"):
				held_rigidbody.rotate_object_local(Vector3.RIGHT, deg_to_rad(-rotation_snap_angle))
			elif event.is_action(&"whistle"):
				held_rigidbody.rotate_object_local(Vector3.RIGHT, deg_to_rad(rotation_snap_angle))

		get_viewport().set_input_as_handled()

	if event.is_action_pressed(&"throw") and not event.is_echo() and not is_holding_object():
		if start_throwable_throw():
			get_viewport().set_input_as_handled()
		return

	if event.is_action_released(&"throw") and is_holding_throwable():
		release_charging_throw()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"action") and not event.is_echo():
		if is_holding_rigidbody():
			drop_held_rigidbody()
			get_viewport().set_input_as_handled()
			return
		if _try_pickup_rigidbody_from_crosshair():
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed(&"shoot") and not event.is_echo() and is_holding_rigidbody():
		start_charging_throw()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_released(&"shoot") and not event.is_echo() and is_holding_rigidbody():
		release_charging_throw()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if player == null:
		return

	# While the throw wind-up is active, keep aiming at the live crosshair direction.
	if is_throwing:
		queued_throw_direction = _get_crosshair_throw_direction()
		player.turn_model_toward_direction(queued_throw_direction, delta)

	if is_charging_throw:
		throw_charge_time += delta
		var throw_dir: Vector3 = _get_crosshair_throw_direction()
		player.turn_model_toward_direction(throw_dir, delta)

		if throw_charge_time >= CHARGE_START_DELAY:
			if not is_throw_queued:
				queue_throw(throw_dir)
			var charge_ratio: float = clampf((throw_charge_time - CHARGE_START_DELAY) / CHARGE_DURATION, 0.0, 1.0)
			throw_power = lerpf(MIN_THROW_POWER, MAX_THROW_POWER, charge_ratio)
			if throw_charge_bar:
				throw_charge_bar.show()
				throw_charge_bar.value = charge_ratio * 100.0

		if throw_charge_time >= CHARGE_START_DELAY + CHARGE_DURATION:
			throw_power = MAX_THROW_POWER
			execute_throw()

	if is_instance_valid(held_rigidbody) and not is_throwing:
		_update_held_object_transform(delta)
		_update_connector_node()


## True if the item spring arm currently holds a [RigidBody3D].
func is_holding_rigidbody() -> bool:
	return player != null and player.item_spring_arm.get_child_count() > 0 \
			and player.item_spring_arm.get_child(0) is RigidBody3D


## True while shared controls belong exclusively to the held object manipulator.
func is_holding_object() -> bool:
	return is_instance_valid(held_rigidbody) or is_holding_throwable() or (player != null and player.item_spring_arm.get_child_count() > 0)


## True while a throwable inventory item or piece of equipment sits in the throwing hand.
func is_holding_throwable() -> bool:
	return is_instance_valid(held_throwable)


## Returns the held-object spring length requested by held object controls.
func get_held_distance(fallback_distance: float) -> float:
	return _held_distance if is_holding_object() else fallback_distance


## Where the held body sits, relative to the camera's view: sideways, up and ahead in metres, as the look stick and
## the D-pad have moved it. The [Camera] aims the item spring arm along it, so the arm's collision cast sweeps the
## line the body actually sits on. Straight ahead at [param fallback_distance] with nothing held.
func get_held_offset(fallback_distance: float) -> Vector3:
	if not is_holding_object():
		return Vector3(0.0, 0.0, fallback_distance)
	return Vector3(_held_offset.x, -_held_offset.y, maxf(_held_distance, held_extent() + held_clearance))


## How far the held body reaches from its middle, from its collision shapes: a sphere's radius, half a box's diagonal,
## half a capsule's height. A body with no shape to measure reaches nothing. Read every frame, since a snowball grows
## while it is pushed along.
func held_extent() -> float:
	if not is_holding_rigidbody():
		return 0.0
	var reach: float = 0.0
	for owner_id: int in held_rigidbody.get_shape_owners():
		var scale: Vector3 = held_rigidbody.shape_owner_get_transform(owner_id).basis.get_scale()
		var grow: float = maxf(maxf(scale.x, scale.y), scale.z)
		for i: int in held_rigidbody.shape_owner_get_shape_count(owner_id):
			var shape: Shape3D = held_rigidbody.shape_owner_get_shape(owner_id, i)
			var extent: float = 0.0
			if shape is SphereShape3D:
				extent = (shape as SphereShape3D).radius
			elif shape is BoxShape3D:
				extent = (shape as BoxShape3D).size.length() * 0.5
			elif shape is CapsuleShape3D:
				extent = (shape as CapsuleShape3D).height * 0.5
			elif shape is CylinderShape3D:
				extent = Vector2((shape as CylinderShape3D).radius, (shape as CylinderShape3D).height * 0.5).length()
			elif shape is ConvexPolygonShape3D or shape is ConcavePolygonShape3D:
				extent = shape.get_debug_mesh().get_aabb().get_longest_axis_size() * 0.5
			reach = maxf(reach, extent * grow)
	return reach


## Starts charging a throw when the shoot button is pressed.
func start_charging_throw() -> void:
	if not is_holding_object():
		return
	is_charging_throw = true
	throw_charge_time = 0.0
	throw_power = MIN_THROW_POWER
	player.requires_shoot_release_after_throw = true
	player.rotate_model_to_direction(_get_crosshair_throw_direction())


## Called when the shoot button is released while charging a throw.
func release_charging_throw() -> void:
	if not is_charging_throw:
		return

	var throw_dir: Vector3 = _get_crosshair_throw_direction()
	player.rotate_model_to_direction(throw_dir)

	if throw_charge_time < CHARGE_START_DELAY:
		# Quick tap: instant weak throw without animation wind-up.
		execute_instant_throw(throw_dir, MIN_THROW_POWER)
	else:
		# Long press release: execute the queued throw with charged power.
		var charge_ratio: float = clampf((throw_charge_time - CHARGE_START_DELAY) / CHARGE_DURATION, 0.0, 1.0)
		throw_power = lerpf(MIN_THROW_POWER, MAX_THROW_POWER, charge_ratio)
		execute_throw()
	is_charging_throw = false


## Executes an instant throw without animation wind-up (for quick taps).
func execute_instant_throw(throw_dir: Vector3, power: float) -> void:
	if not is_holding_object():
		return
	player.rotate_model_to_direction(throw_dir)
	clear_throw_queue()
	is_charging_throw = false
	is_throwing = false
	_throw_what_is_held(throw_dir, power)


## Queues a held-object throw to be executed by the animation call track or charge timeout.
func queue_throw(throw_direction: Vector3) -> void:
	if throw_direction.length_squared() <= 0.001:
		throw_direction = _get_crosshair_throw_direction()

	is_throw_queued = true
	is_throwing = true
	queued_throw_direction = throw_direction.normalized()

	var emote_state: AnimationNodeStateMachinePlayback = player.animation_tree.get(Player.EMOTE_STATE_PLAYBACK_PATH)
	if emote_state:
		player.emote_spine_blend = 1.0
		emote_state.travel("Throw")
		player.is_emoting = true
		player.has_started_emoting = false


## Clears the queued throw state.
func clear_throw_queue() -> void:
	is_throw_queued = false
	queued_throw_direction = Vector3.ZERO


## Throws the held object at the right frame (fired by [method Player.execute_throw]).
func execute_throw() -> void:
	if not is_throw_queued and not is_charging_throw:
		return
	if not is_holding_object():
		clear_throw_queue()
		is_charging_throw = false
		is_throwing = false
		return

	var throw_dir: Vector3 = queued_throw_direction
	if throw_dir.length_squared() <= 0.001:
		throw_dir = _get_crosshair_throw_direction()

	player.rotate_model_to_direction(throw_dir)
	var power: float = throw_power
	clear_throw_queue()
	is_charging_throw = false
	if not player.is_emoting:
		is_throwing = false
	_throw_what_is_held(throw_dir, power)


## Drops the held [RigidBody3D] back into the world without applying an impulse (through the server, see
## [method _let_go]).
func drop_held_rigidbody() -> void:
	if is_instance_valid(held_rigidbody):
		_let_go(Vector3.ZERO)
	else:
		held_rigidbody = null
		_end_hold()


## Starts a throw with nothing in hand: the equipped [Equipment] if it [member Equipment.is_throwable], else
## [method get_selected_throwable]. One leaves the inventory and its model goes into [member throw_hand] while the
## charge runs; releasing "throw" (or a full charge) throws it. Only the Player's multiplayer authority throws.
## False, and nothing is taken, with nothing throwable or while the hands are busy.
func start_throwable_throw() -> bool:
	if player == null or not player.is_multiplayer_authority() or is_holding_object() or is_charging_throw or is_throwing \
			or player.riding_blocks_hands() or player.is_climbing or player.is_hanging_braced or player.is_hanging_free \
			or player.is_paragliding:
		return false
	var equipment: Equipment = get_throwable_equipment()
	if equipment:
		# What lands is an instance of the piece's scene, so only a piece with a scene of its own can fly.
		if not Inventory.has_own_scene(equipment):
			return false
		var damage: float = equipment.throw_damage
		var scene_path: String = player.inventory.forget_equipment(equipment)
		if scene_path.is_empty():
			return false
		throwable_equipment = load(scene_path) as PackedScene
		throwable_damage = damage
	else:
		var item: Item = get_selected_throwable()
		if item == null or player.inventory.remove_item(item, 1) == 0:
			return false
		throwable_item = item
		throwable_damage = item.throw_damage
	held_throwable = ThrownItem.build_model(throwable_item, throwable_equipment)
	if held_throwable == null:
		held_throwable = _icon_in_hand(throwable_item)
	var hand: Node3D = throw_hand if is_instance_valid(throw_hand) else player.player_model
	hand.add_child(held_throwable)
	refresh_contextual_controls()
	start_charging_throw()
	return true


## The equipped piece of equipment that can be thrown, if any.
func get_throwable_equipment() -> Equipment:
	for equipment: Equipment in player.inventory.equipment:
		if equipment.is_throwable:
			return equipment
	return null


## The item the next throw takes: [member Player.selected_throwable] while some is carried, else the first
## throwable item in the inventory, else null.
func get_selected_throwable() -> Item:
	var selected: Item = player.selected_throwable
	if selected and selected.throwable and player.inventory.count_of(selected) > 0:
		return selected
	var throwables: Array[Item] = player.inventory.get_throwable_items()
	return throwables[0] if not throwables.is_empty() else null


## Puts the throwable in hand back where it came from and drops the charge (the pause menu opened mid-charge).
func cancel_throwable_throw() -> void:
	if not is_holding_throwable():
		return
	if throwable_equipment:
		player.inventory.add_equipment_scene(throwable_equipment)
	elif throwable_item:
		player.inventory.add_item(throwable_item, 1)
	_drop_throwable_model()
	clear_throw_queue()
	is_charging_throw = false
	is_throwing = false
	var emote_state: AnimationNodeStateMachinePlayback = player.animation_tree.get(Player.EMOTE_STATE_PLAYBACK_PATH)
	if emote_state and player.is_emoting:
		emote_state.start("Idle")
		player.emote_spine_blend = 0.0
		player.is_emoting = false
		player.has_started_emoting = false
	_end_hold()


## Wired to Player.paused_changed: a menu opening mid-charge cancels the throw.
func _on_player_paused_changed(is_paused: bool) -> void:
	if is_paused:
		cancel_throwable_throw()


## Pushes the held-object control labels; states call this on travel while an object is held.
func refresh_contextual_controls() -> void:
	# Connected here rather than in _ready: the Player's own @onready references resolve after its children are ready
	if not player.controls.input_type_changed.is_connected(_on_input_type_changed):
		player.controls.input_type_changed.connect(_on_input_type_changed)
	_on_input_type_changed(player.controls.current_input_type)


## The state handlers yield the labels while an object is held (see [method NodeStateMachine._on_input_type_changed]).
func _on_input_type_changed(input_type: int) -> void:
	if is_holding_object():
		player.controls.set_labels(get_contextual_controls(input_type))


func get_contextual_controls(input_type: int) -> Dictionary:
	if is_holding_throwable():
		return {
			player.controls.joypad_button_10_label: "Throw",
			player.controls.joypad_button_6_label: "Pause Menu",
			player.controls.left_joystick_label: "Move",
		}
	var controls: Dictionary = {
		player.controls.action_label(&"action", player.controls.joypad_button_0_label): "Drop",
		player.controls.joypad_button_4_label: "Perspective",
		player.controls.joypad_button_6_label: "Pause Menu",
		player.controls.joypad_button_10_label: "Rotate",
		player.controls.joypad_button_15_label: "Screenshot",
		player.controls.joypad_axis_4_plus_label: "Lay Flat",
		player.controls.joypad_axis_5_plus_label: "Throw",
		player.controls.left_joystick_label: "Move",
		player.controls.right_joystick_label: "Move Item",
	}
	if input_type == player.controls.InputType.KEYBOARD_MOUSE:
		if _is_held_rotation_mode:
			controls[player.controls.key_i_label] = "Rotate Up"
			controls[player.controls.key_j_label] = "Rotate Left"
			controls[player.controls.key_k_label] = "Rotate Down"
			controls[player.controls.key_l_label] = "Rotate Right"
		else:
			controls[player.controls.key_i_label] = "Farther"
			controls[player.controls.key_k_label] = "Closer"
	else:
		if _is_held_rotation_mode:
			controls[player.controls.joypad_button_11_label] = "Rotate Up"
			controls[player.controls.joypad_button_12_label] = "Rotate Down"
			controls[player.controls.joypad_button_13_label] = "Rotate Left"
			controls[player.controls.joypad_button_14_label] = "Rotate Right"
		else:
			controls[player.controls.joypad_button_11_label] = "Farther"
			controls[player.controls.joypad_button_12_label] = "Closer"
	return controls


## Throws whatever is held: the throwable in hand, else the node on the item spring arm.
func _throw_what_is_held(throw_dir: Vector3, power: float) -> void:
	if is_holding_throwable():
		_launch_throwable(throw_dir, power)
	else:
		_throw_held_node(player.item_spring_arm.get_child(0), throw_dir, power)


## Sends the throwable in hand flying as a [ThrownItem] from the hand along [param throw_dir] at [member throw_speed]
## times [param power]: through the world's [ProjectileSpawner] (every peer gets the same body, the server's copy
## lands it), or locally without one.
func _launch_throwable(throw_dir: Vector3, power: float) -> void:
	var origin: Transform3D = Transform3D(Basis.IDENTITY, held_throwable.global_position)
	var item: Item = throwable_item
	var equipment_scene: PackedScene = throwable_equipment
	var damage: float = throwable_damage
	_drop_throwable_model()
	var speed: float = throw_speed * power
	var spawner: ProjectileSpawner = ProjectileSpawner.find_for(player)
	if spawner and (item == null or not item.resource_path.is_empty()):
		spawner.fire(THROWN_ITEM_SCENE, origin, throw_dir, speed, player, null, {
			"item": item.resource_path if item else "",
			"equipment": equipment_scene.resource_path if equipment_scene else "",
			"damage": damage,
		})
	else:
		var thrown: ThrownItem = THROWN_ITEM_SCENE.instantiate() as ThrownItem
		thrown.item = item
		thrown.equipment_scene = equipment_scene
		thrown.damage = damage
		var world: Node = player.get_parent() if player.get_parent() else get_tree().current_scene
		world.add_child(thrown)
		thrown.launch(origin, throw_dir, speed, player)
	_end_hold()


## Frees the model in the throwing hand and forgets what it was.
func _drop_throwable_model() -> void:
	if is_instance_valid(held_throwable):
		held_throwable.queue_free()
	held_throwable = null
	throwable_item = null
	throwable_equipment = null
	throwable_damage = 0.0


## The item's icon as a billboard, for a throwable with no model.
func _icon_in_hand(item: Item) -> Node3D:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.texture = item.icon if item else null
	sprite.modulate = item.get_icon_color() if item else Color.WHITE
	sprite.pixel_size = 0.0006
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = true
	return sprite


## Speed (m/s) a body of [param mass] kg leaves a full-charge throw at. The arm and the body share the energy an unladen
## arm would have at [member throw_speed], so (arm + body) v^2 = arm * throw_speed^2: a baseball leaves at 13.6 m/s, a
## football at 12.9, a 1.4 kg snowball at 11.1, a 7.26 kg shot at 7.0, a 37 kg ball of snow at 3.5. It used to be one
## 5 N s impulse for everything, which put a 0.2 kg beach ball at 25 m/s and a snowball at 3.6.
func release_speed(mass: float) -> float:
	return throw_speed * sqrt(throw_arm_mass / (throw_arm_mass + maxf(mass, 0.0)))


## Throws the held node, preferring its own throw methods over a raw impulse.
func _throw_held_node(held_node: Node, throw_dir: Vector3, power: float) -> void:
	if held_node.has_method("throw_with_direction"):
		held_node.call("throw_with_direction", throw_dir, power)
	elif held_node.has_method("throw"):
		held_node.call("throw", throw_dir)
	elif held_node == held_rigidbody:
		_let_go(throw_dir * held_rigidbody.mass * release_speed(held_rigidbody.mass) * power)


## Gets the throw direction from the camera crosshair, falling back to the facing direction.
func _get_crosshair_throw_direction() -> Vector3:
	if player.camera:
		return -player.camera.global_transform.basis.z.normalized()
	var facing_direction: Vector3 = player.get_facing_direction()
	if facing_direction.length_squared() > 0.001:
		return facing_direction
	return -player.global_transform.basis.z.normalized()


## Asks the server for the [RigidBody3D] under the crosshair ([method _request_pickup]). True when there was one.
func _try_pickup_rigidbody_from_crosshair() -> bool:
	if not player.camera or not player.camera.camera_ray_cast.is_colliding() or is_holding_object():
		return false

	# Walk up from the collider to the owning body.
	var node: Node = player.camera.camera_ray_cast.get_collider() as Node
	while node and not node is RigidBody3D:
		node = node.get_parent()
	if node == null or node is VehicleBody3D:
		return false

	_request_pickup.rpc_id(1, get_path_to(node))
	return true


## The server's half of a pickup: the body ([param body_path], from this node, the same on every peer) goes to this
## Player, asked for from the Player's own peer, unless it is already in somebody's hands; then every peer puts it in
## them ([method _carry]).
@rpc("any_peer", "call_local", "reliable")
func _request_pickup(body_path: NodePath) -> void:
	var body: RigidBody3D = get_node_or_null(body_path) as RigidBody3D
	if not multiplayer.is_server() or body == null or body is VehicleBody3D or body.get_parent() is SpringArm3D \
			or multiplayer.get_remote_sender_id() != player.get_multiplayer_authority():
		return
	_carry.rpc(body_path)


## From the server, on every peer: the body goes into this Player's hands, and answers to the carrier's peer for the
## carry, synchronizer and all, so the carrier moves it and every peer sees it.
@rpc("any_peer", "call_local", "reliable")
func _carry(body_path: NodePath) -> void:
	var body: RigidBody3D = get_node_or_null(body_path) as RigidBody3D
	if multiplayer.get_remote_sender_id() != 1 or body == null:
		return
	_pickup_rigidbody(body)
	body.set_multiplayer_authority(player.get_multiplayer_authority())


## Drops ([param impulse] zero) or throws the held body through the server. This side goes quiet first, handing the
## body back to the server here, so the server's first packets meet no rival sender.
func _let_go(impulse: Vector3) -> void:
	held_rigidbody.set_multiplayer_authority(1)
	_request_release.rpc_id(1, impulse)


## The server's half of a drop or a throw, from the carrier's own peer: every peer lets go ([method _release]).
@rpc("any_peer", "call_local", "reliable")
func _request_release(impulse: Vector3) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.get_multiplayer_authority() and is_instance_valid(held_rigidbody):
		_release.rpc(impulse)


## From the server, on every peer: the body goes back where it came from and to the server, which throws it with
## [param impulse] (none for a drop).
@rpc("any_peer", "call_local", "reliable")
func _release(impulse: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_instance_valid(held_rigidbody):
		return
	var body: RigidBody3D = _release_held_rigidbody()
	body.set_multiplayer_authority(1)
	if impulse != Vector3.ZERO and body.is_multiplayer_authority():
		body.freeze = false
		body.apply_impulse(impulse, Vector3.ZERO)


## Freezes the body, disables its world collision, and parents it to the item spring arm; this peer's own part of a
## pickup ([method _carry]).
func _pickup_rigidbody(body: RigidBody3D) -> void:
	held_rigidbody = body
	_held_home = body.get_parent()
	_original_collision_layer = body.collision_layer
	_original_freeze = body.freeze

	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.freeze = true
	body.set_collision_layer_value(1, false)
	body.set_collision_layer_value(2, true)
	body.add_collision_exception_with(player)
	player.add_collision_exception_with(body)

	body.reparent(player.item_spring_arm, true)
	body.transform = Transform3D()
	_held_distance = clampf(player.item_spring_arm.spring_length, held_min_distance, held_max_distance)
	_held_offset = Vector2.ZERO
	_is_held_rotation_mode = false

	var emote_state: AnimationNodeStateMachinePlayback = player.animation_tree.get(Player.EMOTE_STATE_PLAYBACK_PATH)
	if emote_state:
		player.emote_spine_blend = 1.0
		emote_state.start(HOLD_EMOTE)
		player.is_emoting = true
		player.has_started_emoting = false
	# The head follows what is held, not the spine: bending the torso toward a body that is often below the
	# chest folded the Player over it. The head's own limits keep the neck plausible.
	_last_held = body
	player.set_head_look_at_target(body)
	if player.is_multiplayer_authority():
		refresh_contextual_controls()


## Returns the held body to where it lived before, with the collision and freeze state recorded on pickup (on a peer
## whose [SyncedBody] froze it, that is frozen still, under the server's transform).
func _release_held_rigidbody() -> RigidBody3D:
	var body: RigidBody3D = held_rigidbody
	held_rigidbody = null
	body.collision_layer = _original_collision_layer
	body.freeze = _original_freeze
	get_tree().create_timer(RELEASE_GRACE).timeout.connect(_end_release_grace.bind(body))
	var world: Node = _held_home if is_instance_valid(_held_home) else (player.get_parent() if player.get_parent() else get_tree().current_scene)
	if world:
		body.reparent(world, true)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = false
	_end_hold()
	return body


## Lets a released body collide with the Player again, unless it has been picked back up meanwhile.
func _end_release_grace(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or not is_instance_valid(player) or body == held_rigidbody:
		return
	body.remove_collision_exception_with(player)
	player.remove_collision_exception_with(body)


## Clears the carry pose, look-at, connector and control labels once nothing is held.
func _end_hold() -> void:
	_is_held_rotation_mode = false
	if is_instance_valid(_connector_node):
		_connector_node.hide()
	var emote_state: AnimationNodeStateMachinePlayback = player.animation_tree.get(Player.EMOTE_STATE_PLAYBACK_PATH)
	if emote_state and emote_state.get_current_node() == HOLD_EMOTE:
		emote_state.start("Idle")
		player.emote_spine_blend = 0.0
		player.is_emoting = false
		player.has_started_emoting = false
	# Only if the head is still on what was held, so a screen being read keeps the head it asked for.
	var head: LookAtModifier3D = player.head_look_at_modifier
	var looking_at: Node = head.get_node_or_null(head.target_node) if head and not head.target_node.is_empty() else null
	if head and (looking_at == null or looking_at == _last_held):
		player.set_head_look_at_target(null)
	_last_held = null
	if not player.is_multiplayer_authority():
		return
	# Hand the control labels back to the active state.
	player.controls.reset_labels()
	var state_node: NodeStateMachine = player.state_machine.get_node_or_null(NodePath(NodeStateMachine.get_state_name(player.current_state))) as NodeStateMachine
	if state_node:
		state_node._on_input_type_changed(player.controls.current_input_type)


func _update_held_object_transform(delta: float) -> void:
	var dpad_input: Vector2 = Vector2.ZERO if player.is_typing else player.get_vector(&"last_weapon", &"next_weapon", &"seeker", &"whistle")
	if player.is_action_pressed(&"throw") and not player.is_typing:
		var rotation_delta: Vector2 = dpad_input * held_rotation_speed * delta
		held_rigidbody.rotate_object_local(Vector3.RIGHT, deg_to_rad(rotation_delta.y))
		held_rigidbody.rotate_object_local(Vector3.UP, deg_to_rad(-rotation_delta.x))
	else:
		_held_distance = clampf(_held_distance - dpad_input.y * held_depth_speed * delta, held_min_distance, held_max_distance + held_extent())

	var move_input: Vector2 = Vector2.ZERO if player.is_typing else player.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	var move_multiplier: float = 1.0
	if player.controls.current_input_type != player.controls.InputType.KEYBOARD_MOUSE:
		move_multiplier = held_joypad_move_multiplier
	_held_offset += move_input * held_move_speed * move_multiplier * delta
	_held_offset = _held_offset.clamp(-held_max_offset, held_max_offset)
	# The spring arm carries the body: the Camera aims it along get_held_offset(), offset included


func _lay_held_rigidbody_flat() -> void:
	var player_up: Vector3 = player.up_direction.normalized()
	var camera_forward: Vector3 = (-player.camera.global_transform.basis.z).slide(player_up).normalized()
	if camera_forward.length_squared() <= 0.001:
		camera_forward = player.global_transform.basis.z.slide(player_up).normalized()
	var flat_basis: Basis = Basis.looking_at(camera_forward, player_up)
	held_rigidbody.global_basis = flat_basis.rotated(flat_basis.x, -PI * 0.5)


func _is_held_object_control_event(event: InputEvent) -> bool:
	return event.is_action(&"seeker") \
		or event.is_action(&"whistle") \
		or event.is_action(&"last_weapon") \
		or event.is_action(&"next_weapon") \
		or event.is_action(&"look_left") \
		or event.is_action(&"look_right") \
		or event.is_action(&"look_up") \
		or event.is_action(&"look_down") \
		or event.is_action(&"throw") \
		or event.is_action(&"focus")


## Stretches the connector scene from the origin to the held body.
func _update_connector_node() -> void:
	if not is_instance_valid(_connector_node):
		return
	var player_up: Vector3 = player.up_direction.normalized()
	var start_position: Vector3 = connector_origin.global_position if is_instance_valid(connector_origin) \
			else player.global_position + player_up * connector_origin_height
	var connector_vector: Vector3 = held_rigidbody.global_position - start_position
	var connector_length: float = connector_vector.length()
	if connector_length <= 0.001:
		_connector_node.hide()
		return

	var up_vec: Vector3 = player_up
	if absf((connector_vector / connector_length).dot(up_vec)) > 0.99:
		up_vec = player.global_transform.basis.x
	_connector_node.global_position = start_position
	_connector_node.look_at(held_rigidbody.global_position, up_vec)
	_connector_node.scale = Vector3(1.0, 1.0, connector_length / 10.0)
	_connector_node.show()
