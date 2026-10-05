class_name MuzzleFlash
extends Node3D
## Plays a one-shot flash VFX at a gun's muzzle: hidden at rest, shown for the length of the VFX's
## "main" animation when the weapon fires. Any VFX scene with an AnimationPlayer works; wire the
## weapon's [signal Firearm.fired] to [method flash] and the player's animation_finished to
## [method _on_animation_finished] in the scene. Sit it under the Muzzle marker and turn and scale it so the
## VFX's forward axis (+X for the Binbun flashes) runs down the marker's -Z, the barrel.

const FLASH_ANIMATION: StringName = &"main"

@export var vfx: Node3D ## The flash scene; hidden between shots so its light and glow do not linger.
@export var animation_player: AnimationPlayer ## The VFX's player; its "main" animation is one flash.


func _ready() -> void:
	if is_instance_valid(vfx):
		vfx.hide()


## Shows the flash and plays it from the start; [param _projectile] is the round [signal Firearm.fired]
## carries, unused here.
func flash(_projectile: Projectile = null) -> void:
	if not is_instance_valid(vfx) or not is_instance_valid(animation_player):
		return
	vfx.show()
	animation_player.stop()
	animation_player.play(FLASH_ANIMATION)


func _on_animation_finished(_animation: StringName) -> void:
	if is_instance_valid(vfx):
		vfx.hide()
