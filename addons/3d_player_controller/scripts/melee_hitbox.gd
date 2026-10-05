class_name MeleeHitbox
extends Area3D
## An attack volume on a weapon or limb, in the spirit of Zelda's AT collision: it hurts each body it
## overlaps once per swing, only during the swing's active frames, so a hit lands because the weapon
## touched the target. Put it on the bone attachment that carries the weapon and call [method swing]
## when the animation reaches the strike.

signal hit(body: Node3D) ## Emitted once per body per swing.

@export var attacker: Node3D ## The body swinging; never hurts itself, and is named as the hit's source ([method Ability.affect]).
@export var damage: float = 15.0
@export var active_seconds: float = 0.35 ## How long the swing stays live after [method swing].

var live: bool = false ## True during the active frames; the area keeps monitoring so overlaps stay known.
var _hit_this_swing: Array[Node3D] = []

@onready var active_timer: Timer = $ActiveTimer ## Its timeout is wired to [method _on_active_timer_timeout] in the scene.


## Goes live for [member active_seconds]; bodies already inside are struck at once.
func swing() -> void:
	_hit_this_swing.clear()
	live = true
	active_timer.start(active_seconds)
	for body: Node3D in get_overlapping_bodies():
		_on_body_entered(body)


## Wired to body_entered.
func _on_body_entered(body: Node3D) -> void:
	if not live or body == attacker or body in _hit_this_swing or not body.has_method("take_hit"):
		return
	_hit_this_swing.append(body)
	Ability.affect(body, &"take_hit", [damage, global_position], attacker)
	hit.emit(body)


func _on_active_timer_timeout() -> void:
	live = false
