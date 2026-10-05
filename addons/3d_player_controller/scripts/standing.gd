class_name Standing
extends NodeStateMachine


## Called when there is an input event.
func _input(event: InputEvent) -> void:

	# Do nothing if the player is not set
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Attack; an exhausted Player is catching their breath, and HeavyBreathing has no path into the attack animations
	if event.is_action_pressed(&"attack") and player.inventory.can_player_attack and not player.is_exhausted:
		get_viewport().set_input_as_handled()
		player.state_machine.travel(state, States.ATTACKING)
		return

	# A tap of Sprint while still is a backstep (a roll needs the dodge enabled)
	if event.is_action_released(&"sprint") and player.try_dodge(state):
		get_viewport().set_input_as_handled()
		return

	# Jump
	if event.is_action_pressed(&"jump"):
		player.is_boxing = false
		# While focusing (strafing), jumping with forward/backward input performs a flip.
		player.is_front_flipping = player.is_focusing and player.is_action_pressed(&"move_up")
		player.is_back_flipping = player.is_focusing \
				and player.is_action_pressed(&"move_down") \
				and not player.is_front_flipping
		get_viewport().set_input_as_handled()
		player.state_machine.travel(state, States.JUMPING)
		return

	# Crouch
	if event.is_action_pressed(&"crouch"):
		get_viewport().set_input_as_handled()
		player.state_machine.travel(state, States.CROUCHING)
		return


## Called every physics frame.
func _physics_process(_delta: float) -> void:

	# Do nothing if the player is not set
	if not player: return

	# Sprint while the sprint action is held (a continuous action) and the player is moving
	if player.is_action_pressed(&"sprint") and not player.is_exhausted and not player.is_typing and (player.smoothed_motion.y > 0.0 if player.is_focusing else player.smoothed_motion.length() > 0.0):
		player.state_machine.travel(state, States.SPRINTING)
		return

	# Start "pushing" when moving into a wall while unarmed and unencumbered
	if player.get_grounded_locomotion_state() == &"StandingLocomotion" \
	and not player.is_focusing \
	and not (player.held_object and player.held_object.is_holding_object()) \
	and is_player_pushing_into_wall():
		player.state_machine.travel(state, States.PUSHING)
		return

	# Held move input has no signal: while exhausted, swap between HeavyBreathing (idle) and the grounded locomotion (moving)
	if player.is_exhausted:
		var grounded_locomotion: String = String(player.get_grounded_locomotion_state())
		if player.current_locomotion_path != grounded_locomotion:
			player.travel_locomotion(grounded_locomotion)

	# Check if the player is no longer on the floor
	if not player.is_on_floor() and not player.falling_raycast.is_colliding():
		# Start "falling"
		player.state_machine.travel(state, States.FALLING)


## Start "standing".
func start() -> void:
	super.start()
	# Flag the player as "standing"
	player.is_standing = true
	# Transition directly to the grounded locomotion that matches the equipped state.
	player.travel_locomotion(String(player.get_grounded_locomotion_state()))


## Stop "standing".
func stop() -> void:
	super.stop()
	# Flag the player as not "standing"
	player.is_standing = false


## Wired to Inventory.equipment_changed and Player.exhausted_changed in player.tscn: travels to the grounded
## locomotion matching the current equipment and exhaustion, while standing.
func _on_grounded_locomotion_changed(_is_exhausted: bool = false) -> void:
	if process_mode == Node.PROCESS_MODE_INHERIT:
		player.travel_locomotion(String(player.get_grounded_locomotion_state()))
