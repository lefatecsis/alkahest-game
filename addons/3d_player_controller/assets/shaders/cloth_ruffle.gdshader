shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.65;
uniform float specular : hint_range(0.0, 1.0) = 0.25;

// Subtle gentle vertex flutter (avoids polygon tearing)
group_uniforms Vertex_Motion;
uniform bool enable_vertex_motion = true;
uniform float vertex_wave_speed : hint_range(0.0, 20.0) = 6.0;
uniform float vertex_wave_strength : hint_range(0.0, 0.05) = 0.004;
uniform float vertex_wave_frequency : hint_range(0.1, 10.0) = 2.5;

// High-detail cloth ruffle (Normal perturbation for realistic fabric ripples)
group_uniforms Normal_Ruffle;
uniform float ripple_speed : hint_range(0.0, 40.0) = 14.0;
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.45;
uniform float ripple_frequency : hint_range(0.5, 60.0) = 18.0;
uniform float flutter_speed : hint_range(0.0, 60.0) = 28.0;
uniform float flutter_frequency : hint_range(1.0, 80.0) = 36.0;

varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
	
	if (enable_vertex_motion) {
		// Smooth, unified wave oscillation across the canopy
		float wave = sin(VERTEX.x * vertex_wave_frequency + VERTEX.z * (vertex_wave_frequency * 0.7) - TIME * vertex_wave_speed);
		float cross = cos(VERTEX.x * (vertex_wave_frequency * 1.2) - VERTEX.z * vertex_wave_frequency - TIME * (vertex_wave_speed * 1.1));
		VERTEX += NORMAL * ((wave * 0.6 + cross * 0.4) * vertex_wave_strength);
	}
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	
	// High-frequency animated normal perturbation for realistic wind ruffle
	vec2 uv_flow = v_local_pos.xz * ripple_frequency;
	float t = TIME * ripple_speed;
	
	float w1 = sin(uv_flow.x * 0.8 + uv_flow.y * 1.2 - t);
	float w2 = cos(uv_flow.x * 1.4 - uv_flow.y * 0.9 - t * 1.2);
	
	vec2 uv_flutter = v_local_pos.xz * flutter_frequency;
	float tf = TIME * flutter_speed;
	float f1 = sin(uv_flutter.x + uv_flutter.y * 1.3 + tf);
	float f2 = cos(uv_flutter.x * 1.5 - uv_flutter.y * 1.1 + tf * 1.25);
	
	float norm_dx = (w1 * 0.6 + f1 * 0.4) * ripple_strength;
	float norm_dz = (w2 * 0.6 + f2 * 0.4) * ripple_strength;
	
	vec3 ripple_normal = normalize(vec3(norm_dx, 1.0, norm_dz));
	
	// Blend ripple with geometry normal
	NORMAL = normalize(NORMAL + (ripple_normal.x * vec3(1.0, 0.0, 0.0) + ripple_normal.z * vec3(0.0, 0.0, 1.0)) * 0.15);
}
