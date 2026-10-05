extends GutTest

## Purpose: To test loading and saving user settings in PlayerSettingsResource at user://settings.tres
## without leaving the test values in the developer's real settings file.

const AUDIO_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player_audio.tscn")
const AUDIO_SETTINGS_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/audio_settings.tscn")
const CONTROLS_SETTINGS_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/controls_settings.tscn")
const VIDEO_SETTINGS_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/video_settings.tscn")

var _backup: PackedByteArray
var _had_file: bool


func before_each() -> void:
	_had_file = FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH)
	if _had_file:
		_backup = FileAccess.get_file_as_bytes(PlayerSettingsResource.SAVE_PATH)
	PlayerSettingsResource._cached = null


func after_each() -> void:
	if _had_file:
		var file: FileAccess = FileAccess.open(PlayerSettingsResource.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_backup)
		file.close()
		ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
	else:
		DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
		if ResourceLoader.has_cached(PlayerSettingsResource.SAVE_PATH):
			var cached: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH)
			var defaults: PlayerSettingsResource = PlayerSettingsResource.new()
			for property: Dictionary in defaults.get_property_list():
				if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					cached.set(property.name, defaults.get(property.name))
	PlayerSettingsResource._cached = null


func test_save_and_load_settings_resource() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.new()
	settings.dialog_volume = 75.0
	settings.music_volume = 30.0
	settings.vsync_enabled = false
	settings.msaa_index = 2
	settings.save()

	assert_true(FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH), "Save file user://settings.tres should exist")

	var loaded: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	assert_eq(loaded.dialog_volume, 75.0, "Dialog volume should persist")
	assert_eq(loaded.music_volume, 30.0, "Music volume should persist")
	assert_eq(loaded.vsync_enabled, false, "VSync enabled should persist")
	assert_eq(loaded.msaa_index, 2, "MSAA index should persist")


func test_load_or_create_returns_one_shared_instance() -> void:
	assert_same(PlayerSettingsResource.load_or_create(), PlayerSettingsResource.load_or_create(), "Every menu should edit the same instance")


func test_menu_layer_show_hide_toggles_player_paused() -> void:
	var layer: PlayerMenuLayer = PlayerMenuLayer.new()
	add_child_autofree(layer)
	var player: Player = autofree(Player.new())
	layer.player = player

	layer.show_menu()
	assert_true(layer.visible, "show_menu should show the layer")
	assert_true(player.is_paused, "show_menu should pause the player")

	layer.hide_menu()
	assert_false(layer.visible, "hide_menu should hide the layer")
	assert_false(player.is_paused, "hide_menu should unpause the player")


func test_audio_slider_applies_bus_volume_and_saves_on_drag_ended() -> void:
	DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
	add_child_autofree(AUDIO_SCENE.instantiate()) # Creates the buses
	var audio_settings: PlayerMenuLayer = AUDIO_SETTINGS_SCENE.instantiate() as PlayerMenuLayer
	add_child_autofree(audio_settings)

	audio_settings.menu_slider.value = 20.0
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Menu")), linear_to_db(0.2), 0.001, "value_changed should apply the bus volume")
	assert_eq(audio_settings.settings_res.menu_volume, 20.0, "value_changed should update the resource")
	assert_false(FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH), "value_changed should not save to disk")

	audio_settings.menu_slider.drag_ended.emit(true)
	assert_true(FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH), "drag_ended should save to disk")
	PlayerSettingsResource.set_bus_volume(&"Menu", 50.0)


func test_fsr_and_ssaa_are_mutually_exclusive_and_round_trip() -> void:
	var video_settings: PlayerMenuLayer = VIDEO_SETTINGS_SCENE.instantiate() as PlayerMenuLayer
	add_child_autofree(video_settings)

	video_settings._on_ssaa_item_selected(2)
	video_settings._on_fsr_item_selected(1)
	assert_eq(video_settings.settings_res.ssaa_index, 0, "Selecting FSR should reset SSAA")
	assert_eq(video_settings.ssaa_button.selected, 0, "Selecting FSR should reset the SSAA control")

	var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.fsr_index, 1, "FSR index should persist")
	assert_eq(loaded.ssaa_index, 0, "SSAA index should persist as reset")

	video_settings._on_ssaa_item_selected(1)
	assert_eq(video_settings.settings_res.fsr_index, 0, "Selecting SSAA should reset FSR")
	assert_eq(video_settings.fsr_button.selected, 0, "Selecting SSAA should reset the FSR control")
	video_settings._on_ssaa_item_selected(0)


func test_the_on_screen_controls_mode_saves_from_the_controls_menu() -> void:
	var controls_settings: PlayerMenuLayer = CONTROLS_SETTINGS_SCENE.instantiate() as PlayerMenuLayer
	add_child_autofree(controls_settings)
	assert_eq(controls_settings.hud_button.selected, controls_settings.settings_res.hud_mode, "The row opens on what is saved")

	controls_settings.hud_button.selected = PlayerSettingsResource.HudMode.HIDDEN # as the signal path does
	controls_settings._on_on_screen_controls_item_selected(PlayerSettingsResource.HudMode.HIDDEN)
	var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.hud_mode, PlayerSettingsResource.HudMode.HIDDEN, "The pick is written to disk at once")

	controls_settings._on_on_screen_controls_touch_screen_button_pressed()
	assert_eq(controls_settings.hud_button.selected, PlayerSettingsResource.HudMode.AUTO, "The touch button steps round to the start")
	loaded = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.hud_mode, PlayerSettingsResource.HudMode.AUTO, "and that is saved too")


func test_voice_volume_and_mute_persist_and_apply() -> void:
	DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
	add_child_autofree(AUDIO_SCENE.instantiate()) # Creates the buses
	var voice_bus: int = AudioServer.get_bus_index(&"Voice")
	var audio_settings: PlayerMenuLayer = AUDIO_SETTINGS_SCENE.instantiate() as PlayerMenuLayer
	add_child_autofree(audio_settings)

	audio_settings.voice_slider.value = 20.0
	assert_almost_eq(AudioServer.get_bus_volume_db(voice_bus), linear_to_db(0.2), 0.001, "The Voice slider drives the Voice bus")
	assert_eq(audio_settings.settings_res.voice_volume, 20.0, "and the resource")
	audio_settings.mute_voice.button_pressed = true
	assert_true(AudioServer.is_bus_mute(voice_bus), "The toggle mutes the Voice bus on this machine")
	assert_true(audio_settings.settings_res.voice_muted, "and the resource")
	assert_true(FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH), "A toggle saves at once")

	var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.voice_volume, 20.0, "Voice volume persists")
	assert_true(loaded.voice_muted, "Voice mute persists")

	AudioServer.set_bus_mute(voice_bus, false)
	PlayerSettingsResource.set_bus_volume(&"Voice", 100.0)
	loaded.apply_audio_settings()
	assert_true(AudioServer.is_bus_mute(voice_bus), "Startup applies the mute with the other volumes")
	assert_almost_eq(AudioServer.get_bus_volume_db(voice_bus), linear_to_db(0.2), 0.001, "and the Voice volume")
	AudioServer.set_bus_mute(voice_bus, false)
	PlayerSettingsResource.set_bus_volume(&"Voice", 50.0)


func test_chat_rect_persists() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.new()
	assert_eq(settings.chat_rect, Rect2(), "A zero rect means the chat picks its default bottom-left spot")
	settings.chat_rect = Rect2(40.0, 50.0, 300.0, 150.0)
	settings.save()
	var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.chat_rect, Rect2(40.0, 50.0, 300.0, 150.0), "The chat window's rect persists")


func test_toon_mode_persists() -> void:
	var settings: PlayerSettingsResource = PlayerSettingsResource.new()
	assert_eq(settings.toon_mode, 0, "Toon shading is off by default")
	settings.toon_mode = 2
	settings.save()
	var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.toon_mode, 2, "The toon mode persists")


func test_an_old_toon_enabled_setting_migrates_to_newspaper() -> void:
	var script_path: String = (PlayerSettingsResource.new().get_script() as Script).resource_path
	for old_value: Array in [[true, PlayerSettingsResource.TOON_NEWSPAPER], [false, 0]]:
		var file: FileAccess = FileAccess.open(PlayerSettingsResource.SAVE_PATH, FileAccess.WRITE)
		file.store_string('[gd_resource type="Resource" script_class="PlayerSettingsResource" load_steps=2 format=3]\n\n'
			+ '[ext_resource type="Script" path="%s" id="1"]\n\n[resource]\nscript = ExtResource("1")\nmsaa_index = 2\ntoon_enabled = %s\n' % [script_path, str(old_value[0]).to_lower()])
		file.close()
		var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_eq(loaded.toon_mode, old_value[1], "toon_enabled = %s from before toon_mode loads as mode %d" % [old_value[0], old_value[1]])
		assert_eq(loaded.msaa_index, 2, "and the rest of the file still loads")
		assert_false("toon_enabled" in loaded, "The old property is gone")


## Dragging the microphone bar is many small steps: each keeps the value, and the file is written once, when the
## menu closes, rather than on every step (on the web every write goes to IndexedDB).
func test_the_microphone_bar_saves_when_the_menu_closes_not_on_every_step() -> void:
	DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
	var audio_settings: PlayerMenuLayer = AUDIO_SETTINGS_SCENE.instantiate() as PlayerMenuLayer
	add_child_autofree(audio_settings)
	audio_settings.show_menu()

	audio_settings.mic_sensitivity.value = 60.0
	assert_eq(audio_settings.settings_res.voice_sensitivity, 60.0, "The step is kept")
	assert_false(FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH), "but nothing is written yet")

	audio_settings.hide_menu()
	assert_true(FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH), "Closing the menu writes it")
	var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.voice_sensitivity, 60.0)


## The settings path is a static var, so a test run can point it at a folder of its own and never touch the
## player's real settings.
func test_the_settings_path_can_be_redirected() -> void:
	var was: String = PlayerSettingsResource.SAVE_PATH
	PlayerSettingsResource.SAVE_PATH = "user://test_redirected_settings.tres"
	var settings: PlayerSettingsResource = PlayerSettingsResource.new()
	settings.music_volume = 12.0
	settings.save()
	assert_true(FileAccess.file_exists("user://test_redirected_settings.tres"), "The file goes where the path points")
	DirAccess.remove_absolute("user://test_redirected_settings.tres")
	PlayerSettingsResource.SAVE_PATH = was


## Rotate Minimap: shown only while the game has a node in the minimap group (the minimap addon's is), handed to
## every such node as rotate_with_target, and kept with the other video settings.
func test_the_rotate_minimap_toggle_reaches_the_minimap_and_persists() -> void:
	var video_settings: PlayerMenuLayer = VIDEO_SETTINGS_SCENE.instantiate() as PlayerMenuLayer
	add_child_autofree(video_settings)
	video_settings.show_menu()
	assert_false(video_settings.rotate_minimap_button.visible, "No minimap in the game, no toggle")
	video_settings.hide_menu()
	var minimap := Node.new()
	var script := GDScript.new()
	script.source_code = "extends Node\nvar rotate_with_target: bool = false\n"
	script.reload()
	minimap.set_script(script)
	minimap.add_to_group(PlayerSettingsResource.MINIMAP_GROUP)
	add_child_autofree(minimap)
	video_settings.show_menu()
	assert_true(video_settings.rotate_minimap_button.visible, "With one, the toggle is offered")
	video_settings._on_rotate_minimap_toggled(true)
	assert_true(minimap.get("rotate_with_target"), "and turning it on turns the minimap with the Player")
	video_settings.hide_menu()
	var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(loaded.rotate_minimap, "The choice is saved")
	minimap.set("rotate_with_target", false)
	PlayerSettingsResource.load_or_create().apply_video_settings(get_viewport())
	assert_true(minimap.get("rotate_with_target"), "and applied again with the other video settings, as a game starts")
