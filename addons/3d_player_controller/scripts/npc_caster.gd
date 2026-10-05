class_name NpcCaster
extends Node3D
## Casts [Ability] resources for an NPC: the first ready ability whose target is within its cast range and in
## line of sight, standing through its cast time before it lands. Heals are held until the caster is below
## half health. Phase VFX/SFX play through [method Ability.spawn_phase] on every peer, as the Player's do.

signal cast_started(ability: Ability)
signal ability_activated(ability: Ability)

@export var caster: Node3D ## The NPC; abilities read its `target`.
@export var health: Health ## The caster's pools: heals wait for low health, abilities spend energy.
@export var abilities: Array[Ability] = []
@export var fx_root: Node3D ## Phase VFX and bolts are instanced here.
@export var audio: AudioStreamPlayer3D
@export var eye_height: float = 1.6 ## Line-of-sight rays start this far above the caster's origin.

var casting: Ability ## The ability whose cast time is running, if any.
var _cooldown_ends: Dictionary[Ability, int] = {}
var _channeling_vfx: Node3D

@onready var cast_timer: Timer = $CastTimer


func _ready() -> void:
	# The scene's AbilityLibrary, when it has one: the resources here become its loaded copies of the same ids
	var library: AbilityLibrary = AbilityLibrary.find(self)
	if library:
		for i: int in abilities.size():
			abilities[i] = library.resolve(abilities[i])


func is_ready(ability: Ability) -> bool:
	return Time.get_ticks_msec() >= _cooldown_ends.get(ability, 0)


## True when nothing but the target sits between the caster's eyes and the target's focus point.
func has_line_of_sight(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(caster.global_position + Vector3.UP * eye_height, Focus.get_focus_target_position(target))
	if caster is CollisionObject3D:
		query.exclude = [(caster as CollisionObject3D).get_rid()]
	var hit: Dictionary = caster.get_world_3d().direct_space_state.intersect_ray(query)
	# The car a target is driving counts as the target: its body is what the ray can reach
	return hit.is_empty() or hit["collider"] == target or target.is_ancestor_of(hit["collider"]) or hit["collider"] == target.get("riding")


## Starts the first usable ability against [param target]; false when none applies right now.
func try_cast(target: Node3D) -> bool:
	if casting or not is_instance_valid(target):
		return false
	var distance: float = caster.global_position.distance_to(target.global_position)
	for ability: Ability in abilities:
		if not is_ready(ability) or distance > ability.cast_range:
			continue
		if health and ability.energy_cost > 0.0 and health.energy < ability.energy_cost:
			continue
		if ability is HealAbility and health and health.health > health.max_health * 0.5:
			continue
		if not (ability.target_kinds & Ability.Kind.SELF) and not has_line_of_sight(target):
			continue
		_begin(ability)
		return true
	return false


## Starts [param ability] now, whatever its range, cooldown, cost or the heal rule: a test range's way of making an
## NPC run a spell on demand, at [param at] when given ([method Ability.aim_at]), else at the NPC's own target. The
## AI casts through [method try_cast]. False while another cast is running.
func cast(ability: Ability, at: Node3D = null) -> bool:
	if casting or ability == null:
		return false
	Ability.aim_at(caster, at)
	_begin(ability)
	return true


func interrupt() -> void:
	if casting == null:
		return
	casting = null
	cast_timer.stop()
	_stop_channeling.rpc()
	Ability.aim_at(caster, null)


func _begin(ability: Ability) -> void:
	if ability.cast_time <= 0.0:
		_activate(ability)
		return
	casting = ability
	cast_timer.start(ability.cast_time)
	_play(ability, Ability.Phase.CHANNELING, caster.global_position)
	cast_started.emit(ability)


func _on_cast_timer_timeout() -> void:
	var ability: Ability = casting
	casting = null
	_stop_channeling.rpc()
	_activate(ability)


func _activate(ability: Ability) -> void:
	if not ability.activate(caster):
		return
	_cooldown_ends[ability] = Time.get_ticks_msec() + int(ability.cooldown * 1000.0)
	if health:
		health.spend_energy(ability.energy_cost)
	var target: Node3D = ability.get_target(caster)
	var target_path: NodePath = target.get_path() if is_instance_valid(target) else NodePath()
	if ability.projectile_speed > 0.0:
		_play(ability, Ability.Phase.CASTING, caster.global_position + Vector3.UP * 1.3, target_path, ability.get_impact_position(caster))
	else:
		_play(ability, Ability.Phase.CASTING, caster.global_position)
		_land(ability, target, ability.get_impact_position(caster))
	Ability.aim_at(caster, null)
	ability_activated.emit(ability)


## The impact phase; a melee swing that reports no `hit_anything` plays no impact, as the Player's does not.
func _land(ability: Ability, target: Node3D, at: Vector3) -> void:
	ability.impact(caster, target)
	if ability.get(&"hit_anything") == false:
		return
	_play(ability, Ability.Phase.IMPACT, at)


func _play(ability: Ability, phase: Ability.Phase, at: Vector3, target_path: NodePath = NodePath(), destination: Vector3 = Vector3.ZERO) -> void:
	var index: int = abilities.find(ability)
	if index != -1:
		_play_phase.rpc(index, phase, at, target_path, destination)


@rpc("authority", "call_local", "reliable")
func _play_phase(ability_index: int, phase: Ability.Phase, at: Vector3, target_path: NodePath = NodePath(), destination: Vector3 = Vector3.ZERO) -> void:
	var ability: Ability = abilities[ability_index]
	var node: Node3D = ability.spawn_phase(phase, at, fx_root, audio, get_node_or_null(target_path), destination)
	if phase == Ability.Phase.CASTING and node is SpellProjectile and is_multiplayer_authority():
		(node as SpellProjectile).arrived.connect(_on_bolt_arrived.bind(ability_index, target_path))
	elif phase == Ability.Phase.CHANNELING:
		_channeling_vfx = node


func _on_bolt_arrived(at: Vector3, ability_index: int, target_path: NodePath) -> void:
	_land(abilities[ability_index], get_node_or_null(target_path), at)


@rpc("authority", "call_local", "reliable")
func _stop_channeling() -> void:
	if audio:
		audio.stop()
	if is_instance_valid(_channeling_vfx):
		_channeling_vfx.queue_free()
	_channeling_vfx = null
