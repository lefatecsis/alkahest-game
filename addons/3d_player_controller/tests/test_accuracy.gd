extends GutTest
## The Accuracy resource: a spread cone per weapon that shrinks with the shooter's skill.

var accuracy: Accuracy


func before_each() -> void:
	accuracy = Accuracy.new()
	accuracy.spread_degrees = 4.0
	accuracy.expert_spread_degrees = 0.5
	accuracy.expert_level = 10


func test_the_spread_eases_from_novice_to_expert_and_stops_there() -> void:
	assert_eq(accuracy.spread_for(0), 4.0, "A novice gets the full cone")
	assert_almost_eq(accuracy.spread_for(5), 2.25, 0.001, "Halfway to expert is halfway between")
	assert_eq(accuracy.spread_for(10), 0.5, "An expert gets the tight cone")
	assert_eq(accuracy.spread_for(50), 0.5, "Past expert it stops shrinking")
	assert_eq(accuracy.spread_for(-3), 4.0, "Below zero is still a novice")


func test_scattered_rounds_stay_inside_the_cone_and_do_not_all_fly_the_same_way() -> void:
	var aim: Vector3 = Vector3(0.3, 0.1, -1.0).normalized()
	var directions: Array[Vector3] = []
	for _i: int in 200:
		var shot: Vector3 = accuracy.scatter(aim, 0)
		assert_almost_eq(shot.length(), 1.0, 0.0001)
		assert_lte(rad_to_deg(shot.angle_to(aim)), 4.0001, "Inside the novice cone")
		directions.append(shot)
	var widest: float = 0.0
	for shot: Vector3 in directions:
		widest = maxf(widest, rad_to_deg(shot.angle_to(directions[0])))
	assert_gt(widest, 1.0, "Two hundred rounds do not all take the same line")


func test_an_expert_round_barely_strays_and_a_zero_cone_flies_dead_straight() -> void:
	var aim: Vector3 = Vector3.FORWARD
	for _i: int in 50:
		assert_lte(rad_to_deg(accuracy.scatter(aim, 10).angle_to(aim)), 0.5001, "Inside the expert cone")
	accuracy.spread_degrees = 0.0
	accuracy.expert_spread_degrees = 0.0
	assert_eq(accuracy.scatter(aim, 0), aim, "No cone, no stray")
	assert_eq(accuracy.scatter(Vector3.UP, 0), Vector3.UP, "Straight up is handled without a degenerate axis")


func test_the_bundled_resources_load_and_tighten_from_bow_to_rifle() -> void:
	var pistol: Accuracy = load("res://addons/3d_player_controller/resources/accuracy/pistol.tres")
	var rifle: Accuracy = load("res://addons/3d_player_controller/resources/accuracy/rifle.tres")
	var bow: Accuracy = load("res://addons/3d_player_controller/resources/accuracy/bow.tres")
	assert_gt(bow.spread_for(0), pistol.spread_for(0))
	assert_gt(pistol.spread_for(0), rifle.spread_for(0))
	for weapon: Accuracy in [pistol, rifle, bow]:
		assert_lt(weapon.spread_for(weapon.expert_level), weapon.spread_for(0), "Skill tightens every weapon")
