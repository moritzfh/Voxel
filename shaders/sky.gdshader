// Bright afternoon sky with soft cumulus clouds.
shader_type sky;
render_mode use_half_res_pass;

uniform vec3 zenith_color : source_color = vec3(0.10, 0.36, 0.86);
uniform vec3 mid_color : source_color = vec3(0.30, 0.58, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.86, 0.98);
uniform vec3 ground_color : source_color = vec3(0.42, 0.50, 0.46);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.88, 0.66);
uniform float cloud_cover = 0.47;
uniform float cloud_scale = 0.55;
uniform vec2 cloud_offset = vec2(3.7, 1.3);
uniform float exposure = 1.0;
uniform float clouds_enabled = 0.0; // clouds are voxel meshes now

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 6; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}
float cloud_density(vec2 p) {
	// large clumps shaped by low frequency noise, puffy edges by fbm
	float big = vnoise(p * 0.35 + cloud_offset);
	float d = fbm(p) * 0.75 + big * 0.55;
	return smoothstep(cloud_cover, cloud_cover + 0.22, d * 0.85);
}

void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;
	vec3 col;
	if (y >= 0.0) {
		float t = pow(y, 0.5);
		col = mix(horizon_color, mid_color, smoothstep(0.0, 0.35, t));
		col = mix(col, zenith_color, smoothstep(0.35, 1.0, t));
	} else {
		col = mix(horizon_color * 0.9, ground_color, smoothstep(0.0, 0.25, -y));
	}
	vec3 sdir = LIGHT0_DIRECTION;
	float sd = max(dot(dir, sdir), 0.0);
	// sun disk and glow
	col += sun_tint * (pow(sd, 1200.0) * 40.0 + pow(sd, 60.0) * 0.35 + pow(sd, 8.0) * 0.12);
	// clouds on a curved layer
	if (y > 0.0 && clouds_enabled > 0.5) {
		vec2 p = dir.xz / (y + 0.12) * cloud_scale + vec2(TIME * 0.004, TIME * 0.0015);
		float d = cloud_density(p);
		if (d > 0.001) {
			// light: sample towards the sun on the layer for self shadowing
			vec2 ls = normalize(sdir.xz + vec2(0.0001)) * 0.18;
			float d2 = cloud_density(p + ls);
			float lit = clamp(1.0 - (d2 - d) * 1.6 - d2 * 0.35, 0.0, 1.0);
			vec3 shade = mix(vec3(0.66, 0.72, 0.82), vec3(1.0, 0.99, 0.96), lit);
			shade += sun_tint * pow(sd, 12.0) * 0.45 * (1.0 - d);
			float fade = smoothstep(0.0, 0.08, y);
			col = mix(col, shade * 1.02, d * fade * 0.96);
		}
	}
	COLOR = col * exposure;
}
