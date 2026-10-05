class_name Boss
extends Node
## Puts the owner's name and health on the HUD boss bar of the player it is fighting, Breath of the Wild style.
##
## The authority calls [method engage] with the hunted player's peer id; `target_peer` replicates, and the
## peer that owns that player shows the bar on its own Controls. Health follows through [signal Health.health_changed],
## wired to [method _on_health_changed] in the scene that puts the Boss beside its [Health] (enemy_npc.tscn).

@export var boss_name: String = "Boss"
@export var health: Health

var target_peer: int = 0: ## Replicated: the peer whose HUD shows the bar; 0 for nobody.
	set(value):
		target_peer = value
		_refresh()
var _shown_on: Node = null ## The Controls currently showing this boss.


func _ready() -> void:
	_refresh()


func engage(peer_id: int) -> void:
	target_peer = peer_id


func disengage() -> void:
	target_peer = 0


## The boss bar of the player this peer owns, if they have one. A game that took the readout off its Player
## gets null here and no boss bar, which is the point of it being a separate scene.
func _local_boss_bar() -> Node:
	for player: Node in get_tree().get_nodes_in_group("Player"):
		if player.is_multiplayer_authority() and player.get("boss_bar"):
			return player.get("boss_bar")
	return null


func _refresh() -> void:
	if not is_inside_tree():
		return
	var wanted: bool = target_peer != 0 and target_peer == multiplayer.get_unique_id() and health.health > 0.0
	if wanted and _shown_on == null:
		_shown_on = _local_boss_bar()
		if _shown_on:
			_shown_on.call("show_boss", boss_name, health.health / health.max_health)
	elif not wanted and _shown_on:
		_shown_on.call("hide_boss")
		_shown_on = null


func _on_health_changed(value: float, max_value: float) -> void:
	if _shown_on:
		_shown_on.call("update_boss", value / max_value)
	if value <= 0.0:
		_refresh()
