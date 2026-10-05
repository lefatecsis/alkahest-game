@tool
class_name ActionPrompt
extends Node3D
## World-space "Press [button] to ..." prompt with one child per input type (KeyboardMouse, Microsoft, Nintendo, Sony).
##
## Hang one on anything the player can walk up to and interact with. It shows only the sub-prompt for the
## device being played on, which it reads off a [Controls] node, and it can name that node's bottom-action
## button after what it does ("Pick Up", "Get In") while it is up.
##
## Each sub-prompt is laid out from the text itself rather than from fixed positions: the two labels are
## measured, the row is assembled as [code]begin[/code], gap, button art, gap, [code]end[/code], and the whole
## thing is centred on this node. So any wording reads evenly, however long or short either side of the glyph
## is, and a side left blank takes its gap with it.

var _message_begin: String = "Press"
var _message_end: String = "to interact"

@export var message_begin: String = "Press":
	set(value):
		_message_begin = value
		update_text()
	get:
		return _message_begin

@export var message_end: String = "to interact":
	set(value):
		_message_end = value
		update_text()
	get:
		return _message_end

## Turn about the vertical to face the current camera while shown, so the row reads the right way round from
## whichever side the player walked up; off, the prompt keeps the facing it was placed with.
@export var face_camera: bool = true

## Space between the button art and the text on either side of it, in metres.
@export var glyph_gap: float = 0.05:
	set(value):
		glyph_gap = value
		update_text()

@onready var label_3d_1: Label3D = $KeyboardMouse/Label3D
@onready var label_3d_2: Label3D = $Microsoft/Label3D
@onready var label_3d_3: Label3D = $Nintendo/Label3D
@onready var label_3d_4: Label3D = $Sony/Label3D

@onready var label_3d_2_1: Label3D = $KeyboardMouse/Label3D2
@onready var label_3d_2_2: Label3D = $Microsoft/Label3D2
@onready var label_3d_2_3: Label3D = $Nintendo/Label3D2
@onready var label_3d_2_4: Label3D = $Sony/Label3D2


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not Engine.is_editor_hint():
		hide()
	# In the editor the row has to follow anything that changes its width, and a label's own font, font_size
	# and pixel_size have no signal to listen to, so they are checked each frame. Editor only: at runtime the
	# width only changes when the text does, and setting the text lays the row out itself.
	set_process(Engine.is_editor_hint())
	update_text()


## The per-frame pass has one job in each place it runs. In the editor it re-spaces the rows, so the inspector
## shows the real spacing while it is being typed into; in a running game it turns the prompt to the camera,
## and only while one is shown with [member face_camera] on.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		lay_out_all()
		return
	face_the_camera()


## Re-spaces every sub-prompt from its own text. [method lay_out] writes nothing when the numbers already match,
## so an idle scene is not marked unsaved by this.
func lay_out_all() -> void:
	for child: Node3D in get_children():
		lay_out(child)


## Turns the prompt about the vertical so its text reads square to the current camera. The scale the node was
## placed with is kept: [method Basis.looking_at] returns an orthonormal basis, so writing it straight to
## [member Node3D.global_basis] would throw away a scale set here or inherited from a parent.
func face_the_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or not is_visible_in_tree():
		return
	var to_camera: Vector3 = camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() <= 0.0001:
		return
	var scale_was: Vector3 = global_basis.get_scale()
	# The text reads from +Z, so the row's +Z goes toward the camera
	global_basis = Basis.looking_at(-to_camera.normalized(), Vector3.UP).scaled(scale_was)


## Shows only the sub-prompt matching [param controls]' current input type (child names mirror
## [enum Controls.InputType] keys in PascalCase). [param action_label] names the bottom-action button on those
## controls while the prompt is up ("Get In"): the label is kept on the [Controls] node, so every label refresh
## meanwhile re-applies it.
func show_for(controls: Controls, action_label: String = "") -> void:
	if not is_instance_valid(controls):
		return
	# There is no sub-prompt for touch; it borrows the Microsoft art, the way the HUD's own buttons do.
	var input_type: Controls.InputType = controls.current_input_type
	if input_type == Controls.InputType.TOUCH:
		input_type = Controls.InputType.MICROSOFT
	var type_name: String = String(Controls.InputType.keys()[input_type]).to_pascal_case()
	for child: Node3D in get_children():
		child.visible = child.name == type_name
		if child.visible:
			_match_glyph(child, controls)
	if action_label != "":
		controls.claim_action_label(action_label, self)
	show()
	set_process(Engine.is_editor_hint() or face_camera)


## Draws on [param row]'s glyph the button the HUD binds to its [member Controls.prompt_action] (Y where a scheme
## put Action there, A where it did not), so the world prompt and the HUD agree; with no action named, the
## scene's own art stays.
func _match_glyph(row: Node3D, controls: Controls) -> void:
	var glyph: MeshInstance3D = row.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if glyph == null or controls.prompt_action.is_empty():
		return
	var button: TouchScreenButton = controls.action_button(controls.prompt_action)
	var art: Texture2D = controls.button_art(button) if button else null
	if art == null:
		return
	var material: StandardMaterial3D = glyph.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		var base: Material = glyph.mesh.surface_get_material(0) if glyph.mesh else null
		material = base.duplicate() as StandardMaterial3D if base is StandardMaterial3D else StandardMaterial3D.new()
		glyph.set_surface_override_material(0, material)
	material.albedo_texture = art


## Hides the prompt and gives the bottom-action button its label back (unless another prompt has taken it since).
func hide_for(controls: Controls) -> void:
	hide()
	set_process(Engine.is_editor_hint())
	if not is_instance_valid(controls):
		return
	controls.release_action_label(self)


## Hides the prompt and every sub-prompt.
func hide_all() -> void:
	for child: Node3D in get_children():
		child.hide()
	hide()


func update_text() -> void:
	if not is_node_ready():
		return

	label_3d_1.text = message_begin
	label_3d_2.text = message_begin
	label_3d_3.text = message_begin
	label_3d_4.text = message_begin
	label_3d_2_1.text = message_end
	label_3d_2_2.text = message_end
	label_3d_2_3.text = message_end
	label_3d_2_4.text = message_end

	lay_out_all()


## Spaces one sub-prompt out from the width of its own text: [code]begin[/code], gap, button art, gap,
## [code]end[/code], centred on this node so the phrase sits balanced over whatever the prompt is attached to.
## The X of all three is this method's to set; whatever the scene holds is overwritten.
func lay_out(row: Node3D) -> void:
	var begin: Label3D = row.get_node_or_null("Label3D") as Label3D
	var glyph: MeshInstance3D = row.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var end: Label3D = row.get_node_or_null("Label3D2") as Label3D
	if begin == null or glyph == null or end == null:
		return

	var begin_width: float = text_width(begin)
	var end_width: float = text_width(end)
	var glyph_width: float = glyph_size(glyph).x
	# A gap belongs next to text that is there; an empty side takes its gap with it rather than leaving a hole.
	var begin_gap: float = glyph_gap if begin_width > 0.0 else 0.0
	var end_gap: float = glyph_gap if end_width > 0.0 else 0.0

	var x: float = -(begin_width + begin_gap + glyph_width + end_gap + end_width) / 2.0
	_place(begin, x + begin_width / 2.0)
	x += begin_width + begin_gap
	_place(glyph, x + glyph_width / 2.0)
	x += glyph_width + end_gap
	_place(end, x + end_width / 2.0)


## Moves [param node] to [param x], and only when it is not already there: assigning a transform every frame
## would leave the editor showing an untouched scene as modified.
func _place(node: Node3D, x: float) -> void:
	if not is_equal_approx(node.position.x, x):
		node.position.x = x


## How wide [param label] renders, in metres. Measured from the font rather than the drawn mesh, because the
## mesh is not rebuilt until the frame after the text is set and the layout has to be right straight away.
func text_width(label: Label3D) -> float:
	if label.text.is_empty():
		return 0.0
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size


## How big [param glyph]'s quad is, in metres, its own scale included.
func glyph_size(glyph: MeshInstance3D) -> Vector2:
	var quad: QuadMesh = glyph.mesh as QuadMesh
	if quad == null:
		return Vector2(glyph.get_aabb().size.x * glyph.scale.x, glyph.get_aabb().size.y * glyph.scale.y)
	return quad.size * Vector2(glyph.scale.x, glyph.scale.y)
