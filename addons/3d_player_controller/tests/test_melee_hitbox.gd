extends GutTest

## Purpose: A melee hitbox hurts only what it actually overlaps, only while the swing is live, once per
## swing, and never its own attacker.

const HITBOX_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/melee_hitbox.tscn")


class Dummy extends CharacterBody3D:
	var hits: Array[float] = []
	func take_hit(damage: float, _from: Vector3) -> void:
		hits.append(damage)


func _dummy(at: Vector3) -> Dummy:
	var body := Dummy.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	body.add_child(shape)
	body.position = at
	add_child_autofree(body)
	return body


func test_only_overlapped_bodies_are_hit_once_per_swing() -> void:
	var attacker: Dummy = _dummy(Vector3.ZERO)
	var near: Dummy = _dummy(Vector3(0.4, 0.0, 0.0))
	var far: Dummy = _dummy(Vector3(3.0, 0.0, 0.0))
	var hitbox: MeleeHitbox = HITBOX_SCENE.instantiate()
	hitbox.attacker = attacker
	hitbox.damage = 12.0
	attacker.add_child(hitbox)
	watch_signals(hitbox)
	await wait_physics_frames(2)
	assert_false(hitbox.live, "Idle weapons hurt nobody")
	hitbox.swing()
	await wait_physics_frames(3)
	assert_eq(near.hits, [12.0] as Array[float], "The body inside the blade's reach is struck")
	assert_true(far.hits.is_empty(), "A body out of reach is not")
	assert_true(attacker.hits.is_empty(), "The attacker never hurts itself")
	assert_signal_emitted_with_parameters(hitbox, "hit", [near])
	await wait_physics_frames(3)
	assert_eq(near.hits.size(), 1, "One swing lands once even while the blade stays inside")
	await wait_seconds(0.5)
	assert_false(hitbox.live, "The swing ends after its active frames")
	hitbox.swing()
	await wait_physics_frames(3)
	assert_eq(near.hits.size(), 2, "The next swing lands again")
