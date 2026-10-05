class_name Hanging
extends NodeStateMachine

@export_category("Hanging Controls")
@export_group("Keyboard/Mouse Actions")
@export var keyboard_drop_action: StringName = &"crouch"
@export var keyboard_climb_up_action: StringName = &"jump"

@export_group("Controller/Touch Actions")
@export var pad_drop_action: StringName = &"crouch"
@export var pad_climb_up_action: StringName = &"jump"

var _ledge_offset: Vector3 ## Where the ledge top was from the Player when they grabbed it, for a climb where the chest ray finds no wall.


## Called when there is an input event.
func _input(event: InputEvent) -> void:

	# Do nothing if the player is not set or is paused/ragdolling
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Drop / Let go (not while already climbing on to the ledge)
	if event.is_action_pressed(action(keyboard_drop_action, pad_drop_action)) and not player.is_climbing_on:
		# Stop "hanging" and start "falling"
		player.state_machine.travel(state, States.FALLING)
		get_viewport().set_input_as_handled()
		return

	# Hanging, Climbing-On / Back-Eject Leap [Input]
	if event.is_action_pressed(action(keyboard_climb_up_action, pad_climb_up_action)) and not event.is_echo():
		if player.player_input.motion.y < -0.1 and absf(player.player_input.motion.y) > absf(player.player_input.motion.x):
			player.leap_off_wall()
			player.state_machine.travel(state, States.FALLING)
			get_viewport().set_input_as_handled()
		# Climb on where the Player hangs now, not where they grabbed the ledge: a shimmy has moved them since.
		# detect_ledge finds the ledge top here; where the chest ray meets no wall (a thin lip, an eave) the ledge is
		# where it was when grabbed, carried along by the shimmy.
		elif player.is_hanging_braced or player.is_hanging_free:
			if not player.detect_ledge():
				player.climbing_on_target = player.global_position + _ledge_offset
			player.locomotion_state.travel("BracedHangClimbingOn" if player.is_hanging_braced else "FreeHangingClimbingOn")
			player.is_climbing_on = true
			get_viewport().set_input_as_handled()


## Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:

	# Do nothing if the player is not set
	if not player: return

	# Check if the player has reached the floor
	if player.is_on_floor():
		# Start "standing"
		player.state_machine.travel(state, States.STANDING)
		return

	# Update footing status if not climbing onto a ledge
	if not player.is_climbing_on:
		# Check if "hanging" (braced) [Raycast]
		if player.is_hanging_free \
		and player.hanging_braced_detection.is_colliding():
			player.locomotion_state.travel("BracedHangLocomotion")
			player.is_hanging_braced = true
			player.is_hanging_free = false

		# Check if "hanging" (free) [Raycast]
		if player.is_hanging_braced \
		and not player.hanging_braced_detection.is_colliding():
			player.locomotion_state.travel("FreeHangingLocomotion")
			player.is_hanging_braced = false
			player.is_hanging_free = true

	# Keep (rotate towards) facing the wall surface
	player.face_wall(delta)

	if player.is_hanging_braced:
		player.animation_tree.set(player.BRACED_HANG_LOCOMOTION_BLEND_POSITION_PATH, player.smoothed_motion.x)
	elif player.is_hanging_free:
		player.animation_tree.set(player.FREE_HANGING_LOCOMOTION_BLEND_POSITION_PATH, player.smoothed_motion.x)


## Climbing-on animation finished -> stand on the ledge.
func _on_locomotion_node_changed(_state_path: String) -> void:
	if process_mode != Node.PROCESS_MODE_INHERIT: return

	if player.is_climbing_on and player.current_locomotion_node not in ["BracedHangClimbingOn", "FreeHangingClimbingOn"]:
		player.is_climbing_on = false
		player.global_position = player.climbing_on_target
		# Start "standing"
		player.state_machine.travel(state, States.STANDING)


## Start "hanging".
func start() -> void:
	super.start()
	# Stop airborne momentum
	player.velocity = Vector3.ZERO
	player.is_jumping = false
	player.is_falling = false
	player.is_climbing = false
	player.is_climbing_on = false
	# Climbing found this ledge the moment it handed over
	_ledge_offset = player.climbing_on_target - player.global_position
	# Determine if the player can hang braced
	if player.hanging_braced_detection.is_colliding():
		# Travel to the "hanging" (braced) locomotion state
		player.locomotion_state.travel("BracedHangLocomotion")
		# Flag the player as "hanging" (braced)
		player.is_hanging_braced = true
	else:
		# Travel to the "hanging" (free) locomotion state
		player.locomotion_state.travel("FreeHangingLocomotion")
		# Flag the player as "hanging" (free)
		player.is_hanging_free = true


## Stop "hanging".
func stop() -> void:
	super.stop()
	# Flag the player as not "hanging" (nor mid climb-on)
	player.is_hanging_braced = false
	player.is_hanging_free = false
	player.is_climbing_on = false
	player.clear_ledge_visuals()


func get_contextual_controls(_input_type: int) -> Dictionary:
	return {
		player.controls.action_label(&"jump", player.controls.joypad_button_3_label): "Climb Up",
		player.controls.action_label(&"crouch", player.controls.joypad_button_7_label): "Drop",
		player.controls.left_joystick_label: "Shimmy",
		player.controls.right_joystick_label: "Camera",
	}
