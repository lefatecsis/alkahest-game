class_name Sprinting
extends NodeStateMachine


## Called when there is an input event.
func _input(event: InputEvent) -> void:

	# Do nothing if the player is not set
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Attack
	if event.is_action_pressed(&"attack") and player.inventory.can_player_attack:
		get_viewport().set_input_as_handled()
		player.state_machine.travel(state, States.ATTACKING)
		return

	# Jump
	if event.is_action_pressed(&"jump"):
		player.is_boxing = false
		player.state_machine.travel(state, States.JUMPING)
		return

	# Slide; RunningSlide is reached only from StandingLocomotion, so a weapon out or the boxing stance does not slide
	if event.is_action_pressed(&"crouch") and player.current_locomotion_node == "StandingLocomotion":
		player.state_machine.travel(state, States.SLIDING)
		return

	# Sprint { Microsoft: Ⓑ, Nintendo: Ⓐ, Sony: Ⓞ, Keyboard: [Shift] }.
	if event.is_action_released(&"sprint"):
		# A tap rather than a hold is a roll; a hold let go is a walk again
		if player.try_dodge(state):
			return
		# Start "standing"
		player.state_machine.travel(state, States.STANDING)
		return


## Called every physics frame.
func _physics_process(_delta: float) -> void:
	# Do nothing if the player is not set
	if not player: return

	# Check if the player is exhausted
	if player.is_exhausted:
		# Start "standing"
		player.state_machine.travel(state, States.STANDING)
		return

	# Check if the player is no longer on the floor
	if not player.is_on_floor() and not player.falling_raycast.is_colliding():
		# Start "falling"
		player.state_machine.travel(state, States.FALLING)


## Start "sprinting".
func start() -> void:
	super.start()
	# Flag the player as "sprinting"
	player.is_sprinting = true


## Stop "sprinting".
func stop() -> void:
	super.stop()
	# Flag the player as not "sprinting"
	player.is_sprinting = false
