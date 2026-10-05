extends GutTest

## Purpose: To test focus target acquisition, cycling and loss through the TargetDetection area.

const PLAYER_SCENE = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CONTROLS_SCENE = preload("res://addons/3d_player_controller/scenes/ui/player_controls.tscn")

var player: Player
var focus_node: Focus


func before_each() -> void:
	add_child_autofree(CONTROLS_SCENE.instantiate())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	focus_node = player.focus


func after_each() -> void:
	Input.action_release("focus")


## A "Focusable" body with a collision shape so the TargetDetection Area3D overlaps it.
func _add_target(name: String, offset: Vector3) -> CharacterBody3D:
	var target = CharacterBody3D.new()
	target.name = name
	target.add_to_group("Focusable")
	var shape = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	target.add_child(shape)
	add_child_autofree(target)
	target.global_position = player.global_position + offset
	return target


func test_focus_target_cycling_between_multiple_targets() -> void:
	_add_target("Target1", Vector3(0, 0, -3))
	_add_target("Target2", Vector3(3, 0, -3))
	_add_target("Target3", Vector3(-3, 0, -3))
	await wait_physics_frames(2)

	Input.action_press("focus")
	focus_node._physics_process(0.1)
	assert_not_null(focus_node.current_focus_target, "Focus should acquire initial target")
	assert_true(player.get_node("FocusTargetMarker").visible, "Marker should show on the focused target")
	var initial_target = focus_node.current_focus_target

	focus_node.cycle_focus_target(1)
	assert_ne(focus_node.current_focus_target, initial_target, "Focus should cycle to a new target")
	var second_target = focus_node.current_focus_target

	focus_node.cycle_focus_target(1)
	assert_ne(focus_node.current_focus_target, second_target, "Focus should cycle to the third target")

	focus_node.cycle_focus_target(-1)
	assert_eq(focus_node.current_focus_target, second_target, "Focus should cycle back to second target")

	Input.action_release("focus")
	focus_node._physics_process(0.1)
	assert_null(focus_node.current_focus_target, "Focus target should clear after release")
	assert_false(player.get_node("FocusTargetMarker").visible, "Marker should hide once nothing is focused")


func test_target_lost_after_leaving_detection_area() -> void:
	var target = _add_target("TargetFar", Vector3(0, 0, -3))
	await wait_physics_frames(2)

	Input.action_press("focus")
	focus_node._physics_process(0.1)
	assert_eq(focus_node.current_focus_target, target, "Focus should lock on to target")
	# Keep the player still: lock-on movement would otherwise chase the teleported target
	player.set_physics_process(false)

	# Leave the detection area: body_exited starts the grace timer but keeps the lock
	target.global_position = player.global_position + Vector3(0, 0, -50)
	await wait_physics_frames(3)
	assert_false(focus_node.target_loss_timer.is_stopped(), "Leaving the area should start the grace timer")
	assert_eq(focus_node.current_focus_target, target, "Target should still be locked during the grace period")

	# Coming back cancels the loss
	target.global_position = player.global_position + Vector3(0, 0, -3)
	await wait_physics_frames(3)
	assert_true(focus_node.target_loss_timer.is_stopped(), "Re-entering the area should cancel the grace timer")
	assert_eq(focus_node.current_focus_target, target, "Target should stay locked after re-entering")

	target.global_position = player.global_position + Vector3(0, 0, -50)
	await wait_seconds(focus_node.target_loss_timer.wait_time + 0.3)
	assert_null(focus_node.current_focus_target, "Target should be dropped after the grace timer elapses")
