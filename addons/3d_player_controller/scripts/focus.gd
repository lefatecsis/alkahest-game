class_name Focus
extends Node
## The Player's targeting: the Target it has selected, and the lock-on that Focus holds.
##
## The Target ([member selected_target]) is what abilities land on and what the HUD's target frame shows. In a
## scheme that frees the cursor ([member ControlScheme.frees_cursor], the World of Warcraft way) it is picked by
## clicking a body, or by a tap of Focus, which selects the nearest candidate and then cycles through them; it
## stays until the cancel action, a click on nothing, or the body's death. In every other scheme it is the
## lock-on: set while Focus is held ([member current_focus_target], the Breath of the Wild way), gone on release.
##
## Lock-on candidates are bodies in the "Focusable" group overlapping [member target_detection], hostile ones
## first; a locked target that leaves the area is dropped after [member target_loss_timer] elapses. Firearms use
## free aim instead, so lock-on is off while one is equipped, and so does the GTA control scheme
## ([method Player.lock_on_enabled]), where Focus is the over-the-shoulder aim with anything in hand.

signal target_changed(target: Node3D) ## The Target is another body, or none.

## How a body stands to whoever looks at it ([method disposition_toward]): an enemy, a bystander that turns hostile
## when attacked, or a friend a heal can reach.
enum Disposition { HOSTILE, NEUTRAL, FRIENDLY }

const CLICK_REACH: float = 200.0 ## How far a click looks for a body, from the camera.

@export var player: Player
@export var target_detection: Area3D ## Area whose overlapping "Focusable" bodies can be locked on to.
@export var focus_target_marker: Marker3D ## Indicator moved above the Target.
@export var target_loss_timer: Timer ## Grace period after the locked target leaves [member target_detection].
@export var select_reach: float = 40.0 ## How far a Focus tap looks for a body to select, in a scheme that frees the cursor.

var selected_target: Node3D = null: ## The Target: what abilities land on and the target frame shows.
	set(value):
		if value == selected_target:
			return
		selected_target = value
		selected_aim = get_aim_node(value)
		_place_marker()
		target_changed.emit(selected_target)
var current_focus_target: Node3D = null: ## The body currently locked on to, if any; in a scheme that holds Focus it is the Target too.
	set(value):
		if value != current_focus_target:
			current_focus_target = value
			focus_aim = get_aim_node(value)
		if not frees_cursor():
			selected_target = value
var selected_aim: Node3D = null ## Where on the Target to aim ([method get_aim_node]), looked up when the Target changes.
var focus_aim: Node3D = null ## Where on the locked-on body to aim, looked up when the lock changes.
var detection_radius: float = 5.0 ## The radius of [member target_detection]'s sphere, read once on ready; the camera sizes its aim window by it.
var _focus_down: bool = false ## Whether Focus was already held, so a trigger's stream of motion events past the deadzone is one tap, not many.


func _ready() -> void:
	set_process_input(is_multiplayer_authority())
	set_process_unhandled_input(is_multiplayer_authority())
	set_physics_process(is_multiplayer_authority())
	var shape: CollisionShape3D = target_detection.get_node_or_null(^"CollisionShape3D") as CollisionShape3D if target_detection else null
	if shape and shape.shape is SphereShape3D:
		detection_radius = (shape.shape as SphereShape3D).radius


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	# An analog trigger sends a motion event every frame it moves, and each one past the deadzone reads as a press;
	# only the one that crosses from released to held is a tap. Tracked ahead of the gates so a release behind a
	# menu still counts.
	var focus_tap: bool = false
	if event.is_action(&"focus"):
		focus_tap = event.is_action_pressed(&"focus") and not _focus_down
		_focus_down = event.is_action_pressed(&"focus")
	if player == null or player.is_paused or player.is_typing or player.is_ragdolling:
		return
	if frees_cursor():
		# Tab cycles, as it does in World of Warcraft, and so does the pad's Focus slot; the mouse button behind
		# Focus is the camera drag here, so a press of it is not a tap
		if event.is_action_pressed(&"ui_focus_next") or (focus_tap and not event is InputEventMouseButton):
			cycle_selection(1) # a tap: the nearest, then the next
		elif event.is_action_pressed(&"ui_cancel") and is_instance_valid(selected_target):
			# Escape with a Target clears it and goes no further, as in World of Warcraft; the next Escape opens the menu
			clear_selection()
			get_viewport().set_input_as_handled()
	elif focus_tap and is_instance_valid(current_focus_target):
		cycle_focus_target(1) # a tap while locked on: the next target


func _unhandled_input(event: InputEvent) -> void:
	if not frees_cursor() or player == null or player.is_paused or player.is_typing:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and event.is_pressed() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		select(body_under((event as InputEventMouseButton).position)) # a click on nothing clears


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	# The lock-on
	if not player.is_focusing or not player.lock_on_enabled() or player.has_firearm_equipped:
		# Free aim (the GTA scheme, a firearm) never locks on: focus is strafing and the shoulder camera, nothing more
		if current_focus_target:
			_clear_focus_target()
	elif not is_instance_valid(current_focus_target):
		_acquire_focus_target()
	# The Target
	if not frees_cursor():
		selected_target = current_focus_target # held Focus is the Target; released, there is none
	elif is_instance_valid(selected_target) and not selected_target.is_in_group("Focusable"):
		clear_selection() # it died, or is otherwise nothing to target any more
	elif selected_target and not is_instance_valid(selected_target):
		clear_selection()
	if is_instance_valid(selected_target):
		_place_marker()


## True when the Player's scheme keeps the cursor visible, so the Target is clicked or tabbed rather than held.
func frees_cursor() -> bool:
	return player != null and player.control_scheme != null and player.control_scheme.frees_cursor


## Lock-on is unavailable while a firearm is equipped (free aim instead); [method _physics_process] reads the flag.
func _on_equipment_changed() -> void:
	if player.has_firearm_equipped:
		_clear_focus_target()


func _on_target_detection_body_entered(body: Node3D) -> void:
	if body == current_focus_target:
		target_loss_timer.stop()


func _on_target_detection_body_exited(body: Node3D) -> void:
	# Also fires while the scene is being torn down, when the timer can no longer start.
	if body == current_focus_target and target_loss_timer.is_inside_tree():
		target_loss_timer.start()


# The Target

## Makes [param target] the Target; null, or a body that is gone, clears it.
func select(target: Node3D) -> void:
	selected_target = target if is_instance_valid(target) else null


func clear_selection() -> void:
	selected_target = null


## Selects the nearest enemy (hostile or neutral, never a friend: Tab in World of Warcraft) within
## [member select_reach] when nothing is selected, else the next one round (or the previous with a negative
## [param direction]); with no candidate at all the selection clears. Friends are selected by clicking them.
func cycle_selection(direction: int = 1) -> void:
	var targets: Array[Node3D] = targets_within(select_reach).filter(func(body: Node3D) -> bool: return disposition_toward(body, player) != Disposition.FRIENDLY)
	if targets.is_empty():
		clear_selection()
		return
	var current: int = targets.find(selected_target)
	select(targets[posmod(current + direction, targets.size()) if current >= 0 else 0])


## The "Focusable" bodies within [param distance] of the Player, nearest first.
func targets_within(distance: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("Focusable"):
		var body: Node3D = node as Node3D
		if body == null or body == player or not body.is_inside_tree():
			continue
		if body.global_position.distance_to(player.global_position) <= distance:
			out.append(body)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
	return out


## The nearest body within [param distance] that [param accept] (a Callable taking the body) says yes to, or null.
func nearest(distance: float, accept: Callable) -> Node3D:
	for body: Node3D in targets_within(distance):
		if accept.call(body):
			return body
	return null


## The "Focusable" body under [param screen_position], through the Player's camera, or null when the click lands on
## nothing (the ground, a wall, the sky).
func body_under(screen_position: Vector2) -> Node3D:
	var camera: Camera3D = player.camera as Camera3D
	if camera == null or not camera.is_inside_tree():
		return null
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen_position) * CLICK_REACH)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	var node: Node = hit.get("collider") as Node
	while node and not node.is_in_group("Focusable"):
		node = node.get_parent()
	return node as Node3D


## How [param body] stands to [param viewer]: another Player is a friend to a Player and prey to an NPC; an NPC says
## so itself through a [code]disposition[/code] property (an [EnemyNpc] hostile or neutral, a [FollowerNpc]
## friendly); anything else that can be targeted (a dummy) is hostile to a Player, and NPCs ignore each other.
static func disposition_toward(body: Node3D, viewer: Node3D) -> Disposition:
	if body is Player:
		return Disposition.FRIENDLY if viewer is Player else Disposition.HOSTILE
	if viewer is not Player:
		return Disposition.NEUTRAL
	var stated: Variant = body.get("disposition")
	if stated is int:
		return stated as Disposition
	return Disposition.HOSTILE


func _place_marker() -> void:
	if not is_instance_valid(focus_target_marker):
		return
	if is_instance_valid(selected_target) and is_instance_valid(selected_aim):
		focus_target_marker.global_position = selected_aim.global_position + Vector3(0, 0.4, 0)
		focus_target_marker.show()
	else:
		focus_target_marker.hide()


# The lock-on

## Returns the "Marker3D_FocusTarget" descendant of the body, if any.
static func get_focus_target_node(body: Node3D) -> Node3D:
	if not is_instance_valid(body):
		return null
	return body.find_child("Marker3D_FocusTarget", true, false) as Node3D


## The node on [param body] to aim at: its "Marker3D_FocusTarget", else its CollisionShape3D, else the body itself;
## null for no body. Two recursive searches, so the Target and the lock look it up once, as they change.
static func get_aim_node(body: Node3D) -> Node3D:
	if not is_instance_valid(body):
		return null
	var marker: Node3D = get_focus_target_node(body)
	if marker:
		return marker
	var col: Node3D = body.find_child("CollisionShape3D", true, false) as Node3D
	return col if col else body


## Returns the global 3D position to focus on for the given body.
static func get_focus_target_position(body: Node3D) -> Vector3:
	var aim: Node3D = get_aim_node(body)
	return aim.global_position if aim else Vector3.ZERO


## Where the lock aims now: [member focus_aim]'s position, or zero with no lock.
func focus_aim_position() -> Vector3:
	return focus_aim.global_position if is_instance_valid(current_focus_target) and is_instance_valid(focus_aim) else Vector3.ZERO


## The focusable bodies in range, hostile ones first, each group sorted by horizontal angular proximity to the
## camera's centre, so a lock lands on the enemy ahead before the companion at the Player's heel.
func get_focusable_targets() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for body: Node3D in target_detection.get_overlapping_bodies():
		if body != player and body.is_in_group("Focusable"):
			candidates.append(body)

	var cam_forward: Vector3 = -player.spring_arm.global_transform.basis.z.slide(player.up_direction).normalized()
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var hostile_a: bool = disposition_toward(a, player) == Disposition.HOSTILE
		var hostile_b: bool = disposition_toward(b, player) == Disposition.HOSTILE
		if hostile_a != hostile_b:
			return hostile_a
		var dir_a: Vector3 = (a.global_position - player.global_position).slide(player.up_direction).normalized()
		var dir_b: Vector3 = (b.global_position - player.global_position).slide(player.up_direction).normalized()
		return cam_forward.dot(dir_a) > cam_forward.dot(dir_b)
	)
	return candidates


## Locks on to the best focusable body.
func _acquire_focus_target() -> void:
	var targets: Array[Node3D] = get_focusable_targets()
	if not targets.is_empty():
		_set_focus_target(targets[0])


## Cycles the lock to the next or previous focusable target.
func cycle_focus_target(direction: int = 1) -> void:
	var targets: Array[Node3D] = get_focusable_targets()
	if targets.is_empty():
		_clear_focus_target()
		return
	var current_idx: int = targets.find(current_focus_target)
	var next_idx: int = posmod(current_idx + direction, targets.size()) if current_idx >= 0 else 0
	_set_focus_target(targets[next_idx])


## Locks on to [param target]; the Target follows on the next physics step.
func _set_focus_target(target: Node3D) -> void:
	current_focus_target = target
	target_loss_timer.stop()
	selected_target = target


## Releases the lock (also wired to the loss timer's timeout); the Target goes with it.
func _clear_focus_target() -> void:
	current_focus_target = null
	target_loss_timer.stop()
	if not frees_cursor():
		selected_target = null
