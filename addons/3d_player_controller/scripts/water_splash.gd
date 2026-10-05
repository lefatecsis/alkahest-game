class_name WaterSplash
extends Node3D
## One-shot water entry splash: droplet burst plus expanding foam mist.
##
## Scales with [member impact_speed] and frees itself once every emitter has finished
## (each emitter's [signal GPUParticles3D.finished] is wired in the scene).

@export var impact_speed: float = 5.0 ## Downward entry speed (m/s); scales droplet count and velocity.
@export var emitters: Array[GPUParticles3D] ## One-shot emitters started on ready.


func _ready() -> void:
	var intensity: float = clampf(impact_speed / 8.0, 0.4, 1.6)
	for emitter: GPUParticles3D in emitters:
		emitter.amount_ratio = clampf(intensity, 0.1, 1.0)
		var material: ParticleProcessMaterial = emitter.process_material.duplicate() as ParticleProcessMaterial
		material.initial_velocity_min *= intensity
		material.initial_velocity_max *= intensity
		emitter.process_material = material
		emitter.emitting = true


## Frees the splash once no emitter is still emitting.
func _on_emitter_finished() -> void:
	for emitter: GPUParticles3D in emitters:
		if emitter.emitting:
			return
	queue_free()
