class_name StealthAbility
extends Ability
## Toggles [member Player.is_stealthed]: the model fades, followers lose the Player and any attack ends it.


func _init() -> void:
	is_toggle = true
	ends_on_attack = true


func activate(caster: Node3D) -> bool:
	if not caster is Player:
		return false
	(caster as Player).is_stealthed = true
	return true


func deactivate(caster: Node3D) -> void:
	if caster is Player:
		(caster as Player).is_stealthed = false
