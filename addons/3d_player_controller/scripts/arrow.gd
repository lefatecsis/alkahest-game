class_name Arrow
extends Projectile
## A bow projectile: flies nose-first and sticks where it lands. It flies without drag, so the arc the [Bow] solves
## for the crosshair is the arc it flies.
## The template arrow on the bow model has [member is_template] set and never flies.
## arrow.tscn wires [signal Projectile.hit] to its "Impact" player (the TomMusic bow impact), so a landing is heard
## on every peer, each of which simulates the same round.


func _init() -> void:
	is_template = true # the arrow on the bow model; fire_arrow() clears this on the copy it launches
	sticks_on_hit = true
	lifetime = 10.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0


## Point the arrow along its trajectory while in flight, then sweep for hits.
func _physics_process(delta: float) -> void:
	if not freeze and linear_velocity.length() > 0.1:
		var direction: Vector3 = linear_velocity.normalized()
		look_at(global_position + direction, _stable_up(direction))
		rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	super(delta)
