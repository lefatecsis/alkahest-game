// The view through a spyglass: a round porthole, black beyond it, a brass ring at its edge, and a lens that
// darkens and splits its colours a little toward the rim, as real glass does.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// Radius of the porthole, as a share of the screen's shorter side.
uniform float radius : hint_range(0.1, 0.8) = 0.46;
// How soft its edge is, in the same units.
uniform float softness : hint_range(0.0, 0.1) = 0.012;
uniform vec4 rim_color : source_color = vec4(0.62, 0.43, 0.2, 1.0);
uniform float rim_width : hint_range(0.0, 0.1) = 0.014;
// How much the lens darkens toward its edge.
uniform float vignette : hint_range(0.0, 1.0) = 0.45;
// How far the colours split at the rim, in UV.
uniform float aberration : hint_range(0.0, 0.02) = 0.004;

void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	// Centred and aspect-correct: 1 is the screen's shorter side, whatever its shape.
	vec2 p = (SCREEN_UV - 0.5) * size / min(size.x, size.y);
	float d = length(p);
	float edge = clamp(d / radius, 0.0, 1.0);
	vec2 split = (SCREEN_UV - 0.5) * aberration * edge * edge;
	vec3 scene = vec3(
		texture(screen_texture, SCREEN_UV + split).r,
		texture(screen_texture, SCREEN_UV).g,
		texture(screen_texture, SCREEN_UV - split).b
	);
	scene *= 1.0 - vignette * smoothstep(0.55, 1.0, edge);
	float inside = 1.0 - smoothstep(radius - softness, radius, d);
	float ring = smoothstep(radius - rim_width - softness, radius - rim_width, d) * inside;
	// A little shading across the ring, lit from above, so it reads as metal rather than a flat band.
	vec3 brass = rim_color.rgb * (0.75 + 0.35 * -p.y / max(d, 1e-4));
	vec3 color = mix(scene, brass, ring);
	COLOR = vec4(color * inside, 1.0);
}
