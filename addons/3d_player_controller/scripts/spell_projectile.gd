class_name SpellProjectile
extends Node3D
## A WoW-style spell bolt: an ability's casting VFX/SFX fly to the target and always arrive; no physics.
##
## Homing bolts follow a moving target. Every peer flies its own copy; only the caster's authority
## acts on [signal arrived]. Movement is stepped per physics frame because a homing path has no signal.

signal arrived(position: Vector3) ## Emitted at the destination just before the bolt frees itself.

var speed: float = 20.0 ## Metres per second.
var homing: bool = true ## Follow [member target] while it lives; otherwise fly to [member destination].
var target: Node3D ## Followed while homing; a freed target leaves the bolt flying to its last known point.
var destination: Vector3

@onready var audio: AudioStreamPlayer3D = $Audio


func _physics_process(delta: float) -> void:
	if homing and is_instance_valid(target):
		destination = Focus.get_focus_target_position(target)
	var offset: Vector3 = destination - global_position
	var step: float = speed * delta
	if offset.length() <= step:
		global_position = destination
		arrived.emit(destination)
		queue_free()
		return
	global_position += offset.normalized() * step
	if absf(offset.normalized().y) < 0.99:
		look_at(destination)
