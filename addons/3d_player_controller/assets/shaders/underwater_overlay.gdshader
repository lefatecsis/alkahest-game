// Fullscreen underwater filter: wavy refraction of the screen plus a blue-green depth tint.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.07, 0.30, 0.45, 0.38);
uniform float wave_strength : hint_range(0.0, 0.02) = 0.0045;
uniform float wave_speed : hint_range(0.0, 8.0) = 1.6;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec2 uv = SCREEN_UV;
	uv.x += sin(uv.y * 26.0 + TIME * wave_speed) * wave_strength;
	uv.y += cos(uv.x * 22.0 + TIME * wave_speed * 1.3) * wave_strength * 0.7;
	vec3 scene = texture(screen_texture, uv).rgb;
	vec3 color = mix(scene, tint.rgb, tint.a);
	// Darkened edges sell the depth
	float vignette = length(SCREEN_UV - vec2(0.5)) * vignette_strength;
	color *= (1.0 - vignette);
	COLOR = vec4(color, 1.0);
}
