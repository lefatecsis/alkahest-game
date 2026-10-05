shader_type spatial;
render_mode cull_disabled, unshaded;

uniform sampler2D texture_albedo : source_color;
uniform float texture_scale : hint_range(0.1, 10.0) = 1.0;
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform float animation_speed : hint_range(0.0, 5.0) = 1.0;
uniform bool animate = true;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Calculate animated offset
	float animated_y_offset = 0.0;
	if (animate) {
		// Linear animation that loops from -0.25 to 0.25 and repeats
		animated_y_offset = fract(TIME * animation_speed) * 0.5 - 0.25;
	}
	
	// Apply UV offset (like rotating a globe) then scale
	vec2 offset_uv = UV + uv_offset + vec2(0.0, animated_y_offset);
	vec2 scaled_uv = offset_uv * texture_scale;
	
	// Only show texture where UVs are in 0-1 range, otherwise transparent
	if (scaled_uv.x < 0.0 || scaled_uv.x > 1.0 || scaled_uv.y < 0.0 || scaled_uv.y > 1.0) {
		discard; // Make areas outside the texture transparent
	}
	
	vec4 tex_color = texture(texture_albedo, scaled_uv);
	ALBEDO = tex_color.rgb;
	ALPHA = tex_color.a;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
