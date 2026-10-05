extends GutTest

## Purpose: player.tscn documents itself. Every node someone opening the scene has to understand carries an
## editor_description, so the inspector explains the rig rather than the reader having to find the script.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

## Nodes that come out of Mixamo's Y Bot rather than being put there by this scene. They belong to the
## imported .glb, so describing them would mean overriding nodes inside an instanced scene and inviting churn
## every time the model reimports.
const FROM_THE_MODEL: Array[String] = ["Armature", "Alpha_Joints", "Alpha_Surface"]

## The parts of the scene a reader meets first, the Hud's children among them (they are the screen, in scenes/ui/player_hud.tscn). The ragdoll's PhysicalBone3D children are left out: there are
## 52 of them, one per bone, and the bone name says all there is to say.
const DOCUMENTED_BRANCHES: Array[String] = [
	".",
	"CameraMount",
	"CameraMount/CameraSpringArm",
	"CameraMount/CameraSpringArm/Camera3D",
	"CameraMount/ProjectileRaycast",
	"PlayerModel",
	"PlayerModel/Armature/GeneralSkeleton",
	"NodeStateMachine",
	"SFX_Weapons",
	"SFX_Ability",
	"Hud",
]

var player: Player


func before_each() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)


func _children_of(branch: String) -> Array[Node]:
	var node: Node = player if branch == "." else player.get_node_or_null(branch)
	assert_not_null(node, "player.tscn should still have %s" % branch)
	var out: Array[Node] = []
	if node == null:
		return out
	for child: Node in node.get_children():
		if child is PhysicalBone3D or FROM_THE_MODEL.has(String(child.name)):
			continue
		# Only what the scene itself declares. A scene-authored node carries an owner; one attached at run time
		# does not, and those belong to whoever attached them (equipment, a gadget a game adds from code), which
		# are not this scene's to describe.
		if child.owner == null:
			continue
		out.append(child)
	return out


func test_every_node_a_reader_meets_explains_itself() -> void:
	var bare: PackedStringArray = []
	var documented: int = 0
	for branch: String in DOCUMENTED_BRANCHES:
		for child: Node in _children_of(branch):
			if child.editor_description.strip_edges().is_empty():
				bare.append("%s/%s" % [branch, child.name])
			else:
				documented += 1
	assert_eq(bare, PackedStringArray(), "These nodes carry no editor_description; say what they are for.")
	assert_gt(documented, 90, "The scene should still be documented throughout, not whittled down")


func test_the_descriptions_are_sentences_rather_than_labels() -> void:
	var terse: PackedStringArray = []
	for branch: String in DOCUMENTED_BRANCHES:
		for child: Node in _children_of(branch):
			var text: String = child.editor_description.strip_edges()
			if not text.is_empty() and (text.length() < 20 or not text.ends_with(".")):
				terse.append("%s/%s" % [branch, child.name])
	assert_eq(terse, PackedStringArray(), "A description should be a full sentence saying what the node is for.")


func test_the_two_look_at_modifiers_say_how_they_differ() -> void:
	var skeleton: String = "PlayerModel/Armature/GeneralSkeleton"
	var spine: Node = player.get_node("%s/LookAtModifier3D" % skeleton)
	var head: Node = player.get_node("%s/HeadLookAtModifier3D" % skeleton)

	assert_true(spine.editor_description.contains("Spine"), "The spine one should name the bone it bends")
	assert_true(head.editor_description.contains("Head"), "and the head one should name its own")
	assert_ne(spine.editor_description, head.editor_description, "They do different jobs and should read differently")
	assert_eq(spine.bone_name, "Spine", "The spine modifier still bends the Spine")
	assert_eq(head.bone_name, "Head", "and the head modifier the Head")
	# The spine's limit is symmetric, a whole angle across; the head's has a side each way, since it tips further up
	# than down from a rest pose that already leans forward.
	assert_gt(spine.primary_limit_angle * 0.5, head.primary_positive_limit_angle,
		"The neck is the tighter of the two, so a target behind the Player is not followed all the way round")
	assert_gt(spine.primary_limit_angle * 0.5, head.primary_negative_limit_angle, "either way")
