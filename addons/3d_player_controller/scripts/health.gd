class_name Health
extends Node
## Hit points and an optional energy pool for whoever owns it: the Player, enemies, the duck.
##
## Setters clamp and emit, so bars and the HUD follow through signals and puppets update when the
## authority's values replicate. The owner decides what dying means by listening to [signal died].

signal health_changed(health: float, max_health: float)
signal energy_changed(energy: float, max_energy: float)
signal damaged(amount: float, from: Vector3) ## Emitted on the peer that applied the damage.
signal died ## Emitted once when health reaches zero.

@export var max_health: float = 100.0:
	set(value):
		max_health = maxf(value, 1.0)
		health = minf(health, max_health)
		health_changed.emit(health, max_health)
@export var max_energy: float = 0.0 ## 0 means no energy pool.
@export var energy_regen: float = 5.0 ## Energy restored per second, in ticks of the RegenTimer.

var regen_paused: bool = false ## The owner sets this while in combat; energy holds until it clears.

var health: float = 100.0:
	set(value):
		var was_alive: bool = health > 0.0
		health = clampf(value, 0.0, max_health)
		health_changed.emit(health, max_health)
		if was_alive and health <= 0.0:
			died.emit()
var energy: float = 0.0:
	set(value):
		energy = clampf(value, 0.0, max_energy)
		energy_changed.emit(energy, max_energy)

@onready var regen_timer: Timer = $RegenTimer ## Its timeout is wired to [method _on_regen_timer_timeout] in the scene.


func _ready() -> void:
	health = max_health
	energy = max_energy


func is_alive() -> bool:
	return health > 0.0


func damage(amount: float, from: Vector3 = Vector3.ZERO) -> void:
	if health <= 0.0:
		return
	health -= amount
	damaged.emit(amount, from)


## True while a heal would do something: alive and not full.
func can_heal() -> bool:
	return health > 0.0 and health < max_health


## False when already full or dead, so a heal is not wasted.
func heal(amount: float) -> bool:
	if not can_heal():
		return false
	health += amount
	return true


## False when there is not enough energy; nothing is spent then.
func spend_energy(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if energy < amount:
		return false
	energy -= amount
	return true


func _on_regen_timer_timeout() -> void:
	if not regen_paused and max_energy > 0.0 and energy < max_energy:
		energy += energy_regen * regen_timer.wait_time
