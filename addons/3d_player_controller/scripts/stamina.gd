class_name Stamina
extends TextureProgressBar
## Stamina bar: drains while sprinting, climbing, swimming fast, diving or gliding; refills otherwise.
##
## Exhaustion clears only once stamina has fully refilled (BotW style). The bar hides itself via
## [member timer] once full.

signal stamina_changed(stamina: float, max_stamina: float) ## Emitted on every change, for the world-space energy bar.

@export var player: Player
@export var drain_sprint: float = 20.0
@export var drain_paraglide: float = 12.0
@export var drain_climb: float = 5.0
@export var drain_swim: float = 8.0
@export var drain_dive: float = 4.0 ## Constant drain while diving underwater (acts as the breath meter).
@export var sprint_multiplier: float = 1.5 ## Drain multiplier when sprinting while climbing/swimming
@export var regen_rate: float = 15.0
@export var regen_rate_falling: float = 3.0

var stamina: float = 100.0:
	set(val):
		stamina = clampf(val, min_value, max_value)
		value = stamina
		stamina_changed.emit(stamina, max_value)

@onready var timer: Timer = $Timer ## Hides the bar after refilling; its timeout is wired to [method hide] in the scene.


func _ready() -> void:
	set_physics_process(is_multiplayer_authority())
	stamina = max_value


## Takes [param amount] for a swing or a roll: true when it could be paid (always, with stamina off or a cost of 0),
## false when the Player is exhausted; paying the last of it exhausts them, the way a sprint run out does.
func spend(amount: float) -> bool:
	if amount <= 0.0 or not player.enable_stamina:
		return true
	if player.is_exhausted:
		return false
	show()
	timer.stop()
	stamina -= amount
	if stamina <= min_value:
		player.is_exhausted = true
	return true


func _physics_process(delta: float) -> void:
	# No signal exists for this export, so it is checked per frame.
	if not player.enable_stamina:
		stamina = max_value
		player.is_exhausted = false
		hide()
		return

	# Determine which stamina-draining activity (if any) the player is doing
	var climbing_moving: bool = player.is_climbing and player.velocity.length() > 0.1
	var swimming_moving: bool = player.is_swimming \
			and (player.velocity.length() > 0.1 or player.player_input.motion.length() > 0.0 or player.smoothed_motion.length() > 0.0)
	var swimming_fast: bool = swimming_moving and player.is_sprinting
	var swimming_normal: bool = swimming_moving and not player.is_sprinting

	# Sprinting in place costs nothing; drain requires actual movement input. The firearm blend spaces stop at
	# the run clip (no sprint point), so sprinting with a pistol or rifle buys no speed and costs nothing.
	var sprinting_on_land: bool = player.is_sprinting \
			and player.player_input.motion.length() > 0.0 \
			and not player.has_firearm_equipped \
			and not player.is_climbing \
			and not player.is_swimming \
			and not player.is_paragliding
	var draining: bool = sprinting_on_land or climbing_moving or swimming_fast or player.is_diving or player.is_paragliding

	if draining and not player.is_exhausted and stamina > min_value:
		show()
		timer.stop()
		var drain_rate: float = drain_sprint
		if climbing_moving:
			drain_rate = drain_climb * (sprint_multiplier if player.is_sprinting else 1.0)
		elif player.is_diving:
			# Diving drains as a breath meter; fast swimming underwater costs extra
			drain_rate = drain_dive + (drain_swim * sprint_multiplier if swimming_fast else 0.0)
		elif swimming_fast:
			drain_rate = drain_swim * sprint_multiplier
		elif player.is_paragliding:
			drain_rate = drain_paraglide
		stamina -= drain_rate * delta
		if stamina <= min_value:
			player.is_exhausted = true

	# Regenerate when not draining (slowly while falling or treading water);
	# idle climbing and normal-speed swimming hold stamina instead
	elif stamina < max_value and not player.is_climbing and not swimming_normal:
		show()
		timer.stop()
		stamina += (regen_rate_falling if player.is_falling or player.is_swimming else regen_rate) * delta

	if player.is_exhausted and stamina >= max_value:
		player.is_exhausted = false

	if visible and stamina >= max_value and timer.is_stopped():
		timer.start()
