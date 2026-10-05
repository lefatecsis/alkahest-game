class_name ChatWindow
extends Window
## World of Warcraft style chat: a floating, movable and resizable embedded [Window] that starts bottom-left,
## fades when idle and remembers its rect in [PlayerSettingsResource].
##
## Messages travel by RPC through the Godot multiplayer API, so ENet and the SteamMultiplayerPeer both carry
## them. Every peer holds a copy of the sender's Player, and this node with it, so [method _receive_message]
## runs on that copy and relays to the one chat this peer owns. Lines starting with "/" are local commands
## and are never sent. The window stays [member Window.unfocusable] except while the input row is open, so a
## click or scroll on the history never takes the keyboard away from the game.

signal typing_changed(is_typing: bool) ## The input row opened (true) or closed (false); the Player gates gameplay input on it.

const DEFAULT_SIZE: Vector2i = Vector2i(420, 220)
const SCREEN_MARGIN: int = 16
const MAX_MESSAGE_LENGTH: int = 500 ## Longer messages from a peer are cut here.

@export var player: Player
@export var idle_seconds: float = 8.0 ## Seconds without a new message before the window fades.
@export var idle_alpha: float = 0.0 ## Alpha the window fades to when idle; it still catches the mouse.
## Show the window in full on load. Off by default: a chat box is not wanted on screen in a single
## player scene until something is actually said. Off does not mean gone. The window stays in the tree
## drawn at [member idle_alpha], because an embedded [Window] that is hidden outright receives no mouse
## events at all, and hovering where the chat sits is one of the three ways it is asked back:
## [method open_input] from the chat action, a message arriving, or the pointer going there.
## A project that wants no chat at all hides the node itself in its own scene.
@export var start_visible: bool = false
@export var fade_seconds: float = 1.0 ## How long the fade out takes.
@export var fade_in_seconds: float = 0.2 ## How long coming back takes.
@export var name_color: Color = Color(1.0, 0.82, 0.3) ## Sender names in the history.
@export var system_color: Color = Color(0.75, 0.75, 0.75) ## Local command output in the history.

@onready var content: Control = $Content ## Everything visible; its modulate is what fades.
@onready var history: RichTextLabel = $Content/Frame/VBox/History
@onready var input_row: HBoxContainer = $Content/Frame/VBox/InputRow
@onready var input: LineEdit = $Content/Frame/VBox/InputRow/Input
@onready var idle_timer: Timer = $IdleTimer
@onready var save_timer: Timer = $SaveTimer

## Commands typed as "/name args": name -> [Callable(args: PackedStringArray), help line]. Adding one is one line.
@onready var commands: Dictionary[String, Array] = {
	"help": [_command_help, "/help: lists the commands"],
	"teleport": [_command_teleport, "/teleport x y z: moves you to that position"],
	"whereami": [_command_whereami, "/whereami: says where you stand"],
	"heal": [_command_heal, "/heal: full health"],
	"respawn": [_command_respawn, "/respawn: back to the last checkpoint"],
	"clear": [_command_clear, "/clear: empties the history"],
}

## Commands a game adds without editing this file: name -> [callable, help line]. Register them before any chat is
## ready, the way [method PlayerControls.register_scheme] is called from a game's root node in [method Node._enter_tree];
## each joins [member commands] on ready with this chat bound as the callable's last argument, so a game command reads
## [code]func level(args: PackedStringArray, chat: ChatWindow)[/code] and answers through [method append_system].
static var _registered: Dictionary[String, Array] = {}

var settings_res: PlayerSettingsResource
var is_hovered: bool = false ## The mouse is over the window, which keeps it visible so the history can be scrolled.
var _fade_tween: Tween
var _visible_before_pause: bool = false ## What the window was before a menu opened, for [method _on_player_paused_changed].


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if player == null and get_parent() is Player:
		player = get_parent() as Player
	for command_name: String in _registered:
		commands[command_name] = [(_registered[command_name][0] as Callable).bind(self), _registered[command_name][1]]
	# A remote Player's copy only relays RPCs; it never shows
	if not is_multiplayer_authority():
		return
	idle_timer.wait_time = idle_seconds
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	var rect: Rect2 = settings.chat_rect
	if rect.size == Vector2.ZERO:
		var screen: Vector2 = get_parent().get_viewport().get_visible_rect().size
		rect = Rect2(Vector2(SCREEN_MARGIN, screen.y - DEFAULT_SIZE.y - SCREEN_MARGIN), Vector2(DEFAULT_SIZE))
	size = Vector2i(rect.size)
	position = Vector2i(rect.position)
	# The window is shown either way and it is the alpha that decides whether anything is on screen.
	# Hiding it outright would cost the hover, since an embedded Window that is not visible never
	# reports the mouse entering it.
	show()
	content.modulate.a = 1.0 if start_visible else idle_alpha
	if start_visible:
		idle_timer.start() # It is on screen, so the idle fade has something to do
	settings_res = settings # Set last: applying the saved rect above must not arm a save of its own


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_POSITION_CHANGED:
		_on_rect_changed()


## Shows the input row and takes the keyboard; Enter or Send submits, Escape cancels.
func open_input() -> void:
	if input_row.visible:
		return
	# A hidden window is opened by this, not blocked by it: with the chat starting hidden
	# the action that opens it would otherwise do nothing at all.
	if not visible:
		show()
		_fade_to(1.0, 0.0)
	unfocusable = false
	grab_focus()
	input_row.show()
	input.clear()
	input.grab_focus()
	idle_timer.stop()
	_fade_to(1.0, fade_in_seconds)
	typing_changed.emit(true)


## Hides the input row and hands the keyboard back to the game.
func close_input() -> void:
	if not input_row.visible:
		return
	input_row.hide()
	input.release_focus()
	unfocusable = true
	grab_focus() # An unfocusable window cannot take focus, so this releases the embedded focus instead
	idle_timer.start()
	typing_changed.emit(false)


## Sends [param text] to every peer, or runs it locally when it is a "/" command; empty text does nothing.
func send(text: String) -> void:
	var line: String = text.strip_edges()
	if line.is_empty():
		return
	if line.begins_with("/"):
		_run_command(line.substr(1))
		return
	_receive_message.rpc(get_display_name(), line)


## The Steam persona name while Steam is running, else "Player <peer id>".
func get_display_name() -> String:
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	if steamworks and steamworks.get("steam_id") != 0:
		return str(steamworks.get("username"))
	return "Player %d" % multiplayer.get_unique_id()


## Lands on every peer's copy of the sender's Player; relays to the chat that peer owns. Only that Player's
## authority ever sends it.
@rpc("authority", "call_local", "reliable")
func _receive_message(sender: String, text: String) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"ChatWindow"):
		var chat: ChatWindow = node as ChatWindow
		if chat and chat.multiplayer == multiplayer and chat.is_multiplayer_authority():
			chat.append_message(sender, text.left(MAX_MESSAGE_LENGTH))


## Appends "Name: text" with the name coloured; user text is escaped so it cannot inject bbcode.
func append_message(sender: String, text: String) -> void:
	# Somebody has said something, so the window earns its place on screen again.
	if not visible:
		show()
	_append_line("[color=%s]%s:[/color] %s" % [name_color.to_html(false), escape_bbcode(sender), escape_bbcode(text)])


## Appends a local line (command output) in the system colour.
func append_system(text: String) -> void:
	_append_line("[color=%s]%s[/color]" % [system_color.to_html(false), escape_bbcode(text)])


## Escapes "[" and "]" so user text renders literally in a [RichTextLabel].
static func escape_bbcode(text: String) -> String:
	var marker: String = char(1) # Never typed, so "[" can be swapped for "[lb]" after "]" has become "[rb]"
	return text.replace("[", marker).replace("]", "[rb]").replace(marker, "[lb]")


func _append_line(bbcode: String) -> void:
	if not history.get_parsed_text().is_empty():
		history.append_text("\n")
	history.append_text(bbcode)
	_fade_to(1.0, fade_in_seconds)
	idle_timer.start()


## Adds "/[param command_name]" to every chat made from now on: [param callable] takes the typed arguments and the
## chat, [param help] is its /help line. A game registers its own commands (a level select, a debug spawn) here.
static func register_command(command_name: String, help: String, callable: Callable) -> void:
	_registered[command_name.to_lower()] = [callable, help]


## Drops every command a game registered; for tests.
static func forget_registered_commands() -> void:
	_registered.clear()


func _run_command(line: String) -> void:
	var parts: PackedStringArray = line.split(" ", false)
	var command_name: String = parts[0].to_lower() if parts.size() > 0 else ""
	if not commands.has(command_name):
		append_system("Unknown command: /%s, try /help" % command_name)
		return
	(commands[command_name][0] as Callable).call(parts.slice(1))


func _command_help(_args: PackedStringArray) -> void:
	for command_name: String in commands:
		append_system(commands[command_name][1])


func _command_teleport(args: PackedStringArray) -> void:
	if args.size() != 3 or not (args[0].is_valid_float() and args[1].is_valid_float() and args[2].is_valid_float()):
		append_system("Usage: /teleport x y z")
		return
	if not is_instance_valid(player):
		return
	var target: Transform3D = player.global_transform
	target.origin = Vector3(args[0].to_float(), args[1].to_float(), args[2].to_float())
	player.warp_to(target)
	append_system("Teleported to %s" % target.origin)


func _command_whereami(_args: PackedStringArray) -> void:
	if not is_instance_valid(player):
		return
	var at: Vector3 = player.global_position
	append_system("You are at %.1f %.1f %.1f, facing %.0f degrees" % [at.x, at.y, at.z, fmod(rad_to_deg(player.rotation.y) + 360.0, 360.0)])


## Heals this Player alone, on the peer that owns it; the Health node carries the change to the others.
func _command_heal(_args: PackedStringArray) -> void:
	if not is_instance_valid(player) or player.health == null:
		return
	if player.health.heal(player.health.max_health):
		append_system("Healed to %.0f" % player.health.max_health)
	else:
		append_system("Cannot heal now")


func _command_respawn(_args: PackedStringArray) -> void:
	if not is_instance_valid(player):
		return
	player.respawn()
	append_system("Respawned at the last checkpoint")


func _command_clear(_args: PackedStringArray) -> void:
	history.clear()


func _fade_to(alpha: float, seconds: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(content, "modulate:a", alpha, seconds)


func _on_idle_timer_timeout() -> void:
	if is_hovered or input_row.visible:
		return
	_fade_to(idle_alpha, fade_seconds)


func _on_mouse_entered() -> void:
	is_hovered = true
	idle_timer.stop()
	_fade_to(1.0, fade_in_seconds)


func _on_mouse_exited() -> void:
	is_hovered = false
	idle_timer.start()


func _on_input_text_submitted(text: String) -> void:
	send(text)
	close_input()


func _on_send_pressed() -> void:
	_on_input_text_submitted(input.text)


## Escape cancels; every other key is consumed by the [LineEdit] inside this focused window and never reaches the game.
func _on_input_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		input.accept_event()
		close_input()


## Dragging the title bar moves the window (the embedder handles the drag itself).
func _on_title_gui_input(event: InputEvent) -> void:
	if _is_left_press(event):
		start_drag()


## Dragging the bottom-right grip resizes the window.
func _on_grip_gui_input(event: InputEvent) -> void:
	if _is_left_press(event):
		start_resize(DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT)


static func _is_left_press(event: InputEvent) -> bool:
	var button: InputEventMouseButton = event as InputEventMouseButton
	return button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT


## Wired to size_changed and reached from the position notification; saves once the rect settles.
func _on_rect_changed() -> void:
	if settings_res and save_timer.is_inside_tree(): # The tree also resizes the window on the way out
		save_timer.start()


func _on_save_timer_timeout() -> void:
	settings_res.chat_rect = Rect2(Vector2(position), Vector2(size))
	settings_res.save()


## The embedded window draws above every CanvasLayer, so it hides while a menu is up to keep the menu
## clickable.
##
## What it was before the menu opened is remembered and restored, rather than the window being shown
## unconditionally on unpause: a project that hides the chat outright would otherwise have it appear
## the first time the player opened and closed a menu.
func _on_player_paused_changed(paused: bool) -> void:
	if not is_multiplayer_authority():
		return
	if paused:
		_visible_before_pause = visible
		close_input()
		hide()
	else:
		visible = _visible_before_pause
