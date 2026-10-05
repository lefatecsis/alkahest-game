@tool
class_name CelCompositorEffect
extends CompositorEffect
## Cel shading in the Forward+ compositor, the [ToonFilter]'s CEL mode. A compute shader runs once per view after the
## transparent pass and rewrites the colour buffer in place: the luminance is snapped to [member bands] hard steps
## (hue and saturation kept, saturation pushed by [member saturation_boost]) and [member outline_color] ink is laid
## where the depth or the view-space normal jumps against a neighbour [member outline_thickness] pixels away. The
## normal-roughness buffer is what Forward+ adds over the quad filter: creases and folds inside a silhouette get ink
## too. Pixels on the far plane are left alone, so the sky keeps its gradient. Transparent objects are in the colour
## buffer by then but not in the depth buffer, so they are banded but never outlined.
##
## The shader and pipeline are built on the render thread from [member _init] and freed in NOTIFICATION_PREDELETE.
## Without a [RenderingDevice] (headless, Compatibility) nothing is built and the callback is a no-op.

const GLSL: String = """
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;
layout(set = 0, binding = 2) uniform sampler2D normal_texture;

layout(push_constant, std430) uniform Params {
	mat4 inv_projection;
	vec2 raster_size;
	float bands;
	float outline_thickness;
	float depth_threshold;
	float normal_threshold;
	float saturation_boost;
	float has_normals;
	vec4 outline_color;
} params;

const float FAR_CAP = 4000.0; // metres; the far plane, capped
const float SHADOW_FLOOR = 0.35; // perceptual brightness of the darkest band; the lightest is 1.0
const float GAMMA = 2.2;

// View-space distance of the pixel at uv, in metres.
float linear_depth(vec2 uv) {
	float depth = texture(depth_texture, uv).r;
	vec4 view = params.inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return clamp(-view.z / view.w, 0.0, FAR_CAP);
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_texture, uv).xyz * 2.0 - 1.0);
}

void main() {
	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);
	if (xy.x >= int(params.raster_size.x) || xy.y >= int(params.raster_size.y)) {
		return;
	}
	vec2 uv = (vec2(xy) + 0.5) / params.raster_size;
	// Reverse-Z: the far plane is 0. Nothing was drawn there but the sky, which keeps its gradient
	if (texture(depth_texture, uv).r <= 0.0) {
		return;
	}
	vec4 scene = imageLoad(color_image, xy);
	// Hard bands: the luminance is snapped to one of `bands` perceptual levels between SHADOW_FLOOR and 1.0
	float lum = dot(scene.rgb, vec3(0.2126, 0.7152, 0.0722));
	float perceptual = pow(clamp(lum, 0.0, 1.0), 1.0 / GAMMA);
	float band = min(floor(perceptual * params.bands), params.bands - 1.0);
	float toon_lum = pow(mix(SHADOW_FLOOR, 1.0, band / (params.bands - 1.0)), GAMMA);
	// Scale the colour to the band so hue and saturation survive, then push the saturation
	vec3 toon = scene.rgb * (toon_lum / max(lum, 0.0001));
	toon = max(mix(vec3(toon_lum), toon, 1.0 + params.saturation_boost), vec3(0.0));
	// Ink where the depth or the normal jumps against any of the four neighbours
	float depth = linear_depth(uv);
	vec3 normal = view_normal(uv);
	vec2 px = params.outline_thickness / params.raster_size;
	vec2 offsets[4] = vec2[4](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
	float depth_jump = 0.0;
	float normal_jump = 0.0;
	for (int i = 0; i < 4; i++) {
		depth_jump = max(depth_jump, abs(linear_depth(uv + offsets[i]) - depth));
		normal_jump = max(normal_jump, length(view_normal(uv + offsets[i]) - normal));
	}
	float edge = step(params.depth_threshold * max(depth, 0.1), depth_jump);
	edge = max(edge, step(params.normal_threshold, normal_jump) * params.has_normals);
	vec3 color = mix(toon, params.outline_color.rgb, edge * params.outline_color.a);
	imageStore(color_image, xy, vec4(color, scene.a));
}
"""

const NORMAL_ROUGHNESS_CONTEXT: StringName = &"forward_clustered"
const NORMAL_ROUGHNESS_NAME: StringName = &"normal_roughness"
const WORKGROUP: int = 8

@export_range(2, 8) var bands: int = 3 ## Hard light steps the picture is snapped to.
@export_range(1.0, 4.0) var outline_thickness: float = 2.0 ## Pixels between a pixel and the neighbours it is compared with.
@export_range(0.01, 1.0) var depth_threshold: float = 0.1 ## Depth jump, as a share of the depth, that counts as an edge.
@export_range(0.05, 2.0) var normal_threshold: float = 0.5 ## Distance between two unit normals that counts as a crease (0.5 is about 30 degrees).
@export_range(0.0, 1.0) var saturation_boost: float = 0.2 ## 0 keeps the scene's saturation.
@export var outline_color: Color = Color(0.05, 0.03, 0.06, 1.0) ## Alpha is the ink's opacity.

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sampler: RID


func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_normal_roughness = true
	access_resolved_color = true
	access_resolved_depth = true
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		print_verbose("CelCompositorEffect: no RenderingDevice (headless or Compatibility), the effect is inert")
		return
	RenderingServer.call_on_render_thread(_initialize_compute)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		if shader.is_valid():
			rd.free_rid(shader) # Frees the pipeline with it
		if sampler.is_valid():
			rd.free_rid(sampler)


## Render thread: compiles the GLSL and builds the pipeline and the nearest sampler the depth and normals are read with.
func _initialize_compute() -> void:
	var source: RDShaderSource = RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = GLSL
	var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_compute != "":
		push_error("CelCompositorEffect: " + spirv.compile_error_compute)
		return
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	var state: RDSamplerState = RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler = rd.sampler_create(state)


## Render thread, once per frame: dispatches the shader over every view's colour buffer.
func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if rd == null or not pipeline.is_valid() or callback_type != effect_callback_type or render_data == null:
		return
	var buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene_data: RenderSceneData = render_data.get_render_scene_data()
	if buffers == null or scene_data == null:
		return
	var size: Vector2i = buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var has_normals: bool = buffers.has_texture(NORMAL_ROUGHNESS_CONTEXT, NORMAL_ROUGHNESS_NAME)
	var groups_x: int = (size.x - 1) / WORKGROUP + 1
	var groups_y: int = (size.y - 1) / WORKGROUP + 1
	for view: int in buffers.get_view_count():
		var color_image: RID = buffers.get_color_layer(view)
		var depth_texture: RID = buffers.get_depth_layer(view)
		var normal_texture: RID = depth_texture # Bound but ignored when Forward+ did not write normals
		if has_normals:
			normal_texture = buffers.get_texture_slice(NORMAL_ROUGHNESS_CONTEXT, NORMAL_ROUGHNESS_NAME, view, 0, 1, 1)
		var uniform_set: RID = UniformSetCacheRD.get_cache(shader, 0, [
			_image_uniform(0, color_image),
			_sampler_uniform(1, depth_texture),
			_sampler_uniform(2, normal_texture),
		])
		var push_constant: PackedByteArray = _push_constant(scene_data.get_view_projection(view).inverse(), size, has_normals)
		var compute_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
		rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
		rd.compute_list_end()


## The Params block: 112 bytes, a multiple of 16 as push constants must be.
func _push_constant(inv_projection: Projection, size: Vector2i, has_normals: bool) -> PackedByteArray:
	var floats: PackedFloat32Array = PackedFloat32Array()
	for column: Vector4 in [inv_projection.x, inv_projection.y, inv_projection.z, inv_projection.w]:
		floats.append_array(PackedFloat32Array([column.x, column.y, column.z, column.w]))
	floats.append_array(PackedFloat32Array([float(size.x), float(size.y), float(bands), outline_thickness]))
	floats.append_array(PackedFloat32Array([depth_threshold, normal_threshold, saturation_boost, 1.0 if has_normals else 0.0]))
	floats.append_array(PackedFloat32Array([outline_color.r, outline_color.g, outline_color.b, outline_color.a]))
	return floats.to_byte_array()


func _image_uniform(binding: int, image: RID) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(image)
	return uniform


func _sampler_uniform(binding: int, texture: RID) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding
	uniform.add_id(sampler)
	uniform.add_id(texture)
	return uniform
