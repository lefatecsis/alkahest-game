class_name HudReadout
extends CanvasLayer

## What the gameplay readouts share: which [Player] they belong to, and matching the input HUD's size.
##
## A readout is not an input hint. [PlayerControls] says what the buttons do; a boss's health, a magazine count
## and a cast in progress are readouts of systems the player is using, so each one ships as its own scene beside
## the system that drives it ([Boss], [Firearm], [Abilities]) rather than as nodes bolted onto the button HUD.
## A game mounts whichever it wants, moves them where it likes, or leaves them out entirely; every driver checks
## for its readout and does nothing when there is none.
##
## The one thing they borrow from [PlayerControls] is [method Controls.get_effective_scale], so the whole HUD
## stays one size as the window changes and as the player moves the UI Scale slider.

@export var player: Player ## The Player this reads out. Left empty, the nearest Player ancestor.

@onready var content: Control = $Content ## The anchored wrapper everything is drawn in; scaled to match the HUD.


func _ready() -> void:
	if player == null:
		player = _nearest_player()
	get_viewport().size_changed.connect(match_hud_scale)
	# Children are ready before their parents, so the Player's own @onready controls reference is not set yet
	match_hud_scale.call_deferred()


## The nearest [Player] above this node, for the usual case of a readout mounted on the Player itself.
func _nearest_player() -> Player:
	var at: Node = get_parent()
	while at:
		if at is Player:
			return at as Player
		at = at.get_parent()
	return null


## Draws this readout at the size the input HUD is drawn at. The corners of the HUD scale with the window and
## with the player's UI Scale; a readout follows them rather than owning any of that machinery itself.
func match_hud_scale() -> void:
	if content == null or player == null or not is_instance_valid(player.controls):
		return
	var value: Vector2 = Vector2.ONE * player.controls.get_effective_scale()
	if content.scale != value:
		content.scale = value
