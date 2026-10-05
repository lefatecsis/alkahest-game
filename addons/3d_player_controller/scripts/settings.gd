extends PlayerMenuLayer


func _on_audio_pressed() -> void:
	if player == null:
		return
	hide()
	player.audio_settings.show_menu()


func _on_audio_touch_screen_button_pressed() -> void:
	_on_audio_pressed()


func _on_controls_pressed() -> void:
	if player == null:
		return
	hide()
	player.controls_settings.show_menu()


func _on_controls_touch_screen_button_pressed() -> void:
	_on_controls_pressed()


func _on_video_pressed() -> void:
	if player == null:
		return
	hide()
	player.video_settings.show_menu()


func _on_video_touch_screen_button_pressed() -> void:
	_on_video_pressed()


## Return to the pause menu.
func _on_back_pressed() -> void:
	if player == null:
		return
	hide()
	player.pause.show_menu()


func _on_back_touch_screen_button_pressed() -> void:
	_on_back_pressed()
