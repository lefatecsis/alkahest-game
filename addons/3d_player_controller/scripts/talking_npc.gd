class_name TalkingNpc
extends FollowerNpc
## Somebody to talk to. Walk up to them (or look at them) and the prompt offers Talk; Action calls [method talk],
## which holds the Player still, turns the NPC to face them and emits [signal talked_to]. What is said, and how,
## is the game's own (a dialogue addon such as Dialogic): it listens for [signal talked_to], runs its conversation
## and calls [method end_talk] when the conversation is over. Left with no [member FollowerNpc.player] they stand
## where they are; given one they follow, as any FollowerNpc does. The walk and run blend replicates like the enemy's.
##
## Multiplayer: the server decides who is talking. [method talk] and [method end_talk] ask it; it sends the start and
## the end of the conversation to every peer, so [member talker] is the same everywhere and the NPC turns to a
## client as it does to the host. The talker's own peer is held still and gets the signals, as its dialogue runs there.

signal talked_to(player: Player) ## [param player] pressed Action on this NPC: the game's cue to start a conversation. On the talker's own peer.
signal conversation_ended(player: Player) ## [method end_talk] was called: the conversation with [param player] is over. On the talker's own peer.

const LOCOMOTION_BLEND_PATH: String = "parameters/blend_position"

@export var display_name: String = "Villager" ## Who this is, for the game's dialogue box and its quest text.
@export var prompt_label: String = "Talk" ## What the bottom-action button reads while the prompt is up.
@export var pauses_talker: bool = true ## Holds the Player still ([member Player.is_paused]) from [method talk] to [method end_talk], as a menu does.
@export var faces_talker: bool = true ## Turns on the spot to face whoever they are attending to, yaw only; the head modifier does the rest.
@export var head_tracks_player: bool = true ## Turns the head alone to the Player's own head, on top of whatever the body is doing.

var talker: Player ## Who is in conversation with this NPC, while one is; the same on every peer, sent by the server.
var _attention: Player ## Who this NPC has noticed: the one being offered a prompt, or the one being talked to.
var _control_speed: float = 0.0
var locomotion_blend: float = 0.0: ## Replicated: 0 idle, 0.5 walk, 1 run.
	set(value):
		locomotion_blend = value
		if animation_tree:
			animation_tree.set(LOCOMOTION_BLEND_PATH, value)

@onready var mannequin: Node3D = $Mannequin_M
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var action_prompt: ActionPrompt = $ActionPrompt
@onready var head_look_at_modifier: LookAtModifier3D = $Mannequin_M/Armature/GeneralSkeleton/HeadLookAtModifier3D ## Turns the head alone; the body's yaw is [method _face].


func _ready() -> void:
	super()
	animation_tree.active = true


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or delta <= 0.0: # root motion is divided by delta
		return
	var attending: Player = talker if talker else _attention
	if attending and is_instance_valid(attending) and faces_talker:
		# Yaw only. The body turns on the spot and the head modifier carries the pitch, so an NPC looking at a
		# Player on a step above them tips their head rather than leaning the whole torso back.
		_face(attending.global_position, delta)
	if talker:
		_stop_moving()
		_update_locomotion()
		return
	super(delta)
	_update_locomotion()


## Called by [Camera] when this NPC is the one thing the action button would act on. Being the chosen one is
## also when they notice you: they turn to face you and their head comes up, which is the clearest sign of
## which of a crowd is about to be talked to.
func display_menu(looking: Player) -> void:
	if talker:
		return
	action_prompt.show_for(looking.controls, prompt_label)
	notice(looking)


## Turns this NPC's attention to [param who], or lets go when null: the body turns to face them and the head
## modifier tracks their head. Public so a scene can have somebody watch a Player without a prompt.
func notice(who: Player) -> void:
	_attention = who
	if head_look_at_modifier == null:
		return
	var head: Node3D = who.head_attachment if who and is_instance_valid(who) else null
	if head and head_tracks_player:
		head_look_at_modifier.target_node = head_look_at_modifier.get_path_to(head)
		head_look_at_modifier.active = true
	else:
		head_look_at_modifier.target_node = NodePath("")
		head_look_at_modifier.active = false


## Called by [Camera] when they are not.
func hide_menu() -> void:
	for looking: Node in get_tree().get_nodes_in_group(&"Player"):
		if looking is Player and (looking as Player).controls:
			action_prompt.hide_for((looking as Player).controls)
	action_prompt.hide()
	if talker == null:
		notice(null)


## The Camera's Action hook: talk to whoever pressed it.
func equip(who: Player) -> void:
	talk(who)


## Begins a conversation with [param who]: the prompt goes, the Player stands still ([member pauses_talker]), the
## NPC faces them and [signal talked_to] fires for the game to take it from there. False while already talking. The
## server decides: it starts the conversation on every peer unless somebody got there first.
func talk(who: Player) -> bool:
	if talker or who == null:
		return false
	_request_talk.rpc_id(1, get_path_to(who))
	return true


## The game's conversation is over: lets the Player go, emits [signal conversation_ended], and offers the prompt
## again while the Camera still has this NPC as its target. The server ends it on every peer.
func end_talk() -> void:
	if talker:
		_request_end_talk.rpc_id(1)


## A [method talk], on the server: for a Player of the sender's own ([param who_path], from this node, the same on
## every peer), while nobody is talking.
@rpc("any_peer", "call_local", "reliable")
func _request_talk(who_path: NodePath) -> void:
	var who: Player = get_node_or_null(who_path) as Player
	var sender: int = multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and talker == null and who and (sender == multiplayer.get_unique_id() or who.get_multiplayer_authority() == sender):
		_begin_talk.rpc(who_path)


## An [method end_talk], on the server: from the talker's own peer (or the server).
@rpc("any_peer", "call_local", "reliable")
func _request_end_talk() -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and talker and (sender == multiplayer.get_unique_id() or talker.get_multiplayer_authority() == sender):
		_end_talk.rpc()


## The conversation starts, on every peer.
@rpc("authority", "call_local", "reliable")
func _begin_talk(who_path: NodePath) -> void:
	var who: Player = get_node_or_null(who_path) as Player
	if who == null:
		return
	talker = who
	hide_menu()
	notice(who)
	if who.is_multiplayer_authority():
		if pauses_talker:
			who.is_paused = true
		talked_to.emit(who)


## The conversation ends, on every peer.
@rpc("authority", "call_local", "reliable")
func _end_talk() -> void:
	var was: Player = talker
	talker = null
	if is_instance_valid(was) and was.is_multiplayer_authority():
		if pauses_talker:
			was.is_paused = false
		conversation_ended.emit(was)
		# The Camera holds the target across the conversation, so the prompt comes back for whoever was talking
		if (was.camera as Camera) and (was.camera as Camera).interaction_target == self:
			display_menu(was)
			return
	notice(null)


func _face(target: Vector3, delta: float) -> void:
	var to_target: Vector3 = (target - global_position).slide(up_direction)
	if to_target.length_squared() > 0.001:
		var wanted: Transform3D = global_transform.looking_at(global_position + to_target.normalized(), up_direction)
		global_transform = global_transform.interpolate_with(wanted, turn_speed * delta)


## Root motion moves the body, as it does the enemy: the navigation's wish picks the clip, the Root bone carries it.
func _move_with_control(control_velocity: Vector3) -> void:
	_control_speed = control_velocity.slide(up_direction).length()
	if is_on_floor() and not is_swimming:
		control_velocity = (mannequin.global_basis * animation_tree.get_root_motion_position() / get_physics_process_delta_time()).slide(up_direction)
	super(control_velocity)


func _update_locomotion() -> void:
	var wanted_blend: float = 0.0
	if _control_speed > 0.05:
		if walk_speed > 0.0 and _control_speed <= walk_speed:
			wanted_blend = _control_speed / walk_speed * 0.5
		else:
			wanted_blend = 0.5 + clampf((_control_speed - walk_speed) / maxf(move_speed - walk_speed, 0.001), 0.0, 1.0) * 0.5
	locomotion_blend = move_toward(locomotion_blend, wanted_blend, (8.0 if wanted_blend < locomotion_blend else 6.0) * get_physics_process_delta_time())


func sfx_footsteps_play() -> void:
	pass
