extends PlayerMenuLayer

@export_file("*.tscn") var inventory_screen_scene: String = "" ## An InventoryScreen scene; when set, the Inventory button shows and opens it.
@export_file("*.tscn") var spells_screen_scene: String = "" ## A SpellsScreen scene; when set, the Spells button shows and opens it.
@export_file("*.tscn") var quests_screen_scene: String = "res://addons/3d_player_controller/scenes/ui/quest_screen.tscn" ## A QuestScreen scene; when set, the Quests button shows and opens it.
@export_file("*.tscn") var extra_screen_scene: String = "" ## Any PlayerMenuLayer scene of the game's (a journal, a fish index); when set, the Extra button shows and opens it.
@export var extra_screen_label: String = "Journal" ## What the Extra button says.

var inventory_screen: PlayerMenuLayer ## The instanced inventory screen, a sibling of this menu on the Player.
var spells_screen: PlayerMenuLayer ## The instanced spells screen, a sibling of this menu on the Player.
var quests_screen: PlayerMenuLayer ## The instanced quests screen, a sibling of this menu on the Player.
var extra_screen: PlayerMenuLayer ## The instanced extra screen, a sibling of this menu on the Player.

@onready var lobby: Button = $Panel/VBoxContainer/Lobby
@onready var inventory_button: Button = $Panel/VBoxContainer/Inventory
@onready var spells_button: Button = $Panel/VBoxContainer/Spells
@onready var quests_button: Button = $Panel/VBoxContainer/Quests
@onready var extra_button: Button = $Panel/VBoxContainer/Extra
@onready var restart_button: Button = $Panel/VBoxContainer/Restart ## Shown only while playing alone: reloading the scene would break a session.
@onready var save_button: Button = $Panel/VBoxContainer/Save ## Shown while a [SaveGame] is in the scene.
@onready var load_button: Button = $Panel/VBoxContainer/Load ## Shown with Save, enabled while its file exists.


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	var rendering_method: String = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	var lobby_unavailable: bool = rendering_method not in ["forward_plus", "mobile"] \
		or OS.has_feature("gl_compatibility") \
		or OS.has_feature("web") \
		or not Engine.has_singleton("Steam")
	lobby.disabled = lobby_unavailable
	inventory_screen = _instance_screen(inventory_screen_scene, inventory_button)
	spells_screen = _instance_screen(spells_screen_scene, spells_button)
	quests_screen = _instance_screen(quests_screen_scene, quests_button)
	extra_button.text = extra_screen_label
	extra_screen = _instance_screen(extra_screen_scene, extra_button)
	# The Player is still readying its children here, so the screens join it on its own ready signal, in the same
	# frame; a deferred add would be dropped, and the screens left orphaned, for a Player freed before the frame ends
	if player and not player.is_node_ready():
		player.ready.connect(_add_screens, CONNECT_ONE_SHOT)
	elif player:
		_add_screens.call_deferred()


## Instances a menu scene for this menu's Player and shows its button; an empty or bad path hides the button.
func _instance_screen(scene_path: String, button: Button) -> PlayerMenuLayer:
	button.visible = not scene_path.is_empty()
	if not button.visible or player == null or not is_multiplayer_authority():
		return null
	var scene: PackedScene = load(scene_path) as PackedScene
	var screen: PlayerMenuLayer = scene.instantiate() as PlayerMenuLayer if scene else null
	if screen == null:
		button.hide()
		return null
	screen.player = player
	screen.hide() # a screen's own scene saves visible, so it can be seen in the editor; whoever adds it hides it
	return screen


## Puts the instanced screens on the Player, beside this menu.
func _add_screens() -> void:
	for screen: PlayerMenuLayer in [inventory_screen, spells_screen, quests_screen, extra_screen]:
		if screen:
			player.add_child(screen)


## The Spells button only makes sense with a [Spellbook] under the Inventory; decided here, once the Player's
## own ready has filled its inventory node.
func show_menu() -> void:
	# Before the menu is drawn: the frame on screen is the game, which is what a save's preview should be.
	var saving: SaveGame = SaveGame.find_in(get_tree())
	if saving:
		saving.capture_preview()
	super()
	if spells_screen and player and player.inventory and player.inventory.spellbook == null:
		spells_button.hide()
	if quests_screen and player and player.quest_log == null:
		quests_button.hide()
	restart_button.visible = is_single_player()
	var saver: SaveGame = SaveGame.find_in(get_tree())
	save_button.visible = saver != null
	load_button.visible = saver != null
	load_button.disabled = saver == null or not saver.has_save()


## Called when there is an input event; "start" toggles the pause menu. A scene with no Player (a title screen)
## may not have registered the action at all.
func _input(event: InputEvent) -> void:
	if not InputMap.has_action(&"start") or not event.is_action_pressed(&"start"):
		return
	if visible:
		hide_menu()
	elif player and not player.is_paused:
		show_menu()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_lobby_pressed() -> void:
	if player == null or lobby.disabled or player.lobby_manager == null:
		return
	hide()
	player.lobby_manager.show_menu()


func _on_lobby_touch_screen_button_pressed() -> void:
	_on_lobby_pressed()


func _on_resume_pressed() -> void:
	hide_menu()


func _on_resume_touch_screen_button_pressed() -> void:
	_on_resume_pressed()


func _on_inventory_pressed() -> void:
	if inventory_screen == null:
		return
	hide()
	inventory_screen.show_menu()


func _on_inventory_touch_screen_button_pressed() -> void:
	_on_inventory_pressed()


func _on_spells_pressed() -> void:
	if spells_screen == null:
		return
	hide()
	spells_screen.show_menu()


func _on_quests_pressed() -> void:
	if quests_screen == null:
		return
	hide()
	quests_screen.show_menu()


func _on_quests_touch_screen_button_pressed() -> void:
	_on_quests_pressed()


func _on_extra_pressed() -> void:
	if extra_screen == null:
		return
	hide()
	extra_screen.show_menu()


func _on_extra_touch_screen_button_pressed() -> void:
	_on_extra_pressed()


func _on_spells_touch_screen_button_pressed() -> void:
	_on_spells_pressed()


## Reloads the scene, which only a Player alone can do: in a session it would leave a client with no Player and a
## host with none of the clients'.
func _on_restart_pressed() -> void:
	if not is_single_player():
		return
	resume_world()
	get_tree().reload_current_scene()


func _on_restart_touch_screen_button_pressed() -> void:
	_on_restart_pressed()


func _on_settings_pressed() -> void:
	if player == null:
		return
	hide()
	player.settings.show_menu()


func _on_settings_touch_screen_button_pressed() -> void:
	_on_settings_pressed()


func _on_save_pressed() -> void:
	var saver: SaveGame = SaveGame.find_in(get_tree())
	if saver == null:
		return
	saver.save_game()
	hide_menu()


func _on_save_touch_screen_button_pressed() -> void:
	_on_save_pressed()


func _on_load_pressed() -> void:
	var saver: SaveGame = SaveGame.find_in(get_tree())
	if saver == null or not saver.has_save():
		return
	hide_menu()
	saver.load_game()


func _on_load_touch_screen_button_pressed() -> void:
	_on_load_pressed()


## Back to the last checkpoint, or the spawn point before one is taken.
func _on_unstuck_pressed() -> void:
	if player == null:
		return
	player.warp_to(player.respawn_transform)


func _on_unstuck_touch_screen_button_pressed() -> void:
	_on_unstuck_pressed()


## Save and quit, Minecraft style: where there is a SaveGame the game is written, preview and all, before it closes.
func _on_quit_pressed() -> void:
	var saver: SaveGame = SaveGame.find_in(get_tree())
	if saver and is_single_player():
		saver.save_game()
	get_tree().quit()


func _on_quit_touch_screen_button_pressed() -> void:
	_on_quit_pressed()
