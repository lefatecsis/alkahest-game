extends GutTest

## Purpose: a MuzzleFlash keeps its VFX hidden between shots, shows it and plays the "main" animation
## when the gun fires, and hides it again when the animation ends; a flash without its parts does nothing.

var flash: MuzzleFlash
var vfx: Node3D
var player: AnimationPlayer


func before_each() -> void:
	flash = MuzzleFlash.new()
	vfx = Node3D.new()
	vfx.name = "Flash"
	player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	var main := Animation.new()
	main.length = 0.05
	library.add_animation(MuzzleFlash.FLASH_ANIMATION, main)
	player.add_animation_library(&"", library)
	vfx.add_child(player)
	flash.add_child(vfx)
	flash.vfx = vfx
	flash.animation_player = player
	player.animation_finished.connect(flash._on_animation_finished)
	add_child_autofree(flash)


func test_hidden_at_rest() -> void:
	assert_false(vfx.visible, "Nothing shows until a shot")


func test_flash_shows_and_plays_then_hides() -> void:
	flash.flash()
	assert_true(vfx.visible, "The flash shows on fire")
	assert_true(player.is_playing())
	assert_eq(player.current_animation, String(MuzzleFlash.FLASH_ANIMATION))
	await wait_seconds(0.2)
	assert_false(vfx.visible, "Hidden again once the animation has ended")


func test_flash_restarts_when_fired_again_mid_animation() -> void:
	flash.flash()
	await wait_process_frames(2)
	var elapsed: float = player.current_animation_position
	flash.flash()
	assert_lt(player.current_animation_position, maxf(elapsed, 0.001), "A second shot plays from the start")
	assert_true(vfx.visible)


func test_a_flash_without_parts_does_nothing() -> void:
	var bare := MuzzleFlash.new()
	add_child_autofree(bare)
	bare.flash()
	pass_test("No error without a VFX or animation player")
