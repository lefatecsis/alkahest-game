extends GutTest

## Purpose: a Player standing idle on a slope stays where it stands. The step-up SeparationRayShape3D hangs in front
## of the feet, and facing uphill its tip is always buried in the hill; separating along its own tilted axis it pushed
## the body up and forward, so an idle Player crept uphill at about 7 cm a second. With slide_on_slope it separates
## along the ground's normal, which still lifts the Player onto a stair but never pushes it along a slope.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var player: Player


func _box(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(shape)
	body.position = at
	parent.add_child(body)


func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var slope := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(40.0, 1.0, 40.0)
	slope.add_child(shape)
	slope.rotation_degrees = Vector3(15.0, 0.0, 0.0) # a hillside, like the snow demo's
	slope.position.y = -0.5
	root.add_child(slope)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	await wait_seconds(1.5) # land and settle


func test_the_step_ray_separates_along_the_ground() -> void:
	var ray: SeparationRayShape3D = player.separation_ray_shape.shape as SeparationRayShape3D
	assert_true(ray.slide_on_slope, "Along its own axis the buried ray walks the Player up every hill")


func test_an_idle_player_on_a_slope_stays_where_it_stands() -> void:
	assert_true(player.is_on_floor(), "The Player stands on the slope")
	var start: Vector3 = player.global_position
	await wait_seconds(5.0)
	var drift: float = (player.global_position - start).slide(Vector3.UP).length()
	assert_lt(drift, 0.02, "Five seconds idle on a 15 degree slope moves it %.3f m, not the 0.35 m it used to creep" % drift)


func test_the_player_still_walks_up_onto_a_30_cm_curb() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	_box(root, Vector3(40.0, 1.0, 40.0), Vector3(50.0, -0.5, 0.0))
	# a 2 m pit ringed by a curb, so whichever way forward is, the walk meets it
	_box(root, Vector3(40.0, 0.3, 19.0), Vector3(50.0, 0.15, 10.5))
	_box(root, Vector3(40.0, 0.3, 19.0), Vector3(50.0, 0.15, -10.5))
	_box(root, Vector3(19.0, 0.3, 2.0), Vector3(60.5, 0.15, 0.0))
	_box(root, Vector3(19.0, 0.3, 2.0), Vector3(39.5, 0.15, 0.0))
	player.global_position = Vector3(50.0, 0.1, 0.0)
	await wait_seconds(1.0)
	Input.action_press("move_up")
	await wait_seconds(3.0)
	Input.action_release("move_up")
	assert_gt(Vector2(player.global_position.x - 50.0, player.global_position.z).length(), 3.0, "The Player walked out of the pit")
	assert_almost_eq(player.global_position.y, 0.3, 0.05, "and stands on the curb")
