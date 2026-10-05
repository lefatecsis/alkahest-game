extends GutTest

## Purpose: the F3 debug HUD lets a captured mouse go while it is open, so its toggles can be clicked, and hands it
## back when it closes.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var player: Player
var debug: Debug


func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	debug = player.get_node("Hud/Debug") as Debug
	await wait_physics_frames(2)


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_opening_the_hud_lets_a_captured_mouse_go_and_closing_it_takes_it_back() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		pass_test("A headless run cannot capture the mouse, so there is nothing to let go of")
		return
	debug.show()
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "The toggles want a pointer")
	debug.hide()
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED, "and the game gets its mouse back")
