extends GutTest

## Purpose: The seated typing pose. The four Mixamo clips are imported as retargeted animation libraries and
## loaded into the AnimationPlayer, the locomotion state machine runs
## Sitting -> SittingToTyping -> SittingTyping and back off [member Player.is_typing_at_keyboard], and the
## head-only [LookAtModifier3D] turns the head without disturbing the rest of the pose.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const LOCOMOTION_PLAYBACK: String = "parameters/LocomotionStateMachine/playback"

var player: Player


func before_each() -> void:
	# Without ground the Player falls, and Falling owns the locomotion whatever the sitting flags say
	var ground: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(50.0, 1.0, 50.0)
	collision.shape = box
	ground.add_child(collision)
	add_child_autofree(ground)
	ground.position = Vector3(0.0, -0.5, 0.0)

	player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.position = Vector3(0.0, 0.1, 0.0)
	await wait_physics_frames(4)


func _playback() -> AnimationNodeStateMachinePlayback:
	return player.animation_tree.get(LOCOMOTION_PLAYBACK)


func _locomotion() -> String:
	return String(_playback().get_current_node())


func test_the_four_clips_are_loaded_as_animation_libraries() -> void:
	var animation_player: AnimationPlayer = player.get_node("PlayerModel/AnimationPlayer")
	for clip: String in ["Sitting Typing", "Sitting to Typing", "Typing to Sitting", "Sitting Victory"]:
		assert_true(animation_player.has_animation_library(clip),
				"%s should be loaded; a .glb left on the scene importer resolves to null here" % clip)
		assert_not_null(animation_player.get_animation(clip + "/mixamo_com"))


func test_the_clips_are_retargeted_and_only_the_cycle_loops() -> void:
	var animation_player: AnimationPlayer = player.get_node("PlayerModel/AnimationPlayer")
	var typing: Animation = animation_player.get_animation("Sitting Typing/mixamo_com")
	assert_eq(typing.loop_mode, Animation.LOOP_LINEAR, "The typing cycle has to loop or the Player freezes")
	assert_gt(typing.get_track_count(), 0,
			"Tracks only exist once the import is retargeted to mixamo_root_bone_map.tres")
	for one_shot: String in ["Sitting to Typing", "Typing to Sitting"]:
		assert_eq(animation_player.get_animation(one_shot + "/mixamo_com").loop_mode, Animation.LOOP_NONE,
				"%s is a lead-in/lead-out, not a cycle" % one_shot)


func test_the_flag_starts_clear_and_is_not_the_chat_one() -> void:
	assert_false(player.is_typing_at_keyboard)
	assert_false(player.is_typing, "is_typing means a text field has focus; the two must stay separate")


func test_the_chain_runs_into_the_typing_cycle_and_back_out() -> void:
	player.is_sitting = true
	await wait_seconds(0.6)
	assert_eq(_locomotion(), "Sitting", "is_sitting alone should reach the plain sitting pose")

	player.is_typing_at_keyboard = true
	await wait_seconds(0.6)
	assert_eq(_locomotion(), "SittingToTyping", "The lead-in should be entered off the flag")
	await wait_seconds(1.4)
	assert_eq(_locomotion(), "SittingTyping", "and hand over to the cycle when it ends")

	player.is_typing_at_keyboard = false
	await wait_seconds(0.6)
	assert_eq(_locomotion(), "TypingToSitting", "Clearing the flag should play the lead-out")
	await wait_seconds(1.2)
	assert_eq(_locomotion(), "Sitting", "and land back on the plain sitting pose")


func test_the_head_modifier_is_its_own_node_on_the_head_bone() -> void:
	var head: LookAtModifier3D = player.head_look_at_modifier as LookAtModifier3D
	var spine: LookAtModifier3D = player.look_at_modifier as LookAtModifier3D
	assert_not_null(head)
	assert_ne(head, spine, "Aiming already owns the spine modifier; the head needs its own")
	assert_eq(head.bone_name, "Head")
	assert_eq(spine.bone_name, "Spine")
	assert_eq(head.get_node(head.target_node), player.head_look_target,
			"Until something asks for it, it follows the camera's pitch")
	for damp: float in [head.primary_positive_damp_threshold, head.primary_negative_damp_threshold,
			head.secondary_positive_damp_threshold, head.secondary_negative_damp_threshold]:
		assert_eq(damp, 1.0, "Damping below 1 stops the head reaching the target; the spine modifier uses 1 too")


func test_set_head_look_at_target_points_and_clears_it() -> void:
	var head: LookAtModifier3D = player.head_look_at_modifier as LookAtModifier3D
	var target: Node3D = Node3D.new()
	add_child_autofree(target)
	target.global_position = player.global_position + Vector3(0.0, 1.2, -1.0)

	player.set_head_look_at_target(target)
	assert_true(head.active)
	assert_eq(head.get_node(head.target_node), target)

	player.set_head_look_at_target(null)
	assert_true(head.active, "Cleared, the head goes back to following the camera")
	assert_eq(head.get_node(head.target_node), player.head_look_target)


func test_the_head_modifier_is_aimed_and_bounded_the_way_it_was_tuned() -> void:
	var head: LookAtModifier3D = player.head_look_at_modifier as LookAtModifier3D
	# PLUS_Z because the model is turned 180 degrees, so the face looks down the head bone's own +Z. MINUS_Z
	# leaves the neck screwed round backwards, and the angle limit then clamps it near the rest pose, which
	# reads as "nearly right" instead of obviously wrong.
	assert_eq(head.forward_axis, 4, "PLUS_Z is the face direction on this rig")
	assert_false(head.symmetry_limitation, "Up and down are limited apart, since the head rests tipped forward")
	assert_between(rad_to_deg(head.primary_positive_limit_angle + head.primary_negative_limit_angle), 45.0, 90.0,
			"A neck that can swing further than this follows targets it should just ignore")
	assert_between(rad_to_deg(head.secondary_positive_limit_angle), 30.0, 60.0, "Down from rest")
	assert_between(rad_to_deg(head.secondary_negative_limit_angle), 45.0, 75.0, "and up")
	# Last of the skeleton's children, so it lands on top of the spine look-at and the hand IK
	var skeleton: Skeleton3D = player.get_node("PlayerModel/Armature/GeneralSkeleton")
	assert_eq(skeleton.get_child(skeleton.get_child_count() - 1), head,
			"It has to run after the other modifiers or they overwrite the head")


## Note on what is NOT asserted here: that the head visibly turns. [method Skeleton3D.get_bone_global_pose]
## reports the pose before [SkeletonModifier3D]s run, so reading the head bone back gives the animation's
## own pose whatever the modifier is doing, and an assertion on it passes or fails for unrelated reasons
## (the body drifting, say). The rotation itself was checked by eye, from a camera placed at the CRT looking
## back at the Player, with the modifier off and then on.
