extends GutTest
## The world prompt: it shows the sub-prompt for the device in hand and can name the HUD's bottom-action
## button after what it does while it is up.

const CONTROLS_SCENE: PackedScene = preload("res://addons/controls/controls.tscn")
const PROMPT_SCENE: PackedScene = preload("res://addons/controls/action_prompt.tscn")

var _controls: Controls
var _prompt: ActionPrompt


func before_each() -> void:
	_controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(_controls)
	_prompt = PROMPT_SCENE.instantiate()
	add_child_autofree(_prompt)


func test_hidden_until_shown() -> void:
	assert_false(_prompt.visible, "A prompt out of range is down")


func test_shows_the_sub_prompt_for_the_device_in_hand() -> void:
	_controls.current_input_type = Controls.InputType.SONY
	_prompt.show_for(_controls)
	assert_true(_prompt.visible)
	assert_true(_prompt.get_node("Sony").visible, "The PlayStation art is up")
	assert_false(_prompt.get_node("Microsoft").visible, "and no other")

	_controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	_prompt.show_for(_controls)
	assert_true(_prompt.get_node("KeyboardMouse").visible, "Switching device switches the art")
	assert_false(_prompt.get_node("Sony").visible)


## The three pieces are laid out from the width of the text, so any wording spaces evenly. Nothing here
## depends on the font: it asks only that the pieces sit in order, do not overlap, and stay centred.
func test_the_row_is_spaced_from_the_text_and_centred() -> void:
	for pair: Array in [["Press", "to open"], ["Hit", "to pry the lid off the crate"], ["Hold the button", "now"]]:
		_prompt.message_begin = pair[0]
		_prompt.message_end = pair[1]
		var row: Node3D = _prompt.get_node("KeyboardMouse")
		var begin: Label3D = row.get_node("Label3D")
		var glyph: MeshInstance3D = row.get_node("MeshInstance3D")
		var end_label: Label3D = row.get_node("Label3D2")

		var begin_right: float = begin.position.x + _prompt.text_width(begin) / 2.0
		var glyph_left: float = glyph.position.x - _prompt.glyph_size(glyph).x / 2.0
		var glyph_right: float = glyph.position.x + _prompt.glyph_size(glyph).x / 2.0
		var end_left: float = end_label.position.x - _prompt.text_width(end_label) / 2.0

		assert_almost_eq(glyph_left - begin_right, _prompt.glyph_gap, 0.0001,
			"'%s' sits one gap before the glyph" % pair[0])
		assert_almost_eq(end_left - glyph_right, _prompt.glyph_gap, 0.0001,
			"and '%s' one gap after it" % pair[1])

		var left_edge: float = begin.position.x - _prompt.text_width(begin) / 2.0
		var right_edge: float = end_label.position.x + _prompt.text_width(end_label) / 2.0
		assert_almost_eq(left_edge + right_edge, 0.0, 0.0001, "and the whole row is centred on the node")


## A side with nothing on it takes its gap with it, rather than leaving the glyph floating off to one side.
func test_a_blank_side_takes_its_gap_with_it() -> void:
	_prompt.message_begin = ""
	_prompt.message_end = "Open"
	var row: Node3D = _prompt.get_node("KeyboardMouse")
	var glyph: MeshInstance3D = row.get_node("MeshInstance3D")
	var end_label: Label3D = row.get_node("Label3D2")

	var glyph_width: float = _prompt.glyph_size(glyph).x
	var end_width: float = _prompt.text_width(end_label)
	assert_almost_eq(glyph.position.x - glyph_width / 2.0, -(glyph_width + _prompt.glyph_gap + end_width) / 2.0,
		0.0001, "With no leading text the glyph starts the row")
	assert_almost_eq(end_label.position.x + end_width / 2.0, (glyph_width + _prompt.glyph_gap + end_width) / 2.0,
		0.0001, "and the pair is still centred")


## The editor has to show the real spacing as it is typed into, and a label's own font settings have no signal
## to announce themselves, so the layout sweep is what keeps up with them. The editor runs it every frame.
func test_the_row_follows_a_label_that_changes_size() -> void:
	_prompt.message_begin = "Press"
	_prompt.message_end = "to open"
	var row: Node3D = _prompt.get_node("KeyboardMouse")
	var begin: Label3D = row.get_node("Label3D")
	var glyph: MeshInstance3D = row.get_node("MeshInstance3D")
	var was: float = glyph.position.x

	begin.font_size = begin.font_size * 3
	_prompt.lay_out_all()

	assert_ne(glyph.position.x, was, "Growing the text moves the glyph out of its way")
	var begin_right: float = begin.position.x + _prompt.text_width(begin) / 2.0
	var glyph_left: float = glyph.position.x - _prompt.glyph_size(glyph).x / 2.0
	assert_almost_eq(glyph_left - begin_right, _prompt.glyph_gap, 0.0001, "and the gap is still one gap")


## A running game lays the row out when the text is set, so a prompt nobody is standing at does no per-frame
## work at all; only showing one with [member ActionPrompt.face_camera] on buys a frame pass, and hiding it
## gives that back.
func test_the_per_frame_pass_is_only_bought_while_a_prompt_is_up() -> void:
	assert_false(_prompt.is_processing(), "A prompt out of range costs nothing")

	_prompt.show_for(_controls)
	assert_true(_prompt.is_processing(), "Facing the camera needs the frame pass")

	_prompt.hide_for(_controls)
	assert_false(_prompt.is_processing(), "and it is handed back when the prompt goes down")


## With the turn switched off the prompt keeps the facing it was placed with, so a row deliberately aimed
## along a wall stays there, and it pays for no frame pass either.
func test_face_camera_off_keeps_the_placed_facing() -> void:
	_prompt.face_camera = false
	var was: Basis = _prompt.global_basis
	_prompt.show_for(_controls)
	assert_false(_prompt.is_processing(), "No turn to make, so no frame pass")
	assert_eq(_prompt.global_basis, was, "The prompt is still facing where it was put")


## The turn is about the vertical only: the row stays upright however far above or below the camera sits,
## rather than tipping to look up at it.
func test_facing_the_camera_turns_about_the_vertical_only() -> void:
	var camera: Camera3D = Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	camera.global_position = Vector3(6.0, 9.0, 6.0)
	_prompt.show_for(_controls)
	_prompt.face_the_camera()

	assert_almost_eq(_prompt.global_basis.y.dot(Vector3.UP), 1.0, 0.0001, "The row is still upright")
	var facing: Vector3 = _prompt.global_basis.z
	var to_camera: Vector3 = (camera.global_position - _prompt.global_position)
	to_camera.y = 0.0
	assert_almost_eq(facing.normalized().dot(to_camera.normalized()), 1.0, 0.0001, "and its front is on the camera")


## The turn writes a whole basis, so it has to put back the scale the prompt was placed with rather than
## flattening it to one.
func test_facing_the_camera_keeps_the_prompts_scale() -> void:
	var camera: Camera3D = Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	camera.global_position = Vector3(0.0, 1.0, 5.0)
	_prompt.scale = Vector3(2.0, 2.0, 2.0)
	_prompt.show_for(_controls)
	_prompt.face_the_camera()

	assert_almost_eq(_prompt.global_basis.get_scale().x, 2.0, 0.0001, "The prompt is the size it was placed at")


## Every device gets the same treatment, not just the one the demo happens to be showing.
func test_every_sub_prompt_is_laid_out() -> void:
	_prompt.message_begin = "Hit"
	_prompt.message_end = "to pry the lid off the crate"
	for row_name: String in ["KeyboardMouse", "Microsoft", "Nintendo", "Sony"]:
		var row: Node3D = _prompt.get_node(row_name)
		var begin: Label3D = row.get_node("Label3D")
		var end_label: Label3D = row.get_node("Label3D2")
		var left_edge: float = begin.position.x - _prompt.text_width(begin) / 2.0
		var right_edge: float = end_label.position.x + _prompt.text_width(end_label) / 2.0
		assert_almost_eq(left_edge + right_edge, 0.0, 0.0001, "%s is centred too" % row_name)


func test_message_reads_press_something_to_do_something() -> void:
	_prompt.message_end = "to open"
	assert_eq(_prompt.label_3d_1.text, "Press")
	assert_eq(_prompt.label_3d_2_1.text, "to open", "Every device's second label follows the message")
	assert_eq(_prompt.label_3d_2_4.text, "to open")


func test_showing_with_a_label_names_the_action_button() -> void:
	_prompt.show_for(_controls, "Open")
	assert_eq(_controls.prompt_action_label, "Open")
	assert_eq(_controls.joypad_button_0_label.text, "Open")


func test_hiding_gives_the_label_back() -> void:
	_prompt.show_for(_controls, "Open")
	_prompt.hide_for(_controls)
	assert_false(_prompt.visible)
	assert_eq(_controls.prompt_action_label, "", "The button is the state's again")


## Leaving a crate while sitting in a car has to leave the car's label alone.
func test_hiding_one_prompt_leaves_anothers_label() -> void:
	var other: ActionPrompt = PROMPT_SCENE.instantiate()
	add_child_autofree(other)

	_prompt.show_for(_controls, "Open")
	other.show_for(_controls, "Get In")
	_prompt.hide_for(_controls)

	assert_eq(_controls.prompt_action_label, "Get In", "The prompt still in range keeps the button")


func test_hide_all_takes_every_sub_prompt_down() -> void:
	_prompt.show_for(_controls)
	_prompt.hide_all()
	assert_false(_prompt.visible)
	for child: Node3D in _prompt.get_children():
		assert_false(child.visible, "%s is down too" % child.name)


## A project with no HUD in the scene, or one asking before the HUD is ready, hands over null rather than a
## node; the prompt has to cope instead of erroring.
func test_no_controls_node_is_survivable() -> void:
	_prompt.show_for(null, "Open")
	assert_false(_prompt.visible, "Nothing to read the device off, so the prompt stays down")
	_prompt.show_for(_controls)
	_prompt.hide_for(null)
	assert_false(_prompt.visible, "Hiding still works")
