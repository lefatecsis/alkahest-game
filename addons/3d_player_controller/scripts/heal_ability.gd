class_name HealAbility
extends Ability
## Heals through the target's `heal(amount) -> bool` method. Self and Friendly by default: a Player heals the
## friend they have targeted, otherwise themselves; an NPC always heals itself. The cast is refused when the
## target is already full.

@export var amount: float = 50.0


func _init() -> void:
	target_kinds = Kind.SELF | Kind.FRIENDLY


## Refused when the patient has no health to restore.
func can_cast(caster: Node3D) -> bool:
	var target: Node3D = get_target(caster)
	if not target.has_method("heal"):
		return false
	return target.call("can_heal") if target.has_method("can_heal") else true


func activate(caster: Node3D) -> bool:
	return can_cast(caster)


## The heal names its healer ([method Ability.affect]), so the patient's peer accepts it from the healer's (see
## [method Player.heal]).
func impact(caster: Node3D, target: Node3D) -> void:
	if is_instance_valid(target) and target.has_method("heal"):
		Ability.affect(target, &"heal", [amount], caster)


## Heals land on the caster itself or the targeted friend, never at the aim point.
func get_impact_position(caster: Node3D) -> Vector3:
	return get_target(caster).global_position
