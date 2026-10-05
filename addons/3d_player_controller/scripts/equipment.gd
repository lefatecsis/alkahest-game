class_name Equipment
extends Node3D
## A pick-up-able item attached to a Player skeleton bone when equipped.
##
## In the world it is a GTA-style pickup: a child [Area3D] named "PlayerDetection" (its body_entered wired to
## [method _on_player_detection_body_entered] in the scene) equips a copy on the first Player to walk over it, and the
## pickup then vanishes on every peer, so each pickup is taken once with no prompt or button. One standing in the
## world stays in the tree, hidden and no longer monitoring, because peers, saves and drops re-create the piece from
## it by path; a peer joining later is told it is spent. A dropped one is freed ([method _vanish]). The take goes
## through the server, which checks the taker is the sender's own Player before spending the pickup anywhere.
##
## Melee weapons that should register hits need a child [Area3D] named "Hitbox"; [HitDetection]
## enables its monitoring during attack swings. A weapon that should shove props needs a child
## [AnimatableBody3D] named "WeaponBody" (a shape along the blade, on the Weapons physics layer masking
## Hittable, sync_to_physics off: a synced body reverts to its own last transform and ignores the bone
## attachment carrying it): it rides the bone animation and pushes with the swing's real velocity,
## [HitDetection] puts it on its layer only while a swing is live, and it never touches the Player carrying it.

signal details_changed ## What [method get_details] prints has changed (a rod's bait, say); the inventory screen redraws it.

enum EquipmentType {
	AXE_1H,
	AXE_2H,
	BOW,
	DAGGER,
	FISHING_ROD,
	PISTOL,
	RIFLE,
	STAFF,
	SWORD_1H,
	SWORD_2H,
	SWORD_AND_SHIELD,
}

@export var bone_attachment_bone_name: String ## The name of the bone on the player's skeleton to which this equipment will be attached when equipped. (e.g. "RightHand", "LeftHand", etc.)
@export var can_attack: bool = false ## Does this equipment have an attack/melee action that the player can perform?
@export var can_log: bool = false ## Can this equipment chop down trees? (See [Choppable].)
@export var can_mine: bool = false ## Can this equipment mine ore? (See [Mineable].)
@export var can_shoot: bool = false ## Does this equipment have a shooting/ranged action that the player can perform?
@export var is_metal: bool = false ## Made of metal: held in a thunderstorm it draws the lightning, as in Breath of the Wild ([method Player.attracts_lightning]).
@export var display_name: String = "" ## Name displayed in the UI. If empty, falls back to equipment type name.
@export_multiline var description: String = "" ## Flavour text under the name in the inventory.
@export var model_scene: PackedScene ## A 3D model the inventory shows turning in place of the icon; empty keeps the icon.
@export var equipment_type: EquipmentType ## The type of equipment (e.g. AXE_1H, BOW, RIFLE, etc.)
@export var icon: Texture2D ## Icon to display in the UI for this equipment
@export var is_exclusive: bool = false ## Is this equipment exclusive, meaning it cannot be equipped with other equipment types simultaneously?
@export var is_throwable: bool = false ## Can this equipment be thrown? The "throw" action throws the equipped piece ([HeldObject]); it lands as a walk-over pickup of its own scene.
@export var throw_damage: float = 0.0 ## What a thrown one does to whatever it lands on that can take a hit; 0 hurts nothing.
@export var projectile_speed: float = 50.0 ## meters/second (Arrows, Bullets, etc.)
@export var accuracy: Accuracy ## Spread cone for ranged equipment, shrinking with the Player's [code]skill_level[/code]; empty fires dead straight.
@export var position_offset: Vector3: ## Positional offset applied to the equipment when attached to the player.
	set(val):
		position_offset = val
		_update_attachment_offsets()
@export var rotation_offset_degrees: Vector3: ## Rotational offset in degrees applied to the equipment when attached to the player.
	set(val):
		rotation_offset_degrees = val
		_update_attachment_offsets()
@export var scale_offset: Vector3 = Vector3.ONE: ## Scale offset applied to the equipment when attached to the player.
	set(val):
		scale_offset = val
		_update_attachment_offsets()
@export_group("Sounds")
@export var equip_sfx: AudioStream ## Played through the Player's [WeaponAudio] when this is drawn; empty plays the TomMusic sword unsheath on a metal melee weapon ([constant WeaponAudio.BLADED_TYPES]) and nothing on anything else.
@export var stow_sfx: AudioStream ## Played when this is stowed; empty plays the sword sheath on a metal melee weapon and nothing on anything else.
@export var attack_sfx: AudioStream ## Played at the start of each swing (a [Bow]: each shot); empty plays the default sword swing.
@export var hit_sfx: AudioStream ## Played when a swing lands on something that takes a hit; empty plays the default sword impact.
@export_group("")

var equipment_instance: Equipment ## The equipped copy of this item, once [method equip] has run.
var spawned: bool = false ## Put down by the world's [ProjectileSpawner] (a drop, a landed throw): the server's free takes every copy away.
var player: Player

@onready var player_detection: Area3D = get_node_or_null("PlayerDetection") as Area3D ## The walk-over pickup volume, on world copies.
@onready var weapon_body: AnimatableBody3D = get_node_or_null("WeaponBody") as AnimatableBody3D ## The blade's physical body, on melee weapons.


## An equipped copy's weapon body ignores its Player and their ragdoll bones, whatever layers they end up on.
func _ready() -> void:
	if weapon_body == null or not is_instance_valid(player):
		return
	weapon_body.add_collision_exception_with(player)
	if is_instance_valid(player.physical_bone_simulator):
		for bone: Node in player.physical_bone_simulator.find_children("*", "PhysicalBone3D", true, false):
			weapon_body.add_collision_exception_with(bone as PhysicsBody3D)


## Extra lines the inventory prints under [member description]; a rod says what bait is on the line. Empty by default.
## Emit [signal details_changed] when they change, so an open inventory screen redraws them.
func get_details() -> String:
	return ""


func _update_attachment_offsets() -> void:
	if not is_inside_tree() or equipment_instance == null:
		return
	equipment_instance.position = position_offset
	equipment_instance.rotation_degrees = rotation_offset_degrees
	equipment_instance.scale = scale_offset


## Wired to PlayerDetection.body_entered: the Player that walked over the pickup takes it, and the pickup is spent
## on every peer once the server has heard it was this Player's own take ([method _request_vanish]). A Player who
## just dropped it ([method set_dropped_by]) has to step away first.
func _on_player_detection_body_entered(body: Node3D) -> void:
	if body is Player and body.is_multiplayer_authority() and not (has_meta("dropped_by") and get_meta("dropped_by") == body) and equip(body):
		_request_vanish.rpc_id(1, get_path_to(body))


## The server's half of a take, as [method ItemPickup._request_take] is: the Player at [param taker_path] (from this
## node, the same on every peer) must be the sender's own, and then every peer's copy of the pickup goes. A call
## from any other peer, or one naming somebody else's Player, is ignored.
@rpc("any_peer", "call_local", "reliable")
func _request_vanish(taker_path: NodePath) -> void:
	var taker: Player = get_node_or_null(taker_path) as Player
	if not multiplayer.is_server() or taker == null or taker.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return
	_vanish.rpc()


## A drop at [param dropper]'s feet: walking over it takes nothing for them until they have stepped off it once.
## The inventory's drop calls it, and so does the [ProjectileSpawner] building one, before the pickup is in the tree.
func set_dropped_by(dropper: Node3D) -> void:
	set_meta("dropped_by", dropper)
	var detection: Area3D = get_node_or_null("PlayerDetection") as Area3D
	if detection and not detection.body_exited.is_connected(_on_player_detection_body_exited):
		detection.body_exited.connect(_on_player_detection_body_exited)


## Connected by [method set_dropped_by]: the Player who dropped the pickup has walked off it, and it can be taken again.
func _on_player_detection_body_exited(body: Node3D) -> void:
	if has_meta("dropped_by") and get_meta("dropped_by") == body:
		remove_meta("dropped_by")


## The piece went to the taker alone, so the server tells every peer's copy of the pickup to go. A drop, which no
## worn piece names as its origin, is freed, by the server alone for a [member spawned] one (that frees it
## everywhere). A pickup standing in the world hides and stops monitoring instead, since worn pieces are re-created
## from it by path; one saved in the level is hidden on every later joiner as well, told by the server.
@rpc("authority", "call_local", "reliable")
func _vanish() -> void:
	var dropped: bool = owner == null and (Inventory.has_own_scene(self) or has_meta("origin"))
	if dropped and (multiplayer.is_server() or not spawned):
		queue_free()
		return
	hide()
	if player_detection:
		player_detection.set_deferred(&"monitoring", false)
	# Hidden is not gone: every shape it carries (the pickup volume, a blade, a bow's template arrow) would go on
	# stopping rounds, the aim ray and anything rolling through where it lay. Inventory.pickup_from turns them back on.
	for shape: Node in find_children("*", "CollisionShape3D", true, false):
		shape.set_deferred(&"disabled", true)
	if owner and multiplayer.is_server() and not multiplayer.peer_connected.is_connected(_tell_joiner):
		multiplayer.peer_connected.connect(_tell_joiner)


## Connected on the server once a level's pickup is spent: a peer joining later is told it is gone.
func _tell_joiner(peer_id: int) -> void:
	_vanish.rpc_id(peer_id)


## Equips this item on [param target_player]: the inventory duplicates it onto a new [BoneAttachment3D] on the
## skeleton ([method Inventory.equip_pickup]) and this pickup remembers the copy as [member equipment_instance].
## False when the Player already carries one of this type on this bone, or the item cannot be worn.
func equip(target_player: Player) -> bool:
	if target_player == null:
		return false
	var copy: Equipment = target_player.inventory.equip_pickup(self)
	if copy == null:
		return false
	equipment_instance = copy
	return true


## [param direction] pushed off its line by [member accuracy] for the Player's skill; straight without one.
func scatter(direction: Vector3) -> Vector3:
	return accuracy.scatter(direction, player.skill_level) if accuracy and player else direction.normalized()
