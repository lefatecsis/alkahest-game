shader_type spatial;

// The Breath of the Wild look, written for this addon after the way the game reads and after NekotoArts' CC0 "TRUE
// BoTW Toon Shader" (godotshaders.com/shader/update-botw-toon-shader). What BOTW does, as far as anyone outside
// Nintendo has documented it (the zeldaret decompilation covers the game's C++ and carries no shader source):
//  - two bands of light, a lit one in the sun's colour and a shadow one lit by the sky, so shadows read blue-grey;
//  - a terminator that wobbles slightly instead of running as a clean line (the "warbly" shadow), here a bit of
//    animated value noise on the threshold, in world space so it does not swim with the camera;
//  - a soft-edged highlight rather than a hard toon dot, only where the surface is lit;
//  - a rim that shows mostly when the object is seen against the light (the backlit contour), with a fainter one on
//    the lit side, gated so it never lights the inside of a shadow.
// Point and spot lights add their lit band only; the sky-lit shadow comes from the directional sun alone, so several
// lights do not stack shadow colour. The engine's ambient and sky light land on top of both bands as usual.

group_uniforms Albedo;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;

group_uniforms Bands;
uniform float shadow_threshold : hint_range(-1.0, 1.0, 0.01) = 0.12; // The N.L where the lit band gives way to shadow.
uniform float shadow_softness : hint_range(0.0, 0.5, 0.01) = 0.04; // Width of the edge between the bands.
uniform vec4 shadow_color : source_color = vec4(0.36, 0.42, 0.58, 1.0); // What the sky lights the shadow band with.
uniform vec4 light_tint : source_color = vec4(1.0); // Multiplies the sun on the lit band.

group_uniforms Warble;
uniform float warble_amount : hint_range(0.0, 0.5, 0.01) = 0.08; // How far the terminator wanders.
uniform float warble_scale : hint_range(0.1, 20.0, 0.1) = 3.0; // Noise cells per metre.
uniform float warble_speed : hint_range(0.0, 3.0, 0.05) = 0.3;

group_uniforms Specular;
uniform float specular_amount : hint_range(0.0, 1.0, 0.05) = 0.3;
uniform float specular_size : hint_range(1.0, 256.0, 1.0) = 32.0; // Glossiness: bigger is a tighter highlight.
uniform float specular_softness : hint_range(0.0, 1.0, 0.05) = 0.5; // Soft edge on the highlight; 0 is a hard dot.

group_uniforms Rim;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float rim_size : hint_range(0.0, 1.0, 0.01) = 0.62; // Fresnel where the rim starts; smaller is a wider rim.
uniform float rim_softness : hint_range(0.0, 0.5, 0.01) = 0.1;
uniform float rim_lit : hint_range(0.0, 1.0, 0.05) = 0.3; // The rim's strength on the lit band.
uniform float rim_backlight : hint_range(0.0, 2.0, 0.05) = 1.0; // Its strength when the object stands against the light.

varying vec3 world_position;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth value noise, 0 to 1.
float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x00 = mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x);
	float x10 = mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x);
	float x01 = mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x);
	float x11 = mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = (texture(albedo_texture, UV) * albedo_color).rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float warble = (value_noise(world_position * warble_scale + vec3(TIME * warble_speed)) - 0.5) * 2.0 * warble_amount;
	float ndotl = dot(NORMAL, LIGHT) + warble;
	float lit = smoothstep(shadow_threshold - shadow_softness, shadow_threshold + shadow_softness, ndotl) * ATTENUATION;

	// The two bands
	vec3 band = lit * LIGHT_COLOR * light_tint.rgb;
	if (LIGHT_IS_DIRECTIONAL) {
		band += (1.0 - lit) * shadow_color.rgb;
	}
	DIFFUSE_LIGHT += ALBEDO * band;

	// A soft highlight on the lit band only
	vec3 half_vector = normalize(LIGHT + VIEW);
	float highlight = pow(max(dot(NORMAL, half_vector), 0.0), specular_size);
	highlight = smoothstep(0.5 - specular_softness * 0.5, 0.5 + specular_softness * 0.5, highlight) * lit;
	SPECULAR_LIGHT += LIGHT_COLOR * highlight * specular_amount;

	// The rim: strongest against the light, faint on the lit side, never inside a shadow
	float fresnel = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = smoothstep(rim_size - rim_softness, rim_size + rim_softness, fresnel);
	float against = smoothstep(0.0, 0.6, -dot(VIEW, LIGHT));
	rim *= ATTENUATION * (lit * rim_lit + against * rim_backlight);
	DIFFUSE_LIGHT += rim_color.rgb * LIGHT_COLOR * rim;
}
