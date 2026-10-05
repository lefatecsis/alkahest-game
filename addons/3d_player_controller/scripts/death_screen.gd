class_name DeathScreen
extends CanvasLayer
## What the local Player sees between dying and coming back: the screen darkens, the title shows and the
## RespawnTimer's seconds count down. Wired in [code]player.tscn[/code] to Health.died and Player.respawned; a
## puppet never shows it. [member title] and [member subtitle] are the game's to word.

@export var player: Player
@export var title: String = "You Died"
@export var subtitle: String = "Respawning in %d" ## Takes the whole seconds left on the RespawnTimer.

@onready var title_label: Label = %Title
@onready var subtitle_label: Label = %Subtitle


func _ready() -> void:
	set_process(false)
	title_label.text = title


func _process(_delta: float) -> void:
	if player and player.respawn_timer:
		subtitle_label.text = subtitle % ceili(player.respawn_timer.time_left)


## Wired to Health.died: only the owning peer sees its own death screen.
func _on_health_died() -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	show()
	set_process(true)
	_process(0.0)


## Wired to Player.respawned.
func _on_player_respawned() -> void:
	hide()
	set_process(false)
