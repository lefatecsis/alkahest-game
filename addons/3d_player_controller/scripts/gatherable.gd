class_name Gatherable
extends StaticBody3D
## A tree, a boulder, a berry bush: something in the world that gives [member item] when struck. A swing from a
## piece of [Equipment] that [member needs] what it needs (the axe's [member Equipment.can_log], the pickaxe's
## [member Equipment.can_mine], or nothing at all for a bush) counts a hit; every [member hits_per_yield] hits put
## [member yield_count] of the item straight in the striker's [Inventory], and after [member total_yields] the
## thing is spent: hidden (or left standing, a stump or a bare rock, without [member hide_when_spent]), and back after
## [member regrow_seconds] when that is set. In the "Gatherable" group so a swing reaches it the way it reaches an
## enemy ([member HitDetection.strike_groups]).
##
## Instance [code]scenes/prop/gatherable.tscn[/code] (or inherit it) and give it a model and a collision shape: it
## carries the RegrowTimer and the StateSynchronizer. The server counts: a swing is registered on the striker's own
## peer, which asks the server; every strike it counts shakes the thing and fires [signal struck] on every peer, each
## yield goes into the striker's inventory on the striker's peer, and [member hits] and [member is_spent] replicate, so
## a felled tree is felled for everyone.

signal harvested(by: Player, item: Item, count: int) ## On the striker's peer, as the yield goes into their bag.
signal depleted ## On every peer, as the thing is spent.
signal struck(progress: float) ## On every peer, from the server, for every strike it counted: [param progress] is how far toward spent, 0 to 1 (1 on the strike that spends it); toward the next yield when [member total_yields] is 0.

enum Needs { NOTHING, LOGGING, MINING }

@export var item: Item
@export var yield_count: int = 1
@export var hits_per_yield: int = 3
@export var total_yields: int = 3 ## Yields before it is spent; 0 never runs out.
@export var needs: Needs = Needs.NOTHING
@export var regrow_seconds: float = 0.0 ## Back after this long once spent; 0 stays gone.
@export var regrow_timer: Timer ## One-shot, started on the server for [member regrow_seconds] once spent, its timeout wired to [method regrow]; without one a spent thing stays spent.
@export var shake_node: Node3D ## Nudged on every hit, for the feel; the model itself when empty.
@export var hide_when_spent: bool = true ## Hides a spent one and turns off its collision; off, it stays as it stands (a stump, a bare rock) for the game to dress.

var hits: int = 0 ## Replicated from the server: hits toward the next yield.
var yields_given: int = 0 ## Yields since it last grew, counted on the server.
var is_spent: bool = false: ## Replicated from the server: hidden, with its collision off, while true (with [member hide_when_spent]).
	set(value):
		if value == is_spent:
			return
		is_spent = value
		if hide_when_spent:
			visible = not value
			for shape: Node in find_children("*", "CollisionShape3D", true, false):
				(shape as CollisionShape3D).set_deferred(&"disabled", value)
		if value:
			depleted.emit()


func _ready() -> void:
	add_to_group(&"Gatherable")
	if shake_node == null:
		for child: Node in get_children():
			if child is Node3D and not child is CollisionShape3D:
				shake_node = child
				break


## Called by [HitDetection] on the striker's peer for a swing that reached this; [param equipment] is the piece or
## the Player unarmed. The right tool asks the server to count the hit.
func register_weapon_hit(equipment: Node = null, _hit_node: Node = null) -> void:
	var player: Player = (equipment as Equipment).player if equipment is Equipment else equipment as Player
	if is_spent or item == null or player == null or not can_harvest_with(equipment):
		return
	_strike.rpc_id(1, get_path_to(player))


## Whether [param equipment] (a piece, or the Player for bare hands) is the tool for the job.
func can_harvest_with(equipment: Node) -> bool:
	match needs:
		Needs.LOGGING:
			return equipment is Equipment and (equipment as Equipment).can_log
		Needs.MINING:
			return equipment is Equipment and (equipment as Equipment).can_mine
	return true


## The server counts a hit by [param player_path]'s Player (from this node, the same on every peer), from that
## Player's own peer only; a full count sends the yield to the striker and the last yield spends the thing. Every
## counted strike plays on every peer ([method _struck]).
@rpc("any_peer", "call_local", "reliable")
func _strike(player_path: NodePath) -> void:
	var player: Player = get_node_or_null(player_path) as Player
	if not multiplayer.is_server() or is_spent or player == null or player.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return
	hits += 1
	var progress: float = float(yields_given * hits_per_yield + hits) / (hits_per_yield * total_yields) if total_yields > 0 else float(hits) / hits_per_yield
	if hits >= hits_per_yield:
		hits = 0
		yields_given += 1
		_harvest.rpc_id(player.get_multiplayer_authority(), player_path)
		if total_yields > 0 and yields_given >= total_yields:
			is_spent = true
			if regrow_timer and regrow_seconds > 0.0:
				regrow_timer.start(regrow_seconds)
	_struck.rpc(progress)


## A yield, on the striker's peer, where their inventory lives.
@rpc("authority", "call_local", "reliable")
func _harvest(player_path: NodePath) -> void:
	var player: Player = get_node_or_null(player_path) as Player
	if player == null:
		return
	if player.inventory:
		player.inventory.add_item(item, yield_count)
	harvested.emit(player, item, yield_count)


## A strike the server counted, on every peer: the shake and [signal struck].
@rpc("authority", "call_local", "reliable")
func _struck(progress: float) -> void:
	_shake()
	struck.emit(progress)


## Back as it was; the server's (the RegrowTimer's timeout), and the peers follow [member is_spent].
func regrow() -> void:
	if not is_multiplayer_authority():
		return
	yields_given = 0
	hits = 0
	is_spent = false


func _shake() -> void:
	if shake_node == null:
		return
	var tween: Tween = create_tween()
	var rest: Vector3 = shake_node.rotation_degrees
	tween.tween_property(shake_node, "rotation_degrees", rest + Vector3(0.0, 0.0, 3.0), 0.06)
	tween.tween_property(shake_node, "rotation_degrees", rest + Vector3(0.0, 0.0, -2.0), 0.08)
	tween.tween_property(shake_node, "rotation_degrees", rest, 0.08)
