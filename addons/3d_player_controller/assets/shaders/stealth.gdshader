shader_type spatial;
// Stealth: the model becomes a pale, frosted ghost of itself. This is the second of two passes: it is the
// next_pass of a stealth_depth.gdshader material that has already written the body's depth, and it draws after
// it without writing depth of its own, so only the nearest surface is coloured and limbs never show through the
// body. The colour washes toward white while a texture keeps its detail under it.
render_mode depth_draw_never, cull_back;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform vec4 tint : source_color = vec4(1.0); // Multiplied over the washed colour; white leaves it frosted
uniform float brighten : hint_range(0.0, 1.0) = 0.9; // How far the surface's colour washes out toward white
uniform float alpha : hint_range(0.0, 1.0) = 1.0; // 1 is solid; the Player tweens it down as stealth settles in
uniform float rim : hint_range(0.0, 1.0) = 0.2; // The silhouette keeps this much more of its opacity, so it still reads

void fragment() {
	vec4 texel = use_texture ? texture(albedo_texture, UV) : vec4(1.0);
	float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge_alpha = alpha + rim * (1.0 - alpha);
	ALBEDO = texel.rgb * mix(albedo_color.rgb, vec3(1.0), brighten) * tint.rgb;
	ALPHA = texel.a * albedo_color.a * mix(alpha, edge_alpha, fresnel * fresnel);
}
