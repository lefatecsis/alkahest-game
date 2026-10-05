class_name DamageAbility
extends Ability
## Hurts the target through its `take_hit(damage, from)`: a fireball, a bolt, a smite. With a
## [member Ability.projectile_speed] the casting VFX flies to the target as a [SpellProjectile] and the damage
## lands on arrival; the [member Ability.elements] apply on impact as for any ability, so a fire bolt sets the
## grass alight. [member splash_radius] hurts the bodies in the "Focusable" group that close to the impact too, those
## the ability could be cast at ([method Ability.accepts]): a hostile-only bolt splashes the enemies around its
## target and passes the caster's friends and followers by.
##
## Past the hit itself it can keep hurting, in one-second ticks (a firebolt's burn), and it can slow what it
## lands on through the target's own `slow(factor, seconds)` (a frostbolt), for anything that has one. Every hit, tick
## and slow names the caster ([method Ability.affect]), so an enemy puts the caster on its threat table and a Player
## on another peer accepts it.

@export var damage: float = 30.0
@export var splash_radius: float = 0.0 ## Others within this of the impact take [member damage] as well; 0 hits the target alone.

@export_group("Over time", "over_time_")
@export var over_time_damage: float = 0.0 ## Dealt in one-second ticks after the hit, spread over the duration; 0 is none.
@export var over_time_duration: float = 0.0 ## Seconds the ticks go on for.

@export_group("Slow", "slow_")
@export_range(0.0, 1.0) var slow_factor: float = 1.0 ## The target moves at this fraction of its speed after the hit; 1 is no slow.
@export var slow_duration: float = 0.0 ## Seconds the slow lasts.


func _init() -> void:
	target_kinds = Kind.NEUTRAL | Kind.HOSTILE


## A Player always has somewhere to send it: the crosshair finds a target or the bolt goes where it is aimed.
## An NPC needs an actual target, so it never spends the cooldown casting a bolt at nothing.
func can_cast(caster: Node3D) -> bool:
	return caster is Player or is_instance_valid(get_target(caster))


func activate(_caster: Node3D) -> bool:
	return true


func impact(caster: Node3D, target: Node3D) -> void:
	var from: Vector3 = caster.global_position if is_instance_valid(caster) else Vector3.ZERO
	if is_instance_valid(target) and target.has_method("take_hit"):
		Ability.affect(target, &"take_hit", [damage, from], caster)
		_apply_after_effects(target, caster)
	if splash_radius <= 0.0 or not is_instance_valid(target) or not is_instance_valid(caster):
		return
	var at: Vector3 = target.global_position
	for other: Node in target.get_tree().get_nodes_in_group(&"Focusable"):
		if other == target or not other is Node3D or not accepts(other as Node3D, caster) or not other.has_method("take_hit"):
			continue
		if (other as Node3D).global_position.distance_to(at) <= splash_radius:
			Ability.affect(other, &"take_hit", [damage, from], caster)
			_apply_after_effects(other as Node3D, caster)


## The slow and the burn, on whatever the hit landed on. A target with no `slow` of its own simply is not
## slowed, so the same spell works on anything that can be hurt.
func _apply_after_effects(target: Node3D, caster: Node3D) -> void:
	if slow_factor < 1.0 and slow_duration > 0.0 and target.has_method("slow"):
		Ability.affect(target, &"slow", [slow_factor, slow_duration], caster)
	if over_time_damage > 0.0 and over_time_duration > 0.0:
		var ticks: int = maxi(1, roundi(over_time_duration))
		_schedule_tick(target, caster.get_path() if is_instance_valid(caster) and caster.is_inside_tree() else ^"", over_time_damage / ticks, ticks)


## The numbers for the spells screen: the hit, the splash, the ticks, the slow, then what the impact does to
## the world.
func get_details() -> String:
	var lines: PackedStringArray = ["Damage: %d" % roundi(damage)]
	if splash_radius > 0.0:
		lines.append("Splash: %d m" % roundi(splash_radius))
	if over_time_damage > 0.0 and over_time_duration > 0.0:
		lines.append("Damage over time: %d over %d s" % [roundi(over_time_damage), roundi(over_time_duration)])
	if slow_factor < 1.0 and slow_duration > 0.0:
		lines.append("Slows to %d%% for %d s" % [roundi(slow_factor * 100.0), roundi(slow_duration)])
	var world: String = super()
	if not world.is_empty():
		lines.append(world)
	return "\n".join(lines)


func _schedule_tick(target: Node3D, caster_path: NodePath, amount: float, ticks_left: int) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	target.get_tree().create_timer(1.0).timeout.connect(_tick.bind(target, caster_path, amount, ticks_left))


## A tick comes "from" the target itself, so the shove of the first hit never repeats; it still names the caster,
## by path, since the caster may be gone by the last tick.
func _tick(target: Node3D, caster_path: NodePath, amount: float, ticks_left: int) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	Ability.affect(target, &"take_hit", [amount, target.global_position], null if caster_path.is_empty() else target.get_node_or_null(caster_path))
	if ticks_left > 1:
		_schedule_tick(target, caster_path, amount, ticks_left - 1)
