class_name Abilities
extends CanvasLayer
## World of Warcraft style ability caster: tap "ability" to cast the picked ability, hold it to pick another from the wheel.
##
## Timed casts fill the cast bar; movement input, state and locomotion changes interrupt them unless the
## ability sets [member Ability.channel_while_moving], and attacks always do. Walking has no signal (the
## standing blend space absorbs it), so movement input is polled only while such a cast runs. Abilities with a
## [member Ability.projectile_speed] send their casting VFX/SFX flying as a [SpellProjectile] and land the
## impact on arrival, so nothing depends on physics contacts. Toggles (Stealth)
## stay on until cast again or, with [member Ability.ends_on_attack], until the Player attacks or fires.
## Cooldowns are stored as end times (toggles start theirs when they end), so nothing polls. Only the authority reads input;
## each phase's VFX/SFX is played on every peer through an RPC, and effects that must be seen by
## other peers (like [member Player.is_stealthed]) are replicated by the Player.

signal ability_activated(ability: Ability) ## Emitted when an ability's effect lands.
signal ability_deactivated(ability: Ability) ## Emitted when a toggle ends.
signal cast_started(ability: Ability) ## Emitted when a timed cast begins.
signal cast_interrupted(ability: Ability) ## Emitted when a timed cast breaks before landing.

const PROJECTILE_HEIGHT: float = 1.2 ## Bolts leave the caster at chest height.

@export var player: Player
@export var fx_root: Node3D ## Under the Player; phase VFX are instanced here.
@export var hand_anchor: Node3D ## The casting hand (a bone attachment): channeling VFX ride it and bolts leave from it. Without one they sit at the caster's feet and chest.
@export var channeling_audio: AudioStreamPlayer3D
@export var casting_audio: AudioStreamPlayer3D
@export var impact_audio: AudioStreamPlayer3D

const FX_ROOT_PATH: NodePath = ^"SFX_Ability" ## Where [member fx_root] and the three audio players are looked for under the Player when not wired.
const HAND_ANCHOR_PATH: NodePath = ^"PlayerModel/Armature/GeneralSkeleton/SpellHand"


## Fills whichever of [member fx_root], [member hand_anchor] and the audio players is not wired from the Player's
## own nodes: SFX_Ability with its ChannelingAudio, CastingAudio and ImpactAudio, and the SpellHand attachment.
func _wire_from_player() -> void:
	if player == null:
		return
	if fx_root == null:
		fx_root = player.get_node_or_null(FX_ROOT_PATH) as Node3D
	if hand_anchor == null:
		hand_anchor = player.get_node_or_null(HAND_ANCHOR_PATH) as Node3D
	if fx_root:
		if channeling_audio == null:
			channeling_audio = fx_root.get_node_or_null(^"ChannelingAudio") as AudioStreamPlayer3D
		if casting_audio == null:
			casting_audio = fx_root.get_node_or_null(^"CastingAudio") as AudioStreamPlayer3D
		if impact_audio == null:
			impact_audio = fx_root.get_node_or_null(^"ImpactAudio") as AudioStreamPlayer3D
@export var abilities: Array[Ability] = [] ## Abilities on the wheel; the first is picked at start.
@export var active_ability: Ability: ## The ability a tap of "ability" casts; the wheel changes it.
	set(value):
		active_ability = value
		if player and player.controls:
			_update_label()

var casting: Ability ## The ability whose cast time is running, if any.
var active_toggles: Array[Ability] = []
var _cooldown_ends: Dictionary[Ability, int] = {} ## Ability -> Time.get_ticks_msec() when it is ready again.
var _cast_tween: Tween
var _channeling_vfx: Node3D

@onready var hold_timer: Timer = $HoldTimer ## Separates a tap (cast) from a hold (wheel).
@onready var cast_timer: Timer = $CastTimer ## Runs an ability's cast time; its timeout lands the effect.
@onready var radial_menu: RadialMenu = $RadialMenu


func _ready() -> void:
	_wire_from_player()
	_take_from_library()
	set_physics_process(false)
	set_process_unhandled_input(is_multiplayer_authority())
	if not is_multiplayer_authority():
		return
	radial_menu.custom_item_provider = get_wheel_items
	radial_menu.custom_item_selected = _on_wheel_item_selected
	radial_menu.custom_item_is_equipped = _is_wheel_item_active
	if active_ability == null and not abilities.is_empty():
		active_ability = abilities[0]
	# The Player's Controls exist once the Player itself is ready
	player.ready.connect(_update_label, CONNECT_ONE_SHOT)


func _unhandled_input(event: InputEvent) -> void:
	# A menu or the chat blocks the button, as the Inventory's does: in multiplayer the tree is not paused
	if player == null or player.is_paused or player.is_typing or player.riding_blocks_hands() or player.held_object.is_holding_object():
		hold_timer.stop()
		return

	if event.is_action_pressed(&"ability"):
		hold_timer.start()
	elif event.is_action_released(&"ability"):
		# A release while the timer still runs is a tap; a timeout already opened the wheel.
		if hold_timer.is_stopped():
			return
		hold_timer.stop()
		cast(active_ability)


## The scene's [AbilityLibrary], when it has one: every ability here becomes the library's loaded copy of the same
## id, so each caster shares the one warm instance. Without a library the resources stay as set.
func _take_from_library() -> void:
	var library: AbilityLibrary = AbilityLibrary.find(self)
	if library == null:
		return
	for i: int in abilities.size():
		abilities[i] = library.resolve(abilities[i])
	if active_ability:
		active_ability = library.resolve(active_ability)


## Casts the ability called [param id]: one of this caster's own, else the library's. Nothing happens when nobody
## knows the name.
func cast_id(id: StringName) -> void:
	cast(get_ability(id))


## The ability called [param id]: one of this caster's own, else the scene's [AbilityLibrary]'s; null when nobody
## knows the name.
func get_ability(id: StringName) -> Ability:
	for ability: Ability in abilities:
		if ability and ability.get_id() == id:
			return ability
	var library: AbilityLibrary = AbilityLibrary.find(self)
	return library.get_ability(id) if library else null


## Casts [param ability] now, starts its cast bar, or ends it when it is an active toggle. [param at] names what
## it lands on in place of the focus and the aim ([method Ability.aim_at]), a test range's choice; a game cast leaves
## it empty and the ability's own targeting decides.
func cast(ability: Ability, at: Node3D = null) -> void:
	if ability == null:
		return
	if active_toggles.has(ability):
		deactivate(ability)
		return
	if casting or not is_ready(ability):
		return
	Ability.aim_at(player, at)
	if player.health.energy < ability.energy_cost or not ability.can_cast(player):
		Ability.aim_at(player, null) # refused: the chosen body is forgotten with it
		return
	if ability.cast_time <= 0.0:
		_activate(ability)
		return
	casting = ability
	cast_timer.start(ability.cast_time)
	set_physics_process(not ability.channel_while_moving)
	if player.cast_bar:
		player.cast_bar.show_cast(ability.display_name)
		_cast_tween = create_tween()
		_cast_tween.tween_property(player.cast_bar.bar, "value", player.cast_bar.bar.max_value, ability.cast_time)
	_play(ability, Ability.Phase.CHANNELING, _hand_position())
	cast_started.emit(ability)


func is_ready(ability: Ability) -> bool:
	return Time.get_ticks_msec() >= _cooldown_ends.get(ability, 0)


## Seconds left on [param ability]'s cooldown; 0 when it is ready.
func get_cooldown_remaining(ability: Ability) -> float:
	return maxf(0.0, (_cooldown_ends.get(ability, 0) - Time.get_ticks_msec()) / 1000.0)


func interrupt_cast() -> void:
	if casting == null:
		return
	var ability: Ability = casting
	casting = null
	set_physics_process(false)
	cast_timer.stop()
	_hide_cast_bar()
	_stop_channeling.rpc()
	Ability.aim_at(player, null)
	cast_interrupted.emit(ability)


## Ends an active toggle; its cooldown runs from here, like leaving Stealth.
func deactivate(ability: Ability) -> void:
	if not active_toggles.has(ability):
		return
	active_toggles.erase(ability)
	_cooldown_ends[ability] = Time.get_ticks_msec() + int(ability.cooldown * 1000.0)
	ability.deactivate(player)
	ability_deactivated.emit(ability)


func get_wheel_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for ability: Ability in abilities:
		items.append({"display_name": ability.display_name, "icon": ability.icon, "icon_color": ability.icon_color, "item": ability})
	return items


## Lands the effect; false when the ability refused (nothing to aim at, full health), spending nothing.
func _activate(ability: Ability) -> bool:
	if not ability.activate(player):
		return false
	player.health.spend_energy(ability.energy_cost)
	if ability.is_toggle:
		active_toggles.append(ability)
	else:
		_cooldown_ends[ability] = Time.get_ticks_msec() + int(ability.cooldown * 1000.0)
	var target: Node3D = ability.get_target(player)
	var target_path: NodePath = target.get_path() if is_instance_valid(target) else NodePath()
	if ability.projectile_speed > 0.0:
		# The bolt carries the casting phase; the authority's copy lands the impact when it arrives
		_play(ability, Ability.Phase.CASTING, _bolt_origin(), target_path, ability.get_impact_position(player))
	else:
		_play(ability, Ability.Phase.CASTING, player.global_position)
		_land(ability, target, ability.get_impact_position(player))
	Ability.aim_at(player, null)
	ability_activated.emit(ability)
	return true


## Where channeling VFX sit: the casting hand, or the caster's feet without one.
func _hand_position() -> Vector3:
	return hand_anchor.global_position if is_instance_valid(hand_anchor) else player.global_position


## Where a bolt leaves: the casting hand, or chest height without one.
func _bolt_origin() -> Vector3:
	return hand_anchor.global_position if is_instance_valid(hand_anchor) else player.global_position + player.up_direction * PROJECTILE_HEIGHT


## The impact phase: the ability's effect on the target, then its impact VFX/SFX. An ability that reports
## `hit_anything` (a melee swing) plays no impact when it whiffed: no sound, no elements at the caster's feet.
func _land(ability: Ability, target: Node3D, at: Vector3) -> void:
	ability.impact(player, target)
	if ability.get(&"hit_anything") == false:
		return
	_play(ability, Ability.Phase.IMPACT, at)


func _hide_cast_bar() -> void:
	if _cast_tween:
		_cast_tween.kill()
	if player.cast_bar:
		player.cast_bar.hide_cast()


## The picked ability names whichever button casts it, wherever the layout put the action. A layout whose game
## had no such button carries no [code]ability[/code] slot at all, and then there is nothing to name.
func _update_label() -> void:
	var label: Label = player.controls.action_label(&"ability")
	if label == null:
		return
	if active_ability:
		label.text = active_ability.display_name
	else:
		player.controls.reset_labels() # nothing in hand: the button keeps the layout's own word for it (Ability, Cast)


## Only runs during a cast that movement may break.
func _physics_process(_delta: float) -> void:
	if player.player_input.motion.length() > 0.0:
		interrupt_cast()


func _on_cast_timer_timeout() -> void:
	var ability: Ability = casting
	casting = null
	set_physics_process(false)
	_hide_cast_bar()
	_stop_channeling.rpc()
	if not _activate(ability):
		cast_interrupted.emit(ability) # Fizzled at the end of the cast: the channel pose has to drop


## Plays a phase's VFX/SFX here and on every other peer. The ability travels by id ([method Ability.get_id]) and
## each peer looks it up again ([method get_ability]): the owner's loadout is its own (a spellbook rearranges it there
## alone), so a place in [member abilities] means something else on every other peer.
func _play(ability: Ability, phase: Ability.Phase, at: Vector3, target_path: NodePath = NodePath(), destination: Vector3 = Vector3.ZERO) -> void:
	_spawn_phase(ability, phase, at, target_path, destination)
	_play_phase.rpc(ability.get_id(), phase, at, target_path, destination)


## The owner's phase on another peer; an ability that peer cannot name (no library, and not on its copy's own list)
## plays nothing there.
@rpc("authority", "call_remote", "reliable")
func _play_phase(id: StringName, phase: Ability.Phase, at: Vector3, target_path: NodePath = NodePath(), destination: Vector3 = Vector3.ZERO) -> void:
	var ability: Ability = get_ability(id)
	if ability:
		_spawn_phase(ability, phase, at, target_path, destination)


func _spawn_phase(ability: Ability, phase: Ability.Phase, at: Vector3, target_path: NodePath, destination: Vector3) -> void:
	var audio: AudioStreamPlayer3D = [channeling_audio, casting_audio, impact_audio][phase]
	# Channeling VFX are parented to the hand so they follow it through the cast
	var parent: Node3D = hand_anchor if phase == Ability.Phase.CHANNELING and is_instance_valid(hand_anchor) else fx_root
	var node: Node3D = ability.spawn_phase(phase, at, parent, audio, get_node_or_null(target_path), destination)
	if phase == Ability.Phase.CASTING and node is SpellProjectile and is_multiplayer_authority():
		# Only the caster's copy lands the impact
		(node as SpellProjectile).arrived.connect(_on_bolt_arrived.bind(ability, target_path))
	elif phase == Ability.Phase.CHANNELING:
		_channeling_vfx = node


func _on_bolt_arrived(at: Vector3, ability: Ability, target_path: NodePath) -> void:
	_land(ability, get_node_or_null(target_path), at)


@rpc("authority", "call_local", "reliable")
func _stop_channeling() -> void:
	if channeling_audio:
		channeling_audio.stop()
	if is_instance_valid(_channeling_vfx):
		_channeling_vfx.queue_free()
	_channeling_vfx = null


func _on_wheel_item_selected(item: Dictionary, _index: int) -> void:
	active_ability = item["item"]


func _is_wheel_item_active(item: Dictionary, _index: int) -> bool:
	return item["item"] == active_ability


## Wired to the Player's state_changed; movement breaks a cast unless the ability channels while moving.
func _on_state_changed(_from_state: int, _to_state: int) -> void:
	if casting and not casting.channel_while_moving:
		interrupt_cast()


## Wired to the Player's locomotion_node_changed; attacks always interrupt and end toggles that end on attack.
func _on_locomotion_node_changed(state_path: String) -> void:
	var node_name: String = state_path.get_file()
	if node_name.contains("SpellCast") or node_name.ends_with("PowerUp"):
		return # The cast's own clips
	var is_attack: bool = node_name in Attacking.ATTACK_NODES or node_name == "BowFireArrow"
	if casting and (is_attack or not casting.channel_while_moving):
		interrupt_cast()
	if is_attack:
		_end_attack_toggles()


## Wired to the Inventory's equipment_changed; firearms report shots through their fired signal.
func _on_equipment_changed() -> void:
	for item: Equipment in player.inventory.equipment:
		if item is Firearm and not item.fired.is_connected(_on_weapon_fired):
			item.fired.connect(_on_weapon_fired)


func _on_weapon_fired(_projectile: Projectile) -> void:
	_end_attack_toggles()


func _end_attack_toggles() -> void:
	for ability: Ability in active_toggles.duplicate():
		if ability.ends_on_attack:
			deactivate(ability)
