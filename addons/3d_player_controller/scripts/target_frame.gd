class_name TargetFrame
extends PanelContainer
## The Player's Target on the HUD: its name, its health tinted by how it stands to the Player (red hostile, yellow
## neutral, green friendly), and who it is hunting. It shows while the Player has a Target
## ([signal Focus.target_changed]) and hides otherwise; a body without a Health shows its name alone.

const HOSTILE_COLOR: Color = Color(0.85, 0.25, 0.25)
const NEUTRAL_COLOR: Color = Color(0.9, 0.75, 0.2)
const FRIENDLY_COLOR: Color = Color(0.3, 0.8, 0.4)

@export var player: Player: ## Whose Target this shows.
	set(value):
		if player and player.focus and player.focus.target_changed.is_connected(_on_target_changed):
			player.focus.target_changed.disconnect(_on_target_changed)
		player = value
		if is_node_ready():
			_watch_player()

var target: Node3D ## The body shown, if any.
var _health: Health ## The target's Health, while it has one.

@onready var name_label: Label = $VBox/Name
@onready var health_bar: ProgressBar = $VBox/HealthBar
@onready var targeting_label: Label = $VBox/Targeting


func _ready() -> void:
	_watch_player()


func _watch_player() -> void:
	if player == null:
		_on_target_changed(null)
		return
	if not player.is_node_ready():
		# The HUD readies before the Player, whose Focus is @onready; wait for it
		if not player.ready.is_connected(_watch_player):
			player.ready.connect(_watch_player, CONNECT_ONE_SHOT)
		_on_target_changed(null)
		return
	if player.focus == null:
		_on_target_changed(null)
		return
	if not player.focus.target_changed.is_connected(_on_target_changed):
		player.focus.target_changed.connect(_on_target_changed)
	_on_target_changed(player.focus.selected_target)


func _on_target_changed(new_target: Node3D) -> void:
	_unwatch()
	target = new_target if is_instance_valid(new_target) else null
	if target:
		_health = target.get("health") as Health
		if _health:
			_health.health_changed.connect(_on_health_changed)
		if target.has_signal(&"aggroed"):
			target.connect(&"aggroed", _on_target_aggroed)
	refresh()


func _unwatch() -> void:
	if _health and _health.health_changed.is_connected(_on_health_changed):
		_health.health_changed.disconnect(_on_health_changed)
	_health = null
	if is_instance_valid(target) and target.has_signal(&"aggroed") and target.is_connected(&"aggroed", _on_target_aggroed):
		target.disconnect(&"aggroed", _on_target_aggroed)


## Redraws the frame for [member target]: hidden without one.
func refresh() -> void:
	visible = is_instance_valid(target)
	if not visible:
		return
	name_label.text = display_name_of(target)
	health_bar.visible = _health != null
	if _health:
		_on_health_changed(_health.health, _health.max_health)
	health_bar.modulate = color_for(target)
	var prey: Node3D = target.get("target") as Node3D
	targeting_label.text = "Targeting %s" % display_name_of(prey) if is_instance_valid(prey) else ""
	targeting_label.visible = not targeting_label.text.is_empty()


## What [param body] is called: its display name when it has one, else its node name.
func display_name_of(body: Node3D) -> String:
	var shown: Variant = body.get("display_name")
	return shown if shown is String and not (shown as String).is_empty() else String(body.name)


## The bar's tint for how [param body] stands to the Player.
func color_for(body: Node3D) -> Color:
	match Focus.disposition_toward(body, player):
		Focus.Disposition.HOSTILE:
			return HOSTILE_COLOR
		Focus.Disposition.NEUTRAL:
			return NEUTRAL_COLOR
		_:
			return FRIENDLY_COLOR


func _on_health_changed(health: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = health


func _on_target_aggroed(_prey: Node3D) -> void:
	refresh()
