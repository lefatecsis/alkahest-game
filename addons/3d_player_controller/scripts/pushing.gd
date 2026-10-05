class_name Pushing
extends NodeStateMachine

@onready var stop_grace_timer: Timer = $StopGraceTimer ## Restarted on every frame of wall contact (grace for root-motion contact pulses); its timeout ends the push.


## Called every physics frame.
func _physics_process(_delta: float) -> void:

	# Do nothing if the player is not set
	if not player: return

	# Check if the player is no longer on the floor
	if not player.is_on_floor() and not player.falling_raycast.is_colliding():
		# Start "falling"
		player.state_machine.travel(state, States.FALLING)
		return

	# Check if the player has stopped moving or input motion is at or near 0
	if not player.has_move_input or (player.player_input and player.player_input.motion.length_squared() < 0.01):
		# Start "standing"
		player.state_machine.travel(state, States.STANDING)
		return

	# Keep pushing while in contact with the wall (or the ledge raycast is colliding)
	if is_player_pushing_into_wall() or (player.ledge_detection_horizontal and player.ledge_detection_horizontal.is_colliding()):
		stop_grace_timer.start()


## Wall contact was lost for longer than the grace period -> Start "standing".
func _on_stop_grace_timer_timeout() -> void:
	player.state_machine.travel(state, States.STANDING)


## Start "pushing".
func start() -> void:
	super.start()
	# Reset the wall contact grace period
	stop_grace_timer.start()
	# Flag the player as "pushing"; the AnimationTree auto-advances StandingLocomotion -> PushingStart -> Pushing
	player.is_pushing = true


## Stop "pushing".
func stop() -> void:
	super.stop()
	stop_grace_timer.stop()
	# Flag the player as not "pushing"; the AnimationTree auto-advances Pushing -> PushingStop -> StandingLocomotion
	player.is_pushing = false
