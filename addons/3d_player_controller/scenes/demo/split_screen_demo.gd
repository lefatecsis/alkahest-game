extends Node3D
## The demo arena for two on one screen: demo_arena.tscn, the demo with no Player of its own, and a SplitScreen over
## it with two Players, one on each pad. The arena's own script stays, so the pool and the Guide answer both.

@onready var split_screen: SplitScreen = $SplitScreen


func _ready() -> void:
	split_screen.spawn()
	for i: int in split_screen.players.size():
		split_screen.players[i].global_position = Vector3(-2.0 + 4.0 * i, 0.5, 4.0)
		split_screen.players[i].enable_paraglider = true
		split_screen.players[i].enable_stamina = true
		# Half a screen each is too little for the whole button set: only the contextual hints, whatever the
		# saved On-Screen setting says (this is a pads-only arena, so the buttons are known anyway)
		split_screen.players[i].hud_mode_override = PlayerSettingsResource.HudMode.AUTO
