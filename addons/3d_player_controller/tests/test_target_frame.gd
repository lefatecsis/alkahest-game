extends GutTest

## Purpose: the HUD's TargetFrame shows the Player's Target: its name, its health tinted by how it stands to the
## Player, and who it is hunting; it hides with no Target and follows the Target's health as it changes.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/enemy_npc.tscn")
const WOW: ControlScheme = preload("res://addons/3d_player_controller/resources/control_schemes/world_of_warcraft.tres")

var root: Node3D
var player: Player
var frame: TargetFrame


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate()
	player.control_scheme = WOW
	root.add_child(player)
	frame = player.hud.target_frame
	await wait_physics_frames(1)


func test_it_is_on_the_hud_hidden_until_there_is_a_target() -> void:
	assert_not_null(frame, "PlayerHud carries the frame")
	assert_eq(frame.player, player, "handed the Player like every HUD child")
	assert_false(frame.visible, "Nothing targeted, nothing shown")


func test_it_shows_the_target_its_health_and_who_it_hunts() -> void:
	var enemy: EnemyNpc = ENEMY_SCENE.instantiate()
	enemy.position = Vector3(0.0, 0.0, -5.0)
	root.add_child(enemy)
	await wait_physics_frames(1)
	player.focus.select(enemy)
	assert_true(frame.visible, "A Target shows the frame")
	assert_eq(frame.name_label.text, String(enemy.name))
	assert_eq(frame.health_bar.modulate, TargetFrame.HOSTILE_COLOR, "tinted red for an enemy")
	assert_almost_eq(frame.health_bar.value, enemy.health.max_health, 0.01)
	enemy.health.damage(20.0)
	assert_almost_eq(frame.health_bar.value, enemy.health.max_health - 20.0, 0.01, "and its health follows")
	assert_false(frame.targeting_label.visible, "It hunts nobody yet")
	enemy.aggro(player)
	assert_true(frame.targeting_label.visible)
	assert_true(frame.targeting_label.text.ends_with(String(player.name)), "Now it hunts the Player, and the frame says so")
	enemy.disposition = Focus.Disposition.NEUTRAL
	frame.refresh()
	assert_eq(frame.health_bar.modulate, TargetFrame.NEUTRAL_COLOR, "yellow for a neutral")
	player.focus.clear_selection()
	assert_false(frame.visible, "Cleared, hidden again")


func test_a_friend_is_green_and_a_body_without_health_shows_its_name_alone() -> void:
	var friend: Player = PLAYER_SCENE.instantiate()
	friend.name = "Ally"
	friend.position = Vector3(3.0, 0.0, 0.0)
	root.add_child(friend)
	var dummy: CharacterBody3D = CharacterBody3D.new()
	dummy.name = "Dummy"
	dummy.add_to_group("Focusable")
	root.add_child(dummy)
	await wait_physics_frames(1)
	player.focus.select(friend)
	assert_eq(frame.health_bar.modulate, TargetFrame.FRIENDLY_COLOR, "green for a friend")
	assert_true(frame.health_bar.visible)
	player.focus.select(dummy)
	assert_eq(frame.name_label.text, "Dummy")
	assert_false(frame.health_bar.visible, "No Health, no bar")
