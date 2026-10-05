extends GutTest

## Purpose: Physical bones must not collide until the ragdoll simulation starts; the scene sets this, not a deferred lambda.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")


func test_physical_bones_start_with_collision_disabled() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var bones: Array[Node] = player.physical_bone_simulator.find_children("*", "PhysicalBone3D", true, false)
	assert_gt(bones.size(), 0, "Player should have physical bones")
	for bone: PhysicalBone3D in bones:
		assert_eq(bone.collision_layer, 0, "%s layer" % bone.name)
		assert_eq(bone.collision_mask, 0, "%s mask" % bone.name)


## Another peer's copy of a Player never ran its Ragdolling state, so it went on walking while its owner lay on the
## ground, and the owner's world-space model position landed on it as a local offset. The replicated flag's setter
## drops and lifts the body on every peer.
func test_a_puppet_ragdolls_when_its_owner_does() -> void:
	var puppet: Player = PLAYER_SCENE.instantiate() as Player
	puppet.name = "2" # owned by peer 2; this peer is 1
	add_child_autofree(puppet)
	assert_false(puppet.is_multiplayer_authority())
	var rest: Transform3D = puppet.player_model.transform
	var bones: Array[Node] = puppet.physical_bone_simulator.find_children("*", "PhysicalBone3D", true, false)
	puppet.is_ragdolling = true # what the synchronizer does
	assert_true(puppet.player_model.top_level, "The model detaches, so the owner's world-space position means the same here")
	assert_false(puppet.animation_tree.active, "The walk stops")
	assert_true(puppet.collision_shape.disabled, "The capsule is off")
	assert_eq((bones[0] as PhysicalBone3D).collision_layer, 1, "The bones collide while they simulate")
	puppet.player_model.global_position += Vector3(40.0, 0.0, 25.0)
	puppet.is_ragdolling = false
	assert_false(puppet.player_model.top_level)
	assert_eq(puppet.player_model.transform, rest, "Back on its feet the model is at its rest transform again")
	assert_true(puppet.animation_tree.active)
	assert_false(puppet.collision_shape.disabled)
	assert_eq((bones[0] as PhysicalBone3D).collision_layer, 0)


## A peer joining while somebody lies in a ragdoll gets the flag in the spawn state, before the copy is ready, and
## with it the owner's detached model position, which is a world one. The spawn state lands as the synchronizer enters
## the tree, after the Player itself has.
func test_a_late_joiners_copy_starts_lying_where_the_owner_lies() -> void:
	var puppet: Player = PLAYER_SCENE.instantiate() as Player
	puppet.name = "2"
	puppet.position = Vector3(40.0, 0.0, 25.0) # the owner's body, at its hips
	puppet.tree_entered.connect(func() -> void:
		puppet.get_node("PlayerModel").position = Vector3(40.0, 0.0, 25.0) # the owner's model, detached: a world position
		puppet.is_ragdolling = true, CONNECT_ONE_SHOT)
	add_child_autofree(puppet)
	assert_true(puppet.player_model.top_level)
	assert_false(puppet.animation_tree.active)
	assert_true(puppet.collision_shape.disabled)
	assert_almost_eq(puppet.player_model.global_position, puppet.global_position, Vector3.ONE * 0.01, "The body drops where the owner lies, not at twice the distance")
	assert_eq(puppet.initial_player_model_transform.origin, Vector3.ZERO, "and the rest transform is the scene's, not the spawn state's")


## On a live peer the always-sent model position can arrive a frame before the flag: a world position written as a
## local one while the copy is still upright.
func test_a_copy_that_got_the_world_position_first_still_drops_in_place() -> void:
	var puppet: Player = PLAYER_SCENE.instantiate() as Player
	puppet.name = "2"
	add_child_autofree(puppet)
	puppet.global_position = Vector3(40.0, 0.0, 25.0)
	puppet.player_model.position = Vector3(40.0, 0.0, 25.0)
	puppet.is_ragdolling = true
	assert_almost_eq(puppet.player_model.global_position, puppet.global_position, Vector3.ONE * 0.01, "The body drops where the owner lies")
