class_name PlayerMenuLayer
extends CanvasLayer
## Base for the pause, settings and lobby menus: pauses the [Player] while shown and closes on the "start" action.
##
## A menu with [member pauses_world] on (the pause menu, the catch screen) also pauses the whole scene tree while it
## is up, but only when the Player plays alone ([method is_single_player]): with no network peer, or hosting a session
## nobody has joined. A peer arriving meanwhile resumes the tree so the newcomer's world runs; a session still
## connecting (the Steam lobby being created) never pauses; a client never pauses the world. A menu opened from a
## paused one (the inventory from Pause) keeps the pause until it closes: [method hide_menu] always resumes the tree,
## and so does the menu leaving it. Menus keep processing while the tree is paused.
##
## Pausing the tree stops nodes, not the engine clock: a shader's [code]TIME[/code], GPU particles and tweens all run
## on [member Engine.time_scale], so fire, water and wind would keep moving behind the menu. A menu that pauses the
## tree therefore also sets the time scale to zero ([method freeze_time]) and puts it back on resume
## ([method thaw_time]); while it is frozen every [code]delta[/code] is zero, so a menu that animates itself (the catch
## screen's turning fish) keeps its own wall clock.

@export var player: Player
@export var focus_on_show: Control ## Control that receives focus when the menu opens.
@export var pauses_world: bool = false ## Pause the scene tree while this menu is up, in single player.

var _paused_world: bool = false ## This menu paused the tree and has not resumed it yet.

static var _time_scale_before_freeze: float = -1.0 ## [member Engine.time_scale] before a menu froze it, or -1 while none has.


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(is_multiplayer_authority())
	fit_touch_buttons(self)
	multiplayer.peer_connected.connect(_on_peer_connected)


## Sizes every [TouchScreenButton] under [param root] to the [Control] it sits on, now and whenever that control is
## laid out again, so a button a container stretches keeps a touch target to match.
static func fit_touch_buttons(root: Node) -> void:
	for found: Node in root.find_children("*", "TouchScreenButton", true, false):
		var touch: TouchScreenButton = found as TouchScreenButton
		var host: Control = touch.get_parent() as Control
		if host == null or not (touch.shape is RectangleShape2D):
			continue
		touch.shape = touch.shape.duplicate() # A scene shares one shape between its buttons
		_fit_touch_button(touch, host)
		host.resized.connect(_fit_touch_button.bind(touch, host))


static func _fit_touch_button(touch: TouchScreenButton, host: Control) -> void:
	(touch.shape as RectangleShape2D).size = host.size
	touch.position = host.size * 0.5


## The tree can be resumed behind the menu's back (a test, a scene change setting `paused` itself): the clock
## must never stay frozen while the tree runs, so a menu that held it lets go the moment it sees that.
func _process(_delta: float) -> void:
	if _paused_world and is_inside_tree() and not get_tree().paused:
		resume_world()


## Called when there is an input event. A scene with no Player (a title screen showing the settings pages) may
## not have registered the action at all.
func _input(event: InputEvent) -> void:
	if visible and InputMap.has_action(&"start") and event.is_action_pressed(&"start"):
		hide_menu()
		get_viewport().set_input_as_handled()


func show_menu() -> void:
	show()
	if player:
		player.is_paused = true
	if pauses_world and is_single_player():
		get_tree().paused = true
		_paused_world = true
		freeze_time()
	if player == null or player.uses_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if focus_on_show:
		focus_on_show.grab_focus()


func hide_menu() -> void:
	hide()
	if player:
		player.is_paused = false
	resume_world()
	# Captured, or visible under a scheme that frees it; with no Player (a title screen) the cursor stays as it is
	if player and player.uses_mouse:
		Input.mouse_mode = player.cursor_mode()


## Runs the scene tree again, whichever menu paused it.
func resume_world() -> void:
	_paused_world = false
	if is_inside_tree():
		get_tree().paused = false
	thaw_time()


## Stops the engine clock, so shaders, particles and tweens stand as still as the paused tree. The first freeze
## remembers the scale in force (a slow-motion effect, say) and nothing changes until [method thaw_time].
static func freeze_time() -> void:
	if _time_scale_before_freeze < 0.0:
		_time_scale_before_freeze = Engine.time_scale
		Engine.time_scale = 0.0


## Puts the engine clock back to what it was before [method freeze_time]; does nothing when it is not frozen.
static func thaw_time() -> void:
	if _time_scale_before_freeze >= 0.0:
		Engine.time_scale = _time_scale_before_freeze
		_time_scale_before_freeze = -1.0


## A menu freed while it holds the world still (the Player despawning, a scene change) lets it go.
func _exit_tree() -> void:
	if _paused_world:
		resume_world()


## True when this peer plays alone: no network peer at all (Steam not loaded, a web build), or a hosted session
## that is connected with nobody else in it. A peer still connecting is not alone yet, and neither is a client.
func is_single_player() -> bool:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return true
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return multiplayer.is_server() and multiplayer.get_peers().is_empty()


## Someone joined the session: a paused world would stand still for them, so it runs again with the menu still up.
func _on_peer_connected(_peer_id: int) -> void:
	if visible and get_tree().paused:
		resume_world()
