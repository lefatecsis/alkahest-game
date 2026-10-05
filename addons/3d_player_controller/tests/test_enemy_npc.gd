extends GutTest

## Purpose: The EnemyNpc shipped with the addon idles until struck, hunts whoever struck it, takes damage, burns,
## dies into its ragdoll, and comes back through a SaveGame: a saved fighter stands up where it was saved with the
## health it had, a saved corpse stays dead.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/enemy_npc.tscn")

var root: Node3D
var player: Player
var enemy: EnemyNpc


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(60.0, 1.0, 60.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	enemy = ENEMY_SCENE.instantiate()
	enemy.position = Vector3(0.0, 0.0, -12.0)
	root.add_child(enemy)
	await wait_physics_frames(3)


func test_the_enemy_idles_until_struck_then_hunts_the_striker() -> void:
	assert_null(enemy.target)
	assert_true(enemy.is_in_group("Focusable"))
	assert_true(enemy.is_in_group("Saveable"), "The enemy saves with the game")
	watch_signals(enemy)
	enemy.register_weapon_hit(player, null)
	assert_eq(enemy.target, player, "Being struck starts the hunt")
	assert_signal_emitted(enemy, "aggroed")
	assert_eq(enemy.health.health, enemy.health.max_health - enemy.melee_hit_damage)
	assert_true(player.hunters.has(enemy), "The Player knows who hunts them")
	assert_true(player.health.regen_paused)


func test_fire_ticks_damage_and_water_puts_it_out() -> void:
	enemy.burn_tick_timer.wait_time = 0.05
	enemy.burn(0.2, 40.0)
	assert_true(enemy.is_burning)
	await wait_seconds(0.12)
	assert_lt(enemy.health.health, enemy.health.max_health, "Fire costs health")
	enemy.extinguish()
	assert_false(enemy.is_burning)
	var after: float = enemy.health.health
	await wait_seconds(0.12)
	assert_eq(enemy.health.health, after, "Put out, it stops burning")


func test_enough_damage_drops_it_into_the_ragdoll() -> void:
	watch_signals(enemy)
	enemy.take_hit(enemy.health.max_health, player.global_position)
	await wait_physics_frames(2)
	assert_true(enemy.is_dead)
	assert_signal_emitted(enemy, "died")
	assert_true(enemy.collision_shape.disabled)
	assert_false(enemy.is_in_group("Focusable"), "A corpse cannot be locked on to")
	assert_false(enemy.animation_tree.active)


func test_a_saved_fighter_stands_up_where_it_was_saved() -> void:
	enemy.health.health = 55.0
	var state: Dictionary = enemy.save_state()
	assert_eq(state["health"], 55.0)
	assert_false(state["is_dead"])
	enemy.take_hit(500.0, player.global_position)
	await wait_physics_frames(2)
	assert_true(enemy.is_dead)
	enemy.load_state(state)
	await wait_physics_frames(2)
	assert_false(enemy.is_dead, "Loading a living save revives the corpse")
	assert_eq(enemy.health.health, 55.0)
	assert_false(enemy.collision_shape.disabled)
	assert_true(enemy.animation_tree.active)
	assert_true(enemy.is_in_group("Focusable"))
	assert_almost_eq(enemy.global_position, Vector3(0.0, 0.0, -12.0), Vector3.ONE * 0.2)


func test_a_saved_corpse_stays_dead() -> void:
	enemy.take_hit(500.0, player.global_position)
	await wait_physics_frames(2)
	var state: Dictionary = enemy.save_state()
	assert_true(state["is_dead"])
	enemy.load_state(state)
	await wait_physics_frames(1)
	assert_true(enemy.is_dead)
	# And a living enemy handed a corpse's save dies on the spot
	var other: EnemyNpc = ENEMY_SCENE.instantiate()
	root.add_child(other)
	await wait_physics_frames(1)
	other.load_state(state)
	await wait_physics_frames(2)
	assert_true(other.is_dead)


## Death used to clear the target reference and leave the Player's died signal connected, which only showed
## itself one hunt later: a revived enemy turning on the same Player connected the same callable twice and
## Godot refused it. The noise sweep made it easy to hit, because hearing re-aggroes far more often than
## sight does.
func test_a_revived_enemy_can_hunt_the_same_player_again() -> void:
	enemy.register_weapon_hit(player, null)
	assert_eq(enemy.target, player, "It hunts whoever struck it")

	enemy.take_hit(enemy.health.max_health, player.global_position)
	await wait_physics_frames(2)
	assert_true(enemy.is_dead, "and dies")
	assert_false(
		player.health.died.is_connected(enemy._on_target_died),
		"Dying lets go of the Player's died signal as well as the hunt"
	)

	enemy.revive()
	await wait_physics_frames(2)
	enemy.aggro(player)

	assert_eq(enemy.target, player, "Back up, it hunts the same Player again")
	assert_true(player.health.died.is_connected(enemy._on_target_died), "and listens for them dying once more")


## A hunted Player who leaves the game (a peer that disconnected, its Player freed) is let go of through the
## Player's tree_exiting: the enemy used to keep a freed target and stand frozen, never walking home or healing.
func test_the_enemy_lets_go_of_a_hunted_player_who_leaves_the_game() -> void:
	enemy.register_weapon_hit(player, null)
	assert_eq(enemy.target, player)
	assert_true(player.tree_exiting.is_connected(enemy.lose_target), "The hunt listens for the Player leaving")
	player.queue_free()
	await wait_physics_frames(2)
	assert_null(enemy.target, "Gone, the Player is no longer hunted")
	assert_true(enemy.threat.is_empty(), "nor on the threat table")
	assert_true(enemy.is_returning_home, "and the enemy heads back to its post")


## A shove dies away whatever the enemy is doing: the decay lives in the move every branch ends with, so an enemy
## knocked back while walking home no longer slides away from its post for good.
func test_a_shove_dies_away_while_the_enemy_walks_home() -> void:
	enemy.register_weapon_hit(player, null)
	player.queue_free()
	await wait_physics_frames(2)
	assert_true(enemy.is_returning_home, "The enemy is walking home")
	enemy.knock_back(enemy.global_position + Vector3(0.0, 0.0, 1.0), enemy.hit_knockback)
	assert_gt(enemy.knockback_velocity.length(), 0.5, "and takes the shove")
	var settled: bool = await wait_until(func() -> bool: return enemy.knockback_velocity.is_zero_approx(), 2.0)
	assert_true(settled, "which dies away within two seconds, while it is still walking home")


## A swing from a Player this enemy is not hunting is a sneak attack; the striker's own Player says who hunts it,
## so a client's swing, registered on the client's copy that never hunts anyone, is weighed the same way.
func test_a_sneak_attack_lands_harder_only_on_an_enemy_not_hunting_the_striker() -> void:
	enemy.sneak_attack_multiplier = 2.0
	enemy.register_weapon_hit(player, null)
	assert_eq(enemy.health.health, enemy.health.max_health - enemy.melee_hit_damage * 2.0, "Caught unaware, it takes double")
	assert_true(player.hunters.has(enemy), "and now hunts the striker")
	var before: float = enemy.health.health
	enemy.register_weapon_hit(player, null)
	assert_eq(enemy.health.health, before - enemy.melee_hit_damage, "Hunting them, it takes the plain hit")


## A boss puts its health on the hunted Player's boss bar, and the bar follows its Health through the connection
## enemy_npc.tscn wires from Health.health_changed to the Boss node.
func test_a_boss_enemy_shows_its_health_on_the_hunted_players_bar() -> void:
	enemy.is_boss = true
	assert_true(enemy.health.health_changed.is_connected(enemy.boss._on_health_changed), "The scene wires the Boss to the Health")
	enemy.register_weapon_hit(player, null)
	assert_true(player.boss_bar.visible, "Hunted, the Player sees the boss bar")
	var ratio: float = enemy.health.health / enemy.health.max_health
	assert_almost_eq(player.boss_bar.health_bar.value, ratio, 0.001)
	enemy.take_hit(10.0, player.global_position)
	assert_almost_eq(player.boss_bar.health_bar.value, enemy.health.health / enemy.health.max_health, 0.001, "and the bar follows every hit")
