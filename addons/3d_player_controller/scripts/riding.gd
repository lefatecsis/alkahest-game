class_name Riding
extends NodeStateMachine
## Rides whatever [member Player.riding] is: a skateboard, a vehicle, later a horse. The rideable owns the
## gameplay; this state hands it the Player, the input events and the physics tick, plays the animations it
## asks for, and does the Player's side of getting on and off: the get-on and get-off clips, the camera, the
## crosshair, the collision shape and the step-up ray.
##
## Rideable contract (duck typed, the addon depends on no rideable). Methods:
## [code]mount(player)[/code] and [code]dismount(player)[/code] on entering and leaving this state,
## [code]ride(player, delta)[/code] every physics frame; optional [code]ride_input(player, event)[/code],
## [code]locomotion_node_changed(player, state_path)[/code], and
## [code]get_contextual_controls(input_type)[/code] returning label names to text ([code]{"key_k": "Dismount"}[/code]
## for [member Controls.key_k_label]; a key that is a [StringName] names an action instead, and its word goes on
## whichever button carries that action under the rider's layout, so [code]{&"sprint": "Gallop"}[/code] lands on
## the button that sprints wherever that is; a key may also be the [Label] itself).
## Optional properties: [code]blocks_hands[/code] (weapons and items stay holstered, the crosshair hides),
## [code]disables_collision[/code] (the Player's collision shape is off while ridden, for a seat inside a body),
## [code]seat[/code] (a [Node3D] the Player is pinned to every physics frame after the ride, transform and all, so
## they turn and move with the rideable in the same frame while their camera keeps the view it had, as on foot; the
## rider faces along the seat's -Z, Godot's forward, so point the seat the way the rideable travels; the Player
## stays where it is in the tree, so the spawner, the synchronizer and every path to it keep working),
## [code]camera[/code] (a [Camera3D] made current while ridden; the Player's own returns on dismount),
## [code]mount_animation[/code] / [code]dismount_animation[/code] (locomotion nodes played on the way on and off;
## the rideable is not ridden while they play), and [code]input_type[/code] (kept equal to the Player's current
## [enum Controls.InputType]).
## Optional signals: [code]locomotion_requested(state_path, immediate)[/code],
## [code]locomotion_blend_requested(path, value)[/code], [code]jump_requested[/code].
##
## Beyond that a rideable uses the Player as a [CharacterBody3D] plus its movement API: [member Player.orientation],
## [member Player.model_pitch], [method Player.rotate_model_to_direction], [method Player.turn_model_toward_direction],
## [method Player.update_movement_and_rotation], [method Player.warp_to], [member Player.player_model],
## [member Player.player_input], [member Player.camera] and the state flags. Entering is [method Player.mount],
## leaving is [method Player.dismount].

var _mount_animation: String = ""
var _dismount_animation: String = ""
var _clip_seen: bool = false ## The get-on or get-off clip has been reported playing; the next change is its end.
var _seat: Node3D ## The rideable's seat, when it has one; the Player is pinned to it after every ride.
var _excluded_body: RID ## The rideable's body, kept out of the camera's spring arm while ridden.
var _hid_crosshair: bool = false
var _disabled_collision: bool = false
var _disabled_separation_ray: bool = false


## Called when there is an input event.
func _input(event: InputEvent) -> void:
	if not player or player.riding == null or player.is_paused or player.is_typing or player.is_ragdolling: return
	if player.is_mounting or player.is_dismounting: return
	if player.held_object and player.held_object.is_holding_object(): return
	if player.riding.has_method("ride_input"):
		# The HUD is a sibling and may not have seen this event yet, so the rideable is told the device the
		# event itself came from before it reads it: the first E after a pad session gets out of the car,
		# rather than being read as the pad's exit button
		if player.controls and "input_type" in player.riding:
			var device: int = player.controls.input_type_of(event)
			if device >= 0:
				player.riding.set("input_type", device)
		player.riding.call("ride_input", player, event)


## Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if not player or player.riding == null: return
	if player.is_mounting or player.is_dismounting: return
	player.riding.call("ride", player, delta)
	if _seat:
		_pin_to_seat()


## Ends the get-on clip when the animation moves past it, finishes the dismount when the get-off clip has played,
## and passes the change on to the rideable. A clip counts as over only once it has been reported playing, so a
## report that was already on its way when the clip started (the first one after a spawn) does not end it early.
func _on_locomotion_node_changed(state_path: String) -> void:
	if process_mode != Node.PROCESS_MODE_INHERIT or not player or player.riding == null: return
	if player.is_mounting:
		if state_path == _mount_animation:
			_clip_seen = true
		elif _clip_seen:
			player.is_mounting = false
	elif player.is_dismounting:
		if state_path == _dismount_animation:
			_clip_seen = true
		elif _clip_seen:
			player.dismount(true)
			return
	if player.riding.has_method("locomotion_node_changed"):
		player.riding.call("locomotion_node_changed", player, state_path)


## Keeps the rideable's [code]input_type[/code] equal to the Player's, so it reads the right actions.
func _on_input_type_changed(input_type: int) -> void:
	super._on_input_type_changed(input_type)
	if player and player.riding and "input_type" in player.riding:
		player.riding.set("input_type", input_type)


func _on_locomotion_requested(state_path: String, immediate: bool) -> void:
	if immediate:
		player.locomotion_state.start(state_path)
	else:
		player.travel_locomotion(state_path)


func _on_locomotion_blend_requested(path: String, value: float) -> void:
	player.animation_tree.set(path, value)


func _on_jump_requested() -> void:
	player.is_jumping = true
	player.is_jump_queued = true


## Start "riding".
func start() -> void:
	super.start()
	player.is_riding = true
	player.is_mounting = false
	player.is_dismounting = false
	var rideable: Node3D = player.riding
	if rideable.has_signal("locomotion_requested"):
		rideable.connect("locomotion_requested", _on_locomotion_requested)
	if rideable.has_signal("locomotion_blend_requested"):
		rideable.connect("locomotion_blend_requested", _on_locomotion_blend_requested)
	if rideable.has_signal("jump_requested"):
		rideable.connect("jump_requested", _on_jump_requested)
	if player.controls and "input_type" in rideable:
		rideable.set("input_type", player.controls.current_input_type)
	_mount_animation = _animation_name(rideable, "mount_animation")
	_dismount_animation = _animation_name(rideable, "dismount_animation")
	var seat: Variant = rideable.get("seat")
	if seat is Node3D:
		_seat = seat as Node3D
		player.player_model.transform = player.initial_player_model_transform
		_pin_to_seat()
	if rideable is CollisionObject3D and player.camera and player.camera.get_parent() is SpringArm3D:
		_excluded_body = (rideable as CollisionObject3D).get_rid()
		(player.camera.get_parent() as SpringArm3D).add_excluded_object(_excluded_body)
	rideable.call("mount", player)

	# The Player's side of getting on
	_hid_crosshair = rideable.get("blocks_hands") == true and player.crosshair != null
	if _hid_crosshair:
		player.crosshair.hide()
	_disabled_collision = rideable.get("disables_collision") == true and player.collision_shape != null
	if _disabled_collision:
		player.collision_shape.disabled = true
	_disabled_separation_ray = player.separation_ray_shape != null and not player.separation_ray_shape.disabled
	if _disabled_separation_ray:
		player.separation_ray_shape.disabled = true # the rideable owns the ground contact; the step-up ray fights ramps
	var camera: Variant = rideable.get("camera")
	if camera is Camera3D:
		(camera as Camera3D).current = true
	if _mount_animation != "":
		player.is_mounting = true
		_clip_seen = false
		player.locomotion_state.start(_mount_animation)
	player.ride_started.emit(rideable)


## Starts the get-off clip if the rideable has one; [method Player.dismount] finishes once it has played.
## Returns false when there is nothing to play, so the dismount is immediate.
func begin_dismount() -> bool:
	if player.is_dismounting:
		return true
	if _dismount_animation == "" or player.is_mounting:
		return false
	player.is_dismounting = true
	_clip_seen = false
	player.locomotion_state.start(_dismount_animation)
	return true


## Stop "riding".
func stop() -> void:
	super.stop()
	var rideable: Node3D = player.riding
	if _seat:
		_leave_seat()
	if _excluded_body.is_valid() and player.camera and player.camera.get_parent() is SpringArm3D:
		(player.camera.get_parent() as SpringArm3D).remove_excluded_object(_excluded_body)
		_excluded_body = RID()
	if is_instance_valid(rideable):
		rideable.call("dismount", player)
		if rideable.has_signal("locomotion_requested"):
			rideable.disconnect("locomotion_requested", _on_locomotion_requested)
		if rideable.has_signal("locomotion_blend_requested"):
			rideable.disconnect("locomotion_blend_requested", _on_locomotion_blend_requested)
		if rideable.has_signal("jump_requested"):
			rideable.disconnect("jump_requested", _on_jump_requested)

	# The Player's side of getting off
	if _hid_crosshair and player.crosshair:
		player.crosshair.show()
	if _disabled_collision and player.collision_shape:
		player.collision_shape.disabled = false
	if _disabled_separation_ray and player.separation_ray_shape:
		player.separation_ray_shape.disabled = false
	if player.camera:
		player.camera.current = true
	_hid_crosshair = false
	_disabled_collision = false
	_disabled_separation_ray = false
	player.is_riding = false
	player.is_mounting = false
	player.is_dismounting = false
	player.riding = null
	player.ride_ended.emit(rideable)


## The rideable's labels resolved to the label nodes. A key is a [String] naming the [Controls] label it goes on
## ("key_k"), a [StringName] naming an action, put on whichever button carries that action under the rider's
## layout ([method Controls.action_label], so the word follows the action and the keyboard set draws that
## button as the action's key), or the [Label] itself. A name nothing answers to is dropped.
func get_contextual_controls(input_type: int) -> Dictionary:
	if not player or not player.controls or player.riding == null or not player.riding.has_method("get_contextual_controls"):
		return {}
	var named: Dictionary = player.riding.call("get_contextual_controls", input_type)
	var controls: Dictionary = {}
	for key: Variant in named:
		var label: Variant = null
		if key is Label:
			label = key
		elif key is StringName:
			label = player.controls.action_label(key)
		else:
			label = player.controls.get(str(key) + "_label")
		if label is Label:
			controls[label] = named[key]
	return controls


## Puts the Player on the seat, body and all: its transform, facing and up are the seat's and the model sits straight
## on the body, while the camera mount keeps the view it had, as it does on foot where the body never turns. The
## model's rest transform turns it to face the body's -Z, so the rider looks where the seat points;
## [member Player.orientation] (whose +Z is the model's facing) says the same.
func _pin_to_seat() -> void:
	if not is_instance_valid(_seat):
		_seat = null
		return
	var facing_before: Vector3 = -player.global_basis.z
	player.global_transform = _seat.global_transform
	# Undo the body's turn on the camera mount's yaw so the view stays where the rider left it
	player.camera_mount.rotate_y(-facing_before.signed_angle_to(-player.global_basis.z, player.global_basis.y))
	player.velocity = Vector3.ZERO
	player.up_direction = _seat.global_basis.y.normalized()
	player.orientation = Transform3D(_seat.global_basis.rotated(player.up_direction, PI), Vector3.ZERO)


## Leaves the Player where the seat was, upright, the model still facing the way it faced on the seat.
func _leave_seat() -> void:
	var where: Transform3D = player.global_transform
	var facing: Vector3 = player.player_model.global_basis.z.slide(Vector3.UP)
	if facing.length_squared() < 0.001:
		facing = -where.basis.z.slide(Vector3.UP)
	player.global_transform = Transform3D(Basis(Vector3.UP, where.basis.get_euler().y), where.origin)
	player.up_direction = Vector3.UP
	player.orientation = Transform3D(Basis.looking_at(-facing.normalized(), Vector3.UP), Vector3.ZERO)
	_seat = null


## A locomotion node name from a rideable property, or "" when it has none.
static func _animation_name(rideable: Node3D, property: String) -> String:
	var value: Variant = rideable.get(property)
	return value if value is String else ""
