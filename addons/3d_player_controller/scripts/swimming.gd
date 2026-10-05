class_name Swimming
extends NodeStateMachine

@export_category("Swimming Controls")
@export_group("Keyboard/Mouse Actions")
@export var keyboard_climb_out_action: StringName = &"jump"
@export var keyboard_sprint_action: StringName = &"sprint"
@export var keyboard_crouch_action: StringName = &"crouch"

@export_group("Controller/Touch Actions")
@export var pad_climb_out_action: StringName = &"jump"
@export var pad_sprint_action: StringName = &"sprint"
@export var pad_crouch_action: StringName = &"crouch"

@export_group("Diving")
@export var enable_diving: bool = true ## Allows diving below the surface by holding the crouch action.
@export var dive_vertical_speed: float = 2.5 ## Vertical swim speed while descending/ascending (m/s).
@export var dive_entry_depth: float = 1.2 ## Depth below the surface (m) at which surface swimming becomes diving.
@export var dive_buoyancy_factor: float = 0.6 ## Passive float-back-up speed factor when shallow and not descending.
@export var dive_model_pitch_speed: float = 6.0 ## Interpolation speed of the dive body pitch.

@export_group("Water Effects")
@export var splash_scene: PackedScene ## One-shot splash spawned on water entry (assign water_splash.tscn in the scene).
@export var splash_min_impact_speed: float = 2.5 ## Minimum downward entry speed (m/s) that triggers a splash.
@export var enable_underwater_overlay: bool = true ## Fullscreen underwater filter while the camera is submerged.

const WATER_SURFACE_SNAP_RATIO: float = 0.75
const LEDGE_RAY_DEPTH: float = 0.3 ## While swimming the ledge ray scans this far below the surface, so rims flush with the water still register.
const SURFACE_EPSILON: float = 0.05 ## Depth (m) below which the player counts as being at the surface.

var _vertical_swim_effort: float = 0.0 ## 0-1 stroke effort from active vertical dive input (drives the swim blend without stick input).

var _ledge_ray_default_y: float = 0.0 ## Scene height of the ledge ray, restored when leaving the water.
@onready var _underwater_overlay: CanvasLayer = player.get_node_or_null(^"Hud/UnderwaterOverlay") as CanvasLayer if player else null


## Called when there is an input event.
func _input(event: InputEvent) -> void:

	# Do nothing if the player is not set or is paused/ragdolling
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Swimming, Climbing-On [Input]
	if player.current_locomotion_node == "SwimmingAtEdge" \
	and event.is_action_pressed(action(keyboard_climb_out_action, pad_climb_out_action)) \
	and not player.is_climbing_on:
		player.locomotion_state.travel("BracedHangClimbingOn")
		player.is_climbing_on = true


## Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:

	# Do nothing if the player is not set
	if not player: return

	# Water exhaustion check - respawn at safe shore position
	if player.is_exhausted and (player.is_swimming or player.current_state == state):
		if player.last_safe_shore_position != Vector3.ZERO:
			player.global_position = player.last_safe_shore_position
		player.velocity = Vector3.ZERO
		player.is_swimming = false
		_reset_diving()
		if player.stamina:
			player.stamina.stamina = player.stamina.max_value * 0.35
			player.is_exhausted = false
		player.state_machine.travel(state, States.STANDING)
		return

	# Water depth check
	var water_surface_along_up: float = get_water_surface_along_up()
	if is_nan(water_surface_along_up):
		if player.is_swimming:
			player.is_swimming = false
			_reset_diving()
	else:
		var current_position_along_up: float = player.up_direction.dot(player.global_position)
		# Leave the water once the surface drops below the player's mid-height
		if water_surface_along_up <= current_position_along_up + (_get_collision_height() * 0.5):
			player.is_swimming = false

		# Diving [Vertical Swim Control]
		var shoulder_offset: float = _get_collision_height() * WATER_SURFACE_SNAP_RATIO
		var depth_below_surface: float = water_surface_along_up - (current_position_along_up + shoulder_offset)
		var was_diving: bool = player.is_diving
		player.is_diving = enable_diving and player.is_swimming and depth_below_surface > dive_entry_depth
		var vertical_input: float = 0.0
		_vertical_swim_effort = 0.0
		if player.is_swimming and not player.is_climbing_on:
			if player.is_typing or player.is_paused:
				pass # Typed keys never dive or climb out, and nor does anything behind a menu
			elif enable_diving and player.is_action_pressed(action(keyboard_crouch_action, pad_crouch_action)):
				vertical_input = -1.0
				_vertical_swim_effort = 1.0
			elif depth_below_surface > SURFACE_EPSILON and player.is_action_pressed(action(keyboard_climb_out_action, pad_climb_out_action)):
				vertical_input = 1.0
				_vertical_swim_effort = 1.0
			elif not player.is_diving and depth_below_surface > SURFACE_EPSILON:
				# Gentle buoyancy floats the player back up to the surface line
				vertical_input = dive_buoyancy_factor
			# Never swim up through the surface
			if vertical_input > 0.0 and depth_below_surface <= SURFACE_EPSILON:
				vertical_input = 0.0
				_vertical_swim_effort = 0.0
		player.swim_vertical_speed = vertical_input * dive_vertical_speed

		# Pitch the player model while diving so the body follows the swim direction (camera stays level)
		var target_pitch: float = 0.0
		if player.is_diving:
			var h_speed: float = player.velocity.slide(player.up_direction).length()
			# Model mesh faces +Z of the orientation basis, so descending needs a positive X rotation
			target_pitch = atan2(-player.swim_vertical_speed, maxf(h_speed, 1.0))
		player.model_pitch = lerp_angle(player.model_pitch, target_pitch, clampf(delta * dive_model_pitch_speed, 0.0, 1.0))


		# Show the fullscreen underwater filter while the camera is below the water surface
		if _underwater_overlay:
			_underwater_overlay.visible = enable_underwater_overlay \
					and is_instance_valid(player.camera) \
					and player.up_direction.dot(player.camera.global_position) < water_surface_along_up

		# Refresh contextual HUD controls when the dive state flips
		if was_diving != player.is_diving and player.controls:
			_on_input_type_changed(player.controls.current_input_type)

	# Stop "swimming" if the player has been flagged as not "swimming" (e.g. by exiting the pool)
	if not player.is_swimming and player.current_locomotion_node != "BracedHangClimbingOn":
		_reset_diving()
		# Start "standing" or "falling"
		player.state_machine.travel(state, States.STANDING if player.is_on_floor() else States.FALLING)
		return

	# Ledge detection [Raycast]: swim to the edge when a ledge is found, back to open water when it is lost.
	# Scan just below the surface: a rim flush with the water sits under the default ray height.
	if not is_nan(water_surface_along_up):
		player.ledge_detection_horizontal.position.y = water_surface_along_up - player.up_direction.dot(player.global_position) - LEDGE_RAY_DEPTH
	var ledge_detected: bool = player.detect_ledge()
	var current_swimming_node: String = player.current_locomotion_node
	var is_at_edge: bool = current_swimming_node in ["SwimmingAtEdge", "SwimmingToEdge"]
	if is_at_edge and not ledge_detected:
		player.locomotion_state.travel("SwimmingLocomotion")
	elif not is_at_edge and ledge_detected:
		player.locomotion_state.travel("SwimmingToEdge")

	# Swimming, Speed [Input]
	var has_swim_movement: bool = (player.smoothed_motion.y > 0.0 if player.is_focusing else player.smoothed_motion.length() > 0.0)
	if player.is_swimming \
	and not player.is_exhausted \
	and not player.is_typing \
	and not player.is_paused \
	and has_swim_movement \
	and player.is_action_pressed(action(keyboard_sprint_action, pad_sprint_action)):
		player.animation_tree.set("parameters/LocomotionTimeScale/scale", 1.5)
		player.swimming_root_motion_multiplier = 3
		player.is_sprinting = true
	else:
		player.animation_tree.set("parameters/LocomotionTimeScale/scale", 1.0)
		player.swimming_root_motion_multiplier = 2
		player.is_sprinting = false

	# While swimming, keep SwimmingLocomotion active (unless swimming to/at an edge or mantling out) and feed its BlendSpace1D.
	if not is_at_edge and current_swimming_node not in ["BracedHangClimbingOn", "SwimmingLocomotion"] and not player.is_climbing_on:
		player.locomotion_state.travel("SwimmingLocomotion")
	# Feed the BlendSpace1D only while in normal swimming locomotion.
	# Vertical dive/ascend effort counts as stroke movement so diving animates without stick input.
	if current_swimming_node == "SwimmingLocomotion":
		var stroke: float = player.smoothed_motion.y if player.is_focusing else player.smoothed_motion.length()
		player.animation_tree.set(player.SWIMMING_LOCOMOTION_BLEND_POSITION_PATH, maxf(stroke, _vertical_swim_effort))


## Climbing-out animation finished -> stand on the ledge.
func _on_locomotion_node_changed(_state_path: String) -> void:
	if process_mode != Node.PROCESS_MODE_INHERIT: return

	if player.is_climbing_on and player.current_locomotion_node not in ["BracedHangClimbingOn", "FreeHangingClimbingOn"]:
		player.is_climbing_on = false
		player.global_position = player.climbing_on_target
		player.clear_ledge_visuals()
		# Start "standing"
		player.state_machine.travel(state, States.STANDING)


## Start "swimming".
func start() -> void:
	super.start()
	_ledge_ray_default_y = player.ledge_detection_horizontal.position.y
	# Splash on hard water entry, using the pre-impact fall speed
	var impact_speed: float = maxf(-player.velocity.dot(player.up_direction), player.last_fall_speed)
	# Flag the player as "swimming"
	player.is_swimming = true
	# Unconditionally snap player to floating level upon starting swim state
	var up_direction: Vector3 = player.up_direction.normalized()
	var water_surface_along_up: float = get_water_surface_along_up()
	if not is_nan(water_surface_along_up):
		var shoulder_offset: float = _get_collision_height() * WATER_SURFACE_SNAP_RATIO
		var target_position_along_up: float = water_surface_along_up - shoulder_offset
		var current_position_along_up: float = up_direction.dot(player.global_position)
		player.global_position += up_direction * (target_position_along_up - current_position_along_up)
		if impact_speed >= splash_min_impact_speed:
			var surface_point: Vector3 = player.global_position + up_direction * (water_surface_along_up - up_direction.dot(player.global_position))
			_spawn_entry_splash.rpc(surface_point, impact_speed)


## Spawns a one-shot splash at [param at], the water surface above the player, on every peer. Only the owning peer
## knows how hard the Player hit the water and where the surface is, so it sends both with the state change.
@rpc("authority", "call_local", "reliable")
func _spawn_entry_splash(at: Vector3, impact_speed: float) -> void:
	if splash_scene == null or not player.is_inside_tree() or player.get_parent() == null:
		return
	var splash: WaterSplash = splash_scene.instantiate() as WaterSplash
	if splash == null:
		return
	splash.impact_speed = impact_speed
	player.get_parent().add_child(splash)
	splash.global_position = at


## Stop "swimming".
func stop() -> void:
	super.stop()
	# Flag the player as not "swimming" (nor mid climb-out)
	player.is_swimming = false
	player.is_sprinting = false
	player.is_climbing_on = false
	player.clear_ledge_visuals()
	player.ledge_detection_horizontal.position.y = _ledge_ray_default_y
	_reset_diving()


## Clears all diving state (called on exit, exhaustion respawn, and leaving water).
func _reset_diving() -> void:
	player.is_diving = false
	player.swim_vertical_speed = 0.0
	player.model_pitch = 0.0
	_vertical_swim_effort = 0.0
	if _underwater_overlay:
		_underwater_overlay.visible = false


## Height of the player's collision shape, guarded against missing/atypical shapes.
func _get_collision_height() -> float:
	if not is_instance_valid(player.collision_shape) or player.collision_shape.shape == null:
		return 0.0
	var shape: Shape3D = player.collision_shape.shape
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).height
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size.y
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).height
	return 0.0


func get_contextual_controls(_input_type: int) -> Dictionary:
	var controls: Dictionary = {
		player.controls.action_label(&"sprint", player.controls.joypad_button_1_label): "Fast Swim",
		player.controls.left_joystick_label: "Swim",
		player.controls.right_joystick_label: "Camera",
		player.controls.action_label(&"jump", player.controls.joypad_button_3_label): "Surface" if player.is_diving else "Climb Out",
	}
	if player.is_diving:
		controls[player.controls.action_label(&"crouch", player.controls.joypad_button_7_label)] = "Dive Deeper"
	elif enable_diving:
		controls[player.controls.action_label(&"crouch", player.controls.joypad_button_7_label)] = "Dive"
	return controls


## Height of the water surface along up_direction, or NAN when the player is not in a box-shaped water area.
func get_water_surface_along_up() -> float:
	if not is_instance_valid(player.current_water_area):
		return NAN
	var collision_shape: CollisionShape3D = player.current_water_area.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		return NAN
	var up_in_local: Vector3 = collision_shape.global_basis.inverse() * player.up_direction
	var half_size: Vector3 = (collision_shape.shape as BoxShape3D).size * 0.5
	var half_extent_along_up: float = absf(up_in_local.x) * half_size.x \
			+ absf(up_in_local.y) * half_size.y \
			+ absf(up_in_local.z) * half_size.z
	return player.up_direction.dot(collision_shape.to_global(up_in_local.normalized() * half_extent_along_up))
