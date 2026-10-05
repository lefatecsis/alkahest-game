class_name WeaponAudio
extends Node3D
## The Player's weapon one-shots: an [AudioStreamPlayer3D] per slot (EquipAudio, StowAudio, AttackAudio, HitAudio),
## each with a default stream set in player.tscn (the TomMusic sword set as [AudioStreamRandomizer] resources under
## [code]resources/audio/[/code]). An [Equipment]'s [member Equipment.equip_sfx], [member Equipment.stow_sfx],
## [member Equipment.attack_sfx] and [member Equipment.hit_sfx] stand in for the defaults on that weapon (a [Bow]
## brings its own take-out and put-away; its shot travels with the arrow instead, see [Bow]).
##
## The draw and stow defaults are a blade leaving and entering a scabbard, so only metal melee weapons (an axe, a
## dagger, a sword, see [constant BLADED_TYPES]) fall back to them: a staff, a rod, a gun or a shield draws in
## silence unless its scene names its own sounds.
##
## Wired in player.tscn: [code]Inventory.equipment_changed[/code] (drawn and stowed), [signal Player.locomotion_node_changed]
## (a weapon swing node) and [signal HitDetection.weapon_hit] (a swing landing on something that takes a hit).
##
## Multiplayer: a peer's copy of the Player carries the authority's equipment, rebuilt from the inventory's synced
## equipment, so a draw or a stow plays wherever that copy's equipment changes; a swing node arrives on every peer
## with the animation, so the attack sound plays everywhere; a hit is registered on the authority and relayed by
## [method _play_hit] with [code]call_local[/code], the way [Abilities] sends its casting sounds.

const UNARMED_NODES: Array[String] = ["ShortHeadJab", "BackHandCross"] ## Boxing swings: no weapon to hear.
## The metal melee weapons: the only equipment whose draw and stow fall back to the sword unsheath and sheath.
const BLADED_TYPES: Array[Equipment.EquipmentType] = [
	Equipment.EquipmentType.AXE_1H,
	Equipment.EquipmentType.AXE_2H,
	Equipment.EquipmentType.DAGGER,
	Equipment.EquipmentType.SWORD_1H,
	Equipment.EquipmentType.SWORD_2H,
	Equipment.EquipmentType.SWORD_AND_SHIELD,
]

@export var player: Player

var _equipped: Array[Equipment] = [] ## The equipment set last seen, so a change tells a draw from a stow.
var _defaults: Dictionary[AudioStreamPlayer3D, AudioStream] = {} ## Each slot's scene stream, used when a weapon names none.

var armed: bool = false ## Off until the scene-wired SettleTimer runs out, so the kit and a saved loadout arriving at spawn draw and stow in silence.

@onready var equip_audio: AudioStreamPlayer3D = $EquipAudio
@onready var stow_audio: AudioStreamPlayer3D = $StowAudio
@onready var attack_audio: AudioStreamPlayer3D = $AttackAudio
@onready var hit_audio: AudioStreamPlayer3D = $HitAudio


func _ready() -> void:
	for audio: AudioStreamPlayer3D in [equip_audio, stow_audio, attack_audio, hit_audio]:
		_defaults[audio] = audio.stream
	if player and player.inventory:
		_equipped.assign(player.inventory.equipment)


## Wired to Inventory.equipment_changed: what joined the set was drawn, what left it was stowed. Changes before this
## node is ready (a saved loadout coming back in the Inventory's own ready) or before the SettleTimer has run out
## (the spawn kit being granted and stowed) only update the snapshot and make no sound.
func _on_equipment_changed() -> void:
	if not is_node_ready() or player == null or player.inventory == null:
		return
	var now: Array[Equipment] = []
	now.assign(player.inventory.equipment)
	if not armed:
		_equipped = now
		return
	for item: Equipment in now:
		if item not in _equipped:
			_play(equip_audio, item.equip_sfx, is_bladed(item))
	for item: Equipment in _equipped:
		if is_instance_valid(item) and item not in now:
			_play(stow_audio, item.stow_sfx, is_bladed(item))
	_equipped = now


## A metal melee weapon, the kind the default sheath sounds were recorded for.
static func is_bladed(item: Equipment) -> bool:
	return item != null and item.equipment_type in BLADED_TYPES


## Wired to the SettleTimer: from here on equipment changes are the player's own doing and are heard.
func _on_settle_timer_timeout() -> void:
	armed = true


## Wired to Player.locomotion_node_changed, on every peer: a weapon swing node plays the attack sound.
func _on_locomotion_node_changed(state_path: String) -> void:
	var node: String = state_path.get_file()
	if node in HitDetection.SWING_NODES and node not in UNARMED_NODES:
		play_attack(_weapon_stream(&"attack_sfx"))


## Wired to HitDetection.weapon_hit: a weapon landing on something with [code]take_hit[/code] rings out on every peer.
## Fists make no sound, and neither do hits on things that only take weapon hits (a tree, a rock).
func _on_weapon_hit(equipment: Node, target: Node) -> void:
	if not equipment is Equipment or not target.has_method("take_hit"):
		return
	var stream: AudioStream = (equipment as Equipment).hit_sfx
	_play_hit.rpc(stream.resource_path if stream else "")


## Plays the attack slot: [param stream], or the scene default without one.
func play_attack(stream: AudioStream = null) -> void:
	_play(attack_audio, stream)


@rpc("authority", "call_local", "reliable")
func _play_hit(stream_path: String) -> void:
	_play(hit_audio, load(stream_path) as AudioStream if not stream_path.is_empty() else null)


## The equipped melee weapon's own stream for [param property] when it names one; null (the default) otherwise.
func _weapon_stream(property: StringName) -> AudioStream:
	if player == null or player.inventory == null:
		return null
	for item: Equipment in player.inventory.equipment:
		var stream: AudioStream = item.get(property) as AudioStream
		if item.can_attack and stream:
			return stream
	return null


## Plays [param stream] on the slot, or with none the slot's scene default when [param fall_back] allows; without
## either the slot stays quiet.
func _play(audio: AudioStreamPlayer3D, stream: AudioStream, fall_back: bool = true) -> void:
	audio.stream = stream if stream else (_defaults.get(audio) if fall_back else null)
	if audio.stream:
		audio.play()
