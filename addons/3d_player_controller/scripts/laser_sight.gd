class_name LaserSight
extends Node3D
## A laser pointer: a thin beam from a muzzle to the aim point plus a dot on the surface hit.
## [member top_level] is set in the scene so [method aim] can place it in world space while it
## stays a child of the weapon it belongs to.

@onready var beam: MeshInstance3D = %Beam
@onready var dot: MeshInstance3D = %Dot


## Stretches the beam from [param from] to [param to] and parks the dot at [param to].
func aim(from: Vector3, to: Vector3) -> void:
	var length: float = from.distance_to(to)
	if length < 0.001:
		return
	global_position = from
	look_at(to)
	beam.scale = Vector3(1.0, 1.0, length)
	beam.position = Vector3(0.0, 0.0, -length * 0.5)
	dot.global_position = to
