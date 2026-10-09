shader_type spatial;
// Alien ground: mottled moss and soil, rock on steep slopes, and slowly pulsing glowing veins.

uniform vec3 moss_color_a : source_color = vec3(0.05, 0.1, 0.18);
uniform vec3 moss_color_b : source_color = vec3(0.16, 0.09, 0.05);
uniform vec3 soil_color : source_color = vec3(0.12, 0.07, 0.04);
uniform vec3 rock_color : source_color = vec3(0.17, 0.16, 0.18);
uniform vec3 vein_color : source_color = vec3(1.0, 0.45, 0.1);
uniform vec3 spore_color : source_color = vec3(0.2, 0.6, 1.0);
uniform float vein_strength = 1.8;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	float n1 = fbm(p * 0.045);
	float n2 = fbm(p * 0.28 + 7.0);
	float grain = noise(p * 3.0) * 0.6 + noise(p * 9.0) * 0.4;

	vec3 col = mix(moss_color_a, moss_color_b, smoothstep(0.35, 0.65, n1));
	col = mix(col, soil_color, smoothstep(0.5, 0.75, n2) * 0.7);
	col *= 0.8 + 0.4 * grain;
	float slope = 1.0 - world_normal.y;
	col = mix(col, rock_color * (0.7 + 0.5 * grain), smoothstep(0.18, 0.4, slope));

	// Thin branching veins of light that pulse outward from the arena.
	float v = fbm(p * 0.07 + 13.0);
	float vein = 1.0 - smoothstep(0.004, 0.011, abs(v - 0.5));
	float v2 = fbm(p * 0.19 + 31.0);
	vein = max(vein, (1.0 - smoothstep(0.003, 0.012, abs(v2 - 0.5))) * 0.45);
	float pulse = 0.55 + 0.45 * sin(TIME * 1.3 - length(p) * 0.12);
	vein *= 1.0 - smoothstep(0.25, 0.45, slope);

	// Little clusters of glowing spore caps.
	float spots = smoothstep(0.86, 0.9, noise(p * 2.3 + 3.0)) * smoothstep(0.5, 0.65, n1) * (1.0 - smoothstep(0.2, 0.4, slope));

	ALBEDO = col;
	ROUGHNESS = 0.92;
	EMISSION = vein_color * vein * pulse * vein_strength + spore_color * spots * 0.7;
}
