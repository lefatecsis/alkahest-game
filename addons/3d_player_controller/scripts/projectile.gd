class_name Projectile
extends RigidBody3D
## A physical projectile (bullet, arrow) with a swept ray between physics steps so fast rounds
## never tunnel through thin or small targets such as balloons. Projectile scenes sit on
## [constant PROJECTILE_LAYER] alone and mask layer 1, so rounds pass through each other and only collide with
## the world, while an area that watches every layer (a snow field, a grass field) still sees them go by.
## On no layer at all, as they used to be, no area could.
##
## Characters wear hurtboxes, Area3Ds on bone attachments on [constant HURTBOX_LAYER]: when the sweep lands on a
## CharacterBody3D the same ray is cast again for the hurtbox behind the capsule, and [member hit_part] tells the
## handler which body part took the round (one named "Head" is a headshot).
## Hits are delivered, by the round's multiplayer authority alone, to the nearest ancestor of the collider that has
## [code]register_projectile_hit(projectile, point, normal)[/code], or failing that
## [code]register_weapon_hit(weapon, projectile)[/code]; RigidBody3D targets also receive an impulse.

signal hit(collider: Node, point: Vector3, normal: Vector3) ## Emitted once when the projectile lands.

const SHOOTER_EXCEPTION_SECONDS: float = 0.15 ## How long the projectile ignores the body that fired it.
const MAX_AREA_SKIPS: int = 4 ## Areas without a hit handler (water, weather zones) are skipped up to this many times per step.
const HURTBOX_LAYER: int = 2 ## Physics layer of the hurtbox areas that report which body part a round hit.
const PROJECTILE_LAYER: int = 12 ## The layer projectile scenes sit on. No body masks it, so nothing collides with a round but the world it hits.

@export var is_template: bool = false ## A frozen display copy (the arrow shown on the bow model); never flies.
@export var lifetime: float = 5.0 ## Seconds before an unlanded projectile frees itself.
@export var impact_impulse: float = 4.0 ## Impulse (N·s) applied to RigidBody3D targets, scaled by the remaining speed fraction.
@export var sticks_on_hit: bool = false ## Freeze where it lands (arrows) instead of freeing (bullets).
@export var stuck_seconds: float = 1.0 ## How long a stuck projectile stays in the target before freeing.
@export var damage: float = 15.0 ## Passed to `take_hit` handlers such as the Player and enemies.

var shooter: Node3D = null ## The body that fired the projectile.
var pending_launch: Dictionary = {} ## Launch data from a [ProjectileSpawner], applied on ready (every peer simulates the same round).
var weapon: Equipment = null ## The equipment that fired the projectile, passed on to weapon-hit handlers.
var has_hit: bool = false ## True once the projectile has landed.
var hit_part: Area3D ## The hurtbox under the impact, when the target wears any; its name is the body part.

var _launch_speed: float = 1.0
var _previous_position: Vector3
var _flight_velocity: Vector3 = Vector3.ZERO ## Velocity before the current step; physics may already have stopped the body against the target.
var _ignores_shooter: bool = false


func _ready() -> void:
	if is_template:
		freeze = true
		set_physics_process(false)
		for audio: Node in find_children("*", "AudioStreamPlayer3D", true, false):
			(audio as AudioStreamPlayer3D).stop() # a nocked copy of a scene makes no flight sound
	elif not pending_launch.is_empty():
		var data: Dictionary = pending_launch
		pending_launch = {}
		launch(data["origin"], data["direction"], data["speed"], get_node_or_null(data["shooter"]) as Node3D, get_node_or_null(data["weapon"]) as Equipment)
		if data.has("fire_sfx"):
			play_launch_sfx(data["fire_sfx"])


## Places the projectile at [param origin] and sends it along [param direction] at [param speed].
func launch(origin: Transform3D, direction: Vector3, speed: float, from_shooter: Node3D, from_weapon: Equipment = null) -> void:
	shooter = from_shooter
	weapon = from_weapon
	is_template = false
	global_transform = origin
	if direction.length_squared() > 0.0:
		look_at(global_position + direction, _stable_up(direction))
	freeze = false
	linear_velocity = direction.normalized() * speed
	_flight_velocity = linear_velocity
	_launch_speed = maxf(speed, 0.001)
	_previous_position = global_position
	set_physics_process(true)
	if is_instance_valid(shooter):
		_ignores_shooter = true
		add_collision_exception_with(shooter)
		get_tree().create_timer(SHOOTER_EXCEPTION_SECONDS).timeout.connect(_on_shooter_exception_timeout)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_timeout)


## Plays the stream at [param stream_path] where the round is now (the muzzle, on launch) through a speaker beside the
## round that frees itself when the clip ends, so the shot is heard where it was fired however far the round flies or
## how soon it lands. A [Firearm] sends its shot sound along in the launch data, so every peer's copy calls this.
func play_launch_sfx(stream_path: String) -> void:
	var stream: AudioStream = load(stream_path) as AudioStream
	if stream == null or not is_inside_tree():
		return
	var speaker: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	speaker.name = "LaunchSfx"
	speaker.stream = stream
	speaker.bus = &"SFX"
	speaker.finished.connect(speaker.queue_free)
	get_parent().add_child(speaker)
	speaker.global_position = global_position
	speaker.play()


## Sweeps a ray from the previous step's position to the current one to catch anything physics stepped over.
func _physics_process(_delta: float) -> void:
	if has_hit:
		return
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(_previous_position, global_position)
	query.collide_with_areas = true
	# `query.exclude` hands back a copy, so build the list locally and assign it before each cast
	var excludes: Array[RID] = [get_rid()]
	if _ignores_shooter and is_instance_valid(shooter) and shooter is CollisionObject3D:
		excludes.append((shooter as CollisionObject3D).get_rid())
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for _skip: int in MAX_AREA_SKIPS:
		query.exclude = excludes
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			break
		var collider: Node = result.collider as Node
		if collider is Projectile or (collider is Area3D and _find_hit_handler(collider) == null):
			excludes.append(result.rid)
			continue
		if collider is CharacterBody3D:
			hit_part = _hurtbox_behind(query, excludes + [result.rid], collider)
		_apply_hit(collider, result.position, result.normal)
		break
	_previous_position = global_position
	_flight_velocity = linear_velocity


## Contact fallback for rounds physics resolves before the sweep runs (wired in the scene); a character still
## gets its hurtbox looked up along the flight line through the contact. A template never lands.
func _on_body_entered(body: Node) -> void:
	if has_hit or is_template or body == shooter or body is Projectile:
		return
	var along: Vector3 = _flight_velocity.normalized()
	if body is CharacterBody3D and along.length_squared() > 0.0:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position - along, global_position + along)
		hit_part = _hurtbox_behind(query, [get_rid(), (body as CollisionObject3D).get_rid()], body)
	_apply_hit(body, global_position, -along)


## Lands the round. Every peer's copy simulates the same flight, so only the round's multiplayer authority (the
## server for a spawner's round, this peer for a local one) tells the handler; a hit counted on every copy would do
## its damage once per peer. The impulse, [signal hit], sticking and hiding happen on every copy.
func _apply_hit(collider: Node, point: Vector3, normal: Vector3) -> void:
	has_hit = true
	var handler: Node = _find_hit_handler(collider) if is_multiplayer_authority() else null
	if handler:
		if handler.has_method("register_projectile_hit"):
			handler.call("register_projectile_hit", self, point, normal)
		else:
			handler.call("register_weapon_hit", weapon, self)
	if collider is RigidBody3D and collider != shooter:
		var speed_fraction: float = clampf(_flight_velocity.length() / _launch_speed, 0.0, 1.0)
		(collider as RigidBody3D).apply_impulse(_flight_velocity.normalized() * impact_impulse * speed_fraction, point - (collider as Node3D).global_position)
	hit.emit(collider, point, normal)
	if sticks_on_hit:
		global_position = point
		freeze = true
		set_physics_process(false)
		get_tree().create_timer(stuck_seconds).timeout.connect(_free_on_authority)
	else:
		_free_on_authority()


## Casts the same ray on the hurtbox layer, past the capsule, for a hurtbox that belongs to [param body].
func _hurtbox_behind(query: PhysicsRayQueryParameters3D, excludes: Array[RID], body: Node) -> Area3D:
	var probe: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(query.from, query.to, 1 << (HURTBOX_LAYER - 1), excludes)
	probe.collide_with_areas = true
	probe.collide_with_bodies = false
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(probe)
	var part: Area3D = result.get("collider") as Area3D
	return part if part and body.is_ancestor_of(part) else null


## The nearest ancestor (inclusive) that accepts projectile or weapon hits.
func _find_hit_handler(from: Node) -> Node:
	var node: Node = from
	while node:
		if node.has_method("register_projectile_hit") or node.has_method("register_weapon_hit"):
			return node
		node = node.get_parent()
	return null


func _stable_up(direction: Vector3) -> Vector3:
	return Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP


func _on_shooter_exception_timeout() -> void:
	_ignores_shooter = false
	if is_instance_valid(shooter):
		remove_collision_exception_with(shooter)


## Only an unlanded projectile is still around to free; a stuck one frees itself after [member stuck_seconds].
func _on_lifetime_timeout() -> void:
	if not has_hit:
		_free_on_authority()


## Frees the round on its multiplayer authority (the server for spawner-owned rounds, this peer offline or for a local
## copy); a peer's copy stops where it is, hidden, and waits for the spawner's despawn, so the server's despawn never
## arrives for a node the peer has already freed.
func _free_on_authority() -> void:
	if is_multiplayer_authority():
		queue_free()
		return
	freeze = true
	set_physics_process(false)
	hide()
