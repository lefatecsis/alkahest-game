# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name Contrail3D
extends MeshInstance3D

## High-performance, cross-platform 3D Ribbon Contrail using ImmediateMesh.
## Compatible with all Godot renderers: Forward+, Mobile, and GL Compatibility (WebGL2).

@export var emitting: bool = false:
	set(val):
		emitting = val
		if not emitting and is_inside_tree() and points.is_empty():
			if mesh is ImmediateMesh:
				(mesh as ImmediateMesh).clear_surfaces()

@export_range(0.01, 10.0, 0.01) var lifetime: float = 1.0
@export_range(0.001, 2.0, 0.005) var width: float = 0.05
@export_range(0.01, 1.0, 0.01) var min_section_length: float = 0.04
@export var color_gradient: Gradient
@export var width_curve: Curve
@export var billboard: bool = false
@export var double_sided: bool = true

var points: Array[Vector3] = []
var point_ages: Array[float] = []
var point_axes: Array[Vector3] = []
var _last_spawn_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	if not (mesh is ImmediateMesh):
		mesh = ImmediateMesh.new()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_last_spawn_pos = global_position


func clear() -> void:
	points.clear()
	point_ages.clear()
	point_axes.clear()
	if mesh is ImmediateMesh:
		(mesh as ImmediateMesh).clear_surfaces()


func _process(delta: float) -> void:
	# Advance age of existing trail points
	var idx: int = 0
	while idx < points.size():
		point_ages[idx] += delta
		if point_ages[idx] >= lifetime:
			points.remove_at(idx)
			point_ages.remove_at(idx)
			point_axes.remove_at(idx)
		else:
			idx += 1

	var current_pos: Vector3 = global_position
	# Spawn new point when distance threshold is reached while emitting
	if emitting:
		var side_axis: Vector3 = global_transform.basis.x.normalized()
		if side_axis.is_zero_approx():
			side_axis = Vector3.RIGHT
		if points.is_empty():
			points.push_front(current_pos)
			point_ages.push_front(0.0)
			point_axes.push_front(side_axis)
			_last_spawn_pos = current_pos
		else:
			var dist: float = (current_pos - _last_spawn_pos).length()
			var spacing: float = maxf(min_section_length, 0.005)
			if dist >= spacing:
				# Sub-step interpolation for high-speed motion
				var step_dir: Vector3 = (current_pos - _last_spawn_pos) / dist
				var travel: float = spacing
				var count_added: int = 0
				while travel <= dist and count_added < 32:
					points.push_front(_last_spawn_pos + step_dir * travel)
					point_ages.push_front(0.0)
					point_axes.push_front(side_axis)
					travel += spacing
					count_added += 1
				_last_spawn_pos = current_pos

	_render_mesh()


func _render_mesh() -> void:
	var imm_mesh: ImmediateMesh = mesh as ImmediateMesh
	if not imm_mesh:
		return

	imm_mesh.clear_surfaces()

	var count: int = points.size()
	if count < 2:
		return

	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() else null

	# Pass 1: Forward winding
	_draw_strip_pass(imm_mesh, count, cam, false)
	# Pass 2: Reverse winding for double-sided rendering in Compatibility / WebGL
	if double_sided:
		_draw_strip_pass(imm_mesh, count, cam, true)


func _draw_strip_pass(imm_mesh: ImmediateMesh, count: int, cam: Camera3D, flip: bool) -> void:
	imm_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	for i: int in range(count):
		var t: float = clampf(point_ages[i] / maxf(lifetime, 0.001), 0.0, 1.0)

		# Calculate width from curve or linear fade
		var w_factor: float = width_curve.sample(t) if width_curve else (1.0 - t)
		var current_half_w: float = (width * 0.5) * w_factor

		# Calculate color from gradient or default white alpha fade
		var col: Color = color_gradient.sample(t) if color_gradient else Color(1.0, 1.0, 1.0, (1.0 - t) * 0.5)

		var side_dir: Vector3
		if billboard and is_instance_valid(cam):
			var to_cam: Vector3 = (cam.global_position - points[i]).normalized()
			var seg_forward: Vector3 = (points[maxi(0, i - 1)] - points[mini(count - 1, i + 1)]).normalized()
			if seg_forward.is_zero_approx():
				seg_forward = -global_transform.basis.z
			side_dir = to_cam.cross(seg_forward).normalized()
		else:
			side_dir = point_axes[i]

		var offset: Vector3 = side_dir * current_half_w
		var local_p1: Vector3 = to_local(points[i] + offset)
		var local_p2: Vector3 = to_local(points[i] - offset)

		imm_mesh.surface_set_color(col)
		imm_mesh.surface_set_uv(Vector2(0.0, t))
		imm_mesh.surface_add_vertex(local_p2 if flip else local_p1)

		imm_mesh.surface_set_color(col)
		imm_mesh.surface_set_uv(Vector2(1.0, t))
		imm_mesh.surface_add_vertex(local_p1 if flip else local_p2)

	imm_mesh.surface_end()
