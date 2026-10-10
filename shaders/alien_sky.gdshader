shader_type sky;
// Space sky for the alien world: nebula clouds, twinkling stars, a ringed gas giant and a small moon.

uniform vec3 zenith_color : source_color = vec3(0.004, 0.01, 0.035);
uniform vec3 horizon_color : source_color = vec3(0.28, 0.12, 0.05);
uniform vec3 nebula_color_a : source_color = vec3(0.1, 0.3, 0.8);
uniform vec3 nebula_color_b : source_color = vec3(0.85, 0.35, 0.08);
uniform float nebula_strength = 1.2;
uniform float star_density = 0.0025;
uniform float star_brightness = 4.0;

uniform vec3 planet_direction = vec3(-0.55, 0.38, -0.74);
uniform float planet_distance = 10.0;
uniform float planet_radius = 2.2;
uniform vec3 planet_color_a : source_color = vec3(0.95, 0.55, 0.2);
uniform vec3 planet_color_b : source_color = vec3(0.35, 0.12, 0.04);
uniform vec3 planet_atmosphere : source_color = vec3(0.4, 0.7, 1.0);
uniform vec3 ring_normal = vec3(-0.6, 1.0, -0.1);
uniform vec3 ring_color : source_color = vec3(0.85, 0.8, 0.75);

uniform vec3 moon_direction = vec3(0.6, 0.55, -0.6);
uniform float moon_size = 0.03;
uniform vec3 moon_color : source_color = vec3(0.75, 0.9, 1.0);

uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.6, 0.25);

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 hash33(vec3 p) {
	return vec3(hash31(p), hash31(p + 19.19), hash31(p + 47.47));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x),
			mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
			mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

float stars(vec3 dir, float scale, float density) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float result = 0.0;
	// Each cell may hold one star; look at the cell and its close neighbours so stars aren't clipped.
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 c = cell + vec3(float(x), float(y), float(z));
				float h = hash31(c);
				if (h < density) {
					vec3 star_pos = c + hash33(c);
					float d = length(p - star_pos);
					float twinkle = 0.7 + 0.3 * sin(TIME * (1.0 + h * 900.0) + h * 3000.0);
					result += smoothstep(0.09, 0.0, d) * twinkle * (0.4 + 0.6 * hash31(c + 3.3));
				}
			}
		}
	}
	return result;
}

// Returns the distance along the ray to a sphere, or -1 if it misses.
float ray_sphere(vec3 dir, vec3 center, float radius) {
	float b = dot(dir, center);
	float c = dot(center, center) - radius * radius;
	float h = b * b - c;
	if (h < 0.0) {
		return -1.0;
	}
	return b - sqrt(h);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;

	// Base gradient, darkest straight up, a warm haze at the horizon.
	vec3 col = mix(horizon_color, zenith_color, smoothstep(-0.05, 0.55, up));
	col = mix(col, horizon_color * 0.5, smoothstep(0.0, -0.4, up));

	// Nebula: two layers of warped noise in different colours.
	vec3 q = dir * 2.2;
	float warp = fbm(q + vec3(0.0, 0.0, TIME * 0.003));
	float n1 = fbm(q * 1.3 + warp * 1.8);
	float n2 = fbm(q * 2.1 - warp * 1.2 + 5.0);
	float band = exp(-pow(dot(dir, normalize(vec3(0.3, 0.6, 0.75))) * 2.2, 2.0));
	vec3 nebula = nebula_color_a * pow(smoothstep(0.35, 0.85, n1), 2.0) * (0.4 + band)
		+ nebula_color_b * pow(smoothstep(0.4, 0.9, n2), 2.5) * (0.3 + band * 0.8);
	float dust = smoothstep(0.45, 0.75, fbm(q * 4.0 + 11.0));
	nebula *= 1.0 - dust * 0.6;
	col += nebula * nebula_strength * smoothstep(-0.15, 0.2, up);

	// Stars, dimmed by the nebula dust and the horizon haze.
	if (!AT_CUBEMAP_PASS) {
		float s = stars(dir, 160.0, star_density * 0.35) * 1.6 + stars(dir, 320.0, star_density);
		col += vec3(0.9, 0.92, 1.0) * s * star_brightness * smoothstep(-0.02, 0.25, up) * (1.0 - dust * 0.5);
	}

	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(0.5, 0.3, 0.5));

	// Ringed gas giant.
	vec3 pdir = normalize(planet_direction);
	vec3 center = pdir * planet_distance;
	float t_planet = ray_sphere(dir, center, planet_radius);
	vec3 rn = normalize(ring_normal);
	float denom = dot(dir, rn);
	float t_ring = abs(denom) > 0.0001 ? dot(center, rn) / denom : -1.0;
	float ring_alpha = 0.0;
	vec3 ring_col = vec3(0.0);
	if (t_ring > 0.0) {
		vec3 hit = dir * t_ring - center;
		float r = length(hit) / planet_radius;
		float bands = 0.65 + 0.2 * sin(r * 60.0) + 0.15 * sin(r * 17.0 + 1.3);
		ring_alpha = smoothstep(1.3, 1.4, r) * smoothstep(2.05, 1.95, r) * bands * 0.7;
		ring_alpha *= 1.0 - smoothstep(1.7, 1.72, r) * smoothstep(1.78, 1.76, r) * 0.9;
		// The planet's shadow falls across the rings on the side away from the sun.
		float shadow = smoothstep(-0.2, 0.2, dot(normalize(hit), sun_dir)) * 0.7 + 0.3;
		ring_col = ring_color * shadow;
	}
	// Soft atmospheric halo around the planet.
	float closest = length(cross(dir, center));
	float halo = smoothstep(planet_radius * 1.25, planet_radius, closest) * step(0.0, dot(dir, pdir));
	col += planet_atmosphere * halo * 0.25;
	bool ring_in_front = t_ring > 0.0 && (t_planet < 0.0 || t_ring < t_planet);
	if (t_planet > 0.0) {
		vec3 n = normalize(dir * t_planet - center);
		float lat = n.y * 0.6 + dot(n, rn) * 0.4;
		float swirl = fbm(vec3(lat * 14.0, n.x * 2.0, n.z * 2.0));
		vec3 surface = mix(planet_color_b, planet_color_a, 0.5 + 0.5 * sin(lat * 22.0 + swirl * 4.0));
		surface = mix(surface, planet_color_a * 1.3, smoothstep(0.6, 0.8, swirl) * 0.4);
		float light = clamp(dot(n, sun_dir), 0.0, 1.0);
		float rim = pow(1.0 - clamp(dot(n, -dir), 0.0, 1.0), 3.0);
		col = surface * (0.06 + light * 1.1) + planet_atmosphere * rim * (0.25 + light);
		if (ring_in_front) {
			col = mix(col, ring_col, ring_alpha);
		}
	} else if (ring_in_front) {
		col = mix(col, ring_col, ring_alpha);
	}

	// Small icy moon.
	vec3 mdir = normalize(moon_direction);
	float md = dot(dir, mdir);
	float moon_disc = smoothstep(cos(moon_size), cos(moon_size * 0.97), md);
	if (moon_disc > 0.0) {
		vec3 local = (dir - mdir * md) / sin(moon_size);
		vec3 n = normalize(local - mdir * sqrt(max(1.0 - dot(local, local), 0.0)));
		float light = clamp(dot(n, sun_dir) * 0.8 + 0.2, 0.0, 1.0);
		float craters = 0.75 + 0.25 * fbm(n * 9.0);
		col = mix(col, moon_color * light * craters * 1.4, moon_disc);
	}
	col += moon_color * pow(max(md, 0.0), 600.0) * 0.6;

	// Glow of the local star.
	if (LIGHT0_ENABLED) {
		float sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		col += sun_glow_color * (pow(sd, 900.0) * 18.0 + pow(sd, 40.0) * 0.5 + pow(sd, 6.0) * 0.12);
	}

	COLOR = col;
}
