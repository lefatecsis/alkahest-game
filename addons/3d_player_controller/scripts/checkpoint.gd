class_name Checkpoint
extends Area3D
## A place a [Player] comes back to after dying. Walking through it makes [member Player.respawn_transform] the
## [member respawn_point] (or this node), heals when [member heals] is on, and emits [signal activated]; a
## [SaveGame] in the scene with [member SaveGame.save_on_checkpoint] writes the game on it. The body signal is
## wired in [code]checkpoint.tscn[/code]; only the Player's own peer answers, so a checkpoint replicates nothing.

signal activated(player: Player) ## A Player passed through and took this as their respawn point.

@export var one_shot: bool = false ## Fires once per Player rather than every time they pass through.
@export var heals: bool = true ## Restores the Player to full health on activation.
@export var respawn_point: Node3D ## Where the Player comes back, facing along its -Z; the area's own transform when empty.

var _activated_by: Array[Player] = []


func _ready() -> void:
	add_to_group(&"Checkpoint")
	for saver: Node in get_tree().get_nodes_in_group(&"SaveGame"):
		if saver is SaveGame:
			(saver as SaveGame).watch_checkpoint(self)


## The transform a respawn lands on.
func get_respawn_transform() -> Transform3D:
	return respawn_point.global_transform if respawn_point else global_transform


## Wired to body_entered: the Player's own peer takes the checkpoint.
func _on_body_entered(body: Node3D) -> void:
	if body is Player and body.is_multiplayer_authority():
		take(body as Player)


## Hands [param player] this checkpoint (a bonfire rested at, a shrine prayed at), as walking through it would.
func take(player: Player) -> void:
	if one_shot and _activated_by.has(player):
		return
	if not _activated_by.has(player):
		_activated_by.append(player)
	player.set_checkpoint(get_respawn_transform())
	if heals:
		player.heal(player.health.max_health)
	activated.emit(player)
