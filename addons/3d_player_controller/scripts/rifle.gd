class_name Rifle
extends Firearm
## A [Firearm] that also loops the "RifleFiringStanding" spine emote while the Player holds shoot and stands
## still; on the move the emote fights the walk, so the rifle just fires.

const FIRING_EMOTE: StringName = &"RifleFiringStanding"


func _init() -> void:
	magazine_size = 30
	reserve_rounds = 90


func _physics_process(delta: float) -> void:
	super(delta)
	var emote_state: AnimationNodeStateMachinePlayback = player.animation_tree.get(Player.EMOTE_STATE_PLAYBACK_PATH)
	var emote_node: StringName = emote_state.get_current_node()
	if player.is_shooting and not player.has_move_input:
		player.emote_spine_blend = 1.0
		# The firing clip auto-advances to the aiming idle; restart it while shoot is held.
		if emote_node != FIRING_EMOTE:
			emote_state.start(FIRING_EMOTE)
	elif emote_node == FIRING_EMOTE or emote_node == &"RifleAimingStandingIdle":
		player.emote_spine_blend = 0.0
		emote_state.start("Idle")
