class_name SyncedBody
extends MultiplayerSynchronizer
## Replicates a physics body from its multiplayer authority (the server by default).
## Peers that do not own the body freeze it kinematically so replicated transforms are not fought by
## local physics; the authority simulates as usual. Pair it with
## [code]resources/replication/rigid_body_replication.tres[/code] (RigidBody3D) or
## [code]resources/replication/character_body_replication.tres[/code] (CharacterBody3D).


func _ready() -> void:
	var body: RigidBody3D = get_parent() as RigidBody3D
	if body and not is_multiplayer_authority():
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
