extends GutTest

## Purpose: Vitals drains hunger and thirst by the second, eats health once either pool is empty, and eating or
## drinking puts it right. Only the owning peer drains: the Health it eats replicates, so a puppet's copy draining
## as well would take the damage twice.

const HEALTH_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/health.tscn")


## A Vitals with its own Health under an owner that belongs to [param authority].
func _make_vitals(authority: int = 1) -> Vitals:
	var owner_node: Node = Node.new()
	var health: Health = HEALTH_SCENE.instantiate()
	owner_node.add_child(health)
	var vitals: Vitals = Vitals.new()
	vitals.health = health
	vitals.hunger_drain = 50.0
	vitals.thirst_drain = 100.0
	vitals.starving_damage = 20.0
	owner_node.add_child(vitals)
	owner_node.set_multiplayer_authority(authority) # recursive, as a Player's own does in _enter_tree
	add_child_autofree(owner_node)
	return vitals


func test_the_pools_drain_and_an_empty_one_costs_health() -> void:
	var vitals: Vitals = _make_vitals()
	watch_signals(vitals)
	await wait_seconds(0.5)
	assert_lt(vitals.hunger, vitals.capacity, "Hunger drains by the second")
	assert_lt(vitals.thirst, vitals.hunger, "and thirst faster")
	await wait_seconds(0.8)
	assert_signal_emitted(vitals, "dehydrated", "Thirst runs out first")
	assert_lt(vitals.health.health, vitals.health.max_health, "and an empty pool eats health")


func test_eating_and_drinking_top_up_and_recover() -> void:
	var vitals: Vitals = _make_vitals()
	watch_signals(vitals)
	vitals.thirst = 0.0
	await wait_physics_frames(3)
	vitals.drink(50.0)
	vitals.eat(50.0)
	await wait_physics_frames(3)
	assert_gt(vitals.thirst, 0.0, "A drink refills thirst")
	assert_signal_emitted(vitals, "recovered", "and both pools above zero again is a recovery")
	vitals.eat(1000.0)
	assert_eq(vitals.hunger, vitals.capacity, "A pool never passes its capacity")


func test_a_puppets_copy_never_drains() -> void:
	var vitals: Vitals = _make_vitals(2)
	assert_false(vitals.is_multiplayer_authority(), "This Vitals belongs to peer 2")
	vitals.thirst = 0.0
	await wait_seconds(0.3)
	assert_eq(vitals.hunger, vitals.capacity, "Only the owner drains")
	assert_eq(vitals.health.health, vitals.health.max_health, "and only the owner's copy takes the damage")
