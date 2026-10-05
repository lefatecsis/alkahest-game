class_name PlayerNoise
extends Node
## How much noise the Player is making, from 0 (silent) to 1 (as loud as they get), and who can hear it.
##
## Three things feed it. Moving sets a floor: sneaking is almost silent, walking low, running and sprinting
## loud, and being [member Player.is_stealthed] quiets all of it. On top of that sit one-off noises that spike
## the reading and fall back, a landing, a slide, a swing, a thrown object, a gunshot. And talking on
## push-to-talk is noise like any other: the reading follows how loudly you are actually speaking, measured
## from the captured voice rather than from the fact of holding the key, so a whisper carries less than a
## shout and saying nothing with the key held carries nothing at all.
##
## Anything within [member hearing_range] scaled by the current level hears it: every [EnemyNpc] in earshot is
## told to [code]aggro[/code] the Player, which is what makes sprinting past a sleeping enemy a mistake and
## sneaking past one a choice. A gunshot at full level carries the whole range; a sneaking Player is
## effectively inaudible. Only the authority listens, so a peer cannot wake another peer's enemies.

signal level_changed(level: float) ## The reading changed; the HUD meter follows this.
signal heard_by(listener: Node3D) ## [param listener] was close enough to hear and has been set on the Player.

@export var player: Player ## Whose noise this is; the Player above it when empty.

@export_group("Moving")
@export var still_speed: float = 0.3 ## Below this the Player counts as standing still, and is silent.
@export var loud_speed: float = 5.5 ## The pace at which moving is as loud as that way of moving gets.
@export var crouch_multiplier: float = 0.5 ## What crouching does to the noise. It halves it rather than capping it, so crouch-walking still reads on the meter and still carries: moving carefully is quieter, not silent.
@export var walking_level: float = 0.55 ## The ceiling on foot at an ordinary pace.
@export var sprinting_level: float = 0.9 ## The ceiling while sprinting.
@export var stealth_multiplier: float = 0.35 ## What [member Player.is_stealthed] does to the moving floor.
@export var swimming_multiplier: float = 0.6 ## Water carries less of the footfall.

@export_group("One-off noises")
@export var landing_noise: float = 0.7 ## Coming down from a fall.
@export var slide_noise: float = 0.6
@export var melee_noise: float = 0.5 ## A swing that lands.
@export var throw_noise: float = 0.4
@export var firearm_noise: float = 1.0 ## A gunshot, the loudest thing the Player has.

@export_group("Voice")
@export var voice_multiplier: float = 0.85 ## What a full-voice shout on push-to-talk reads. Talking is sustained rather than a one-off, so it holds the reading up for as long as you speak.

@export_group("Response")
@export var decay_per_second: float = 1.1 ## How fast a one-off noise falls back to the moving floor.
@export var smoothing: float = 9.0 ## How quickly the reading chases its target; the meter is smoothed, not twitchy.
@export var hearing_range: float = 30.0 ## Metres a noise of 1.0 carries. The range scales with the level, so a sneak carries almost nothing.
@export var listen_interval: float = 0.25 ## Seconds between sweeps for listeners; noise does not need testing every frame.

var level: float = 0.0: ## The current reading, 0 to 1.
	set(value):
		var clamped: float = clampf(value, 0.0, 1.0)
		if is_equal_approx(clamped, level):
			return
		level = clamped
		level_changed.emit(level)

var _spike: float = 0.0 ## The decaying part, from one-off noises.
var _since_listen: float = 0.0
var _connected_firearms: Array[Firearm] = []


## The Player's state_changed, HitDetection's weapon_hit and the inventory's equipment_changed are wired to the
## handlers below in player.tscn.
func _ready() -> void:
	if player == null:
		player = get_parent() as Player
	if player == null:
		set_physics_process(false)
		return
	_follow_equipment()


func _physics_process(delta: float) -> void:
	# Only the peer driving this Player decides how loud they are, and only it wakes anything
	if not player.is_multiplayer_authority():
		return
	_spike = maxf(_spike - decay_per_second * delta, 0.0)
	var target: float = maxf(maxf(moving_level(), voice_level()), _spike)
	level = move_toward(level, target, smoothing * delta)

	_since_listen += delta
	if _since_listen >= listen_interval:
		_since_listen = 0.0
		_wake_listeners(level)


## The floor the Player's movement sets, before any one-off noise on top. Movement here is driven by root
## motion rather than by a speed export, so the tier comes from what the Player is doing (crouched, sprinting,
## or neither) and the pace within that tier comes from how fast they are actually travelling.
func moving_level() -> float:
	var speed: float = player.velocity.slide(player.up_direction).length()
	if speed <= still_speed:
		return 0.0
	var pace: float = clampf((speed - still_speed) / maxf(loud_speed - still_speed, 0.001), 0.0, 1.0)
	var out: float = (sprinting_level if player.is_sprinting else walking_level) * pace
	# Each of these halves or softens what is already there, rather than capping it. A ceiling would mean a
	# crouched Player reads the same flat line whether they are still or moving as fast as a crouch allows.
	if player.is_crouching:
		out *= crouch_multiplier
	if player.is_stealthed:
		out *= stealth_multiplier
	if player.is_swimming:
		out *= swimming_multiplier
	return out


## How much of the reading the Player's own voice accounts for. Push-to-talk only: a Player who is not
## broadcasting is not speaking, whatever their microphone is picking up.
func voice_level() -> float:
	var voice: VoiceChat = player.voice_chat
	if voice == null or not voice.is_broadcasting:
		return 0.0
	return clampf(voice.voice_loudness, 0.0, 1.0) * voice_multiplier


## A one-off noise of [param amount], which spikes the reading and falls back. Anything in the world can call
## this: a door slamming, a pot breaking, a whistle.
##
## It wakes anything in earshot straight away rather than waiting for the next sweep. A gunshot is loud for a
## moment and then gone, and at one sweep every quarter second it would often have decayed below the distance
## to the listener before anyone was asked, so a shot could go unheard entirely.
func make_noise(amount: float) -> void:
	var made: float = clampf(amount, 0.0, 1.0)
	_spike = maxf(_spike, made)
	if player and player.is_multiplayer_authority():
		_wake_listeners(made)


## How far the current reading carries, in metres.
func audible_distance() -> float:
	return hearing_range * level


## Tells every [EnemyNpc] within earshot of a noise of [param at_level] to come looking. [method EnemyNpc.aggro]
## refuses a dead enemy, one already hunting this Player and a dead Player, so this can be shouted every sweep.
func _wake_listeners(at_level: float) -> void:
	var reach: float = hearing_range * clampf(at_level, 0.0, 1.0)
	if reach <= 0.01 or player.health == null or not player.health.is_alive():
		return
	var reach_squared: float = reach * reach
	for node: Node in get_tree().get_nodes_in_group(&"Enemies"):
		var enemy: EnemyNpc = node as EnemyNpc
		if enemy == null or enemy.is_dead or enemy.target == player:
			continue
		if enemy.global_position.distance_squared_to(player.global_position) > reach_squared:
			continue
		enemy.aggro(player)
		heard_by.emit(enemy)


## Landing and sliding are noises the state machine already announces.
func _on_state_changed(from_state: int, to_state: int) -> void:
	if to_state == NodeStateMachine.States.SLIDING:
		make_noise(slide_noise)
	elif from_state == NodeStateMachine.States.FALLING and to_state != NodeStateMachine.States.FALLING:
		make_noise(landing_noise)


func _on_weapon_hit(_equipment: Node, _target: Node) -> void:
	make_noise(melee_noise)


func _on_firearm_fired(_projectile: Projectile) -> void:
	make_noise(firearm_noise)


## Equipment comes and goes, so the gunfire hook follows it rather than being wired once in the scene.
func _follow_equipment() -> void:
	for firearm: Firearm in _connected_firearms:
		if is_instance_valid(firearm) and firearm.fired.is_connected(_on_firearm_fired):
			firearm.fired.disconnect(_on_firearm_fired)
	_connected_firearms.clear()
	for node: Node in player.find_children("*", "Firearm", true, false):
		var firearm: Firearm = node as Firearm
		if firearm and not firearm.fired.is_connected(_on_firearm_fired):
			firearm.fired.connect(_on_firearm_fired)
			_connected_firearms.append(firearm)
