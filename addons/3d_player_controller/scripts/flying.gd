class_name Flying
extends NodeStateMachine

const DOUBLE_TAP_TIME: float = 0.3 ## Window (s) in which a second stop-action press stops flying.

@export_category("Flying Controls")
@export_group("Keyboard/Mouse Actions")
@export var keyboard_up_action: StringName = &"jump"
@export var keyboard_down_action: StringName = &"crouch"
@export var keyboard_stop_action: StringName = &"crouch" ## Requires a double-press

@export_group("Controller/Touch Actions")
@export var pad_up_action: StringName = &"jump"
@export var pad_down_action: StringName = &"action"
@export var pad_stop_action: StringName = &"action" ## Requires a double-press

var _double_tap_timer: SceneTreeTimer ## Runs after a stop-action press; a second press before it expires stops flying.


## Called when there is an input event.
func _input(event: InputEvent) -> void:

	# Do nothing if the player is not set or is paused/ragdolling
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Stop flying on a double-press of the stop action
	if event.is_action_pressed(action(keyboard_stop_action, pad_stop_action)) and not event.is_echo():
		if _double_tap_timer and _double_tap_timer.time_left > 0.0:
			_double_tap_timer = null
			player.state_machine.travel(state, States.STANDING if player.is_on_floor() else States.FALLING)
		else:
			_double_tap_timer = get_tree().create_timer(DOUBLE_TAP_TIME)


## Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:

	# Do nothing if the player is not set
	if not player: return

	var up_dir: Vector3 = player.up_direction.normalized()

	# Check if the player has reached the floor
	if player.is_on_floor():
		# Start "standing"
		player.state_machine.travel(state, States.STANDING)
		return

	# While flying, movement is driven relative to camera / input
	var target_motion: Vector2 = player.player_input.motion

	# Update sprint flag and locomotion blend position in FlyingLocomotion
	player.is_sprinting = player.is_action_pressed(&"sprint") and not player.is_exhausted and not player.is_typing and not player.is_paused
	var speed_blend: float = target_motion.length()
	if player.is_sprinting:
		speed_blend *= 1.5
	player.animation_tree.set(Player.FLYING_LOCOMOTION_BLEND_POSITION_PATH, speed_blend)

	# Calculate camera-relative movement direction projected onto up_dir plane
	var camera_basis: Basis = player.spring_arm.global_transform.basis
	var target_dir: Vector3 = camera_basis * Vector3(target_motion.x, 0.0, -target_motion.y)
	target_dir = target_dir.slide(up_dir)

	if target_dir.length_squared() > 0.001 and not player.is_firing_arrow:
		target_dir = target_dir.normalized()
		var q_from: Quaternion = player.orientation.basis.get_rotation_quaternion()
		var q_to: Quaternion = Basis.looking_at(-target_dir, up_dir).get_rotation_quaternion()
		player.orientation.basis = Basis(q_from.slerp(q_to, delta * player.rotation_interpolate_speed))

	# Horizontal speed
	var fly_speed: float = 14.0 if player.is_sprinting else 8.0
	var h_velocity: Vector3 = Vector3.ZERO
	if target_dir.length_squared() > 0.001:
		h_velocity = target_dir.normalized() * fly_speed * (speed_blend / (1.5 if player.is_sprinting else 1.0))

	# Vertical control along player.up_direction (jump to fly upward along up_dir, crouch/down to fly downward along -up_dir)
	var v_speed: float = 0.0
	if player.is_typing or player.is_paused:
		pass # Typed keys never fly, and nor does anything behind a menu
	elif player.is_action_pressed(action(keyboard_up_action, pad_up_action)):
		v_speed = 6.0
	elif player.is_action_pressed(action(keyboard_down_action, pad_down_action)):
		v_speed = -6.0

	player.velocity = h_velocity + (up_dir * v_speed)
	player.update_movement_and_rotation(delta)


## Start "flying".
func start() -> void:
	super.start()
	# Flag the player as "flying"
	player.is_flying = true
	# Flag the player as not jumping or falling
	player.is_jumping = false
	player.is_falling = false
	# Teleport locomotion playback into the FlyingLocomotion animation state.
	player.locomotion_state.start("FlyingLocomotion")


## Stop "flying".
func stop() -> void:
	super.stop()
	# Flag the player as not "flying"
	player.is_flying = false
	_double_tap_timer = null


func get_contextual_controls(input_type: int) -> Dictionary:
	return {
		player.controls.action_label(&"jump", player.controls.joypad_button_3_label): "Fly Up",
		player.controls.left_joystick_label: "Fly",
		player.controls.right_joystick_label: "Camera",
		player.controls.joypad_button_7_label if input_type == Controls.InputType.KEYBOARD_MOUSE else player.controls.action_label(&"action", player.controls.joypad_button_0_label): "Fly Down",
	}
