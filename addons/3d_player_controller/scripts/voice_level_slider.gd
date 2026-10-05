@tool
class_name VoiceLevelSlider
extends Range
## The microphone row in Audio settings: one bar that is both the meter and the setting, after PulseAudio's.
##
## The track runs from nothing on the left to [member Range.max_value] on the right, shading green through
## yellow into red, with a mark where a normal voice should land ([member normal_value]). The handle riding on
## it is the sensitivity you have chosen. Behind it, [member level] fills as you speak.
##
## Calibrating is then one action rather than a number somebody has to guess for every microphone: talk, and
## drag the handle until your ordinary voice fills the bar to the mark. Quiet microphone, push it right; a
## headset that clips, pull it left.

@export var level: float = 0.0: ## The live reading, 0 to 1, drawn behind the handle. The menu feeds this from the Player.
	set(value):
		var clamped: float = clampf(value, 0.0, 1.0)
		if is_equal_approx(clamped, level):
			return
		level = clamped
		queue_redraw()

@export_group("Track")
@export var quiet_color: Color = Color(0.11, 0.55, 0.15) ## Under a normal voice.
@export var loud_color: Color = Color(0.95, 0.83, 0.16) ## Past it.
@export var hot_color: Color = Color(0.85, 0.16, 0.14) ## Into the top, where a voice would be clipping.
@export var normal_value: float = 100.0 ## Where a normal voice ought to land; the mark, and where the colours turn.
@export var track_height: float = 22.0
@export var corner_radius: float = 3.0

@export_group("Handle")
@export var handle_color: Color = Color(0.1, 0.1, 0.1)
@export var handle_width: float = 14.0
@export var handle_height: float = 11.0
@export var focus_color: Color = Color(1.0, 1.0, 1.0, 0.85)

@export_group("Level")
@export var unlit_color: Color = Color(0.0, 0.0, 0.0, 0.55) ## Dims the part of the bar the voice has not reached, so the lit part reads as a level rather than washing the colour out.
@export var edge_color: Color = Color(1.0, 1.0, 1.0, 0.7) ## The leading edge of the level.
@export var level_follow_speed: float = 10.0

var _drawn_level: float = 0.0
var _gradient: GradientTexture2D
var _dragging: bool = false


func _ready() -> void:
	custom_minimum_size.y = maxf(custom_minimum_size.y, track_height + handle_height + 6.0)
	focus_mode = Control.FOCUS_ALL
	_build_gradient()
	set_process(true)


## Where [param at] sits across the bar, 0 to 1. The handle, the mark and the colours all have to agree, and
## they only do if every one of them measures from min_value rather than from zero.
func ratio_of(at: float) -> float:
	return clampf((at - min_value) / maxf(max_value - min_value, 0.001), 0.0, 1.0)


## A texture rather than a column of rectangles, so the shading is actually smooth.
func _build_gradient() -> void:
	var gradient: Gradient = Gradient.new()
	var turn: float = clampf(ratio_of(normal_value), 0.05, 0.95)
	gradient.offsets = PackedFloat32Array([0.0, turn * 0.75, turn, 1.0])
	gradient.colors = PackedColorArray([quiet_color, quiet_color, loud_color, hot_color])
	_gradient = GradientTexture2D.new()
	_gradient.gradient = gradient
	_gradient.width = 256
	_gradient.height = 1
	_gradient.fill_from = Vector2(0.0, 0.0)
	_gradient.fill_to = Vector2(1.0, 0.0)


func _process(delta: float) -> void:
	if is_equal_approx(_drawn_level, level):
		return
	_drawn_level = move_toward(_drawn_level, level, level_follow_speed * delta)
	queue_redraw()


func _draw() -> void:
	if _gradient == null:
		_build_gradient()
	var width: float = size.x
	var top: float = handle_height + 3.0
	var track: Rect2 = Rect2(0.0, top, width, track_height)

	# The bar itself, shaded across its whole width whatever the handle is doing
	draw_texture_rect(_gradient, track, false)

	# How loud you are right now: the bar is lit up to the level and dimmed past it, so it fills like a meter
	# instead of the colour being washed out wherever the voice has reached.
	var lit: float = width * _drawn_level
	if _drawn_level < 0.999:
		draw_rect(Rect2(Vector2(lit, top), Vector2(width - lit, track_height)), unlit_color)
	if _drawn_level > 0.001:
		draw_line(Vector2(lit, top), Vector2(lit, top + track_height), edge_color, 2.0)

	# Where a normal voice should land, measured the same way the handle is
	var mark: float = width * ratio_of(normal_value)
	draw_line(Vector2(mark, top - 2.0), Vector2(mark, top + track_height + 2.0), Color(0.0, 0.0, 0.0, 0.7), 2.0)

	# The handle, pointing down at the setting, the way the sketch has it
	var at: float = width * clampf(ratio, 0.0, 1.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(at - handle_width * 0.5, 0.0),
		Vector2(at + handle_width * 0.5, 0.0),
		Vector2(at, handle_height),
	]), handle_color)
	if has_focus():
		draw_polyline(PackedVector2Array([
			Vector2(at - handle_width * 0.5, 0.0),
			Vector2(at + handle_width * 0.5, 0.0),
			Vector2(at, handle_height),
			Vector2(at - handle_width * 0.5, 0.0),
		]), focus_color, 1.5, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if button.pressed:
				grab_focus()
				_set_from_x(button.position.x)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x)
		accept_event()
	elif event.is_action_pressed(&"ui_left"):
		value -= step if step > 0.0 else 1.0
		accept_event()
	elif event.is_action_pressed(&"ui_right"):
		value += step if step > 0.0 else 1.0
		accept_event()


func _set_from_x(x: float) -> void:
	ratio = clampf(x / maxf(size.x, 1.0), 0.0, 1.0)
