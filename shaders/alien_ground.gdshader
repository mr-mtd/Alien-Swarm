shader_type spatial;
// Alien ground: cooled basalt crust broken into plates by glowing cracks, with rivers and pools of
// flowing lava. Everything is in world space, so the detail stays the same size on hills and flats.
// The terrain script stores how much lava covers each vertex in COLOR.r.

uniform vec3 crust_color_a : source_color = vec3(0.07, 0.06, 0.065);
uniform vec3 crust_color_b : source_color = vec3(0.13, 0.1, 0.09);
uniform vec3 ash_color : source_color = vec3(0.2, 0.17, 0.16);
uniform vec3 crack_color : source_color = vec3(1.0, 0.32, 0.06);
uniform vec3 lava_hot : source_color = vec3(1.0, 0.55, 0.12);
uniform vec3 lava_cool : source_color = vec3(0.7, 0.07, 0.01);
// Size of the crust plates in metres. Smaller numbers tile the pattern more often.
uniform float plate_size = 1.6;
uniform float crack_strength = 1.8;
uniform float lava_strength = 1.7;
uniform float lava_flow_speed = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;
varying float lava;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

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

// Cellular pattern. x: distance from the cell edge (0 on a crack), y: a random value per cell.
vec2 plates(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = i + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(d2 - d1, hash(id));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lava = COLOR.r;
}

void fragment() {
	// On steep slopes, project from the side so the plates don't stretch down the mountains.
	vec3 n = abs(world_normal);
	vec2 p = world_pos.xz;
	if (n.x > n.y && n.x > n.z) {
		p = world_pos.zy;
	} else if (n.z > n.y) {
		p = world_pos.xy;
	}
	float slope = 1.0 - world_normal.y;

	// Broad regions: some crust is still hot and cracked wide open, some has cooled almost black.
	float heat = smoothstep(0.5, 0.75, fbm(world_pos.xz * 0.035 + 5.0)) * 0.7;
	heat = max(heat, smoothstep(0.0, 0.45, lava));

	// Big plates with wide cracks, and smaller fractures inside them.
	vec2 warp = (vec2(fbm(p * 0.7), fbm(p * 0.7 + 17.0)) - 0.5) * 1.1;
	vec2 big = plates(p / plate_size + warp);
	vec2 small = plates(p / (plate_size * 0.38) + warp * 1.8 + 9.0);
	float grain = noise(p * 6.0) * 0.55 + noise(p * 19.0) * 0.45;
	float lumps = fbm(p * 1.3);

	vec3 col = mix(crust_color_a, crust_color_b, big.y * 0.7 + lumps * 0.3);
	col = mix(col, ash_color, smoothstep(0.55, 0.8, fbm(p * 0.22 + 3.0)) * 0.6);
	col *= 0.65 + 0.6 * grain;
	// Plate edges sag toward the cracks.
	col *= mix(0.45, 1.0, smoothstep(0.0, 0.12, big.x));
	col = mix(col, ash_color * (0.6 + 0.6 * grain), smoothstep(0.3, 0.6, slope) * 0.7);

	// Crack width wanders along each crack so they look torn rather than drawn.
	float crack_width = mix(0.02, 0.08, heat) * (0.4 + 1.2 * noise(p * 2.5 + 40.0));
	float crack = 1.0 - smoothstep(crack_width * 0.4, crack_width, big.x);
	float fine = (1.0 - smoothstep(0.01, 0.035, small.x)) * heat * 0.4 * smoothstep(0.55, 0.8, noise(p * 0.9 + 33.0));
	float glow_bed = (1.0 - smoothstep(0.0, crack_width * 3.0, big.x)) * heat * 0.25;
	float flicker = 0.75 + 0.25 * sin(TIME * 1.7 + big.y * 40.0 + lumps * 6.0);
	// Cooled ground keeps only some of its cracks lit, so the plates don't read as a tiled grid.
	float lit = mix(smoothstep(0.4, 0.7, noise(p * 0.8 + big.y * 3.0)), 1.0, heat);
	float along = smoothstep(0.35, 0.65, noise(p * 1.1 + 70.0));
	float crack_heat = ((crack * mix(0.15, 1.0, heat) * lit + glow_bed) * along + fine) * flicker;
	crack_heat *= 1.0 - smoothstep(0.35, 0.6, slope) * 0.6;
	vec3 crack_glow = mix(crack_color, lava_hot, crack * heat * 0.4);

	// Lava: slow churning flow with darker crust skins drifting across it.
	vec2 lp = world_pos.xz * 0.45;
	vec2 drift = vec2(TIME * lava_flow_speed * 0.6, TIME * lava_flow_speed * 0.25);
	vec2 swirl = vec2(fbm(lp + drift), fbm(lp + vec2(5.2, 1.3) - drift * 0.7));
	float flow = fbm(lp * 1.6 + swirl * 2.2 + drift);
	vec2 skin = plates(lp * 1.5 + swirl * 1.5 - drift * 0.8);
	float crust_skin = smoothstep(0.1, 0.25, skin.x) * smoothstep(0.5, 0.7, flow) * 0.8;
	vec3 molten = mix(lava_cool, lava_hot, smoothstep(0.3, 0.8, flow));
	molten = mix(molten, lava_hot * 1.25, (1.0 - smoothstep(0.0, 0.06, skin.x)) * 0.5);
	float pulse = 0.85 + 0.15 * sin(TIME * 0.9 + flow * 8.0);

	// Roughen the shoreline so it doesn't follow the terrain's triangles.
	float edge = lava + (fbm(world_pos.xz * 0.45) - 0.5) * 0.7;
	float lava_mask = smoothstep(0.42, 0.55, edge);
	// A ring of hot glowing rock right at the lava's edge.
	float shore = smoothstep(0.15, 0.42, edge) * (1.0 - lava_mask);

	vec3 rock_emit = crack_glow * crack_heat * crack_strength + crack_color * shore * 1.2;
	vec3 lava_emit = (molten * (1.0 - crust_skin) + lava_cool * crust_skin * 0.25) * pulse * lava_strength;
	vec3 lava_albedo = mix(vec3(0.3, 0.08, 0.02), crust_color_a, crust_skin);

	ALBEDO = mix(col, lava_albedo, lava_mask);
	ROUGHNESS = mix(0.88 - 0.25 * smoothstep(0.7, 0.95, grain), 0.35, lava_mask);
	EMISSION = mix(rock_emit, lava_emit, lava_mask);
}
