class_name KillZone
extends Area3D
## The bottom of the world, lava, the void: a [Player] that falls in dies here and comes back at their checkpoint
## through the ordinary death flow (ragdoll, the death screen, the RespawnTimer, [method Player.respawn]). With
## [member lethal] off they are only put back at [member Player.respawn_transform], for a pit that costs nothing.
## Anything else that carries a [Health] (an enemy, a companion) is killed outright on its own authority. A Player
## riding or flying through is left alone: the vehicle is what fell, and a flier is not falling.

signal killed(body: Node3D) ## A body was killed or put back by this zone.

@export var lethal: bool = true ## Kill the Player rather than teleport them back to their checkpoint.


## Wired to body_entered in [code]kill_zone.tscn[/code].
func _on_body_entered(body: Node3D) -> void:
	if not contains(body.global_position):
		return
	if body is Player:
		var player: Player = body as Player
		if not player.is_multiplayer_authority() or player.is_riding or player.is_flying:
			return
		if lethal and player.health.is_alive():
			# Straight to the health, not through take_hit: a roll's invulnerability frames do not save anyone from lava
			player.health.damage(player.health.max_health, global_position)
		elif not lethal:
			player.warp_to(player.respawn_transform)
		killed.emit(body)
		return
	if not lethal or not body.is_multiplayer_authority():
		return
	var health: Health = body.get("health") as Health
	if health and health.is_alive():
		health.damage(health.max_health, global_position)
		killed.emit(body)


## Whether [param point] is inside one of this zone's box shapes right now. The body signal reports the physics
## step's overlaps, and a Player whose shape comes back on as they are put elsewhere (the ragdoll ending on a
## respawn) is reported a step late, from where the shape last was; a shape that is not a box counts as a hit.
func contains(point: Vector3) -> bool:
	for child: Node in get_children():
		if not child is CollisionShape3D:
			continue
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision.disabled:
			continue
		if not collision.shape is BoxShape3D:
			return true
		var local: Vector3 = collision.to_local(point)
		var half: Vector3 = (collision.shape as BoxShape3D).size * 0.5
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return true
	return false
