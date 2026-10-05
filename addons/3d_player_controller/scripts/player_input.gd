class_name InputSynchronizer
extends MultiplayerSynchronizer

# Synchronized controls
@export var motion: Vector2 = Vector2()


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process(is_multiplayer_authority())
	set_physics_process(is_multiplayer_authority())
	set_process_input(is_multiplayer_authority())


## Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	var player: Player = get_parent() as Player
	if player and (player.is_paused or player.is_typing or player.is_ragdolling):
		motion = Vector2.ZERO
		return

	motion = _get_vector(player, &"move_left", &"move_right", &"move_down", &"move_up")

	if player == null:
		return

	# Manual movement input cancels click-to-move navigation.
	if motion.length_squared() > 0.0:
		player.is_navigating = false
	elif player.is_navigating:
		motion = _get_navigation_motion(player)


## The Player's own reading of the sticks ([method Player.get_vector], their pad alone in a split screen), or the
## whole input with no Player above.
static func _get_vector(player: Player, negative_x: StringName, positive_x: StringName, negative_y: StringName, positive_y: StringName) -> Vector2:
	if player:
		return player.get_vector(negative_x, positive_x, negative_y, positive_y)
	return Input.get_vector(negative_x, positive_x, negative_y, positive_y)


## Gets the camera-relative motion that steers the player toward the navigation path.
func _get_navigation_motion(player: Player) -> Vector2:
	if player.navigation_agent.is_navigation_finished():
		player.is_navigating = false
		return Vector2.ZERO
	var next_position: Vector3 = player.navigation_agent.get_next_path_position()
	var world_direction: Vector3 = (next_position - player.global_position).slide(player.up_direction)
	if world_direction.length_squared() < 0.0001:
		return Vector2.ZERO
	world_direction = world_direction.normalized()
	# Invert the camera-relative mapping used in Player.apply_input().
	var camera_basis: Basis = player.spring_arm.global_transform.basis
	var local_direction: Vector3 = camera_basis.inverse() * world_direction
	var navigation_motion: Vector2 = Vector2(local_direction.x, -local_direction.z)
	if navigation_motion.length_squared() < 0.0001:
		return Vector2.ZERO
	return navigation_motion.normalized()
