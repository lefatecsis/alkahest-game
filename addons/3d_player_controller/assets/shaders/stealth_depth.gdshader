shader_type spatial;
// The first of stealth's two passes: it writes the body's depth and draws nothing, so the ghost that follows it
// (stealth.gdshader, this material's next_pass) colours only the nearest surface and the body reads as one pale
// shape. depth_draw_always writes depth whatever the alpha; the single depth_prepass_alpha pass this replaces let
// the far arm, the far leg and the joint bands show through the torso at stealth's alpha.
render_mode depth_draw_always, unshaded, cull_back;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
