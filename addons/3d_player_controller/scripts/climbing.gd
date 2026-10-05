class_name Climbing
extends NodeStateMachine

@export_category("Climbing Controls")
@export_group("Keyboard/Mouse Actions")
@export var keyboard_drop_action: StringName = &"crouch"
@export var keyboard_hop_action: StringName = &"jump"
@export var keyboard_sprint_action: StringName = &"sprint"

@export_group("Controller/Touch Actions")
@export var pad_drop_action: StringName = &"crouch"
@export var pad_hop_action: StringName = &"jump"
@export var pad_sprint_action: StringName = &"sprint"

@export_group("Climbing Jump")
## Stamina a hop up, left or right off the wall costs, as Breath of the Wild's climbing jump takes a chunk of the wheel
## at once. Its exact figure is not published, so this is a tunable; the hop that pays the last of it still goes, and
## leaves the Player exhausted. Leaping back off the wall is free.
@export var hop_stamina_cost: float = 15.0

@export_group("Rain Slipping")
@export var rain_slip_enabled: bool = true ## BotW-style slipping on wet walls during rain.
@export var rain_slip_precipitation_threshold: float = 0.4 ## Precipitation strength at which walls become slippery.
@export var rain_slip_interval: float = 1.6 ## Seconds of wet climbing between slips.
@export var rain_slip_distance: float = 0.6 ## Meters slid down the wall per slip.
@export var rain_climb_timescale: float = 0.65 ## Climb animation speed multiplier on wet walls (sprint climbing is blocked).

## Minimum stick/key deflection for climbing hop direction input.
const HOP_INPUT_DEADZONE: float = 0.1

@onready var rain_slip_timer: Timer = $RainSlipTimer ## Repeats every [member rain_slip_interval] while the wall is wet; each timeout slips the climber down.


## Called when there is an input event.
func _input(event: InputEvent) -> void:

	# Do nothing if the player is not set or is paused/ragdolling
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Drop / Let go
	if event.is_action_pressed(action(keyboard_drop_action, pad_drop_action)):
		# Start "falling"
		player.state_machine.travel(state, States.FALLING)
		get_viewport().set_input_as_handled()
		return

	# Climbing, Hopping [Input]
	if not player.is_on_floor() \
	and event.is_action_pressed(action(keyboard_hop_action, pad_hop_action)) \
	and not event.is_echo() \
	and player.current_locomotion_node in ["ClimbingLocomotion", "BracedHangLocomotion"]:
		var motion: Vector2 = player.player_input.motion
		# Check: Down/Back input past deadzone -> Wall Leap / Back-Eject off wall
		var leap_back: bool = motion.y < -HOP_INPUT_DEADZONE and absf(motion.y) > absf(motion.x)
		# Check: Left input past deadzone, and |x| > |y| ensures horizontal input dominance (<45° angle to -X).
		var hop_left: bool = motion.x < -HOP_INPUT_DEADZONE and absf(motion.x) > absf(motion.y)
		# Check: Right input past deadzone, and |x| > |y| ensures horizontal input dominance (<45° angle to +X).
		var hop_right: bool = motion.x > HOP_INPUT_DEADZONE and absf(motion.x) > absf(motion.y)
		# Check: Up input past deadzone, and |y| > |x| ensures vertical input dominance (<45° angle to +Y).
		var hop_up: bool = motion == Vector2.ZERO or (motion.y > HOP_INPUT_DEADZONE and absf(motion.y) > absf(motion.x))
		# A hop is a climbing jump, and costs its chunk of stamina; an exhausted Player cannot make one
		var climbing_on: bool = player.is_hanging_braced and player.ledge_detection_vertical and player.ledge_detection_vertical.is_colliding()
		if not leap_back and not climbing_on and (hop_left or hop_right or hop_up) and not player.stamina.spend(hop_stamina_cost):
			get_viewport().set_input_as_handled()
			return
		# Determine which hop direction to take based on input
		if leap_back:
			player.leap_off_wall()
			player.state_machine.travel(state, States.FALLING)
			get_viewport().set_input_as_handled()
			return
		elif hop_left:
			player.locomotion_state.travel("BracedHangHopLeft")
			player.is_hopping_from_climbing = player.is_climbing
			player.is_climbing_hopping_left = true
			player.is_climbing_hopping_right = false
			player.is_climbing_hopping_up = false
			get_viewport().set_input_as_handled()
		elif hop_right:
			player.locomotion_state.travel("BracedHangHopRight")
			player.is_hopping_from_climbing = player.is_climbing
			player.is_climbing_hopping_left = false
			player.is_climbing_hopping_right = true
			player.is_climbing_hopping_up = false
			get_viewport().set_input_as_handled()
		else:
			# Check if the player can climb on to the ledge detection target
			if player.is_hanging_braced and player.ledge_detection_vertical and player.ledge_detection_vertical.is_colliding():
				player.climbing_on_target = player.ledge_detection_vertical.get_collision_point()
				player.locomotion_state.travel("BracedHangClimbingOn")
				player.is_climbing = false
				player.is_climbing_on = true
				player.is_hanging_braced = false
				player.is_hanging_free = false
				player.is_climbing_hopping_left = false
				player.is_climbing_hopping_right = false
				player.is_climbing_hopping_up = false
				get_viewport().set_input_as_handled()
			# If the ledge detection target is not valid, the player will hop up instead.
			elif hop_up:
				player.locomotion_state.travel("BracedHangHopUp")
				player.is_hopping_from_climbing = player.is_climbing
				player.is_climbing_hopping_left = false
				player.is_climbing_hopping_right = false
				player.is_climbing_hopping_up = true
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

	# Check if the player is exhausted: let go of the wall
	if player.is_exhausted and not player.is_climbing_on:
		# Start "falling"
		player.state_machine.travel(state, States.FALLING)
		return

	# Rain slipping [Weather]: wet walls periodically slide the player down (BotW style)
	var wall_is_wet: bool = rain_slip_enabled \
			and player.is_climbing \
			and player.get_precipitation_strength() >= rain_slip_precipitation_threshold
	if not wall_is_wet:
		rain_slip_timer.stop()
	elif rain_slip_timer.is_stopped():
		rain_slip_timer.start(rain_slip_interval)

	# Ledge detection [Raycast]
	var ledge_detected: bool = player.detect_ledge()

	# Check if "climbing" player has reached a ledge -> Start "hanging" (braced)
	if ledge_detected and player.is_climbing and player.player_input.motion.length() > 0.1:
		var player_top_position: float = player.global_position.y + player.collision_shape.shape.height + 0.1
		# Check if the player's top position has reached or exceeded the ledge detection marker's Y-position
		if player_top_position >= player.ledge_detection_marker.global_position.y:
			# Start "hanging"
			player.state_machine.travel(state, States.HANGING)
			return

	# Climbing, Speed Up [Input]; sprint climbing is blocked on wet walls
	if player.is_climbing \
	and not player.is_exhausted \
	and not player.is_typing \
	and not player.is_paused \
	and not wall_is_wet \
	and player.is_action_pressed(action(keyboard_sprint_action, pad_sprint_action)):
		player.animation_tree.set("parameters/LocomotionTimeScale/scale", 1.5)
		player.is_sprinting = true
	else:
		player.animation_tree.set("parameters/LocomotionTimeScale/scale", rain_climb_timescale if wall_is_wet else 1.0)
		player.is_sprinting = false

	# Keep (rotate towards) facing the wall surface
	player.face_wall(delta)

	if player.is_climbing:
		player.animation_tree.set(player.CLIMBING_LOCOMOTION_BLEND_POSITION_PATH, player.smoothed_motion)


## Tracks hop and climb-on animations: hops end back in climbing/hanging, climbing on ends on top of the ledge.
func _on_locomotion_node_changed(_state_path: String) -> void:
	if process_mode != Node.PROCESS_MODE_INHERIT: return

	var current_node: String = player.current_locomotion_node
	# Climbing, Hopping [Status]
	var was_hopping: bool = player.is_climbing_hopping_left or player.is_climbing_hopping_right or player.is_climbing_hopping_up
	player.is_climbing_hopping_left = current_node == "BracedHangHopLeft"
	player.is_climbing_hopping_right = current_node == "BracedHangHopRight"
	player.is_climbing_hopping_up = current_node == "BracedHangHopUp"
	if was_hopping and not (player.is_climbing_hopping_left or player.is_climbing_hopping_right or player.is_climbing_hopping_up):
		player.is_climbing = player.is_hopping_from_climbing
		player.is_hanging_braced = not player.is_hopping_from_climbing
		player.is_hanging_free = false
		player.is_hopping_from_climbing = false

	# Climbing, Climbing On [Status]
	if player.is_climbing_on and current_node not in ["BracedHangClimbingOn", "FreeHangingClimbingOn"]:
		player.is_climbing_on = false
		player.global_position = player.climbing_on_target


## The wet wall slips the climber down.
func _on_rain_slip_timer_timeout() -> void:
	player.global_position -= player.up_direction * rain_slip_distance


## Start "climbing".
func start() -> void:
	super.start()
	# Stop airborne momentum
	player.velocity = Vector3.ZERO
	player.is_jumping = false
	player.is_falling = false
	# Flag the player as "climbing"
	player.is_climbing = true
	player.is_hanging_braced = false
	player.is_hanging_free = false
	player.is_climbing_on = false
	player.is_climbing_hopping_left = false
	player.is_climbing_hopping_right = false
	player.is_climbing_hopping_up = false
	# Travel to the "climbing" locomotion state
	player.locomotion_state.travel("ClimbingLocomotion")


## Stop "climbing".
func stop() -> void:
	super.stop()
	rain_slip_timer.stop()
	# Flag the player as not "climbing" and reset the hop/climb-on/hang flags it drives
	player.is_climbing = false
	player.is_climbing_hopping_left = false
	player.is_climbing_hopping_right = false
	player.is_climbing_hopping_up = false
	player.is_climbing_on = false
	player.is_hanging_braced = false
	player.is_hanging_free = false
	player.is_hopping_from_climbing = false
	# Reset timescale in case "sprint" action is still pressed
	player.animation_tree.set("parameters/LocomotionTimeScale/scale", 1.0)
	player.is_sprinting = false
	player.clear_ledge_visuals()


func get_contextual_controls(_input_type: int) -> Dictionary:
	return {
		player.controls.action_label(&"jump", player.controls.joypad_button_3_label): "Hop",
		player.controls.action_label(&"sprint", player.controls.joypad_button_1_label): "Fast Climb",
		player.controls.action_label(&"crouch", player.controls.joypad_button_7_label): "Drop",
		player.controls.left_joystick_label: "Climb",
		player.controls.right_joystick_label: "Camera",
	}
