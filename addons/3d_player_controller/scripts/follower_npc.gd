class_name FollowerNpc
extends CharacterBody3D
## An NPC that follows the Player over the navigation mesh, swims in water areas and takes knockback from physics bodies.

signal collided(impact_speed: float) ## Emitted when the NPC starts pressing against something (not while it stays in contact).
signal swimming_changed(is_swimming: bool) ## Emitted when the NPC enters or leaves the water.

@export var disposition: Focus.Disposition = Focus.Disposition.FRIENDLY ## How it stands to a Player ([method Focus.disposition_toward]): a follower is friendly, so a heal reaches it and a hostile spell passes it by; an [EnemyNpc] is hostile, hunting whoever enters its aggro area, or neutral, leaving everyone alone until attacked and hostile from then until it dies or is revived.
@export var player: Player: ## The Player to follow.
	set(value):
		if player:
			remove_collision_exception_with(player)
		player = value
		if player:
			add_collision_exception_with(player)
@export var move_speed: float = 2.0 ## Speed at which the NPC moves
@export var walk_speed: float = 0.0 ## Speed used within 1.5 m of [member follow_distance]; 0 keeps [member move_speed] throughout.
@export var turn_speed: float = 10.0 ## Speed at which the NPC turns
@export var follow_distance: float = 2.0 ## Distance to maintain from the player
@export var follow_slack: float = 0.5 ## Once stopped at follow_distance, the player must get this much further away before the NPC moves again, so it never shuffles at the boundary.
@export var max_follow_distance: float = INF ## Maximum distance before the NPC stops following
@export var follow_height_tolerance: float = 1.5 ## Height difference from the player still considered "close enough".
@export var follow_while_driving: bool = false ## Keep following while the player drives.
@export var swim_climb_speed: float = 2.5 ## Upward speed used to climb out of water against a wall.
@export var swimming_depth_offset: float = -0.2 ## Depth to submerge when swimming
@export var min_impact_speed: float = 2.0 ## Minimum collider speed that counts as an impact
@export var impact_upward_boost: float = 2.0 ## Extra upward speed added on impact
@export var knockback_damping: float = 6.0 ## How quickly knockback velocity decays
@export var mass: float = 2.0 ## Mass of the NPC in kg, used when pushing rigid bodies
@export var push_force: float = 1.0 ## Push force multiplier on RigidBody3D objects

var in_water_area: Area3D = null ## The water [Area3D] the NPC is currently inside, set by the world.
var is_swimming: bool = false: ## Is the NPC below a water surface?
	set(value):
		if value == is_swimming:
			return
		is_swimming = value
		swimming_changed.emit(value)
var knockback_velocity: Vector3 = Vector3.ZERO
var _holding_distance: bool = false ## Stopped at follow_distance; released past follow_distance + follow_slack.
var _was_colliding: bool = false

@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D


## Returns the height of the water area's box top along [param up], in world units.
static func get_water_surface_along_up(water_area: Area3D, up: Vector3) -> float:
	var shape_node: CollisionShape3D = water_area.get_node("CollisionShape3D")
	var box: BoxShape3D = shape_node.shape as BoxShape3D
	var up_in_local: Vector3 = shape_node.global_basis.inverse() * up
	var half_size: Vector3 = box.size * 0.5
	var half_extent_along_up: float = absf(up_in_local.x) * half_size.x \
			+ absf(up_in_local.y) * half_size.y \
			+ absf(up_in_local.z) * half_size.z
	return up.dot(shape_node.to_global(up_in_local.normalized() * half_extent_along_up))


func _ready() -> void:
	add_to_group("Focusable") # a friend can be targeted, for a heal or a word
	navigation_agent_3d.target_desired_distance = follow_distance


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	# Float at the water surface or fall under gravity
	var height_along_up: float = up_direction.dot(global_position)
	var water_surface: float = get_water_surface_along_up(in_water_area, up_direction) if is_instance_valid(in_water_area) else -INF
	is_swimming = water_surface > height_along_up
	if is_swimming:
		var vertical_correction: float = (water_surface + swimming_depth_offset - height_along_up) * 5.0
		if vertical_correction < 0.0 and is_on_floor():
			vertical_correction = 0.0
		if up_direction.dot(velocity) > 1.0:
			velocity += get_gravity() * delta
		else:
			velocity -= velocity.project(up_direction)
			velocity += up_direction * vertical_correction
	elif not is_on_floor():
		velocity += get_gravity() * delta

	if not player or player.is_stealthed or (player.riding_blocks_hands() and not follow_while_driving):
		_stop_moving()
		return
	up_direction = player.up_direction
	_follow_player(delta)


## Steers toward the player along the navigation path, or directly while swimming.
func _follow_player(delta: float) -> void:
	var offset: Vector3 = player.global_position - global_position
	if offset.length() > max_follow_distance:
		_stop_moving()
		return

	navigation_agent_3d.target_position = player.global_position
	var horizontal_distance: float = offset.slide(up_direction).length()
	var vertical_distance: float = absf(up_direction.dot(offset))
	if horizontal_distance <= follow_distance:
		_holding_distance = true
	elif horizontal_distance > follow_distance + follow_slack:
		_holding_distance = false
	var is_close_enough: bool = _holding_distance and vertical_distance < follow_height_tolerance
	# A swimming NPC keeps going until it climbs out after a player on land
	if is_swimming and not player.is_swimming:
		is_close_enough = false
	if is_close_enough or (navigation_agent_3d.is_navigation_finished() and not is_swimming):
		_face_player(delta)
		_stop_moving()
		return

	# Fall back to heading straight for the player when there is no path or while swimming
	var target_position: Vector3 = player.global_position
	if not is_swimming and navigation_agent_3d.is_target_reachable():
		target_position = navigation_agent_3d.get_next_path_position()
		if (target_position - global_position).slide(up_direction).length() < 0.1:
			target_position = player.global_position

	var direction: Vector3 = global_position.direction_to(target_position).slide(up_direction)
	if direction.length_squared() < 0.001:
		_stop_moving()
		return
	direction = direction.normalized()

	# Face the direction of movement
	var target_transform: Transform3D = global_transform.looking_at(global_position + direction, up_direction)
	global_transform = global_transform.interpolate_with(target_transform, turn_speed * delta)

	var speed: float = move_speed
	if is_swimming:
		speed *= 0.5
		if is_on_wall():
			velocity -= velocity.project(up_direction)
			velocity += up_direction * swim_climb_speed
	elif walk_speed > 0.0 and horizontal_distance < follow_distance + 1.5:
		# Walk when close to the player, run when farther away
		speed = lerpf(walk_speed, move_speed, clampf((horizontal_distance - follow_distance) / 1.5, 0.0, 1.0))

	speed *= movement_scale

	if navigation_agent_3d.avoidance_enabled:
		# With avoidance, movement happens in _on_velocity_computed
		navigation_agent_3d.set_velocity(direction * speed)
	else:
		_move_with_control(direction * speed)


## Smoothly turns to face the player.
func _face_player(delta: float) -> void:
	var to_player: Vector3 = (player.global_position - global_position).slide(up_direction)
	if to_player.length_squared() > 0.001:
		var target_transform: Transform3D = global_transform.looking_at(global_position + to_player.normalized(), up_direction)
		global_transform = global_transform.interpolate_with(target_transform, turn_speed * delta)


func _stop_moving() -> void:
	if navigation_agent_3d.avoidance_enabled:
		navigation_agent_3d.set_velocity(Vector3.ZERO)
	_move_with_control(Vector3.ZERO)


var movement_scale: float = 1.0: ## Fraction of normal speed the navigation asks for; [method slow] lowers it for a while, and it reads 0 while [member frozen].
	get:
		return 0.0 if frozen else movement_scale
var frozen: bool = false ## Held still whatever [method slow] says, set on the server: a [Flashlight]'s beam on something that only moves in the dark. Letting go leaves any slow running.
var _slow_timer: SceneTreeTimer


## Slows to [param factor] of normal speed for [param seconds]; counts on the server, clients relay theirs.
## [param source_path] names the caster, and a client may only relay for a caster of its own (see
## [method _may_affect]).
func slow(factor: float, seconds: float, source_path: NodePath = ^"") -> void:
	if not multiplayer.is_server():
		_request_slow.rpc_id(1, factor, seconds, source_path)
		return
	movement_scale = clampf(factor, 0.0, 1.0)
	_slow_timer = get_tree().create_timer(maxf(seconds, 0.0))
	_slow_timer.timeout.connect(_end_slow.bind(_slow_timer))


@rpc("any_peer", "call_remote", "reliable")
func _request_slow(factor: float, seconds: float, source_path: NodePath) -> void:
	if multiplayer.is_server() and _may_affect(source_path):
		slow(factor, seconds, source_path)


## Whether a client's relayed effect ([method slow], and an [EnemyNpc]'s hit and heal) may land: only from the
## server or from the peer that owns [param source_path], the attacker or caster, as [method Player._may_affect]
## has it. Anyone else is ignored.
func _may_affect(source_path: NodePath) -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0 or sender == 1 or sender == multiplayer.get_unique_id():
		return true
	var source: Node = null if source_path.is_empty() else get_node_or_null(source_path)
	return source != null and source.get_multiplayer_authority() == sender


func _end_slow(timer: SceneTreeTimer) -> void:
	if timer == _slow_timer: # A newer slow runs on its own timer
		movement_scale = 1.0


## Moves with the given control velocity on top of knockback and vertical motion. The knockback decays here, since
## every branch of every NPC's physics step ends in this call: an enemy that is stunned, casting, patrolling or
## walking home used to keep its full shove for good, because the decay sat in the hunting branch alone.
func _move_with_control(control_velocity: Vector3) -> void:
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, knockback_damping * get_physics_process_delta_time())
	velocity = control_velocity.slide(up_direction) + knockback_velocity + velocity.project(up_direction)
	var movement_velocity: Vector3 = velocity
	move_and_slide()
	_check_impacts(movement_velocity)


## Adds an instantaneous velocity change, e.g. when hit by a vehicle.
func apply_impulse(impulse: Vector3, _position: Vector3 = Vector3.ZERO) -> void:
	knockback_velocity += impulse.slide(up_direction)
	velocity += impulse.project(up_direction)


## Takes knockback from fast rigid bodies, pushes slower ones, and reports new collisions.
func _check_impacts(movement_velocity: Vector3) -> void:
	var max_impact_speed: float = 0.0
	for i: int in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var impact_speed: float = -movement_velocity.dot(collision.get_normal())
		if collision.get_collider() is RigidBody3D:
			var body: RigidBody3D = collision.get_collider() as RigidBody3D
			var incoming_speed: float = body.linear_velocity.dot(collision.get_normal())
			impact_speed = maxf(impact_speed, incoming_speed)
			if incoming_speed >= min_impact_speed and knockback_velocity.length() < min_impact_speed:
				apply_impulse(body.linear_velocity + up_direction * impact_upward_boost)

			# Push the rigid body based on relative velocity and effective mass
			var push_dir: Vector3 = -collision.get_normal()
			var relative_velocity_proj: float = movement_velocity.dot(push_dir) - body.linear_velocity.dot(push_dir)
			if relative_velocity_proj > 0.0:
				var effective_mass: float = (mass * body.mass) / (mass + body.mass)
				var push_impulse: Vector3 = push_dir * (relative_velocity_proj * effective_mass * push_force)
				body.apply_impulse(push_impulse, collision.get_position() - body.global_position)
		max_impact_speed = maxf(max_impact_speed, impact_speed)

	# Report only the first frame of contact, not continuous pressing against an obstacle
	var is_colliding: bool = get_slide_collision_count() > 0 or is_on_wall()
	if is_colliding and not _was_colliding:
		collided.emit(max_impact_speed)
	_was_colliding = is_colliding
