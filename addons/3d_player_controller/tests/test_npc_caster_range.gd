extends GutTest

## Purpose: NpcCaster.cast(ability, at) and Abilities.cast(ability, at) start a given ability on demand at a chosen
## body (Ability.aim_at, honoured by get_target ahead of focus, aim and an NPC's target, and forgotten once the
## effect lands or the cast breaks), so a test range can run any spell in either direction; the NPC one ignores
## range, cooldown, cost and the heal rule, and the AI keeps choosing through try_cast.

const ENEMY_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/enemy_npc.tscn")
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const HEAL: Ability = preload("res://addons/3d_player_controller/resources/abilities/heal.tres")

var root: Node3D
var enemy: EnemyNpc
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	enemy = ENEMY_SCENE.instantiate()
	enemy.position = Vector3(0.0, 0.0, -40.0) # well outside any cast range
	root.add_child(enemy)
	await wait_physics_frames(1)


func test_cast_runs_a_spell_the_ai_would_refuse() -> void:
	enemy.target = player
	assert_false(enemy.caster.try_cast(player), "The AI will not cast at forty metres, and holds a heal at full health")
	watch_signals(enemy.caster)
	assert_true(enemy.caster.cast(HEAL), "cast() does not ask")
	var started: bool = enemy.caster.casting == HEAL or get_signal_emit_count(enemy.caster, "ability_activated") > 0
	assert_true(started, "The heal's sequence is running")


func test_cast_waits_for_a_cast_in_progress_and_needs_an_ability() -> void:
	enemy.target = player
	assert_false(enemy.caster.cast(null), "Nothing to cast")
	if HEAL.cast_time > 0.0:
		assert_true(enemy.caster.cast(HEAL))
		assert_false(enemy.caster.cast(HEAL), "One at a time: a cast already running is not interrupted")


func test_a_chosen_body_is_the_target_until_the_effect_lands() -> void:
	var heal_on_player: Ability = HEAL
	assert_true(enemy.caster.cast(heal_on_player, player), "The enemy casts the heal at the Player")
	assert_eq(heal_on_player.get_target(enemy), player, "so it lands on the Player, not on the enemy the heal would pick")
	enemy.caster.interrupt()
	assert_null(Ability.chosen_target(enemy), "A broken cast forgets the body")
	assert_true(enemy.caster.cast(heal_on_player))
	assert_eq(heal_on_player.get_target(enemy), enemy, "Without one the heal's own rule stands: itself")
	enemy.caster.interrupt()
	# The Player's side goes the same way
	var friend: Player = PLAYER_SCENE.instantiate()
	friend.position = Vector3(3.0, 0.0, 0.0)
	root.add_child(friend)
	await wait_physics_frames(1)
	friend.health.health = 30.0
	player.abilities.cast(HEAL, friend)
	assert_eq(HEAL.get_target(player), friend, "A heal the Player was told to cast at a friend lands there")
	player.abilities.interrupt_cast()
	assert_null(Ability.chosen_target(player))
	player.abilities.cast(HEAL, enemy)
	assert_null(Ability.chosen_target(player), "Told to heal an enemy, which cannot be healed, the cast is refused and the body forgotten")
	player.abilities.cast(HEAL)
	assert_eq(HEAL.get_target(player), player, "and on the Player when nothing was chosen")
	player.abilities.interrupt_cast()
