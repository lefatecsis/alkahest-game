class_name Crouching
extends NodeStateMachine


## Called when there is an input event.
func _input(event: InputEvent) -> void:

	# Do nothing if the player is not set
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Attack; an exhausted Player is catching their breath, and HeavyBreathing has no path into the attack animations
	if event.is_action_pressed(&"attack") and player.inventory.can_player_attack and not player.is_exhausted:
		player.state_machine.travel(state, States.ATTACKING)
		return

	# Jump
	if event.is_action_pressed(&"jump"):
		player.is_boxing = false
		player.state_machine.travel(state, States.JUMPING)
		return

	# Crouch { Controller: Left Stick, Keyboard: Left Control }
	if event.is_action_released(&"crouch"):
		# Start "standing"
		player.state_machine.travel(state, States.STANDING)
		return


## Called every physics frame.
func _physics_process(_delta: float) -> void:

	# Do nothing if the player is not set
	if not player: return

	# Check if the player is no longer on the floor
	if not player.is_on_floor() and not player.falling_raycast.is_colliding():
		# Start "falling"
		player.state_machine.travel(state, States.FALLING)


## Start "crouching".
func start() -> void:
	super.start()
	# Flag the player as "crouching"
	player.is_crouching = true
	# Reduce the player's collision shape height and adjust its position to match the crouching posture
	player.collision_shape.shape.height = player.initial_collision_shape_height * 0.8
	player.collision_shape.position = Vector3(0, player.collision_shape.shape.height * 0.5, 0)


## Stop "crouching".
func stop() -> void:
	super.stop()
	# Flag the player as not "crouching"
	player.is_crouching = false
	# Reset the player's collision shape to its initial height and position
	player.collision_shape.shape.height = player.initial_collision_shape_height
	player.collision_shape.position = player.initial_collision_shape_position
