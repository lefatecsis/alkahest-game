class_name Vitals
extends Node
## Hunger and thirst for a survival game: two pools that drain by the second and, at empty, take
## [member starving_damage] a second off the owner's [Health]. [method eat] and [method drink] top them up (a game
## wires them to its food items). [signal vitals_changed] feeds a HUD; [signal starving] and [signal dehydrated]
## fire once as each runs out, [signal recovered] when both are back above zero. Only the owner's authority
## drains: the Health it eats is replicated, so a puppet's copy draining too would take the damage twice.

signal vitals_changed(hunger: float, thirst: float, capacity: float)
signal starving
signal dehydrated
signal recovered

@export var health: Health ## Whose life the empty pools eat; the parent's `health` when empty.
@export var capacity: float = 100.0
@export var hunger_drain: float = 1.0 ## Points a second.
@export var thirst_drain: float = 1.5 ## Points a second: thirst bites first.
@export var starving_damage: float = 2.0 ## Health a second while either pool is empty.
@export var enabled: bool = true ## Off, nothing drains (a menu, a cutscene, a game that does not want it yet).

var hunger: float = 100.0:
	set(value):
		hunger = clampf(value, 0.0, capacity)
		vitals_changed.emit(hunger, thirst, capacity)
var thirst: float = 100.0:
	set(value):
		thirst = clampf(value, 0.0, capacity)
		vitals_changed.emit(hunger, thirst, capacity)

var _was_empty: bool = false


func _ready() -> void:
	set_physics_process(is_multiplayer_authority())
	if health == null and get_parent():
		health = get_parent().get("health") as Health
	hunger = capacity
	thirst = capacity


func _physics_process(delta: float) -> void:
	if health == null and get_parent():
		health = get_parent().get("health") as Health # the parent's onready pool arrives after this child's ready
	if not enabled or health == null or not health.is_alive():
		return
	var hungry_before: bool = hunger <= 0.0
	var thirsty_before: bool = thirst <= 0.0
	hunger -= hunger_drain * delta
	thirst -= thirst_drain * delta
	if hunger <= 0.0 and not hungry_before:
		starving.emit()
	if thirst <= 0.0 and not thirsty_before:
		dehydrated.emit()
	var empty: bool = hunger <= 0.0 or thirst <= 0.0
	if empty:
		health.damage(starving_damage * delta)
	elif _was_empty:
		recovered.emit()
	_was_empty = empty


func eat(amount: float) -> void:
	hunger += amount


func drink(amount: float) -> void:
	thirst += amount


## Both pools as one number for a quick read: the lower of the two, 0 to 1.
func worst_fraction() -> float:
	return minf(hunger, thirst) / maxf(capacity, 0.01)
