extends GutTest

## Purpose: To test bow firing, and that throwing a held object while a bow is equipped does not trigger the bow.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const ARROW_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/arrow.tscn")
const BOW_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/bow.gd")
const ARROW_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/arrow.gd")

class MockHeldCharacter extends CharacterBody3D:
	var player: Player
	var is_held: bool = false

	func pick_up() -> void:
		if not player or not player.item_spring_arm:
			return
		is_held = true
		if get_parent():
			get_parent().remove_child(self)
		player.item_spring_arm.add_child(self)
		position = Vector3.ZERO

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release("shoot")
	if is_instance_valid(root):
		root.free()
		root = null


## A bow with a draw sound; `with_player` wires it to the player's locomotion signal like equip() does.
func _make_bow(with_player: bool) -> Bow:
	var bow = Node3D.new()
	bow.set_script(BOW_SCRIPT)
	bow.equipment_type = Equipment.EquipmentType.BOW
	var draw_sound = AudioStreamPlayer3D.new()
	draw_sound.name = "BowDrawArrow"
	bow.add_child(draw_sound)
	if with_player:
		bow.player = player
	root.add_child(bow)
	player.inventory.add_equipment(bow)
	player.inventory.can_player_shoot = true
	return bow


func test_holding_rigidbody_with_bow_equipped_blocks_bow_draw():
	var bow = _make_bow(true)
	var draw_sound = bow.get_node("BowDrawArrow")
	assert_true(player.equipped_bow, "Bow should be equipped.")

	var body = RigidBody3D.new()
	root.add_child(body)
	player.held_object._pickup_rigidbody(body)
	assert_true(player.held_object.is_holding_object(), "Player should be holding an object.")
	assert_false(player.is_shooting, "is_shooting should be false while holding object.")
	assert_false(player.is_drawing_arrow, "is_drawing_arrow should be false while holding object.")
	assert_true(player.head_look_at_modifier.active, "Picking up should turn the head to the body.")

	player.start_charging_throw()
	assert_true(player.held_object.is_charging_throw, "Throw should be charging.")
	assert_false(player.is_shooting, "is_shooting should remain false while charging throw.")

	# A draw node change while holding must not trigger the bow
	bow._on_locomotion_node_changed("Bow/BowDrawArrow")
	assert_false(draw_sound.playing, "Bow draw sound should not play while holding an object.")

	player.held_object.execute_throw()
	assert_false(player.is_drawing_arrow, "is_drawing_arrow should not be true on throw.")
	assert_false(draw_sound.playing, "Bow draw sound should not play on throw.")
	assert_false(player.look_at_modifier.active, "Throwing should clear the look-at modifier.")


func test_holding_little_buddy_with_bow_equipped_blocks_bow_draw():
	var bow = _make_bow(false)
	var draw_sound = bow.get_node("BowDrawArrow")

	var buddy = MockHeldCharacter.new()
	root.add_child(buddy)
	buddy.player = player
	buddy.pick_up()
	assert_true(player.held_object.is_holding_object(), "is_holding_object should be true when Little Buddy is held.")
	assert_false(player.is_shooting, "is_shooting should be false while holding Little Buddy.")

	player.start_charging_throw()
	assert_false(player.is_drawing_arrow, "is_drawing_arrow should remain false while charging throw.")

	player.held_object.execute_instant_throw(Vector3.FORWARD, 1.0)
	assert_false(player.is_drawing_arrow, "is_drawing_arrow should not be true after throw.")
	assert_false(draw_sound.playing, "Bow draw sound should not play on throw.")


func test_shooting_bow_works_normally_when_empty_handed():
	_make_bow(false)
	assert_false(player.held_object.is_holding_object(), "Player is not holding an object.")
	Input.action_press("shoot")
	assert_true(player.is_shooting, "is_shooting should be true when pressing shoot with bow equipped and empty hands.")
	Input.action_release("shoot")
	assert_false(player.is_shooting, "is_shooting should be false when shoot action is released.")


func test_fire_node_spawns_one_arrow_along_the_projectile_ray():
	var bow = _make_bow(true)
	var template = RigidBody3D.new()
	template.name = "Arrow"
	template.set_script(ARROW_SCRIPT)
	bow.add_child(template)
	bow.arrow_node = template
	# Arrows come out of the inventory now: one AmmoItem for the bow, built here so no .tres is loaded
	var quiver := AmmoItem.new()
	quiver.id = &"test_arrow"
	quiver.weapon_type = Equipment.EquipmentType.BOW
	quiver.rounds_per_unit = 1
	player.inventory.add_item(quiver, 3)
	await wait_physics_frames(1)
	assert_true(template.freeze, "The template arrow stays frozen.")

	var arrows_before: int = root.get_children().filter(func(n): return n is Arrow).size()
	bow._on_locomotion_node_changed("Bow/BowFireArrow")
	var arrows: Array = root.get_children().filter(func(n): return n is Arrow)
	assert_eq(arrows.size(), arrows_before + 1, "Firing should spawn exactly one arrow.")
	assert_eq(player.inventory.count_of(quiver), 2, "The shot took one arrow from the inventory.")

	var arrow: Arrow = arrows.back()
	assert_false(arrow.is_template, "The fired arrow is not a template.")
	assert_eq(arrow.shooter, player, "The fired arrow remembers its shooter.")
	assert_false(arrow.freeze, "The fired arrow is free to fly.")
	var ray: RayCast3D = player.projectile_raycast
	var ray_dir: Vector3 = -ray.global_basis.z
	assert_almost_eq((arrow.global_position - ray.global_position).cross(ray_dir).length(), 0.0, 0.01, "The arrow leaves on the crosshair line.")
	assert_almost_eq(arrow.linear_velocity.normalized().dot(ray_dir), 1.0, 0.05, "Arrow velocity should follow the projectile ray.")
	assert_gt(arrow.linear_velocity.normalized().y, ray_dir.y, "The arrow is lobbed above the straight line, to allow for the drop.")
	assert_almost_eq(arrow.linear_velocity.length(), bow.projectile_speed, 0.01, "Arrow speed should match the bow's projectile_speed.")
	arrow.free()


func test_the_arrow_scene_has_a_tip_marker_at_the_head_that_leads_in_flight() -> void:
	var arrow: Arrow = ARROW_SCENE.instantiate()
	arrow.is_template = false
	root.add_child(arrow)
	var tip: Marker3D = arrow.get_node("Tip")
	var mesh: MeshInstance3D = arrow.get_node("MeshInstance3D")
	var head: float = mesh.position.y + (mesh.mesh as CylinderMesh).height * 0.5
	assert_almost_eq(tip.position.y, head, 0.02, "The Tip marker sits at the head end of the shaft, like a gun's Muzzle")
	assert_almost_eq(tip.position.x, 0.0, 0.001)
	assert_almost_eq(tip.position.z, 0.0, 0.001)
	arrow.launch(Transform3D(Basis.IDENTITY, Vector3(0.0, 5.0, -3.0)), Vector3.RIGHT, 20.0, null)
	await wait_physics_frames(3)
	var along: Vector3 = arrow.linear_velocity.normalized()
	assert_almost_eq((tip.global_position - arrow.global_position).normalized().dot(along), 1.0, 0.01, "In flight the tip leads: the shaft's +Y is turned along the velocity")
	arrow.free()


## Fires an arrow at [param speed] on the bow's arc through [param target] and returns where it landed: on a wall
## standing at the target, facing the shooter, or with [param on_floor] on a floor whose top is at the target's height
## (Vector3.INF when it never landed). The shot starts clear of the Player at the origin.
func _land(from: Vector3, target: Vector3, speed: float, on_floor: bool) -> Vector3:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(6.0, 0.2, 6.0) if on_floor else Vector3(6.0, 6.0, 0.2)
	body.add_child(shape)
	body.position = target - (Vector3(0.0, 0.1, 0.0) if on_floor else Vector3(0.0, 0.0, 0.1))
	root.add_child(body)
	var arrow = RigidBody3D.new()
	arrow.set_script(ARROW_SCRIPT)
	arrow.is_template = false
	root.add_child(arrow)
	watch_signals(arrow)
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	arrow.launch(Transform3D(Basis.IDENTITY, from), Bow.arc_direction(from, target, speed, gravity), speed, null)
	await wait_physics_frames(40)
	var landed: Array = get_signal_parameters(arrow, "hit")
	return landed[1] if landed else Vector3.INF


func test_the_arc_lands_an_arrow_on_a_level_target_15_m_out():
	var target := Vector3(30.0, 5.0, -15.0)
	var point: Vector3 = await _land(Vector3(30.0, 5.0, 0.0), target, 50.0, false)
	assert_lt(point.distance_to(target), 0.5, "Aimed on the arc, the arrow hits the wall on the crosshair instead of below it: %s" % point)


func test_the_arc_lands_an_arrow_on_a_target_3_m_below():
	var target := Vector3(30.0, 2.0, -15.0) # the pond from the bank
	var point: Vector3 = await _land(Vector3(30.0, 5.0, 0.0), target, 50.0, true)
	assert_lt(point.distance_to(target), 0.5, "A shot down at the water lands where the crosshair is: %s" % point)


func test_an_aim_point_out_of_range_still_fires_straight():
	var straight: Vector3 = Vector3(0.0, 0.0, -500.0).normalized()
	assert_eq(Bow.arc_direction(Vector3.ZERO, Vector3(0.0, 0.0, -500.0), 50.0, 9.8), straight, "No arc reaches 500 m at 50 m/s: the arrow flies at the crosshair")
	assert_eq(Bow.arc_direction(Vector3.ZERO, Vector3(0.0, -3.0, -15.0), 50.0, 0.0), Vector3(0.0, -3.0, -15.0).normalized(), "Without gravity the line is straight")
	var lobbed: Vector3 = Bow.arc_direction(Vector3.ZERO, Vector3(0.0, 0.0, -15.0), 50.0, 9.8)
	assert_almost_eq(lobbed.length(), 1.0, 0.001, "A unit direction")
	assert_almost_eq(lobbed.y, sin(0.5 * asin(9.8 * 15.0 / 2500.0)), 0.001, "The low arc: sin(2a) = g d / v^2 on a level target")
