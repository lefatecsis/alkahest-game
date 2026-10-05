class_name Dodging
extends NodeStateMachine
## The Souls roll: a tap of Sprint ([method Player.try_dodge]) dives forward along the direction moved, or backsteps
## when still, on root-motion clips; the first [member Player.dodge_iframe_seconds] of it take no hit. The dive is
## the standing one from a stand, the sprinting one out of a run ([member Player.dodge_from_run]), the rifle's own
## pair with a rifle in hand and the bow's with a bow, and from the air ([method Player.try_air_dive]) the falling
## dive that rolls out of the landing. It ends when the clip hands back to a locomotion node, and stands the
## Player back up.

const FLIP_NODES: Array[String] = ["FowardFlip", "Backflip"]
const TIMEOUT: float = 3.0 ## The clip never arrived (a transition the tree could not path): stand up regardless. Past the longest dive, which gets up on its own.

var _entered_flip: bool = false
var _iframes_left: float = 0.0
var _elapsed: float = 0.0


func _on_locomotion_node_changed(_state_path: String) -> void:
	if process_mode != Node.PROCESS_MODE_INHERIT:
		return
	var node: String = player.current_locomotion_node
	if node in FLIP_NODES or node.ends_with("Dive"):
		_entered_flip = true
	elif _entered_flip:
		player.state_machine.travel(state, States.STANDING)


func _physics_process(delta: float) -> void:
	if not player:
		return
	_elapsed += delta
	if _iframes_left > 0.0:
		_iframes_left -= delta
		if _iframes_left <= 0.0:
			player.dodge_invulnerable = false
	if _elapsed > TIMEOUT:
		player.state_machine.travel(state, States.STANDING)


## Start "dodging": face the way the stick points and roll that way, or backstep in place.
func start() -> void:
	super.start()
	player.is_dodging = true
	player.is_boxing = false
	player.dodge_invulnerable = player.dodge_iframe_seconds > 0.0
	_iframes_left = player.dodge_iframe_seconds
	_entered_flip = false
	_elapsed = 0.0
	var motion: Vector2 = player.player_input.motion
	var moving: bool = motion.length_squared() > 0.01
	if moving and player.spring_arm:
		var direction: Vector3 = (player.spring_arm.global_transform.basis * Vector3(motion.x, 0.0, -motion.y)).slide(player.up_direction)
		if direction.length_squared() > 0.001:
			player.orientation.basis = Basis.looking_at(-direction.normalized(), player.up_direction)
	if player.dive_from_air:
		player.dive_from_air = false
		player.is_front_flipping = true
		player.is_back_flipping = false
		player.travel_locomotion("FallingDive")
	elif moving:
		player.is_front_flipping = true
		player.is_back_flipping = false
		player.travel_locomotion(dive_node(player.dodge_from_run))
	else:
		player.is_back_flipping = true
		player.is_front_flipping = false
		player.travel_locomotion("Backflip")


## The locomotion node for a forward roll: the rifle's and the bow's stay inside their groups, the rest is the
## standing dive from a stand or the sprinting dive out of a run.
func dive_node(from_run: bool) -> String:
	if player.equipped_rifle:
		return "Rifle/RifleRunningDive" if from_run else "Rifle/RifleStandingDive"
	if player.equipped_bow:
		return "Bow/BowDive"
	return "SprintingDive" if from_run else "StandingDive"


## Stop "dodging".
func stop() -> void:
	super.stop()
	player.is_dodging = false
	player.dodge_invulnerable = false
	player.is_front_flipping = false
	player.is_back_flipping = false
