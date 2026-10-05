// Screen-space toon filter on a full-screen quad under the camera: the opaque scene is posterised into a few
// luminance bands (hue and saturation kept) and dark outlines are inked where the depth buffer jumps. Only the
// screen and depth textures are read, so it compiles in Forward+, Mobile and Compatibility alike.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform int bands : hint_range(2, 16) = 4; // luminance steps the picture is flattened into
uniform float softness : hint_range(0.0, 0.5) = 0.08; // width of the ramp between two bands, as a share of a band
uniform vec4 outline_color : source_color = vec4(0.05, 0.03, 0.06, 1.0); // alpha is the outline's opacity
uniform float outline_threshold : hint_range(0.01, 1.0) = 0.12; // depth jump, as a share of the depth, that counts as an edge
uniform float outline_thickness : hint_range(0.5, 4.0) = 1.5; // pixels
uniform float outline_distance : hint_range(1.0, 500.0) = 80.0; // metres past which outlines fade out
uniform float strength : hint_range(0.0, 1.0) = 1.0; // 0 shows the plain scene

const float FAR_CAP = 4000.0; // the sky's infinite depth, capped

void vertex() {
	// Cover the screen whatever the quad's transform: straight to clip space (z = 1 is the near plane under reverse-Z)
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// View-space distance of the pixel at uv, in metres.
float linear_depth(vec2 uv, mat4 inv_projection) {
	float depth = texture(depth_texture, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = ndc.z * 2.0 - 1.0;
#endif
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return clamp(-view.z / view.w, 0.0, FAR_CAP);
}

void fragment() {
	vec3 scene = texture(screen_texture, SCREEN_UV).rgb;
	// Posterise the luminance, then scale the colour to it so hue and saturation survive
	float lum = dot(scene, vec3(0.2126, 0.7152, 0.0722));
	float steps = float(bands);
	float band = lum * steps;
	float level = floor(band) + smoothstep(1.0 - softness, 1.0, fract(band));
	float toon_lum = clamp((level + 0.5) / steps, 0.0, 1.0);
	vec3 toon = scene * (toon_lum / max(lum, 0.001));
	// Ink where the depth jumps against a neighbour; the jump is relative to the depth, and far outlines fade
	float depth = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec2 px = outline_thickness / VIEWPORT_SIZE;
	float jump = abs(linear_depth(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX) - depth);
	jump = max(jump, abs(linear_depth(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX) - depth));
	jump = max(jump, abs(linear_depth(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX) - depth));
	jump = max(jump, abs(linear_depth(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX) - depth));
	float threshold = outline_threshold * max(depth, 0.1);
	float edge = smoothstep(threshold, threshold * 2.0, jump) * (1.0 - smoothstep(outline_distance * 0.5, outline_distance, depth));
	vec3 color = mix(toon, outline_color.rgb, edge * outline_color.a);
	ALBEDO = mix(scene, color, strength);
}
