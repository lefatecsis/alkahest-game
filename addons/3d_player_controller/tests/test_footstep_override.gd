extends GutTest

## Purpose: a surface can lend the Player its own steps (the snow addon's crunch), and then only those sound, not the
## ground's under them; without one, the ground's own steps play as before.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var player: Player


func before_each() -> void:
	player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)


func test_a_lent_step_plays_instead_of_the_ground_s() -> void:
	var crunch: AudioStreamWAV = AudioStreamWAV.new()
	player.footstep_override = crunch
	player.audio.play_footstep(null)
	assert_true(player.audio.sfx_footsteps_surface.playing, "The lent step plays")
	assert_eq(player.audio.sfx_footsteps_surface.stream, crunch)
	assert_false(player.audio.sfx_footsteps_stone.playing, "and the ground's own does not")


func test_without_one_the_ground_s_step_plays() -> void:
	player.footstep_override = null
	player.audio.play_footstep(null)
	assert_false(player.audio.sfx_footsteps_surface.playing)
	assert_true(player.audio.sfx_footsteps_stone.playing, "Bare ground sounds as stone")
