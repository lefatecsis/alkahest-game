extends Node3D
## Inventory demo: a yard of pickups and the Player, whose inventory is saved to user:// between runs. Using an item
## only signals, so the demo shows the signal on the hint label; a game would apply the effect there.

const DEMO_TREE: SpellTree = preload("res://addons/3d_player_controller/inventory/resources/spell_tree_demo.tres")
## The player controller's Controls node registers the InputMap actions the inventory listens for. The demo tops up
## anything still missing, from the same list the tests use, so it works even with Controls removed.
const CONTRACT_ACTIONS := preload("res://addons/3d_player_controller/inventory/tests/contract_actions.gd")

@onready var player: Player = $Player
@onready var camera: Camera3D = $Camera3D
@onready var hint: Label = $HUD/Hint
@onready var hint_timer: Timer = $HUD/HintTimer

var _hint_text: String = ""
var _actions: RefCounted = CONTRACT_ACTIONS.new()


func _ready() -> void:
	_actions.add_missing()
	_drop_camera_if_the_player_has_one()
	_hint_text = hint.text
	player.inventory.spellbook.tree = DEMO_TREE
	player.inventory.spellbook.skill_points = 3
	player.inventory.persist = true
	player.inventory.load_save()


## The demo carries a camera so the yard can be seen without a Player, but the Player brings its own and
## that one should win.
func _drop_camera_if_the_player_has_one() -> void:
	if not is_instance_valid(camera):
		return
	for node: Node in player.find_children("", "Camera3D", true, false):
		if node != camera:
			camera.queue_free()
			return

## Wired to Player/Hud/Inventory.item_used.
func _on_item_used(item: Item, count: int) -> void:
	hint.text = "Used %d x %s (item_used signal; the game applies the effect)" % [count, item.get_display_name()]
	hint_timer.start()


## Wired to Player/Hud/Inventory.item_dropped.
func _on_item_dropped(item: Item, count: int, _pickup: Node3D) -> void:
	hint.text = "Dropped %d x %s" % [count, item.get_display_name()]
	hint_timer.start()


## Wired to HUD/HintTimer.timeout.
func _on_hint_timer_timeout() -> void:
	hint.text = _hint_text


## Leaves the InputMap as it was found, erasing only the actions this demo added.
func _exit_tree() -> void:
	_actions.remove_added()
