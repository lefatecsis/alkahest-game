extends GutTest

## Purpose: A TalkingNpc offers Talk while looked at, and Action begins a conversation that is the game's to run:
## the Player stands still, the NPC keeps the talker and emits talked_to, and end_talk lets go, emits
## conversation_ended and offers the prompt again. The addon says nothing itself.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const NPC_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/talking_npc.tscn")

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await wait_physics_frames(2)


func _npc(offset: Vector3) -> TalkingNpc:
	var npc: TalkingNpc = NPC_SCENE.instantiate()
	npc.display_name = "Bob"
	root.add_child(npc)
	npc.global_position = player.global_position + offset
	return npc


func test_a_talking_npc_offers_talk_and_hands_the_conversation_to_the_game() -> void:
	var npc: TalkingNpc = _npc(Vector3(0.0, 0.0, -2.0))
	await wait_physics_frames(2)
	watch_signals(npc)
	npc.display_menu(player)
	assert_true(npc.action_prompt.visible, "Looked at, the prompt shows")
	assert_eq(player.controls.prompt_action_label, "Talk")
	npc.hide_menu()
	assert_false(npc.action_prompt.visible)
	npc.equip(player)
	assert_signal_emitted_with_parameters(npc, "talked_to", [player])
	assert_eq(npc.talker, player)
	assert_true(player.is_paused, "The Player stands still while talking")
	assert_false(npc.talk(player), "One conversation at a time")
	npc.display_menu(player)
	assert_false(npc.action_prompt.visible, "No prompt mid-conversation")
	npc.end_talk()
	assert_null(npc.talker, "Let go once the game says the conversation is over")
	assert_false(player.is_paused)
	assert_signal_emitted_with_parameters(npc, "conversation_ended", [player])
	npc.end_talk()
	assert_signal_emit_count(npc, "conversation_ended", 1, "Ending twice is nothing")


func test_an_npc_that_does_not_pause_leaves_the_player_free() -> void:
	var npc: TalkingNpc = _npc(Vector3(0.0, 0.0, -2.0))
	npc.pauses_talker = false
	await wait_physics_frames(2)
	assert_true(npc.talk(player))
	assert_false(player.is_paused)
	npc.end_talk()
	assert_false(player.is_paused)


func test_the_prompt_comes_back_for_the_camera_target_when_the_talk_ends() -> void:
	var npc: TalkingNpc = _npc(Vector3(0.0, 0.0, -1.5))
	await wait_physics_frames(6)
	assert_eq(player.camera.looking_at, npc, "Standing in front of the NPC, the camera ray lands on them")
	assert_true(npc.action_prompt.visible)
	npc.equip(player)
	assert_false(npc.action_prompt.visible)
	npc.end_talk()
	assert_true(npc.action_prompt.visible, "Still the target, so the prompt is offered again")
	assert_eq(player.controls.prompt_action_label, "Talk")


## An export repacks scenes, and a node added inside the instanced model survives that only when the model is
## marked editable; without it the web build's Guide had no head modifier at all.
func test_the_head_modifier_survives_the_repacking_an_export_does() -> void:
	var original: Node = NPC_SCENE.instantiate()
	var repacked: PackedScene = PackedScene.new()
	assert_eq(repacked.pack(original), OK)
	original.free()
	var npc: Node = repacked.instantiate()
	assert_not_null(npc.get_node_or_null("Mannequin_M/Armature/GeneralSkeleton/HeadLookAtModifier3D"))
	npc.free()
