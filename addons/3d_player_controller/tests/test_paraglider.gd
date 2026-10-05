extends GutTest

## Purpose: To test the Paraglider scene and its Trail3D contrail nodes.

class TestParagliderContrails:
	extends GutTest

	const Contrail3D = preload("res://addons/3d_player_controller/scripts/contrail_3d.gd")
	var paraglider_scene = preload("res://addons/3d_player_controller/scenes/equipment/paraglider.tscn")
	var paraglider: Node3D

	func before_each() -> void:
		paraglider = paraglider_scene.instantiate()
		add_child_autofree(paraglider)

	func test_paraglider_instantiation() -> void:
		assert_not_null(paraglider, "Paraglider should instantiate successfully.")
		var left_wing = paraglider.get_node_or_null("LeftWing")
		var right_wing = paraglider.get_node_or_null("RightWing")
		assert_not_null(left_wing, "LeftWing node should exist.")
		assert_not_null(right_wing, "RightWing node should exist.")
		assert_is(left_wing, Contrail3D, "LeftWing should be a Contrail3D node.")
		assert_is(right_wing, Contrail3D, "RightWing should be a Contrail3D node.")

	func test_trail_properties_configured() -> void:
		var left_wing: Contrail3D = paraglider.get_node("LeftWing") as Contrail3D
		var right_wing: Contrail3D = paraglider.get_node("RightWing") as Contrail3D
		
		assert_false(left_wing.emitting, "LeftWing trail should not emit by default.")
		assert_false(right_wing.emitting, "RightWing trail should not emit by default.")
		assert_almost_eq(left_wing.width, 0.05, 0.001)
		assert_almost_eq(right_wing.width, 0.05, 0.001)
		assert_almost_eq(left_wing.lifetime, 1.0, 0.001)
		assert_almost_eq(right_wing.lifetime, 1.0, 0.001)
		assert_almost_eq(left_wing.min_section_length, 0.06, 0.001)
		assert_not_null(left_wing.color_gradient, "LeftWing should have a color gradient.")
		assert_not_null(left_wing.width_curve, "LeftWing should have a width curve.")

	## The Player carries its own glider, saved hidden, with state_changed wired to it in player.tscn.
	func test_paraglider_state_toggles_trail_emitting() -> void:
		var player_scene = preload("res://addons/3d_player_controller/scenes/player.tscn")
		var mock_player: Player = player_scene.instantiate() as Player
		add_child_autofree(mock_player)
		paraglider = mock_player.get_node("PlayerModel/Armature/GeneralSkeleton/ParagliderBoneAttachment/Paraglider")
		var left_wing: Contrail3D = paraglider.get_node("LeftWing") as Contrail3D
		var right_wing: Contrail3D = paraglider.get_node("RightWing") as Contrail3D
		assert_false(paraglider.visible, "The glider is packed away until the Player glides")

		# Simulate paragliding started
		mock_player.current_state = NodeStateMachine.States.PARAGLIDING

		assert_true(paraglider.visible, "Paraglider should be visible when paragliding.")
		assert_true(left_wing.emitting, "LeftWing trail should emit when paragliding.")
		assert_true(right_wing.emitting, "RightWing trail should emit when paragliding.")

		# Simulate paragliding stopped
		mock_player.current_state = NodeStateMachine.States.STANDING

		assert_false(paraglider.visible, "Paraglider should be hidden when not paragliding.")
		assert_false(left_wing.emitting, "LeftWing trail should not emit when not paragliding.")
		assert_false(right_wing.emitting, "RightWing trail should not emit when not paragliding.")
