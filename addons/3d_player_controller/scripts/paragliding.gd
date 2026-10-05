class_name Paragliding
extends NodeStateMachine

@export_category("Paragliding Controls")
@export_group("Keyboard/Mouse Actions")
@export var keyboard_stop_action: StringName = &"crouch" ## Cancels the glide so the player can fall and grab walls to climb.
@export var keyboard_dive_action: StringName = &"sprint"

@export_group("Controller/Touch Actions")
@export var pad_stop_action: StringName = &"action"
@export var pad_dive_action: StringName = &"sprint"

@export_group("Glide Physics")
@export var glide_speed: float = 4.0 ## Minimum forward glide speed (m/s).
@export var dive_glide_speed: float = 8.0 ## Minimum forward speed while dive-gliding (m/s).
@export var glide_gravity_factor: float = 0.35 ## Gravity damping while gliding (1.0 = full gravity).
@export var max_glide_descent_speed: float = 4.0 ## Terminal descent speed during a normal glide (m/s).
@export var dive_acceleration: float = 15.0 ## Downward acceleration during a steep dive (m/s²).
@export var max_dive_speed: float = 12.0 ## Terminal descent speed during a steep dive (m/s).

@export_group("Thermal Updrafts")
@export var updraft_catch_boost: float = 6.0 ## Immediate vertical boost (m/s) when catching an updraft (BotW standard).
@export var updraft_lift_acceleration: float = 20.0 ## Continued lift acceleration inside an updraft (m/s²).
@export var max_updraft_lift_speed: float = 8.5 ## Maximum vertical speed from updraft lift (m/s).
@export var updraft_stamina_regen: float = 40.0 ## Stamina recovered per second while riding an updraft.

var is_in_updraft: bool = false
var is_diving: bool = false


## Called when there is an input event.
func _input(event: InputEvent) -> void:
	# Do nothing if the player is not set or is paused/ragdolling
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Off the glider onto the shield: Focus held and Action pressed, as in Breath of the Wild
	if event.is_action_pressed(&"action") and not event.is_echo() and player.try_shield_surf(state):
		get_viewport().set_input_as_handled()
		return

	# Stop "paragliding" and start "falling"
	if event.is_action_pressed(action(keyboard_stop_action, pad_stop_action)) and not event.is_echo():
		player.state_machine.travel(state, States.FALLING)


## Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	# Do nothing if the player is not set
	if not player: return

	# Check if the player has reached the floor
	if player.is_on_floor():
		# Start "standing"
		player.state_machine.travel(state, States.STANDING)
		return

	# Check if the player is exhausted: close the paraglider
	if player.is_exhausted:
		# Start "falling"
		player.state_machine.travel(state, States.FALLING)
		return

	# Check for thermal updraft areas
	var was_in_updraft: bool = is_in_updraft
	is_in_updraft = player.is_in_updraft()
	is_diving = not player.is_typing and not player.is_paused and player.is_action_pressed(action(keyboard_dive_action, pad_dive_action))

	# While paragliding, regular locomotion is blocked and movement is driven directly (below)
	# Use camera-relative input, then remove any component along up_direction so glide steering stays tangential.
	var camera_basis: Basis = player.spring_arm.global_transform.basis
	var target_dir: Vector3 = camera_basis * Vector3(player.player_input.motion.x, 0.0, -player.player_input.motion.y)
	target_dir = target_dir.slide(player.up_direction)
	if target_dir.length_squared() > 0.001 and not player.is_firing_arrow:
		# Slerp model orientation toward flight direction for smooth, frame-rate independent turning.
		target_dir = target_dir.normalized()
		var q_from: Quaternion = player.orientation.basis.get_rotation_quaternion()
		var q_to: Quaternion = Basis.looking_at(-target_dir, player.up_direction).get_rotation_quaternion()
		player.orientation.basis = Basis(q_from.slerp(q_to, delta * player.rotation_interpolate_speed))

	# Keep horizontal momentum while enforcing a minimum forward glide speed for controllability.
	var current_h_vel: Vector3 = player.velocity.slide(player.up_direction)
	var base_speed: float = dive_glide_speed if is_diving else glide_speed
	var target_glide_speed: float = maxf(current_h_vel.length(), base_speed)
	if target_dir.length_squared() > 0.001:
		current_h_vel = target_dir.normalized() * target_glide_speed

	var vertical_speed: float = player.velocity.dot(player.up_direction)

	if is_in_updraft:
		# Thermal updraft: immediate catch boost, then continued lift; recovers stamina (BotW standard)
		if not was_in_updraft:
			vertical_speed = maxf(vertical_speed, updraft_catch_boost)
		vertical_speed = minf(vertical_speed + delta * updraft_lift_acceleration, max_updraft_lift_speed)
		if player.enable_stamina and player.stamina:
			player.stamina.stamina += delta * updraft_stamina_regen
	elif is_diving:
		# Steep dive downwards
		vertical_speed = maxf(vertical_speed - delta * dive_acceleration, -max_dive_speed)
	else:
		# Normal damped descent
		vertical_speed = minf(vertical_speed, 0.0)
		vertical_speed += player.get_gravity().dot(player.up_direction) * glide_gravity_factor * delta
		vertical_speed = maxf(vertical_speed, -max_glide_descent_speed)

	player.velocity = current_h_vel + (player.up_direction * vertical_speed)
	player.update_movement_and_rotation(delta)


## Start "paragliding".
func start() -> void:
	super.start()
	# Flag the player as "paragliding"
	player.is_paragliding = true
	# Hide equipped item visuals while gliding to avoid clipping into the paraglider.
	player.inventory.set_equipment_visibility(false)
	# Teleport locomotion playback into the Paragliding animation state.
	player.locomotion_state.start("Paragliding")

	# Check if starting inside an active thermal updraft
	is_in_updraft = player.is_in_updraft()
	var vertical_speed: float = player.velocity.dot(player.up_direction)
	if is_in_updraft:
		# Paraglider catch: immediate upward launch boost, even when deployed near the ground (BotW standard)
		vertical_speed = maxf(vertical_speed, updraft_catch_boost)
	else:
		vertical_speed = minf(vertical_speed, 0.0)
	player.velocity = player.velocity.slide(player.up_direction) + (player.up_direction * vertical_speed)


## Stop "paragliding".
func stop() -> void:
	super.stop()
	# Flag the player as not "paragliding"
	player.is_paragliding = false
	is_in_updraft = false
	is_diving = false
	# Restore equipped item visuals when exiting glide.
	player.inventory.set_equipment_visibility(true)


func get_contextual_controls(input_type: int) -> Dictionary:
	return {
		player.controls.left_joystick_label: "Steer",
		player.controls.right_joystick_label: "Camera",
		player.controls.action_label(&"sprint", player.controls.joypad_button_1_label): "Dive",
		player.controls.joypad_button_7_label if input_type == Controls.InputType.KEYBOARD_MOUSE else player.controls.action_label(&"action", player.controls.joypad_button_0_label): "Cancel",
	}
