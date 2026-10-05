class_name Jumping
extends NodeStateMachine


## Called when there is an input event.
func _input(event: InputEvent) -> void:

	# Do nothing if the player is not set
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# A dive from the air, Odyssey's move: Sprint, or Throw with Crouch held (ZL and Y), while off the ground
	if event.is_action_pressed(&"sprint") or (event.is_action_pressed(&"throw") and player.is_action_pressed(&"crouch")):
		if player.try_air_dive(state):
			get_viewport().set_input_as_handled()
			return

	# Shield surfing: Focus held and Action pressed in the air drops the Player onto their shield
	if event.is_action_pressed(&"action") and not event.is_echo() and player.try_shield_surf(state):
		get_viewport().set_input_as_handled()
		return

	# Jump action triggers while jumping
	if event.is_action_pressed(&"jump") and not player.is_on_floor():
		# A game with a double jump means the jump, wall or no wall
		if player.air_jump():
			get_viewport().set_input_as_handled()
			return
		if player.ledge_detection_horizontal.is_colliding():
			# Exhausted players cannot grab the wall
			if not player.is_exhausted:
				player.state_machine.travel(state, States.CLIMBING)
				get_viewport().set_input_as_handled()
			return
		elif (not player.paraglider_raycast.is_colliding() or player.is_in_updraft()) and not player.is_exhausted:
			player.state_machine.travel(state, States.PARAGLIDING)
			get_viewport().set_input_as_handled()
			return
		elif player.paraglider_raycast.is_colliding() and not player.is_jump_queued:
			player.state_machine.travel(state, States.FLYING)
			get_viewport().set_input_as_handled()
			return


## Called every physics frame.
func _physics_process(_delta: float) -> void:

	# Do nothing if the player is not set
	if not player: return

	# Check if the player has reached the floor
	if player.is_on_floor() and not player.is_jump_queued:
		# The landing hurts, and a hard enough one kills: the death takes it from there
		player.take_fall(player.last_fall_speed)
		if not player.health.is_alive():
			return
		if player.last_fall_speed >= player.lethal_fall_speed:
			player.state_machine.travel(state, States.RAGDOLLING)
		else:
			# Start "standing"
			player.state_machine.travel(state, States.STANDING)
		return

	# Hand off to "falling" once the jump starts descending so is_falling drives the falling animation and air control.
	if not player.is_on_floor() and not player.is_jump_queued and player.velocity.dot(player.up_direction) < 0.0:
		player.state_machine.travel(state, States.FALLING)


## Start "jumping".
func start() -> void:
	super.start()
	# Flag the player as "jumping"
	player.is_jumping = true
	# Flag the player as having a "jump queued"
	player.is_jump_queued = true
	# A platformer leaves the ground now; the clip's keyframe then finds nothing queued, and the clip is asked for
	# by name since the tree's own edge waits for a queued jump
	if player.instant_jump and player.is_on_floor():
		player.execute_jump()
		player.travel_locomotion("RunningJump" if player.has_move_input else "JumpingUp")
	# HeavyBreathing has no direct jump edge; return to the normal locomotion graph.
	if player.current_locomotion_node == "HeavyBreathing":
		player.travel_locomotion("StandingLocomotion")


## Stop "jumping".
func stop() -> void:
	super.stop()
	# Flag the player as not "jumping"
	player.is_jumping = false
	# Flag the player as not having a "jump queued"
	player.is_jump_queued = false
	# Flag the player as not "flipping"
	player.is_front_flipping = false
	player.is_back_flipping = false
