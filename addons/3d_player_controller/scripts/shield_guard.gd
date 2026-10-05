class_name ShieldGuard
extends Node
## Breath of the Wild's shield: with a shield on the arm, holding Focus (ZL) on the ground raises it ([member
## Player.is_guarding], replicated, so every peer sees the guard pose), and a hit that comes from in front does no
## damage, only pushing the Player back a little. Pressing Action (A) just before the hit lands parries it: nothing
## gets through, and the attacker is thrown back and, an NPC, staggered ([method EnemyNpc.parried], on the server) or,
## a Player, shoved back on their own peer ([method Player.parried]). No slow motion: the fight carries straight on.
##
## It all happens on the guarding Player's own peer, where [method Player.take_hit] arrives, whoever threw the hit.

signal blocked(from: Vector3) ## A hit from [param from] was caught on the shield, on the guarding Player's peer.
signal parried(from: Vector3) ## A hit from [param from] was parried, on the guarding Player's peer.

@export var player: Player
@export var parry_action: StringName = &"action" ## Pressed while guarding, it readies a parry: A, as in the games.
@export_range(0.05, 1.0, 0.01, "suffix:s") var parry_window: float = 0.25 ## How long after the press a hit is parried rather than only blocked.
@export_range(30.0, 180.0, 1.0, "suffix:°") var guard_angle: float = 120.0 ## How wide the shield covers in front: Breath of the Wild's GuardableAngle.
@export var block_pushback: float = 1.5 ## Speed (m/s) a blocked hit pushes the guarding Player back.
@export var parry_label: String = "Parry" ## The Action button's word while guarding.

@onready var block_audio: AudioStreamPlayer3D = get_node_or_null("BlockAudio") as AudioStreamPlayer3D

var _parry_until: float = -1.0


## The guard follows Focus on the Player's own peer; the flag it sets replicates.
func _physics_process(_delta: float) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	var guarding: bool = player.is_focusing and can_guard()
	if guarding != player.is_guarding:
		player.is_guarding = guarding
		if player.controls:
			if guarding:
				player.controls.claim_action_label(parry_label, self)
			else:
				player.controls.release_action_label(self)


## Whether the Player could raise a shield now: one on the arm, feet on the ground, and hands free of anything else
## (a swing, a carried body, a ride, a climb, the water, the glider).
func can_guard() -> bool:
	if player.get_guard_shield() == null or not player.is_on_floor():
		return false
	return not (player.is_attacking or player.is_riding or player.is_shield_surfing or player.is_swimming \
			or player.is_climbing or player.is_hanging_braced or player.is_hanging_free or player.is_paragliding \
			or player.is_ragdolling or player.is_sitting or player.is_dodging or player.is_typing or player.is_paused \
			or (player.held_object and player.held_object.is_holding_object()))


## Action while guarding readies the parry, and is spent on it rather than on a pickup or a talk.
func _input(event: InputEvent) -> void:
	if player == null or not player.is_multiplayer_authority() or not player.is_guarding:
		return
	if event.is_action_pressed(parry_action) and not event.is_echo():
		_parry_until = _now() + parry_window
		get_viewport().set_input_as_handled()


## On the guarding Player's own peer, as a hit from [param from] arrives: true when the shield caught it, so it does
## nothing more. A parry sends the attacker [param source_path] names reeling; a block only pushes the Player back.
func intercept(from: Vector3, source_path: NodePath) -> bool:
	if not player.is_guarding or not covers(from):
		return false
	if _now() <= _parry_until:
		_parry_until = -1.0
		var source: Node = null if source_path.is_empty() else player.get_node_or_null(source_path)
		if source and source != player and source.has_method("parried"):
			source.call("parried", source.get_path_to(player))
		_ring.rpc(true)
		parried.emit(from)
	else:
		player.knock_back(from, block_pushback)
		_ring.rpc(false)
		blocked.emit(from)
	return true


## Whether a hit from [param from] meets the shield: inside [member guard_angle] of the way the Player faces.
func covers(from: Vector3) -> bool:
	var to: Vector3 = (from - player.global_position).slide(player.up_direction)
	if to.length_squared() < 0.0001:
		return false # from where the Player stands (a bolt from above, a fall): not something a shield faces
	var facing: Vector3 = player.player_model.global_basis.z.slide(player.up_direction)
	return rad_to_deg(facing.angle_to(to)) <= guard_angle * 0.5


## The shield ringing on every peer; a parry rings higher.
@rpc("authority", "call_local", "unreliable")
func _ring(was_parry: bool) -> void:
	if block_audio and block_audio.stream:
		block_audio.pitch_scale = 1.35 if was_parry else 1.0
		block_audio.play()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
