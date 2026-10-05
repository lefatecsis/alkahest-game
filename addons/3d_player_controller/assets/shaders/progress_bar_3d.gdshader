shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

// Per-instance so every bar tracks its own progress and colour with one shared material.
instance uniform float ratio : hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 fill_color : source_color = vec4(0.35, 0.85, 0.3, 1.0);
uniform vec4 background_color : source_color = vec4(0.1, 0.1, 0.1, 0.75);

void vertex() {
	// Billboard the quad towards the camera, keeping node scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0],
			INV_VIEW_MATRIX[1],
			INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]) * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float fill = step(UV.x, ratio);
	vec4 color = mix(background_color, fill_color, fill);
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
