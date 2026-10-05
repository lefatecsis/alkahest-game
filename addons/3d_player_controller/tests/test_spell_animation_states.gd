extends GutTest
## The spell animation states wired into the Player's AnimationTree: one-shot casts return to locomotion on
## their own, the looping Spell Casting channel leaves when code travels back, and every state is reachable
## from its group's locomotion through travel_locomotion.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var _root: AnimationNodeStateMachine


func before_each() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	var tree: AnimationTree = player.get_node("AnimationTree")
	_root = (tree.tree_root as AnimationNodeBlendTree).get_node("LocomotionStateMachine")
	player.free()


func _group(name: String) -> AnimationNodeStateMachine:
	return _root.get_node(name) as AnimationNodeStateMachine


func _transition(machine: AnimationNodeStateMachine, from: String, to: String) -> AnimationNodeStateMachineTransition:
	for i: int in machine.get_transition_count():
		if machine.get_transition_from(i) == from and machine.get_transition_to(i) == to:
			return machine.get_transition(i)
	return null


func test_the_shield_group_has_the_sword_and_shield_spells() -> void:
	var shield: AnimationNodeStateMachine = _group("Shield")
	for state: String in ["ShieldPowerUp", "ShieldSpellCast", "ShieldSpellCasting"]:
		assert_true(shield.has_node(state), state)
		assert_true(shield.has_transition("ShieldLocomotion", state), "Reachable from ShieldLocomotion: " + state)
		assert_true(shield.has_transition(state, "ShieldLocomotion"), "Returns to ShieldLocomotion: " + state)
	assert_eq((shield.get_node("ShieldSpellCast") as AnimationNodeAnimation).animation, &"Sword And Shield Spell Cast/mixamo_com")
	assert_eq((shield.get_node("ShieldSpellCasting") as AnimationNodeAnimation).animation, &"Sword And Shield Spell Casting/mixamo_com")
	assert_eq((shield.get_node("ShieldPowerUp") as AnimationNodeAnimation).animation, &"Sword And Shield Power Up/mixamo_com")
	assert_true(shield.has_transition("ShieldPowerUp", "ShieldSpellCast"), "A power up can go straight into the cast")
	assert_true(shield.has_transition("ShieldSpellCasting", "ShieldSpellCast"), "The channel can land as the cast")


func test_the_greatsword_group_has_the_great_sword_spells() -> void:
	var greatsword: AnimationNodeStateMachine = _group("GreatSword")
	for state: String in ["GreatSwordPowerUp", "GreatSwordSpellCast", "GreatSwordSpellCasting"]:
		assert_true(greatsword.has_node(state), state)
		assert_true(greatsword.has_transition("GreatSwordLocomotion", state), "Reachable from GreatSwordLocomotion: " + state)
		assert_true(greatsword.has_transition(state, "GreatSwordLocomotion"), "Returns to GreatSwordLocomotion: " + state)
	assert_eq((greatsword.get_node("GreatSwordSpellCast") as AnimationNodeAnimation).animation, &"Great Sword Spell Cast/mixamo_com")
	assert_eq((greatsword.get_node("GreatSwordSpellCasting") as AnimationNodeAnimation).animation, &"Great Sword Spell Casting/mixamo_com")
	assert_eq((greatsword.get_node("GreatSwordPowerUp") as AnimationNodeAnimation).animation, &"Great Sword Power Up/mixamo_com")


func test_the_standing_one_handed_casts_sit_beside_standing_locomotion() -> void:
	var casts: Dictionary = {
		"SpellCastForwards": &"Standing 1H Spell Cast Forwards/mixamo_com",
		"SpellCastSweepingSideways": &"Standing 1H Spell Cast Sweeping Sideways/mixamo_com",
		"SpellCastSweepingUpwards": &"Standing 1H Spell Cast Sweeping Upwards/mixamo_com",
		"SpellCastUpwards": &"Standing 1H Spell Cast Upwards/mixamo_com",
	}
	for state: String in casts:
		assert_true(_root.has_node(state), state)
		assert_eq((_root.get_node(state) as AnimationNodeAnimation).animation, casts[state])
		assert_true(_root.has_transition("StandingLocomotion", state), "Reachable from StandingLocomotion: " + state)
		var back: AnimationNodeStateMachineTransition = _transition(_root, state, "StandingLocomotion")
		assert_eq(back.switch_mode, AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END, "A one-shot cast returns when it ends: " + state)
		assert_eq(back.advance_mode, AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO, "Without code having to travel back: " + state)


func test_the_casting_channel_only_leaves_when_travelled() -> void:
	for group: String in ["Shield", "GreatSword"]:
		var machine: AnimationNodeStateMachine = _group(group)
		var out: AnimationNodeStateMachineTransition = _transition(machine, group + "SpellCasting", group + "Locomotion")
		assert_eq(out.advance_mode, AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED, group + " Spell Casting loops until code travels back")
		var cast_out: AnimationNodeStateMachineTransition = _transition(machine, group + "SpellCast", group + "Locomotion")
		assert_eq(cast_out.advance_mode, AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO, group + " Spell Cast returns on its own")
