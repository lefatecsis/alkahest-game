extends GutTest

## Purpose: the microphone row in Audio settings. One bar that is both the meter and the setting: the handle is
## the sensitivity, the fill behind it is what the microphone is hearing, and the sensitivity it saves is what
## the Player measures voice against.

const SETTINGS_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/audio_settings.tscn")
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")


func _slider() -> VoiceLevelSlider:
	var slider: VoiceLevelSlider = VoiceLevelSlider.new()
	slider.min_value = 10.0
	slider.max_value = 150.0
	slider.value = 100.0
	slider.size = Vector2(200.0, 40.0)
	add_child_autofree(slider)
	return slider


func test_the_handle_spans_the_whole_range() -> void:
	var slider: VoiceLevelSlider = _slider()

	slider.value = slider.min_value
	assert_almost_eq(slider.ratio, 0.0, 0.001, "At the bottom the handle is hard left")
	slider.value = slider.max_value
	assert_almost_eq(slider.ratio, 1.0, 0.001, "and at the top hard right")


func test_the_level_is_held_between_nothing_and_full() -> void:
	var slider: VoiceLevelSlider = _slider()

	slider.level = 2.5
	assert_almost_eq(slider.level, 1.0, 0.001, "A reading past the top fills the bar and no more")
	slider.level = -1.0
	assert_almost_eq(slider.level, 0.0, 0.001, "and one below the bottom empties it")


func test_the_level_is_separate_from_the_setting() -> void:
	var slider: VoiceLevelSlider = _slider()
	slider.value = 60.0

	slider.level = 0.9

	assert_almost_eq(slider.value, 60.0, 0.001, "Talking does not move the handle; the bar is the meter, the handle is the choice")


func test_dragging_the_bar_sets_the_sensitivity() -> void:
	var slider: VoiceLevelSlider = _slider()
	await wait_process_frames(1)

	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(slider.size.x * 0.5, 20.0)
	slider._gui_input(press)

	assert_almost_eq(slider.ratio, 0.5, 0.02, "Clicking halfway along puts the handle halfway along")


## A quieter microphone needs fewer bytes to mean the same thing, so turning the sensitivity up lowers the bar
## the Player measures against. That is the whole point of the row: the number stops being a guess.
func test_the_sensitivity_moves_what_counts_as_a_full_voice() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	var was: float = settings.voice_sensitivity

	settings.voice_sensitivity = 100.0
	var normal: float = player.voice_chat.voice_full_bytes()
	settings.voice_sensitivity = 150.0
	var sensitive: float = player.voice_chat.voice_full_bytes()
	settings.voice_sensitivity = 50.0
	var deaf: float = player.voice_chat.voice_full_bytes()

	assert_lt(sensitive, normal, "More sensitive means less voice is needed to read as talking")
	assert_gt(deaf, normal, "and less sensitive means more")
	assert_gt(VoiceChat.loudness_of(500, sensitive), VoiceChat.loudness_of(500, deaf),
		"so the same packet reads louder on the sensitive setting")
	settings.voice_sensitivity = was
	settings.save()


func test_the_menu_shows_the_row_and_keeps_what_was_set() -> void:
	var menu: Node = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	await wait_process_frames(1)

	assert_not_null(menu.mic_sensitivity, "Audio settings carries the microphone row")
	assert_almost_eq(menu.mic_sensitivity.value, PlayerSettingsResource.load_or_create().voice_sensitivity, 0.001,
		"and opens on the sensitivity already saved")


## The handle, the mark and where the colours turn all have to agree. They only do if each measures from
## min_value rather than from zero, which they did not at first: with a minimum of 10 the mark sat at 100/150
## while the handle sat at (100-10)/140, and the two drifted apart.
func test_the_mark_and_the_handle_measure_the_same_way() -> void:
	var slider: VoiceLevelSlider = _slider()
	slider.normal_value = 100.0

	slider.value = 100.0

	assert_almost_eq(slider.ratio_of(slider.normal_value), slider.ratio, 0.001,
		"The handle set to the normal value lands exactly on the mark")


func test_the_ends_of_the_bar_are_the_ends_of_the_range() -> void:
	var slider: VoiceLevelSlider = _slider()

	assert_almost_eq(slider.ratio_of(slider.min_value), 0.0, 0.001, "The bottom of the range is the left edge")
	assert_almost_eq(slider.ratio_of(slider.max_value), 1.0, 0.001, "and the top is the right edge")
	assert_almost_eq(slider.ratio_of(-500.0), 0.0, 0.001, "with anything past the ends held there")
	assert_almost_eq(slider.ratio_of(9999.0), 1.0, 0.001)


## The row says which key to hold, and says it from the InputMap rather than from a string somebody typed, so
## rebinding push-to-talk changes the instruction instead of leaving it lying about the old key.
func test_the_row_names_the_key_push_to_talk_is_actually_bound_to() -> void:
	var menu: Node = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	await wait_process_frames(1)

	var had: bool = InputMap.has_action(&"broadcast")
	if not had:
		InputMap.add_action(&"broadcast")
	var was: Array[InputEvent] = InputMap.action_get_events(&"broadcast")
	InputMap.action_erase_events(&"broadcast")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_B
	InputMap.action_add_event(&"broadcast", key)

	assert_eq(menu.talk_key_name(), "B", "It reads the binding as it stands")
	assert_true(menu.microphone_hint().contains("B"), "and the tip names that key")
	assert_true(menu.microphone_label_text().contains("B"), "as does the label")

	InputMap.action_erase_events(&"broadcast")
	for event: InputEvent in was:
		InputMap.action_add_event(&"broadcast", event)
	if not had:
		InputMap.erase_action(&"broadcast")


## Voice chat is keyboard-only here, and a project could unbind it entirely. The row should still make sense.
func test_the_row_copes_with_push_to_talk_being_unbound() -> void:
	var menu: Node = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	await wait_process_frames(1)

	var had: bool = InputMap.has_action(&"broadcast")
	var was: Array[InputEvent] = InputMap.action_get_events(&"broadcast") if had else ([] as Array[InputEvent])
	if had:
		InputMap.action_erase_events(&"broadcast")

	assert_eq(menu.talk_key_name(), "", "With nothing bound there is no key to name")
	assert_true(menu.microphone_hint().contains("push-to-talk"), "so the tip says what to press in words")
	assert_eq(menu.microphone_label_text(), "Microphone", "and the label drops the key rather than reading half a sentence")

	for event: InputEvent in was:
		InputMap.action_add_event(&"broadcast", event)


## The Zelda layout binds every usable button, so a pad player cannot hold push-to-talk at all. Voice
## activation is how they talk: speaking past the mark opens the channel and falling under it closes it.
func test_voice_activation_transmits_by_speaking() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	var was: bool = settings.voice_activation
	settings.voice_activation = true

	assert_true(player.voice_chat.voice_activation_enabled(), "The Player reads the setting")
	# The frame is driven by hand with no time passing: with no voice packet arriving the reading falls away at
	# VOICE_FALLOFF_PER_SECOND, and a slow CI frame would drop it under the mark before the check
	player.voice_chat.voice_loudness = VoiceChat.VOICE_ACTIVATION_LEVEL + 0.1
	player.voice_chat._process(0.0)
	assert_true(player.voice_chat.is_broadcasting, "Speaking past the mark opens the channel")

	player.voice_chat.voice_loudness = 0.0
	player.voice_chat._process(0.0)
	assert_false(player.voice_chat.is_broadcasting, "and going quiet closes it again")

	settings.voice_activation = was
	settings.save()


## The mark on the bar and the level that counts as speaking have to be the same thing, or the instruction
## "drag until an ordinary voice reaches the mark" sets the wrong threshold.
func test_the_mark_is_the_level_that_transmits() -> void:
	var menu: Node = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	await wait_process_frames(1)
	var bar: VoiceLevelSlider = menu.mic_sensitivity

	assert_almost_eq(bar.ratio_of(bar.normal_value), VoiceChat.VOICE_ACTIVATION_LEVEL, 0.001,
		"The mark sits exactly where speaking starts transmitting")


## The colours turn at the mark too. The mark's value is set in the scene, before the bar builds its gradient on
## ready; set afterwards from the menu's code, the turn sat four percent right of the mark.
func test_the_colours_turn_at_the_mark() -> void:
	var menu: Node = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	var bar: VoiceLevelSlider = menu.mic_sensitivity

	assert_eq(bar.normal_value, 94.0, "The mark is set in audio_settings.tscn")
	assert_almost_eq(bar._gradient.gradient.offsets[2], bar.ratio_of(bar.normal_value), 0.001,
		"and the gradient turns from green to yellow exactly there")


## Holding the key still works with voice activation on, for a player who would rather not trust the meter.
func test_the_key_still_works_with_voice_activation_on() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	var was: bool = settings.voice_activation
	settings.voice_activation = true

	player.voice_chat.start_broadcasting()
	assert_true(player.voice_chat.is_broadcasting, "The key opens the channel whatever the meter says")
	player.voice_chat.stop_broadcasting()
	assert_false(player.voice_chat.is_broadcasting, "and closes it")

	settings.voice_activation = was
	settings.save()


## With voice activation on there is no key to hold, so the row stops telling you to hold one.
func test_the_row_stops_naming_a_key_when_there_is_none_to_hold() -> void:
	var menu: Node = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	await wait_process_frames(1)
	var was: bool = menu.settings_res.voice_activation

	menu.settings_res.voice_activation = true
	assert_false(menu.microphone_label_text().contains("hold"), "Nothing to hold, so nothing about holding")
	assert_true(menu.microphone_hint().contains("Speaking past the mark"), "and the tip says what actually transmits")

	menu.settings_res.voice_activation = false
	assert_true(menu.microphone_hint().contains("Hold"), "Back on the key, the tip says to hold it")

	menu.settings_res.voice_activation = was


## Push-to-talk is the default, and voice activation is opted into. An open microphone is not something to
## hand somebody without asking: it transmits the room until they find the toggle and turn it off.
func test_voice_activation_is_off_until_it_is_asked_for() -> void:
	var fresh: PlayerSettingsResource = PlayerSettingsResource.new()

	assert_false(fresh.voice_activation, "A profile that has never been touched holds the key to talk")
