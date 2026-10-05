extends GutTest

## Purpose: Abilities work the World of Warcraft way on the Zelda-style controls: a tap of "ability"
## casts the picked ability, a hold opens the wheel to pick another, timed casts run a cast bar that any
## movement interrupts, toggles such as Stealth end on attack, and cooldowns gate recasts.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const STEALTH: Ability = preload("res://addons/3d_player_controller/resources/abilities/stealth.tres")
const HEAL: Ability = preload("res://addons/3d_player_controller/resources/abilities/heal.tres")

var player: Player
var abilities: Abilities
var stealth: StealthAbility
var heal: HealAbility
var sender


func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(20.0, 1.0, 20.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.enable_stamina = true
	abilities = player.abilities
	stealth = STEALTH.duplicate()
	heal = HEAL.duplicate()
	abilities.abilities = [stealth, heal]
	abilities.active_ability = stealth
	sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	await wait_physics_frames(20)


func after_each() -> void:
	sender.release_all()
	sender.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_player_scene_ships_with_stealth_and_heal_picked_first() -> void:
	var fresh: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(fresh)
	await wait_physics_frames(2)
	assert_eq(fresh.abilities.abilities.size(), 2)
	assert_eq(fresh.abilities.active_ability, fresh.abilities.abilities[0])
	assert_eq(fresh.controls.joypad_button_9_label.text, "Stealth", "The left shoulder label names the picked ability")


func test_wheel_lists_abilities_and_picking_does_not_cast() -> void:
	var items: Array[Dictionary] = abilities.get_wheel_items()
	assert_eq(items.size(), 2)
	assert_eq(items[1]["display_name"], "Heal")
	assert_eq(items[1]["item"], heal)
	assert_true(abilities.radial_menu.custom_item_is_equipped.call(items[0], 0), "The picked ability draws as equipped")
	abilities.radial_menu.custom_item_selected.call(items[1], 1)
	assert_eq(abilities.active_ability, heal)
	assert_null(abilities.casting, "Picking from the wheel only changes the active ability")
	assert_eq(player.controls.joypad_button_9_label.text, "Heal")


func test_holding_ability_opens_the_wheel_and_a_tap_casts() -> void:
	sender.action_down("ability")
	await wait_seconds(0.3)
	assert_true(abilities.radial_menu.is_open(), "Holding the ability action opens the wheel")
	assert_false(player.is_stealthed)
	sender.action_up("ability")
	await wait_physics_frames(2)
	assert_false(abilities.radial_menu.is_open())
	assert_false(player.is_stealthed, "Releasing after a hold is not a cast")

	sender.action_down("ability")
	await wait_physics_frames(1)
	sender.action_up("ability")
	await wait_physics_frames(1)
	assert_true(player.is_stealthed, "A tap casts the picked ability")


## M10: a pad's ability button behind the pause menu or the chat casts nothing and opens no wheel, as the
## Inventory's button does; in multiplayer the tree is not paused, so the flags are what stop it.
func test_paused_or_typing_blocks_the_ability_button() -> void:
	player.is_paused = true
	sender.action_down("ability")
	await wait_physics_frames(1)
	sender.action_up("ability")
	await wait_physics_frames(1)
	assert_false(player.is_stealthed, "A tap behind the pause menu casts nothing")
	player.is_paused = false

	player.is_typing = true
	sender.action_down("ability")
	await wait_seconds(0.3)
	assert_false(abilities.radial_menu.is_open(), "A hold while typing opens no wheel")
	sender.action_up("ability")
	await wait_physics_frames(1)
	assert_false(player.is_stealthed, "and its release casts nothing")
	player.is_typing = false

	sender.action_down("ability")
	await wait_physics_frames(1)
	sender.action_up("ability")
	await wait_physics_frames(1)
	assert_true(player.is_stealthed, "Out of the menu and the chat, a tap casts again")


func test_stealth_toggles_fades_the_model_and_costs_mana_not_stamina() -> void:
	watch_signals(abilities)
	var before: float = player.health.energy
	var stamina_before: float = player.stamina.stamina
	abilities.cast(stealth)
	assert_true(player.is_stealthed)
	assert_signal_emitted_with_parameters(abilities, "ability_activated", [stealth])
	assert_almost_eq(player.health.energy, before - stealth.energy_cost, 0.01, "Abilities draw on the mana pool")
	assert_eq(player.stamina.stamina, stamina_before, "The stamina wheel is for moving, not casting")
	_assert_ghosted(player, 1.0, "The ghost starts solid")
	var glider: MeshInstance3D = player.get_node("PlayerModel/Armature/GeneralSkeleton/ParagliderBoneAttachment/Paraglider/Paraglider2/Paraglider") as MeshInstance3D
	var fabric: Material = glider.get_surface_override_material(0)
	assert_eq((fabric as ShaderMaterial).shader, StealthLook.STEALTH_DEPTH_SHADER, "The packed-away glider fades with the body, so it opens as a ghost too")
	await wait_seconds(player.stealth_look.fade_time + 0.2)
	_assert_ghosted(player, 1.0 - player.stealth_look.transparency, "and settles to the stealth alpha over the fade time")

	abilities.cast(stealth)
	assert_false(player.is_stealthed, "Casting an active toggle ends it")
	assert_signal_emitted_with_parameters(abilities, "ability_deactivated", [stealth])
	await wait_seconds(player.stealth_look.fade_time + 0.2)
	for mesh: MeshInstance3D in _body_meshes(player):
		for surface: int in mesh.mesh.get_surface_count():
			assert_null(mesh.get_surface_override_material(surface), "The original look is back once the fade out lands")
	assert_ne((glider.get_surface_override_material(0) as ShaderMaterial).shader, StealthLook.STEALTH_DEPTH_SHADER, "and the glider wears its fabric again")


func test_attacking_ends_stealth() -> void:
	abilities.cast(stealth)
	player.locomotion_node_changed.emit("ShortHeadJab")
	assert_false(player.is_stealthed, "A melee swing breaks stealth")
	assert_true(abilities.active_toggles.is_empty())


func test_heal_casts_over_time_and_restores_health() -> void:
	watch_signals(abilities)
	player.health.health = 20.0
	heal.cast_time = 0.3
	abilities.cast(heal)
	assert_eq(abilities.casting, heal)
	assert_true(player.cast_bar.bar.visible, "A timed cast shows the cast bar")
	assert_eq(player.cast_bar.label.text, "Heal", "The cast bar names the spell")
	assert_signal_emitted(abilities, "cast_started")
	assert_almost_eq(player.health.health, 20.0, 0.01, "Nothing lands until the cast finishes")
	await wait_seconds(0.5)
	assert_null(abilities.casting)
	assert_false(player.cast_bar.bar.visible)
	assert_almost_eq(player.health.health, 70.0, 0.01, "The heal restores health once the cast lands")
	assert_signal_emitted_with_parameters(abilities, "ability_activated", [heal])


func test_heal_lands_on_a_locked_on_player_instead_of_the_caster() -> void:
	var friend: Player = PLAYER_SCENE.instantiate()
	friend.position = Vector3(2.0, 0.0, 0.0)
	player.get_parent().add_child(friend)
	await wait_physics_frames(2)
	friend.health.health = 30.0
	player.focus.current_focus_target = friend
	assert_eq(player.selected_target, friend, "Held Focus is the Target")
	heal.cast_time = 0.0
	abilities.cast(heal)
	assert_almost_eq(friend.health.health, 80.0, 0.01, "The targeted player is healed")
	assert_eq(player.health.health, player.health.max_health, "The caster is untouched")
	assert_true(player.is_in_group("Focusable"), "Players can be locked on to, so they can be healed")


func test_heal_is_refused_at_full_health_without_spending_its_cooldown() -> void:
	heal.cast_time = 0.0
	abilities.cast(heal)
	assert_true(abilities.is_ready(heal), "A refused cast spends no cooldown")


func test_moving_interrupts_a_cast() -> void:
	watch_signals(abilities)
	player.health.health = 20.0
	heal.cast_time = 1.0
	abilities.cast(heal)
	player.locomotion_node_changed.emit("Walking")
	assert_null(abilities.casting)
	assert_signal_emitted_with_parameters(abilities, "cast_interrupted", [heal])
	assert_false(player.cast_bar.bar.visible)
	assert_true(abilities.cast_timer.is_stopped())
	assert_almost_eq(player.health.health, 20.0, 0.01, "An interrupted heal lands nothing")


func test_walking_input_interrupts_a_cast() -> void:
	player.health.health = 20.0
	heal.cast_time = 2.0
	abilities.cast(heal)
	assert_true(abilities.is_physics_processing(), "Movement is polled only while a breakable cast runs")
	sender.action_down("move_up")
	await wait_physics_frames(3)
	sender.action_up("move_up")
	assert_null(abilities.casting, "Walking breaks the cast even though the standing blend space keeps the locomotion node")
	assert_false(abilities.is_physics_processing())


func test_channel_while_moving_survives_movement_but_not_attacks() -> void:
	watch_signals(abilities)
	player.health.health = 20.0
	heal.cast_time = 2.0
	heal.channel_while_moving = true
	abilities.cast(heal)
	assert_false(abilities.is_physics_processing(), "A channel-while-moving cast polls nothing")
	sender.action_down("move_up")
	await wait_physics_frames(3)
	sender.action_up("move_up")
	player.locomotion_node_changed.emit("Walking")
	player.state_changed.emit(NodeStateMachine.States.STANDING, NodeStateMachine.States.JUMPING)
	assert_eq(abilities.casting, heal, "Moving keeps a channel-while-moving cast going")
	assert_signal_not_emitted(abilities, "cast_interrupted")
	player.locomotion_node_changed.emit("ShortHeadJab")
	assert_null(abilities.casting, "Attacking still interrupts")
	assert_signal_emitted_with_parameters(abilities, "cast_interrupted", [heal])


func test_cooldown_gates_recasts() -> void:
	stealth.cooldown = 0.2
	abilities.cast(stealth)
	abilities.cast(stealth)
	assert_false(player.is_stealthed)
	assert_false(abilities.is_ready(stealth))
	assert_gt(abilities.get_cooldown_remaining(stealth), 0.0)
	abilities.cast(stealth)
	assert_false(player.is_stealthed, "The cooldown blocks the recast")
	await wait_seconds(0.3)
	assert_true(abilities.is_ready(stealth))
	abilities.cast(stealth)
	assert_true(player.is_stealthed)


func test_a_cast_needs_the_energy_cost() -> void:
	player.health.energy = 5.0
	abilities.cast(stealth)
	assert_false(player.is_stealthed, "Stealth costs more mana than the Player has")


## A PackedScene whose root is a plain Node3D, standing in for a particle effect.
func _make_vfx() -> PackedScene:
	var node := Node3D.new()
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()
	return scene


func test_channeling_fx_run_for_the_cast_and_stop_when_interrupted() -> void:
	player.health.health = 20.0
	heal.cast_time = 1.0
	heal.channeling_vfx = _make_vfx()
	heal.channeling_sfx = AudioStreamGenerator.new()
	abilities.cast(heal)
	await wait_physics_frames(1)
	assert_eq(abilities.hand_anchor.get_child_count(), 1, "The channeling VFX rides the casting hand")
	assert_eq(abilities.fx_root.get_child_count(), 3)
	assert_true(abilities.channeling_audio.playing)
	assert_eq(abilities.channeling_audio.stream, heal.channeling_sfx)
	abilities.interrupt_cast()
	await wait_physics_frames(1)
	assert_eq(abilities.hand_anchor.get_child_count(), 0, "Interrupting frees the channeling VFX")
	assert_false(abilities.channeling_audio.playing)


func test_casting_and_impact_fx_play_when_the_effect_lands() -> void:
	player.health.health = 20.0
	heal.cast_time = 0.0
	heal.casting_vfx = _make_vfx()
	heal.impact_vfx = _make_vfx()
	heal.casting_sfx = AudioStreamGenerator.new()
	heal.impact_sfx = AudioStreamGenerator.new()
	heal.fx_lifetime = 0.2
	abilities.cast(heal)
	await wait_physics_frames(1)
	assert_eq(abilities.fx_root.get_child_count(), 5, "Casting and impact VFX are instanced")
	assert_eq(abilities.casting_audio.stream, heal.casting_sfx)
	assert_eq(abilities.impact_audio.stream, heal.impact_sfx)
	assert_true(abilities.casting_audio.playing)
	assert_true(abilities.impact_audio.playing)
	await wait_seconds(0.4)
	assert_eq(abilities.fx_root.get_child_count(), 3, "One-shot VFX free themselves after fx_lifetime")


func test_impact_lands_where_the_ability_says() -> void:
	var ranged := RangedAbility.new()
	ranged.impact_vfx = _make_vfx()
	abilities.abilities.append(ranged)
	abilities.cast(ranged)
	await wait_physics_frames(1)
	var vfx: Node3D = abilities.fx_root.get_child(3)
	assert_almost_eq(vfx.global_position, player.global_position + Vector3(0.0, 0.0, -5.0), Vector3.ONE * 0.01)


class RangedAbility extends Ability:
	func get_impact_position(caster: Node3D) -> Vector3:
		return caster.global_position + Vector3(0.0, 0.0, -5.0)


## A bolt aimed at a fixed dummy, recording every impact target.
class BoltAbility extends Ability:
	var dummy: Node3D
	var hits: Array[Node3D] = []
	func _init() -> void:
		projectile_speed = 10.0
	func get_target(_caster: Node3D) -> Node3D:
		return dummy
	func impact(_caster: Node3D, target: Node3D) -> void:
		hits.append(target)


## A crosshair-aimed spell that hurts what it lands on, standing in for the host project's DamageAbility.
class FocusBolt extends Ability:
	var damage: float = 20.0
	func _init() -> void:
		target_kinds = Kind.NEUTRAL | Kind.HOSTILE
	func impact(caster: Node3D, target: Node3D) -> void:
		if is_instance_valid(target) and target.has_method("take_hit"):
			target.take_hit(damage, caster.global_position)


func _make_bolt(at: Vector3) -> BoltAbility:
	var bolt := BoltAbility.new()
	bolt.dummy = Node3D.new()
	bolt.dummy.position = at
	player.get_parent().add_child(bolt.dummy)
	bolt.casting_vfx = _make_vfx()
	bolt.impact_vfx = _make_vfx()
	bolt.casting_sfx = AudioStreamGenerator.new()
	abilities.abilities.append(bolt)
	return bolt


func test_projectile_spell_flies_the_casting_fx_to_the_target_and_lands_impact_on_arrival() -> void:
	var bolt := _make_bolt(Vector3(4.0, 0.0, 0.0))
	abilities.cast(bolt)
	var projectile: SpellProjectile = abilities.fx_root.get_child(3)
	assert_lt(projectile.global_position.distance_to(abilities.hand_anchor.global_position), 0.05, "The bolt leaves from the casting hand")
	await wait_physics_frames(1)
	assert_true(projectile.homing, "Spell projectiles home by default")
	assert_eq(projectile.get_child_count(), 2, "The bolt carries the casting VFX next to its audio player")
	assert_eq(projectile.audio.stream, bolt.casting_sfx)
	assert_true(bolt.hits.is_empty(), "Nothing lands until the bolt arrives")
	bolt.dummy.position = Vector3(0.0, 0.0, 4.0)
	await wait_seconds(0.8)
	assert_eq(bolt.hits, [bolt.dummy] as Array[Node3D], "Impact lands on the target when the bolt arrives")
	assert_false(is_instance_valid(projectile), "The bolt frees itself on arrival")
	var impact_vfx: Node3D = abilities.fx_root.get_child(3)
	assert_lt(impact_vfx.global_position.distance_to(bolt.dummy.global_position), 1.5, "Impact VFX spawn where the moved target ended up")


func test_non_homing_bolt_flies_to_where_the_target_was() -> void:
	var bolt := _make_bolt(Vector3(4.0, 0.0, 0.0))
	bolt.projectile_homing = false
	abilities.cast(bolt)
	await wait_physics_frames(1)
	bolt.dummy.position = Vector3(0.0, 0.0, 4.0)
	await wait_seconds(0.8)
	assert_eq(bolt.hits.size(), 1)
	assert_lt(abilities.fx_root.get_child(3).global_position.distance_to(Vector3(4.0, 0.0, 0.0)), 1.5, "Impact lands at the original aim point")


func test_a_hostile_spell_falls_back_to_the_aim_point_without_a_target() -> void:
	var aimed := Ability.new()
	aimed.target_kinds = Ability.Kind.HOSTILE
	assert_null(aimed.get_target(player))
	var at: Vector3 = aimed.get_impact_position(player)
	assert_gt(at.distance_to(player.global_position), 5.0, "With nothing locked on the impact lands along the aim ray")


func test_puppets_fade_when_the_replicated_flag_arrives() -> void:
	var puppet: Player = PLAYER_SCENE.instantiate()
	puppet.name = "999"
	add_child_autofree(puppet)
	await wait_physics_frames(2)
	assert_false(puppet.is_multiplayer_authority())
	assert_false(puppet.abilities.is_processing_unhandled_input(), "Only the authority casts")
	puppet.is_stealthed = true
	await wait_seconds(puppet.stealth_look.fade_time + 0.2)
	_assert_ghosted(puppet, 1.0 - puppet.stealth_look.transparency)


func test_cast_styles_map_to_the_weapon_group_clips() -> void:
	var spell := Ability.new()
	assert_eq(spell.get_cast_state("", false), "", "No style, no clip")
	spell.cast_style = Ability.CastStyle.FORWARD
	assert_eq(spell.get_cast_state("", false), "SpellCastForwards")
	assert_eq(spell.get_cast_state("", true), "", "Unarmed has no channel loop")
	assert_eq(spell.get_cast_state("Shield", true), "Shield/ShieldSpellCasting")
	assert_eq(spell.get_cast_state("Shield", false), "Shield/ShieldSpellCast")
	assert_eq(spell.get_cast_state("GreatSword", true), "GreatSword/GreatSwordSpellCasting")
	assert_eq(spell.get_cast_state("GreatSword", false), "GreatSword/GreatSwordSpellCast")
	assert_eq(spell.get_cast_state("Rifle", false), "", "Groups without spell clips play nothing")
	spell.cast_style = Ability.CastStyle.POWER_UP
	assert_eq(spell.get_cast_state("Shield", false), "Shield/ShieldPowerUp")
	assert_eq(spell.get_cast_state("GreatSword", false), "GreatSword/GreatSwordPowerUp")
	assert_eq(spell.get_cast_state("", false), "SpellCastUpwards", "Unarmed has no power up clip; the upward cast stands in")
	spell.cast_style = Ability.CastStyle.UPWARD
	assert_eq(spell.get_cast_state("", false), "SpellCastUpwards")
	spell.cast_style = Ability.CastStyle.SWEEPING_SIDEWAYS
	assert_eq(spell.get_cast_state("", false), "SpellCastSweepingSideways")
	spell.cast_style = Ability.CastStyle.SWEEPING_UPWARD
	assert_eq(spell.get_cast_state("", false), "SpellCastSweepingUpwards")


func test_the_shipped_spells_carry_styles_and_sounds() -> void:
	assert_eq(HEAL.cast_style, Ability.CastStyle.UPWARD)
	assert_not_null(HEAL.channeling_sfx)
	assert_not_null(HEAL.casting_sfx)
	assert_eq(STEALTH.cast_style, Ability.CastStyle.SWEEPING_SIDEWAYS)
	assert_not_null(STEALTH.casting_sfx)


func _equip_shield() -> void:
	var shield := Equipment.new()
	shield.equipment_type = Equipment.EquipmentType.SWORD_AND_SHIELD
	player.get_parent().add_child(shield)
	player.inventory.add_equipment(shield)
	await wait_physics_frames(2)
	# A fresh group enters through its draw clip; skip straight to the stance
	(player.animation_tree.get("parameters/LocomotionStateMachine/Shield/playback") as AnimationNodeStateMachinePlayback).start("ShieldLocomotion")
	await wait_physics_frames(2)
	assert_eq(player.current_locomotion_path, "Shield/ShieldLocomotion")


func test_a_timed_cast_holds_the_shield_channel_then_plays_the_cast_clip() -> void:
	await _equip_shield()
	player.health.health = 20.0
	heal.cast_time = 0.4
	abilities.cast(heal)
	await wait_physics_frames(2)
	assert_eq(player.current_locomotion_path, "Shield/ShieldSpellCasting", "The channel plays for the cast time")
	assert_eq(abilities.casting, heal, "The cast's own clip never interrupts it")
	await wait_seconds(0.6)
	assert_eq(player.current_locomotion_path, "Shield/ShieldSpellCast", "The cast clip plays as the effect lands")
	assert_eq(player.health.health, 70.0)


func test_an_interrupted_channel_drops_the_pose() -> void:
	await _equip_shield()
	player.health.health = 20.0
	heal.cast_time = 1.0
	abilities.cast(heal)
	await wait_physics_frames(2)
	assert_eq(player.current_locomotion_path, "Shield/ShieldSpellCasting")
	abilities.interrupt_cast()
	await wait_physics_frames(2)
	assert_eq(player.current_locomotion_path, "Shield/ShieldLocomotion", "Back to the shield stance even while the channel was still fading in")
	assert_eq(player.health.health, 20.0)
	# And an interrupt after the fade travels back the ordinary way
	abilities.cast(heal)
	await wait_seconds(0.4)
	assert_eq(player.current_locomotion_path, "Shield/ShieldSpellCasting")
	abilities.interrupt_cast()
	await wait_physics_frames(2)
	assert_eq(player.current_locomotion_path, "Shield/ShieldLocomotion", "Back to the shield stance")


func test_an_unarmed_cast_plays_its_standing_clip_only_when_it_lands() -> void:
	player.health.health = 20.0
	heal.cast_time = 0.4
	abilities.cast(heal)
	await wait_physics_frames(2)
	assert_eq(player.current_locomotion_path, "StandingLocomotion", "Unarmed there is no channel clip")
	await wait_seconds(0.6)
	assert_eq(player.current_locomotion_path, "SpellCastUpwards", "Heal casts upward")
	stealth.cast_style = Ability.CastStyle.FORWARD
	await wait_seconds(2.5) # The upward clip has to end first
	abilities.cast(stealth)
	await wait_physics_frames(2)
	assert_eq(player.current_locomotion_path, "SpellCastForwards", "An instant cast plays its clip at once")


func test_a_cast_refused_when_it_lands_drops_the_channel_pose() -> void:
	await _equip_shield()
	player.health.health = 20.0
	heal.cast_time = 0.4
	watch_signals(abilities)
	abilities.cast(heal)
	await wait_physics_frames(2)
	assert_eq(player.current_locomotion_path, "Shield/ShieldSpellCasting")
	player.health.health = player.health.max_health # Healed by someone else meanwhile: the landing is refused
	await wait_seconds(0.6)
	assert_signal_not_emitted(abilities, "ability_activated")
	assert_signal_emitted(abilities, "cast_interrupted", "A fizzle counts as an interrupt so the pose drops")
	assert_eq(player.current_locomotion_path, "Shield/ShieldLocomotion", "No cast clip and no channel pose left behind")


func test_a_doomed_cast_is_refused_before_its_bar_runs() -> void:
	watch_signals(abilities)
	player.health.health = player.health.max_health
	heal.cast_time = 1.0
	abilities.cast(heal)
	assert_null(abilities.casting, "Heal at full health never starts channeling")
	assert_signal_not_emitted(abilities, "cast_started")
	var bolt := FocusBolt.new()
	bolt.cast_time = 1.0
	abilities.abilities.append(bolt)
	abilities.cast(bolt)
	assert_eq(abilities.casting, bolt, "A damage spell with nothing locked on still casts, forward")
	abilities.interrupt_cast()


func test_an_unarmed_channel_holds_the_ready_to_cast_emote() -> void:
	player.health.health = 20.0
	heal.cast_time = 0.4
	heal.cooldown = 0.0
	abilities.cast(heal)
	await wait_physics_frames(2)
	var emote: AnimationNodeStateMachinePlayback = player.animation_tree.get(Player.EMOTE_STATE_PLAYBACK_PATH)
	assert_eq(emote.get_current_node(), &"ReadyToCastSpell", "The upper body readies the spell while the bar runs")
	assert_eq(player.animation_tree.get("parameters/EmoteSpineBlend2/blend_amount"), 1.0)
	assert_eq(player.current_locomotion_path, "StandingLocomotion", "The legs keep the standing locomotion")
	await wait_seconds(0.6)
	assert_eq(emote.get_current_node(), &"Idle", "The pose lets go as the effect lands")
	assert_eq(player.animation_tree.get("parameters/EmoteSpineBlend2/blend_amount"), 0.0)
	assert_eq(player.current_locomotion_path, "SpellCastUpwards")
	# An interrupt lets go too
	player.health.health = 20.0
	await wait_seconds(2.5)
	abilities.cast(heal)
	await wait_physics_frames(2)
	assert_eq(emote.get_current_node(), &"ReadyToCastSpell")
	abilities.interrupt_cast()
	await wait_physics_frames(1)
	assert_eq(emote.get_current_node(), &"Idle")


## The body's meshes: everything under the skeleton but the packed-away glider, whose fabric is a shader of its own
## and so ghosts plain white.
## The body's own meshes: not the glider or the spyglass the hand carries, which wear materials of their own.
func _body_meshes(who: Player) -> Array:
	var glider: Node = who.get_node("PlayerModel/Armature/GeneralSkeleton/ParagliderBoneAttachment")
	var spyglass: Node = who.get_node("PlayerModel/Armature/GeneralSkeleton/SpyglassBoneAttachment")
	return who.skeleton.find_children("*", "MeshInstance3D").filter(func(mesh: Node) -> bool: return not glider.is_ancestor_of(mesh) and not spyglass.is_ancestor_of(mesh))


## Every surface of the body wears the ghost, a depth pass with the stealth shader after it carrying the surface's
## own colour, at [param alpha].
func _assert_ghosted(who: Player, alpha: float, text: String = "") -> void:
	for mesh: MeshInstance3D in _body_meshes(who):
		for surface: int in mesh.mesh.get_surface_count():
			var depth: ShaderMaterial = mesh.get_surface_override_material(surface) as ShaderMaterial
			assert_not_null(depth, mesh.name + " wears the ghost")
			if depth == null:
				continue
			assert_eq(depth.shader, StealthLook.STEALTH_DEPTH_SHADER, "The first pass writes the body's depth")
			var ghost: ShaderMaterial = depth.next_pass as ShaderMaterial
			assert_not_null(ghost, "and the ghost is the pass after it")
			if ghost == null:
				continue
			assert_eq(ghost.shader, StealthLook.STEALTH_SHADER)
			assert_gt(ghost.render_priority, depth.render_priority, "drawn after the depth, so only the nearest surface is coloured")
			assert_almost_eq(float(ghost.get_shader_parameter(&"alpha")), alpha, 0.02, text)
			assert_ne(ghost.get_shader_parameter(&"albedo_color"), Color.WHITE, "It keeps the surface's own colour")


func test_the_ghost_colours_only_the_nearest_surface() -> void:
	# A single see-through pass let the far arm, the far leg and the joint bands show through the torso. The depth
	# pass has to write depth however transparent the body is, and the ghost after it must not write its own.
	var depth_code: String = StealthLook.STEALTH_DEPTH_SHADER.code
	var ghost_code: String = StealthLook.STEALTH_SHADER.code
	assert_string_contains(depth_code, "depth_draw_always", "The depth pass writes depth whatever the alpha")
	assert_string_contains(depth_code, "ALPHA = 0.0", "and draws nothing itself")
	assert_string_contains(ghost_code, "depth_draw_never", "The ghost only reads the depth the first pass wrote")
	assert_false(ghost_code.contains("depth_prepass_alpha"), "and does not go back to the single pass that showed limbs through")


class HittableDummy extends Area3D: # An Area3D, so the Player's ledge rays never take the box for a wall to climb
	var hits: Array[float] = []
	func take_hit(damage: float, _from: Vector3) -> void:
		hits.append(damage)


func _put_dummy_ahead() -> HittableDummy:
	var dummy := HittableDummy.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2.0, 2.0, 2.0)
	dummy.add_child(shape)
	player.get_parent().add_child(dummy)
	var ray: RayCast3D = player.projectile_raycast # Put it on the crosshair line, four metres out
	ray.force_raycast_update()
	dummy.global_position = ray.global_position - ray.global_basis.z * 4.0
	return dummy


func test_without_a_lock_a_damage_spell_fires_at_whatever_the_crosshair_points_at() -> void:
	await wait_physics_frames(10) # Let the Player settle on the floor first
	var ray: RayCast3D = player.projectile_raycast
	var dummy := _put_dummy_ahead()
	await wait_physics_frames(2)
	dummy.global_position = ray.global_position - ray.global_basis.z * 4.0
	await wait_physics_frames(2)
	ray.force_raycast_update()
	var bolt := FocusBolt.new()
	bolt.projectile_speed = 12.0
	bolt.damage = 20.0
	abilities.abilities.append(bolt)
	assert_null(player.current_focus_target, "Nothing locked on")
	assert_eq(bolt.get_target(player), dummy, "The crosshair picks the target")
	abilities.cast(bolt)
	assert_true(abilities.fx_root.get_child(3) is SpellProjectile, "The bolt is away")
	await wait_seconds(0.8)
	assert_eq(dummy.hits, [20.0] as Array[float], "It lands on what the crosshair pointed at")


func test_without_anything_ahead_a_damage_spell_still_flies_to_the_aim_point() -> void:
	var bolt := FocusBolt.new()
	bolt.projectile_speed = 40.0
	abilities.abilities.append(bolt)
	watch_signals(abilities)
	assert_null(bolt.get_target(player))
	abilities.cast(bolt)
	assert_signal_emitted(abilities, "ability_activated", "It casts anyway")
	var projectile: SpellProjectile = abilities.fx_root.get_child(3)
	assert_null(projectile.target)
	assert_gt(projectile.destination.distance_to(player.global_position), 5.0, "It flies off along the crosshair")


## Spawn state lands on a late joiner's puppet before its skeleton exists, so the setter cannot apply the look;
## ready does it instead.
func test_a_late_joiner_sees_a_player_who_was_already_stealthed() -> void:
	var puppet: Player = PLAYER_SCENE.instantiate()
	puppet.set_multiplayer_authority(2)
	puppet.is_stealthed = true
	add_child_autofree(puppet)
	_assert_ghosted(puppet, 1.0, "The ghost is on from ready; its alpha starts its fade from 1")


## Equipment fades with the body: a sword attached at runtime has no owner, which the ghost pass used to skip,
## and a sword picked up while already stealthed is ghosted the moment it arrives.
func test_stealth_fades_the_equipment_too() -> void:
	var worn_first: Equipment = _equip_bare_piece("WornFirst", Equipment.EquipmentType.SWORD_1H, "RightHand")
	abilities.cast(stealth)
	await wait_seconds(player.stealth_look.fade_time + 0.2)
	_assert_piece_ghosted(worn_first, 1.0 - player.stealth_look.transparency, "what was in hand fades with the body")
	var worn_later: Equipment = _equip_bare_piece("WornLater", Equipment.EquipmentType.DAGGER, "LeftHand")
	await wait_seconds(player.stealth_look.fade_time + 0.2)
	_assert_piece_ghosted(worn_later, 1.0 - player.stealth_look.transparency, "and so does what is picked up meanwhile")
	abilities.cast(stealth)
	await wait_seconds(player.stealth_look.fade_time + 0.2)
	for piece: Equipment in [worn_first, worn_later]:
		for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
			assert_null(mesh.get_surface_override_material(0), "%s is solid again" % piece.name)


## A bare piece of equipment with one visible mesh, equipped on the player as a walk-over pickup would be.
func _equip_bare_piece(piece_name: String, type: Equipment.EquipmentType, bone: String) -> Equipment:
	var pickup: Equipment = Equipment.new()
	pickup.name = piece_name
	pickup.equipment_type = type
	pickup.bone_attachment_bone_name = bone
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = null
	pickup.add_child(mesh)
	add_child_autofree(pickup)
	var worn: Equipment = player.inventory.equip_pickup(pickup)
	assert_not_null(worn, piece_name + " is equipped")
	return worn


func _assert_piece_ghosted(piece: Equipment, alpha: float, text: String) -> void:
	var meshes: Array[Node] = piece.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, piece.name + " has a mesh to fade")
	for mesh: MeshInstance3D in meshes:
		var depth: ShaderMaterial = mesh.get_surface_override_material(0) as ShaderMaterial
		assert_not_null(depth, piece.name + " wears the ghost")
		var ghost: ShaderMaterial = depth.next_pass as ShaderMaterial if depth else null
		assert_not_null(ghost, piece.name + "'s ghost is the pass after its depth")
		if ghost:
			assert_almost_eq(float(ghost.get_shader_parameter(&"alpha")), alpha, 0.02, text)


## A stand-in for anything a spell can land on: it records what it was hit for and whether it was slowed.
class Dummy extends Node3D:
	var hits: Array[float] = []
	var slowed_to: float = 1.0
	var slowed_for: float = 0.0
	func take_hit(amount: float, _from: Vector3) -> void:
		hits.append(amount)
	func total() -> float:
		var sum: float = 0.0
		for h: float in hits:
			sum += h
		return sum
	func slow(factor: float, seconds: float) -> void:
		slowed_to = factor
		slowed_for = seconds


## A body that stands with the caster: a follower, a co-op partner's pet.
class FriendlyDummy extends Dummy:
	var disposition: Focus.Disposition = Focus.Disposition.FRIENDLY


func _make_dummy(at: Vector3, focusable: bool = true, friendly: bool = false) -> Dummy:
	var dummy: Dummy = FriendlyDummy.new() if friendly else Dummy.new()
	dummy.position = at
	if focusable:
		dummy.add_to_group(&"Focusable")
	add_child_autofree(dummy)
	return dummy


## The plain case: the hit lands on the target for the ability's damage, and on nothing else.
func test_a_damage_ability_hurts_what_it_lands_on() -> void:
	var bolt := DamageAbility.new()
	bolt.damage = 24.0
	var target: Dummy = _make_dummy(Vector3.ZERO)
	var bystander: Dummy = _make_dummy(Vector3(3.0, 0.0, 0.0))

	bolt.impact(player, target)

	assert_eq(target.hits, [24.0] as Array[float], "The target takes the damage")
	assert_eq(bystander.hits.size(), 0, "and nobody standing near it does")


## With a splash radius the Focusable bodies inside it the ability could be cast at take the hit as well: a
## hostile-only bolt passes the caster's friends by, and the caster never hits itself.
func test_splash_catches_the_focusable_bodies_around_the_impact() -> void:
	var bolt := DamageAbility.new()
	bolt.damage = 10.0
	bolt.splash_radius = 4.0
	var target: Dummy = _make_dummy(Vector3.ZERO)
	var near: Dummy = _make_dummy(Vector3(3.0, 0.0, 0.0))
	var far: Dummy = _make_dummy(Vector3(9.0, 0.0, 0.0))
	var unlisted: Dummy = _make_dummy(Vector3(1.0, 0.0, 0.0), false)
	var friend: Dummy = _make_dummy(Vector3(-2.0, 0.0, 0.0), true, true)
	var partner: Player = PLAYER_SCENE.instantiate()
	partner.position = Vector3(0.0, 0.0, 2.0)
	add_child_autofree(partner)

	bolt.impact(player, target)

	assert_eq(target.total(), 10.0, "The target is hit")
	assert_eq(near.total(), 10.0, "and so is what stands inside the splash")
	assert_eq(far.hits.size(), 0, "but not what stands outside it")
	assert_eq(unlisted.hits.size(), 0, "and not a body that is not Focusable")
	assert_eq(friend.hits.size(), 0, "A hostile bolt spares a friendly body in the splash")
	assert_eq(partner.health.health, partner.health.max_health, "and a co-op partner")
	assert_eq(player.health.health, player.health.max_health, "and the caster")


## A frostbolt slows what it hits, for as long as it says, through the target's own slow().
func test_a_slowing_ability_slows_what_it_hits() -> void:
	var bolt := DamageAbility.new()
	bolt.damage = 18.0
	bolt.slow_factor = 0.6
	bolt.slow_duration = 5.0
	var target: Dummy = _make_dummy(Vector3.ZERO)

	bolt.impact(player, target)

	assert_almost_eq(target.slowed_to, 0.6, 0.001, "The target is slowed to the ability's fraction")
	assert_almost_eq(target.slowed_for, 5.0, 0.001, "for the ability's duration")


## No slow set, nothing slowed: the same class is a plain bolt until it is given one.
func test_an_ability_with_no_slow_leaves_the_target_at_speed() -> void:
	var bolt := DamageAbility.new()
	var target: Dummy = _make_dummy(Vector3.ZERO)

	bolt.impact(player, target)

	assert_eq(target.slowed_to, 1.0, "Nothing took the target's speed")
	assert_eq(target.slowed_for, 0.0)


## The owner sends a phase by the ability's id and every other peer looks it up in its own copy's list (or the
## library): the owner's loadout is its own, so the same place in the list is another spell elsewhere.
func test_a_peer_plays_the_phase_of_the_ability_named_not_the_one_at_that_place() -> void:
	var first := DamageAbility.new()
	first.id = &"test_first_bolt"
	first.casting_sfx = AudioStreamGenerator.new()
	var second := DamageAbility.new()
	second.id = &"test_second_bolt"
	second.casting_sfx = AudioStreamGenerator.new()
	abilities.abilities = [second, first] # this copy's order is not the owner's
	abilities._play_phase(&"test_first_bolt", Ability.Phase.CASTING, player.global_position)
	assert_eq(abilities.casting_audio.stream, first.casting_sfx, "The ability called by the id plays")
	abilities.casting_audio.stop()
	abilities.casting_audio.stream = null
	abilities._play_phase(&"test_unknown_bolt", Ability.Phase.CASTING, player.global_position)
	assert_null(abilities.casting_audio.stream, "An id this peer cannot name plays nothing")
	assert_eq(abilities.get_ability(&"test_second_bolt"), second, "get_ability finds the caster's own by id")


## A burn keeps hurting after the hit, one tick a second, the stated damage spread over the duration.
func test_damage_over_time_ticks_after_the_hit() -> void:
	var bolt := DamageAbility.new()
	bolt.damage = 10.0
	bolt.over_time_damage = 9.0
	bolt.over_time_duration = 3.0
	var target: Dummy = _make_dummy(Vector3.ZERO)

	bolt.impact(player, target)
	assert_eq(target.hits.size(), 1, "The hit itself lands at once")

	await wait_seconds(3.4)

	assert_eq(target.hits.size(), 4, "and three ticks follow it, one a second")
	assert_almost_eq(target.total(), 19.0, 0.01, "The burn deals what it says over the duration")


## The details a spells screen reads out name every part the ability actually has, and nothing it does not.
func test_the_details_read_out_every_part_the_ability_has() -> void:
	var plain := DamageAbility.new()
	plain.damage = 30.0
	var plain_details: String = plain.get_details()
	assert_string_contains(plain_details, "Damage: 30")
	assert_false(plain_details.contains("Slows"), "A plain bolt does not claim a slow")
	assert_false(plain_details.contains("Splash"), "nor a splash")

	var frost := DamageAbility.new()
	frost.damage = 18.0
	frost.splash_radius = 3.0
	frost.slow_factor = 0.6
	frost.slow_duration = 5.0
	frost.over_time_damage = 9.0
	frost.over_time_duration = 3.0
	var frost_details: String = frost.get_details()
	assert_string_contains(frost_details, "Damage: 18")
	assert_string_contains(frost_details, "Splash: 3 m")
	assert_string_contains(frost_details, "Damage over time: 9 over 3 s")
	assert_string_contains(frost_details, "Slows to 60% for 5 s")


## A damage spell an NPC has no target for is not cast at all, so no cooldown is spent on nothing; a Player
## always may, because the crosshair sends it wherever it is aimed.
func test_an_npc_needs_a_target_before_it_can_cast_a_bolt() -> void:
	var bolt := DamageAbility.new()
	var npc := Node3D.new()
	add_child_autofree(npc)

	assert_false(bolt.can_cast(npc), "Nothing to send it at")
	assert_true(bolt.can_cast(player), "The Player aims it with the crosshair")


## set_progress takes a ratio, but a ProgressBar's own range is 0 to 100 by default, so passing the ratio
## straight through left the bar looking empty through a whole cast. Caught on screen rather than by a test,
## which is why there is one now.
func test_the_cast_bar_fills_by_the_ratio_it_is_given() -> void:
	var bar: ProgressBar = player.cast_bar.bar
	player.cast_bar.show_cast("Heal")
	assert_eq(bar.value, 0.0, "It starts empty")

	player.cast_bar.set_progress(0.5)
	assert_almost_eq(bar.value / bar.max_value, 0.5, 0.001, "Half way through the cast is a half-full bar")

	player.cast_bar.set_progress(1.0)
	assert_almost_eq(bar.value, bar.max_value, 0.001, "and the end of the cast fills it")

	player.cast_bar.hide_cast()
	assert_false(bar.visible, "The cast over, the bar goes")
