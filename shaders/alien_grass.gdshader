shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
// Alien grass: dark roots fading to glowing tips. Sways in the wind and bends away from the player.
// Each MultiMesh instance stores its tip colour in INSTANCE_CUSTOM.rgb and a random phase in .a.

uniform vec3 root_color : source_color = vec3(0.02, 0.05, 0.07);
uniform float tip_glow = 1.4;
uniform float wind_strength = 0.16;
uniform float wind_speed = 1.3;
uniform vec3 player_position = vec3(0.0, -1000.0, 0.0);
uniform float push_radius = 1.3;

varying vec3 tip_color;
varying float height;

void vertex() {
	tip_color = INSTANCE_CUSTOM.rgb;
	height = UV.y;
	vec3 root = MODEL_MATRIX[3].xyz;
	float bend = UV.y * UV.y;
	float phase = INSTANCE_CUSTOM.a * 6.2831;

	vec2 wind = vec2(
		sin(TIME * wind_speed + root.x * 0.13 + root.z * 0.07 + phase * 0.35),
		cos(TIME * wind_speed * 0.73 + root.z * 0.11 + phase * 0.2) * 0.5
	) * wind_strength;
	// Gusts roll across the field.
	wind *= 0.7 + 0.6 * smoothstep(0.3, 1.0, sin(TIME * 0.4 + root.x * 0.05 - root.z * 0.03));

	vec2 away = root.xz - player_position.xz;
	float dist = length(away);
	float near = (1.0 - smoothstep(0.2, push_radius, dist)) * step(abs(root.y - player_position.y), 2.5);
	vec2 push = dist > 0.001 ? away / dist * near * 0.55 : vec2(0.0);

	VERTEX.xz += (wind + push) * bend;
	VERTEX.y -= near * 0.3 * bend;
}

void fragment() {
	float t = smoothstep(0.0, 1.0, height);
	ALBEDO = mix(root_color, tip_color * 0.55, t);
	ROUGHNESS = 0.75;
	EMISSION = tip_color * pow(height, 3.0) * tip_glow;
}
