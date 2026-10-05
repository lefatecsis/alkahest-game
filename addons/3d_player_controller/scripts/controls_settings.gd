extends PlayerMenuLayer
## The Controls page of the settings menu: whether the on-screen controls are drawn, and which game's pad layout
## the Player answers to. Both are saved to [PlayerSettingsResource] on this machine and take effect at once.

@onready var hud_button: OptionButton = $Panel/VBoxContainer/OnScreenControls ## Items are [enum PlayerSettingsResource.HudMode] in order.
@onready var scheme_button: OptionButton = $Panel/VBoxContainer/ControlScheme ## [constant PlayerControls.BUILT_IN_SCHEMES] then the registered layouts, in order; filled by [method _fill_scheme_button].

var settings_res: PlayerSettingsResource


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	settings_res = PlayerSettingsResource.load_or_create()
	hud_button.selected = clampi(settings_res.hud_mode, 0, hud_button.item_count - 1)
	_fill_scheme_button()


func _on_on_screen_controls_item_selected(index: int) -> void:
	settings_res.hud_mode = index
	if player:
		player.apply_hud_visibility()
	settings_res.save()


func _on_on_screen_controls_touch_screen_button_pressed() -> void:
	hud_button.selected = (hud_button.selected + 1) % hud_button.item_count
	_on_on_screen_controls_item_selected(hud_button.selected)


## The scheme goes straight on the Player, so the pad is laid out the new way as soon as the menu closes.
## Names the layouts from the scheme resources themselves rather than from items typed into the scene, so a
## game or another addon that registers a [ControlScheme] gets it listed without touching this menu. The pick
## is saved by name, so a layout registering late cannot change what an already saved choice means.
##
## There is no "Default" entry. It said the same thing as Zelda for anyone who had not changed it, which only
## made the menu harder to read; the layout a Player starts with is [constant PlayerControls.DEFAULT_SCHEME],
## and the menu simply shows whichever layout is on.
func _fill_scheme_button() -> void:
	scheme_button.clear()
	var wanted: String = settings_res.control_scheme_name
	if wanted.is_empty() and player and player.control_scheme:
		wanted = player.control_scheme.scheme_name # nothing saved: show what the Player is actually using
	var picked: int = 0
	var offered: Array[ControlScheme] = PlayerControls.schemes()
	for at: int in offered.size():
		scheme_button.add_item(offered[at].scheme_name, at)
		if offered[at].scheme_name == wanted:
			picked = at
	scheme_button.selected = picked


func _on_control_scheme_item_selected(index: int) -> void:
	var offered: Array[ControlScheme] = PlayerControls.schemes()
	settings_res.control_scheme_name = offered[index].scheme_name if index >= 0 and index < offered.size() else ""
	settings_res.apply_control_scheme(player)
	settings_res.save()


func _on_control_scheme_touch_screen_button_pressed() -> void:
	scheme_button.selected = (scheme_button.selected + 1) % scheme_button.item_count
	_on_control_scheme_item_selected(scheme_button.selected)


## Return to main settings menu.
func _on_back_pressed() -> void:
	if player == null:
		return
	hide()
	player.settings.show_menu()


func _on_back_touch_screen_button_pressed() -> void:
	_on_back_pressed()
