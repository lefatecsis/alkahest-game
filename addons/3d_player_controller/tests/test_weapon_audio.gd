extends GutTest

## Purpose: the Player's WeaponAudio plays the TomMusic weapon one-shots on events that already happen: a drawn sword
## unsheathes and a stowed one sheathes, a bow takes out and puts away, a weapon swing node plays the attack (a punch
## does not), a hit on something that takes damage plays the impact (a prop or a fist does not), a weapon's own streams
## replace the defaults, a bow's release sound (its scene's own, else the bow attack) travels with the arrow and plays
## where it left, and a landing arrow plays its impact.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const SWORD_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/demo/wooden_sword.tscn")
const ARROW_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/arrow.tscn")
const ARROW_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/arrow.gd")
const AUDIO_DIR: String = "res://addons/3d_player_controller/resources/audio/"
const BOW_DIR: String = "res://addons/3d_player_controller/assets/tommusic/fantasy_sfx/Attacks/Bow Attacks Hits and Blocks/"


class Dummy extends CharacterBody3D:
	var hits: int = 0

	func take_hit(_damage: float, _from: Vector3) -> void:
		hits += 1

	func register_weapon_hit(_equipment: Node, _hit_node: Node) -> void:
		hits += 1


class Prop extends StaticBody3D:
	func register_weapon_hit(_equipment: Node, _hit_node: Node) -> void:
		pass


var root: Node3D
var player: Player
var audio: WeaponAudio
var hit_detection: HitDetection


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	audio = player.weapon_audio
	hit_detection = player.get_node("HitDetection")
	await wait_physics_frames(2)
	audio.armed = true # Past the spawn settle window; the settle test below arms itself


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
		root = null


func _equip_sword() -> Equipment:
	var pickup: Equipment = SWORD_SCENE.instantiate()
	root.add_child(pickup)
	return player.inventory.equip_pickup(pickup)


## A bow on the Player with a template arrow and three arrows to shoot, as test_bow_throw builds one.
func _make_bow(with_release_node: bool) -> Bow:
	var bow := Bow.new()
	bow.equipment_type = Equipment.EquipmentType.BOW
	var template := RigidBody3D.new()
	template.name = "Arrow"
	template.set_script(ARROW_SCRIPT)
	bow.add_child(template)
	if with_release_node:
		var release := AudioStreamPlayer3D.new()
		release.name = "BowFireArrow"
		release.stream = load(AUDIO_DIR + "bow_impact.tres") as AudioStream # any sound saved in a file of its own
		bow.add_child(release)
	bow.player = player
	root.add_child(bow)
	player.inventory.add_equipment(bow)
	player.inventory.can_player_shoot = true
	var quiver := AmmoItem.new()
	quiver.id = &"test_arrow"
	quiver.weapon_type = Equipment.EquipmentType.BOW
	quiver.rounds_per_unit = 1
	player.inventory.add_item(quiver, 3)
	return bow


func test_the_player_carries_a_player_per_slot_with_the_sword_defaults() -> void:
	assert_not_null(audio, "player.tscn has a WeaponAudio")
	var expected: Dictionary = {
		audio.equip_audio: ["sword_unsheath.tres", 2],
		audio.stow_audio: ["sword_sheath.tres", 2],
		audio.attack_audio: ["sword_attack.tres", 3],
		audio.hit_audio: ["sword_impact.tres", 3],
	}
	for slot: AudioStreamPlayer3D in expected:
		var randomizer: AudioStreamRandomizer = slot.stream as AudioStreamRandomizer
		assert_not_null(randomizer, slot.name + " picks from a set")
		assert_eq(randomizer.resource_path, AUDIO_DIR + expected[slot][0], slot.name + " defaults to the TomMusic sword set")
		assert_eq(randomizer.streams_count, expected[slot][1], slot.name + " carries every variant")
		assert_eq(slot.bus, &"SFX")
		assert_false(slot.playing, slot.name + " is quiet at spawn")


func test_drawing_a_sword_unsheathes_and_stowing_it_sheathes() -> void:
	var sword: Equipment = _equip_sword()
	assert_not_null(sword, "The sword is equipped")
	assert_true(audio.equip_audio.playing, "Drawing plays the unsheath")
	assert_eq(audio.equip_audio.stream.resource_path, AUDIO_DIR + "sword_unsheath.tres")
	assert_false(audio.stow_audio.playing, "Nothing was stowed")
	player.inventory.stow_equipment(sword)
	assert_true(audio.stow_audio.playing, "Stowing plays the sheath")
	assert_eq(audio.stow_audio.stream.resource_path, AUDIO_DIR + "sword_sheath.tres")


func test_a_bow_takes_out_and_puts_away() -> void:
	var bow := Bow.new()
	bow.equipment_type = Equipment.EquipmentType.BOW
	root.add_child(bow)
	assert_eq(bow.equip_sfx.resource_path, AUDIO_DIR + "bow_take_out.tres", "The bow brings its own draw")
	assert_eq(bow.stow_sfx.resource_path, AUDIO_DIR + "bow_put_away.tres", "and put-away")
	assert_eq(bow.attack_sfx.resource_path, AUDIO_DIR + "bow_attack.tres", "and shot")
	player.inventory.add_equipment(bow)
	assert_true(audio.equip_audio.playing, "Equipping the bow plays")
	assert_eq(audio.equip_audio.stream.resource_path, AUDIO_DIR + "bow_take_out.tres", "the bow's take-out, not the sword's")
	player.inventory.remove_equipment(bow)
	assert_true(audio.stow_audio.playing, "Unequipping the bow plays")
	assert_eq(audio.stow_audio.stream.resource_path, AUDIO_DIR + "bow_put_away.tres", "the bow's put-away")


func test_a_weapon_swing_node_plays_the_attack_and_a_punch_does_not() -> void:
	player.locomotion_node_changed.emit("GreatSword/GreatSwordDownwardSlash")
	assert_true(audio.attack_audio.playing, "A swing node reaching the Player plays the attack, on every peer")
	assert_eq(audio.attack_audio.stream.resource_path, AUDIO_DIR + "sword_attack.tres")
	audio.attack_audio.stop()
	for node: String in ["ShieldCrossSlash", "GreatSwordPowerSlash"]:
		audio._on_locomotion_node_changed(node)
		assert_true(audio.attack_audio.playing, node + " is a weapon swing")
		audio.attack_audio.stop()
	for node: String in ["ShortHeadJab", "BackHandCross", "Standing", "Bow/BowDrawArrow"]:
		audio._on_locomotion_node_changed(node)
		assert_false(audio.attack_audio.playing, node + " is not a weapon swing")


func test_a_hit_on_something_that_takes_damage_plays_the_impact() -> void:
	var sword: Equipment = _equip_sword()
	var hitbox: Area3D = sword.get_node("Hitbox")
	var dummy := Dummy.new()
	root.add_child(dummy)
	watch_signals(hit_detection)
	hit_detection._on_hitbox_body_entered(dummy, hitbox, sword)
	assert_signal_emitted_with_parameters(hit_detection, "weapon_hit", [sword, dummy])
	assert_true(audio.hit_audio.playing, "A registered weapon hit on a body with take_hit rings out")
	assert_eq(audio.hit_audio.stream.resource_path, AUDIO_DIR + "sword_impact.tres")
	audio.hit_audio.stop()

	hit_detection._on_locomotion_node_changed("Standing") # a new swing forgets the last targets
	var prop := Prop.new()
	root.add_child(prop)
	hit_detection._on_hitbox_body_entered(prop, hitbox, sword)
	assert_signal_emitted_with_parameters(hit_detection, "weapon_hit", [sword, prop])
	assert_false(audio.hit_audio.playing, "A prop that only takes weapon hits (a tree, a rock) makes no clang")

	hit_detection._on_locomotion_node_changed("ShortHeadJab")
	hit_detection._on_hitbox_body_entered(dummy, hit_detection.right_hand_hitbox, null)
	assert_signal_emitted_with_parameters(hit_detection, "weapon_hit", [player, dummy])
	assert_false(audio.hit_audio.playing, "Fists are not a sword")


func test_a_weapons_own_streams_replace_the_defaults() -> void:
	var sword: Equipment = _equip_sword()
	sword.attack_sfx = load(AUDIO_DIR + "bow_attack.tres")
	sword.hit_sfx = load(AUDIO_DIR + "bow_impact.tres")
	audio._on_locomotion_node_changed("ShieldDownwardSlash")
	assert_eq(audio.attack_audio.stream.resource_path, AUDIO_DIR + "bow_attack.tres", "The equipped weapon's attack_sfx plays for its swing")
	var dummy := Dummy.new()
	root.add_child(dummy)
	hit_detection._on_hitbox_body_entered(dummy, sword.get_node("Hitbox"), sword)
	assert_eq(audio.hit_audio.stream.resource_path, AUDIO_DIR + "bow_impact.tres", "and its hit_sfx for its hit")
	assert_true(audio.hit_audio.playing)
	player.inventory.stow_equipment(sword)
	audio.attack_audio.stop()
	audio._on_locomotion_node_changed("ShieldDownwardSlash")
	assert_eq(audio.attack_audio.stream.resource_path, AUDIO_DIR + "sword_attack.tres", "Stowed, the default is back")


## The release sound goes with the arrow, as a gun's shot goes with its round ([method Projectile.play_launch_sfx]):
## the speaker stands where the arrow left, on every peer that builds the arrow, rather than on the shooter's alone.
func test_a_shot_sends_the_bow_attack_with_the_arrow_unless_the_bow_scene_brings_a_release_sound() -> void:
	var bow: Bow = _make_bow(false)
	await wait_physics_frames(1)
	bow._on_locomotion_node_changed("Bow/BowFireArrow")
	var speakers: Array[Node] = get_tree().root.find_children("LaunchSfx", "AudioStreamPlayer3D", true, false)
	assert_eq(speakers.size(), 1, "The shot plays beside the arrow it sent")
	assert_eq((speakers[0] as AudioStreamPlayer3D).stream.resource_path, AUDIO_DIR + "bow_attack.tres", "with the bow attack")
	assert_false(audio.attack_audio.playing, "and not through the Player's attack slot, which only this peer would hear")
	for speaker: Node in speakers:
		speaker.free()
	player.inventory.remove_equipment(bow)
	bow.queue_free()

	var scene_bow: Bow = _make_bow(true)
	await wait_physics_frames(1)
	scene_bow._on_locomotion_node_changed("Bow/BowFireArrow")
	speakers = get_tree().root.find_children("LaunchSfx", "AudioStreamPlayer3D", true, false)
	assert_eq(speakers.size(), 1, "A bow with its own BowFireArrow node sends that sound instead, once")
	assert_eq((speakers[0] as AudioStreamPlayer3D).stream.resource_path, AUDIO_DIR + "bow_impact.tres")
	assert_false((scene_bow.get_node("BowFireArrow") as AudioStreamPlayer3D).playing, "The node itself stays quiet")
	for speaker: Node in speakers:
		speaker.free()
	for arrow: Node in get_tree().root.find_children("*", "RigidBody3D", true, false).filter(func(n: Node) -> bool: return n is Arrow and not (n as Arrow).is_template):
		arrow.free()


func test_a_landing_arrow_plays_its_impact() -> void:
	var arrow: Arrow = ARROW_SCENE.instantiate()
	root.add_child(arrow)
	var impact: AudioStreamPlayer3D = arrow.get_node("Impact")
	assert_eq(impact.stream.resource_path, AUDIO_DIR + "bow_impact.tres", "The arrow carries the bow impact set")
	assert_true((arrow.get_node("Swish") as AudioStreamPlayer3D).autoplay, "The flight swish still autoplays")
	assert_false(impact.playing, "Quiet in flight")
	var wall := StaticBody3D.new()
	root.add_child(wall)
	arrow._apply_hit(wall, Vector3.ZERO, Vector3.UP)
	assert_true(arrow.has_hit)
	assert_true(impact.playing, "Landing plays the impact, on every peer that simulates the round")


func test_the_spawn_kit_arrives_in_silence_and_later_changes_are_heard() -> void:
	audio.armed = false
	var timer: Timer = audio.get_node("SettleTimer")
	assert_true(timer.one_shot, "The settle window is a scene-wired one-shot timer")
	assert_false(timer.is_stopped(), "counting down from spawn (autostart clears itself once the timer has entered the tree)")
	assert_true(timer.timeout.is_connected(audio._on_settle_timer_timeout))
	var sword: Equipment = _equip_sword()
	assert_not_null(sword)
	assert_false(audio.equip_audio.playing, "Equipment granted at spawn makes no sound")
	player.inventory.stow_equipment(sword)
	assert_false(audio.stow_audio.playing, "nor does stowing the kit")
	audio._on_settle_timer_timeout()
	assert_true(audio.armed)
	player.inventory.equip_from_backpack(sword.get_parent())
	assert_true(audio.equip_audio.playing, "Once settled, drawing is heard")



func test_a_staff_draws_and_stows_in_silence_while_an_axe_uses_the_sword_set() -> void:
	var staff := Equipment.new()
	staff.equipment_type = Equipment.EquipmentType.STAFF
	root.add_child(staff)
	player.inventory.add_equipment(staff)
	assert_false(audio.equip_audio.playing, "A staff is not a blade: no unsheath")
	player.inventory.remove_equipment(staff)
	assert_false(audio.stow_audio.playing, "and no sheath")
	var axe := Equipment.new()
	axe.equipment_type = Equipment.EquipmentType.AXE_1H
	root.add_child(axe)
	player.inventory.add_equipment(axe)
	assert_true(audio.equip_audio.playing, "An axe is metal: the sword unsheath stands in")
	assert_eq(audio.equip_audio.stream.resource_path, AUDIO_DIR + "sword_unsheath.tres")
	player.inventory.remove_equipment(axe)
	assert_true(audio.stow_audio.playing)
	for type: Equipment.EquipmentType in [Equipment.EquipmentType.PISTOL, Equipment.EquipmentType.RIFLE, Equipment.EquipmentType.FISHING_ROD, Equipment.EquipmentType.STAFF, Equipment.EquipmentType.BOW]:
		var quiet: Equipment = autofree(Equipment.new())
		quiet.equipment_type = type
		assert_false(WeaponAudio.is_bladed(quiet), "%s draws in silence unless its scene says otherwise" % Equipment.EquipmentType.keys()[type])
