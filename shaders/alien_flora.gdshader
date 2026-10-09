shader_type spatial;
render_mode cull_disabled;
// Shared material for the procedural trees, shrubs, rocks and crystals.
// Vertex colour RGB is the surface colour; vertex alpha is how strongly that spot glows.

uniform float glow_strength = 2.5;
uniform float sway = 0.03;
uniform float roughness_value = 0.65;
uniform vec3 rim_color : source_color = vec3(0.45, 0.3, 0.8);
uniform float rim_strength = 0.35;

varying float glow;
varying vec3 instance_origin;

void vertex() {
	glow = COLOR.a;
	instance_origin = MODEL_MATRIX[3].xyz;
	// Taller parts lean further in the breeze, so trunks stay planted.
	float lean = sway * VERTEX.y * VERTEX.y * 0.1;
	VERTEX.x += sin(TIME * 0.9 + instance_origin.x * 0.2 + instance_origin.z * 0.31) * lean;
	VERTEX.z += cos(TIME * 0.7 + instance_origin.z * 0.17) * lean * 0.6;
}

void fragment() {
	float pulse = 0.75 + 0.25 * sin(TIME * 1.7 + instance_origin.x * 0.7 + instance_origin.z * 0.5);
	ALBEDO = COLOR.rgb * mix(1.0, 0.6, glow);
	ROUGHNESS = roughness_value;
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	EMISSION = COLOR.rgb * glow * glow_strength * pulse + rim_color * rim * rim_strength;
}
