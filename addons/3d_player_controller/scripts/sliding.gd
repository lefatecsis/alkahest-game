class_name Sliding
extends NodeStateMachine
## The slide out of a sprint: [Sprinting] enters it only from StandingLocomotion, the one locomotion node with an
## edge into RunningSlide. It stands back up once the clip hands off to another locomotion node, falls when the
## ground goes, and gives up after [constant TIMEOUT] should the clip never arrive, so the half-height capsule
## can never stick.

const TIMEOUT: float = 3.0 ## The clip never arrived (a transition the tree could not path): stand up regardless. Past the RunningSlide clip, which gets up on its own.

var _elapsed: float = 0.0


## Stand back up once the RunningSlide animation hands off to another locomotion node.
func _on_locomotion_node_changed(_state_path: String) -> void:
	if process_mode != Node.PROCESS_MODE_INHERIT: return

	if player.current_locomotion_node != "RunningSlide":
		player.state_machine.travel(state, States.STANDING)


## Called every physics frame: off a ledge mid-slide falls, and a slide that never played stands up.
func _physics_process(delta: float) -> void:
	if not player: return
	_elapsed += delta
	if not player.is_on_floor() and not player.falling_raycast.is_colliding():
		player.state_machine.travel(state, States.FALLING)
	elif _elapsed > TIMEOUT:
		player.state_machine.travel(state, States.STANDING)


## Start "sliding".
func start() -> void:
	super.start()
	_elapsed = 0.0
	# Flag the player as "sliding"
	player.is_sliding = true
	# Reduce the player's collision shape height and adjust its position to match the sliding posture
	player.collision_shape.shape.height = player.initial_collision_shape_height * 0.5
	player.collision_shape.position = Vector3(0, player.collision_shape.shape.height * 0.5, 0)


## Stop "sliding".
func stop() -> void:
	super.stop()
	# Flag the player as not "sliding"
	player.is_sliding = false
	# Reset the player's collision shape to its initial height and position
	player.collision_shape.shape.height = player.initial_collision_shape_height
	player.collision_shape.position = player.initial_collision_shape_position
