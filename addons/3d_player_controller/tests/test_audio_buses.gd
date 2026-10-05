extends GutTest

## Purpose: The settings menus adjust the Dialog/Menu/Music/SFX buses, so the Audio node must create them when the project's bus layout lacks them.

const AUDIO_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player_audio.tscn")


func test_audio_node_creates_missing_buses_and_footsteps_use_sfx() -> void:
	var audio: Audio = AUDIO_SCENE.instantiate() as Audio
	add_child_autofree(audio)
	for bus_name: StringName in Audio.BUSES:
		assert_ne(AudioServer.get_bus_index(bus_name), -1, "Bus %s should exist" % bus_name)
	assert_eq(audio.sfx_footsteps_grass.bus, &"SFX", "Footstep players should play on the SFX bus")


func test_set_bus_volume_changes_bus_db() -> void:
	add_child_autofree(AUDIO_SCENE.instantiate())
	PlayerSettingsResource.set_bus_volume(&"SFX", 50.0)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")), linear_to_db(0.5), 0.001)
	PlayerSettingsResource.set_bus_volume(&"SFX", 100.0)
