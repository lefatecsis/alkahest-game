extends GutTest

## Purpose: an enemy keeps a threat table, the World of Warcraft way. Hits, projectiles, abilities and the aggro
## area add threat per attacker, the highest holds its attention, the dead fall off it, and a neutral enemy
## ignores the aggro area until it is attacked, when it turns hostile until it dies or is revived.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/enemy_npc.tscn")

var root: Node3D
var player: Player
var other: Player
var enemy: EnemyNpc


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(60.0, 1.0, 60.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	other = PLAYER_SCENE.instantiate() # both this peer's own, so the enemy's hunted_by lands on them
	other.position = Vector3(4.0, 0.0, 0.0)
	root.add_child(other)
	enemy = ENEMY_SCENE.instantiate()
	enemy.position = Vector3(0.0, 0.0, -12.0)
	root.add_child(enemy)
	await wait_physics_frames(3)


func test_the_highest_threat_holds_its_attention() -> void:
	assert_eq(enemy.disposition, Focus.Disposition.HOSTILE, "An enemy is hostile by default")
	enemy.register_weapon_hit(player, null)
	assert_eq(enemy.target, player, "The first hit starts the hunt")
	assert_almost_eq(enemy.threat[player], enemy.melee_hit_damage, 0.01, "worth its damage on the table")
	enemy.add_threat(other, enemy.melee_hit_damage * 0.5)
	assert_eq(enemy.target, player, "Half as much threat does not turn it")
	enemy.add_threat(other, enemy.melee_hit_damage)
	assert_eq(enemy.target, other, "More does")
	assert_true(other.hunters.has(enemy), "and the new prey knows")
	assert_false(player.hunters.has(enemy), "while the old one is let go")


func test_the_dead_fall_off_the_table() -> void:
	enemy.add_threat(other, 10.0)
	enemy.add_threat(player, 30.0)
	assert_eq(enemy.target, player)
	player.health.damage(player.health.max_health)
	await wait_physics_frames(1)
	assert_false(enemy.threat.has(player), "A dead attacker is off the table")
	assert_eq(enemy.target, other, "and the next on it is hunted")


func test_a_neutral_waits_to_be_attacked_then_turns_hostile_until_revived() -> void:
	enemy.disposition = Focus.Disposition.NEUTRAL
	watch_signals(enemy)
	enemy._on_aggro_area_body_entered(player)
	assert_null(enemy.target, "Walking up to a neutral means nothing to it")
	assert_true(enemy.threat.is_empty())
	enemy.register_weapon_hit(player, null)
	assert_eq(enemy.disposition, Focus.Disposition.HOSTILE, "Struck, it turns hostile")
	assert_signal_emitted(enemy, "provoked")
	assert_eq(enemy.target, player, "and hunts the striker")
	enemy.health.damage(enemy.health.max_health)
	await wait_physics_frames(2)
	assert_true(enemy.threat.is_empty(), "Death clears the table")
	enemy.revive()
	assert_eq(enemy.disposition, Focus.Disposition.NEUTRAL, "and a revived neutral is neutral again")


func test_the_aggro_area_is_worth_less_than_any_hit() -> void:
	enemy._on_aggro_area_body_entered(other)
	assert_eq(enemy.target, other, "Walking into the area is enough to be hunted")
	assert_almost_eq(enemy.threat[other], EnemyNpc.AGGRO_AREA_THREAT, 0.01)
	enemy.register_weapon_hit(player, null)
	assert_eq(enemy.target, player, "but one hit from somebody else outweighs it")
