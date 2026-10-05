extends GutTest

## Purpose: with the cursor showing, a left click on the ground walks the Player there over the navigation mesh and
## drops the click marker (three spheres wrapped in a scrolling arrow, from the Guild Wars Heroes Island project)
## where it landed, gone after half a second; a click on a body is a Target being picked, not a place to walk to.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CONTROLS_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/player_controls.tscn")
const WOW: ControlScheme = preload("res://addons/3d_player_controller/resources/control_schemes/world_of_warcraft.tres")

var root: Node3D
var player: Player


func before_each() -> void:
	add_child_autofree(CONTROLS_SCENE.instantiate())
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate()
	player.control_scheme = WOW
	root.add_child(player)
	await wait_physics_frames(2)


func _markers() -> Array[Node]:
	return root.get_children().filter(func(node: Node) -> bool: return node.name.begins_with("ClickMarker"))


func test_a_click_on_the_ground_walks_there_and_drops_the_marker() -> void:
	var ahead: Vector3 = player.global_position - player.global_basis.z * 4.0
	var on_screen: Vector2 = player.camera.unproject_position(ahead)
	watch_signals(player)
	player.click_to_move_at(on_screen)
	assert_true(player.is_navigating, "The Player sets off")
	assert_signal_emitted(player, "navigating_changed")
	assert_lt(player.navigation_agent.target_position.distance_to(ahead), 0.5, "for where the click landed on its movement plane")
	var markers: Array[Node] = _markers()
	assert_eq(markers.size(), 1, "and one marker is dropped there")
	var marker: Node3D = markers[0]
	assert_lt(marker.global_position.distance_to(ahead), 0.5)
	assert_eq(marker.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D).size(), 3, "Three spheres wrapped in the arrow")
	var material: ShaderMaterial = (marker.get_child(0) as MeshInstance3D).mesh.material
	assert_eq(material.shader.resource_path, "res://addons/3d_player_controller/assets/shaders/click_to_move.gdshader", "with the Guild Wars scrolling-arrow shader")
	assert_true(bool(material.get_shader_parameter(&"animate")), "animating")
	await wait_seconds(0.7)
	assert_eq(_markers().size(), 0, "Gone after half a second")


func test_a_click_on_a_body_picks_it_and_does_not_walk() -> void:
	var dummy: CharacterBody3D = CharacterBody3D.new()
	dummy.name = "Dummy"
	dummy.add_to_group("Focusable")
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 1.0
	dummy.add_child(shape)
	root.add_child(dummy)
	dummy.global_position = player.global_position - player.global_basis.z * 4.0 + Vector3.UP * 1.0
	await wait_physics_frames(2)
	var on_screen: Vector2 = player.camera.unproject_position(dummy.global_position)
	assert_eq(player.focus.body_under(on_screen), dummy, "The click lands on the body")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = get_viewport().get_final_transform() * on_screen # a window pixel; the viewport maps it back through the stretch
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	await wait_process_frames(1)
	var release: InputEventMouseButton = click.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	assert_eq(player.selected_target, dummy, "so it is the Target")
	assert_false(player.is_navigating, "and the Player stays put")
	assert_eq(_markers().size(), 0, "with no marker dropped")
