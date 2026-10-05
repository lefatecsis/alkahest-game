extends GutTest

## Purpose: Unit tests for underwater diving: descend/ascend control, dive state,
## model pitch, buoyancy, surface clamping, contextual controls, and cleanup.

const PLAYER_SCENE = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CONTROLS_SCENE = preload("res://addons/3d_player_controller/scenes/ui/player_controls.tscn")

var player: Player
var swimming_node: Swimming
var water: Area3D


func before_each() -> void:
	var controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(controls)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	swimming_node = player.get_node("NodeStateMachine/Swimming") as Swimming
	assert_not_null(swimming_node, "Swimming state node should exist")

	# Water volume: box centered at origin, surface at y = +5
	water = Area3D.new()
	water.add_to_group("WATER")
	var water_col := CollisionShape3D.new()
	water_col.name = "CollisionShape3D" # Runtime add_child would otherwise auto-name it "@CollisionShape3D@N"
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 10.0, 100.0)
	water_col.shape = box
	water.add_child(water_col)
	add_child_autofree(water)

	player.global_position = Vector3(0.0, 3.0, 0.0)
	player.current_water_area = water
	swimming_node.start()


func after_each() -> void:
	Input.action_release("crouch")
	Input.action_release("jump")


func test_start_snaps_to_surface() -> void:
	var shoulder_height: float = player.global_position.y + swimming_node._get_collision_height() * Swimming.WATER_SURFACE_SNAP_RATIO
	assert_almost_eq(shoulder_height, 5.0, 0.1, "Swim start should snap the player's shoulders to the water surface")
	assert_false(player.is_diving, "Player should not be diving at the surface")


func test_holding_crouch_descends() -> void:
	Input.action_press("crouch")
	swimming_node._physics_process(0.1)
	assert_lt(player.swim_vertical_speed, 0.0, "Holding crouch should swim the player downward")


func test_deep_submersion_sets_diving_and_pitches_model() -> void:
	# Move well below the dive entry depth
	player.global_position.y = 1.0
	Input.action_press("crouch")
	for i in range(10):
		swimming_node._physics_process(0.05)
	assert_true(player.is_diving, "Player deep below the surface should be diving")
	assert_gt(player.model_pitch, 0.0, "Model should pitch nose-down (positive X rotation) while swimming downward")
	assert_true(player.is_swimming, "Diving player is still swimming")


func test_holding_jump_ascends_while_submerged() -> void:
	player.global_position.y = 1.0
	swimming_node._physics_process(0.05)
	assert_true(player.is_diving)
	Input.action_press("jump")
	swimming_node._physics_process(0.05)
	assert_gt(player.swim_vertical_speed, 0.0, "Holding jump while diving should ascend")


func test_shallow_buoyancy_floats_back_to_surface() -> void:
	# Slightly submerged (0.5m below the float line), no input
	player.global_position.y -= 0.5
	swimming_node._physics_process(0.05)
	assert_false(player.is_diving, "Shallow submersion should not count as diving")
	assert_gt(player.swim_vertical_speed, 0.0, "Buoyancy should float a shallow player back up")


func test_cannot_swim_up_through_surface() -> void:
	Input.action_press("jump")
	swimming_node._physics_process(0.05)
	assert_eq(player.swim_vertical_speed, 0.0, "Ascending at the surface should not push the player out of the water")


func test_contextual_controls_swap_between_surface_and_diving() -> void:
	var surface_controls: Dictionary = swimming_node.get_contextual_controls(0)
	assert_true(surface_controls.values().has("Dive"), "Surface swimming should offer a Dive control")
	assert_true(surface_controls.values().has("Climb Out"), "Surface swimming should offer Climb Out")

	player.is_diving = true
	var dive_controls: Dictionary = swimming_node.get_contextual_controls(0)
	assert_true(dive_controls.values().has("Surface"), "Diving should offer a Surface control")
	assert_true(dive_controls.values().has("Dive Deeper"), "Diving should offer Dive Deeper")
	player.is_diving = false


func test_stop_resets_diving_state() -> void:
	player.is_diving = true
	player.swim_vertical_speed = -2.0
	player.model_pitch = -0.8
	swimming_node.stop()
	assert_false(player.is_diving, "Stopping swimming should clear diving")
	assert_eq(player.swim_vertical_speed, 0.0, "Stopping swimming should clear vertical swim speed")
	assert_eq(player.model_pitch, 0.0, "Stopping swimming should reset the model pitch")


func test_exhaustion_while_diving_respawns_at_shore_and_resets() -> void:
	player.last_safe_shore_position = Vector3(10.0, 0.0, 10.0)
	player.global_position.y = 1.0
	player.is_diving = true
	player.is_exhausted = true
	swimming_node._physics_process(0.05)
	assert_eq(player.global_position, Vector3(10.0, 0.0, 10.0), "Exhausted diver should respawn at the shore")
	assert_false(player.is_diving, "Diving should be cleared on exhaustion respawn")
	assert_eq(player.model_pitch, 0.0, "Model pitch should be reset on exhaustion respawn")


func test_diving_drains_stamina() -> void:
	player.enable_stamina = true
	player.is_diving = true
	var stamina: TextureProgressBar = player.stamina
	stamina.stamina = 80.0
	stamina._physics_process(1.0)
	assert_lt(stamina.stamina, 80.0, "Diving should drain stamina like a breath meter")
	player.is_diving = false


func test_dive_pitch_pivots_at_hips_not_feet() -> void:
	player.velocity = Vector3.ZERO
	player.model_pitch = 0.0
	player.update_movement_and_rotation(0.016)
	var pivot_local := Vector3(0.0, player.model_pitch_pivot_height, 0.0)
	var hip_before: Vector3 = player.player_model.global_transform * pivot_local
	var feet_before: Vector3 = player.player_model.global_position

	player.model_pitch = 1.0
	player.update_movement_and_rotation(0.016)
	var hip_after: Vector3 = player.player_model.global_transform * pivot_local
	var feet_after: Vector3 = player.player_model.global_position

	assert_lt(hip_before.distance_to(hip_after), 0.02, "The hip point must stay fixed while the dive pitch is applied")
	assert_gt(feet_before.distance_to(feet_after), 0.1, "The model origin (feet) should swing around the hip pivot")

	# Clearing the pitch restores the original model placement
	player.model_pitch = 0.0
	player.update_movement_and_rotation(0.016)
	assert_lt(feet_before.distance_to(player.player_model.global_position), 0.02, "Model origin must be restored when the pitch clears")


func test_vertical_dive_effort_animates_swim_stroke_without_stick_input() -> void:
	player.global_position.y = 1.0
	player.smoothed_motion = Vector2.ZERO
	player.locomotion_state.start("SwimmingLocomotion")
	player.animation_tree.advance(0.01)
	Input.action_press("crouch")
	swimming_node._physics_process(0.05)
	var blend: float = player.animation_tree.get(player.SWIMMING_LOCOMOTION_BLEND_POSITION_PATH)
	assert_almost_eq(blend, 1.0, 0.001, "Pure-vertical diving must drive the swim stroke blend (no treading-water idle)")

	# Releasing all input returns to the idle blend
	Input.action_release("crouch")
	player.global_position.y = 4.0 # back near the surface so buoyancy stops
	swimming_node._physics_process(0.05)
	swimming_node._physics_process(0.05)
	var idle_blend: float = player.animation_tree.get(player.SWIMMING_LOCOMOTION_BLEND_POSITION_PATH)
	assert_almost_eq(idle_blend, 0.0, 0.001, "No input should return the swim blend to treading water")


func _find_splash() -> Node:
	for node in player.get_parent().find_children("*", "Node3D", true, false):
		var node_script: Script = node.get_script() as Script
		if node_script and node_script.resource_path.ends_with("water_splash.gd"):
			return node
	return null


func test_hard_water_entry_spawns_splash() -> void:
	player.velocity = Vector3(0.0, -6.0, 0.0)
	player.global_position = Vector3(0.0, 3.0, 0.0)
	swimming_node.start()
	var splash: Node = _find_splash()
	assert_not_null(splash, "A hard water entry should spawn a WaterSplash")
	if splash:
		splash.free()


func test_gentle_water_entry_spawns_no_splash() -> void:
	player.velocity = Vector3(0.0, -0.5, 0.0)
	player.last_fall_speed = 0.5
	player.global_position = Vector3(0.0, 3.0, 0.0)
	swimming_node.start()
	assert_null(_find_splash(), "A gentle water entry should not splash")


func test_underwater_overlay_follows_camera_submersion() -> void:
	var overlay: CanvasLayer = player.get_node("Hud/UnderwaterOverlay") as CanvasLayer
	assert_not_null(overlay, "Player scene should contain the UnderwaterOverlay")
	assert_false(overlay.visible, "Overlay should start hidden")

	# Camera above the surface while surface swimming
	swimming_node._physics_process(0.05)
	assert_false(overlay.visible, "Overlay should stay hidden while the camera is above water")

	# Deep dive puts the camera below the surface
	player.global_position.y = 0.0
	swimming_node._physics_process(0.05)
	assert_true(overlay.visible, "Overlay should show once the camera is submerged")

	swimming_node.stop()
	assert_false(overlay.visible, "Overlay must hide when swimming stops")


## Holding Crouch dives through the Player's own reading of the action: a pad player in a split screen does not
## dive on the keyboard's Crouch, and nobody dives behind a menu.
func test_the_dive_reads_the_players_own_input_and_stops_behind_a_menu() -> void:
	Input.action_press("crouch")
	player.input_device = 0
	swimming_node._physics_process(0.1)
	assert_eq(player.swim_vertical_speed, 0.0, "Pad 0's player does not dive on the keyboard")
	player.input_device = -1
	player.is_paused = true
	swimming_node._physics_process(0.1)
	assert_eq(player.swim_vertical_speed, 0.0, "and nobody dives behind a menu")
	player.is_paused = false
	swimming_node._physics_process(0.1)
	assert_lt(player.swim_vertical_speed, 0.0, "while the whole input still does")
