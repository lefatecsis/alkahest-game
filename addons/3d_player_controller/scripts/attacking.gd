class_name Attacking
extends NodeStateMachine

@export var boxing_inactivity_delay: float = 2.0 ## Seconds without an attack before the boxing stance is dropped.
@export var attack_timeout: float = 1.0 ## Seconds to reach an attack animation before the state gives up and returns to standing.

## Locomotion nodes that count as an active attack animation.
const ATTACK_NODES: Array[String] = [
	"GreatSwordDownwardSlash", ## 2-Handed Weapon, Attack 1 of 3
	"GreatSwordLowSlash", ## 2-Handed Weapon, Attack 2 of 3
	"GreatSwordPowerSlash", ## 2-Handed Weapon, Attack 3 of 3
	"ShieldDownwardSlash", ## Sword and Shield, Attack 1 of 3
	"ShieldCrossSlash", ## Sword and Shield, Attack 2 of 3
	"ShieldPowerSlash", ## Sword and Shield, Attack 3 of 3
	"ShortHeadJab", ## Unarmed / Boxing, Attack 1 of 2
	"BackHandCross", ## Unarmed / Boxing, Attack 2 of 2
]

@onready var boxing_inactivity_timer: Timer = $BoxingInactivityTimer ## Restarted on every attack while boxing; its timeout ends the boxing stance.
@onready var attack_timeout_timer: Timer = $AttackTimeoutTimer ## Runs until an attack animation starts; if none ever does (no transition from the current locomotion), its timeout leaves the state.
var _has_entered_attack: bool = false


## Called when there is an input event.
func _input(event: InputEvent) -> void:

	# Do nothing if the player is not set
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Attack { Microsoft: Ⓧ, Nintendo: Ⓨ, Sony: 🟗, Keyboard: [Alt] }
	if not event.is_action_pressed(&"attack") or not player.inventory.can_player_attack:
		return
	# The press that brought the Player here was paid for in start(); the grounded states mark it handled
	if get_viewport().is_input_handled():
		return
	# The next swing in the sequence costs what the first did; out of breath, the combo ends here
	if not player.stamina.spend(player.attack_stamina_cost):
		return
	# Start the attack sequence timer
	player.attack_sequence_timer.start()
	var current_node: String = player.current_locomotion_node

	# Attack Sequence: 1-Handed Weapon and Shield
	if player.inventory.has_one_handed_or_shield_equipped():
		# Queue the next attack in the sequence (changing the variable causes the AnimationTree to travel)
		if current_node == "ShieldDownwardSlash": ## Sword and Shield, Attack 1 of 3
			player.attack_sequence = 1
		elif current_node == "ShieldCrossSlash": ## Sword and Shield, Attack 2 of 3
			player.attack_sequence = 2
		elif current_node == "ShieldPowerSlash": ## Sword and Shield, Attack 3 of 3
			player.attack_sequence = 3

	# Attack Sequence: 2-Handed Weapon
	elif player.inventory.has_heavy_weapon_equipped():
		if current_node == "GreatSwordDownwardSlash": ## 2-Handed Weapon, Attack 1 of 3
			player.attack_sequence = 1
		elif current_node == "GreatSwordLowSlash": ## 2-Handed Weapon, Attack 2 of 3
			player.attack_sequence = 2
		elif current_node == "GreatSwordPowerSlash": ## 2-Handed Weapon, Attack 3 of 3
			player.attack_sequence = 3

	# Attack Sequence: Unarmed / Boxing
	elif player.inventory.is_unarmed():
		player.is_boxing = true
		player.is_attacking = true
		boxing_inactivity_timer.start(boxing_inactivity_delay)
		if current_node == "ShortHeadJab": ## Unarmed / Boxing, Attack 1 of 2
			player.attack_sequence = 1
		elif current_node == "BackHandCross": ## Unarmed / Boxing, Attack 2 of 2
			player.attack_sequence = 2


## Tracks the attack animation: once one has played and ended, drop the attack (boxing) or return to standing.
func _on_locomotion_node_changed(_state_path: String) -> void:
	if process_mode != Node.PROCESS_MODE_INHERIT: return

	if player.current_locomotion_node in ATTACK_NODES:
		_has_entered_attack = true
		attack_timeout_timer.stop()
	elif _has_entered_attack:
		if player.inventory.is_unarmed() and player.is_boxing:
			# Finished attack animation while boxing: clear the attack but stay in the boxing stance until the inactivity timer fires
			player.is_attacking = false
			_has_entered_attack = false
			player.attack_sequence = 0
		else:
			# Stop "attacking", start "standing"
			player.state_machine.travel(state, States.STANDING)


## No attack for [member boxing_inactivity_delay] seconds -> drop the boxing stance.
func _on_boxing_inactivity_timer_timeout() -> void:
	player.state_machine.travel(state, States.STANDING)


## No attack animation started within [member attack_timeout] (the locomotion had no way into one) -> back to standing
## rather than staying flagged as attacking.
func _on_attack_timeout_timer_timeout() -> void:
	if not _has_entered_attack:
		player.state_machine.travel(state, States.STANDING)


## Start "attacking".
func start() -> void:
	super.start()
	# Flag the player as "attacking"
	player.is_attacking = true
	_has_entered_attack = player.current_locomotion_node in ATTACK_NODES
	if not _has_entered_attack:
		attack_timeout_timer.start(attack_timeout)
	# Flag as boxing if unarmed and start the inactivity delay
	if player.inventory.is_unarmed():
		player.is_boxing = true
		boxing_inactivity_timer.start(boxing_inactivity_delay)
	# Start the attack sequence timer
	player.attack_sequence_timer.start()
	# Reset the attack state variables
	player.attack_sequence = 0
	# The first swing's stamina (the state is only entered with breath to spare)
	player.stamina.spend(player.attack_stamina_cost)


## Stop "attacking".
func stop() -> void:
	super.stop()
	# Flag the player as not "attacking"
	player.is_attacking = false
	player.is_boxing = false
	_has_entered_attack = false
	boxing_inactivity_timer.stop()
	attack_timeout_timer.stop()
	# Stop the attack sequence timer
	player.attack_sequence_timer.stop()
	# Reset the state variables
	player.attack_sequence = 0
