@tool
class_name NoiseMeter
extends Control
## The noise readout, after Breath of the Wild's: a round dark badge with a line across the middle that
## answers how much noise the Player is making.
##
## Silent, it is a flat line. As [member PlayerNoise.level] rises the line breaks into a waveform, taller and
## busier the louder it gets, so the shape says at a glance whether a sneak is working. The badge and the line
## keep the colours the placeholder was drawn with.

@export var noise: PlayerNoise: ## Whose noise to draw: wired in the scene, or set by [method follow] when this peer's Player spawns.
	set(value):
		if noise and noise.level_changed.is_connected(_on_level_changed):
			noise.level_changed.disconnect(_on_level_changed)
		noise = value
		if noise and not noise.level_changed.is_connected(_on_level_changed):
			noise.level_changed.connect(_on_level_changed)

@export var line_color: Color = Color(0.5294118, 0.33333334, 0.43529412) ## The placeholder's mauve.
@export var line_thickness: float = 2.0
@export var quiet_thickness: float = 2.0 ## The flat line's height, which it keeps when silent.
@export var amplitude: float = 11.0 ## How far the waveform swings at a reading of 1.
@export var waves: float = 3.0 ## Peaks across the badge at a reading of 1; a louder noise is busier as well as taller.
@export var speed: float = 9.0 ## How fast the waveform travels, so a loud reading moves rather than sitting still.
@export var points: int = 33 ## Samples across the width; enough for a smooth line on a 36px badge.
@export var follow_speed: float = 12.0 ## How fast the drawn shape eases toward a new reading.

var level: float = 0.0 ## The reading as it last arrived from [PlayerNoise].

var _drawn: float = 0.0 ## What is actually on screen, eased toward [member level] every frame.
var _phase: float = 0.0


## Draws [param player]'s noise. Wire a [PlayerSpawner]'s local_player_spawned here in the scene: it hands over the
## Player this peer controls, never another peer's copy, which would stay flat.
func follow(player: Player) -> void:
	noise = player.get_node_or_null(^"PlayerNoise") as PlayerNoise if is_instance_valid(player) else null


func _process(delta: float) -> void:
	if noise == null:
		return
	# Two things caused a continued noise to look like it was stuttering, and both are fixed here. The reading
	# only changes on the physics tick while this draws every frame, so the shape is eased toward it rather
	# than stepped with it. And the wave used to travel at a speed that scaled with the reading, so every
	# change in loudness jumped its pace as well as its size; it now travels steadily and only its shape
	# answers the reading.
	_drawn = move_toward(_drawn, level, follow_speed * delta)
	# A flat line has nothing to animate, so a silent meter costs a redraw only while it is settling
	if _drawn <= 0.001 and is_equal_approx(_phase, 0.0):
		return
	_phase = fposmod(_phase + delta * speed, TAU)
	queue_redraw()


func _on_level_changed(value: float) -> void:
	level = clampf(value, 0.0, 1.0)


func _draw() -> void:
	var width: float = size.x
	var middle: float = size.y * 0.5
	if width <= 0.0:
		return
	if _drawn <= 0.001:
		# Flat: the placeholder's own line, a bar across the middle
		draw_rect(Rect2(0.0, middle - quiet_thickness * 0.5, width, quiet_thickness), line_color)
		return
	var swing: float = amplitude * _drawn
	var cycles: float = maxf(waves * _drawn, 0.5)
	var line: PackedVector2Array = []
	for i: int in points:
		var along: float = float(i) / float(points - 1)
		# Tapered at both ends, so the wave sits inside the badge instead of being clipped by it
		var taper: float = sin(along * PI)
		var y: float = middle + sin(along * TAU * cycles + _phase) * swing * taper
		line.append(Vector2(along * width, y))
	draw_polyline(line, line_color, line_thickness, true)
