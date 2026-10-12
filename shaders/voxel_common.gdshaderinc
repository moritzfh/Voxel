// Shared colour-voxel shading.
// CUSTOM0 (RGBA8): r = encoded voxel (material << 2 | variant), g = ambient occlusion 0..3,
//                  b = voxel size index (size = 2^(b - 5) m), a = 255.

uniform vec3 palette[256];
uniform float emission_tab[256];
uniform float roughness_tab[64];
uniform float jitter_tab[64];
uniform float bevel_strength = 0.2;
uniform float ao_strength = 0.55;
uniform float ambient_lift = 0.07;
uniform float saturation = 1.0;

varying vec3 v_local;
varying vec3 v_lnrm;
varying flat float v_id;
varying float v_ao;
varying flat float v_vs;

float vx_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// call inside vertex(): varyings can only be written there
#define VOXEL_VERTEX_SETUP v_local = VERTEX; v_lnrm = NORMAL; v_id = floor(CUSTOM0.r * 255.0 + 0.5); v_ao = CUSTOM0.g * 255.0 / 3.0; v_vs = exp2(floor(CUSTOM0.b * 255.0 + 0.5) - 5.0);

// returns albedo; writes roughness / emission strength
vec3 voxel_color(out float rough, out float emis, out float ao_out) {
	int id = int(v_id);
	int m = id >> 2;
	vec3 p = v_local / v_vs;
	vec3 n = normalize(v_lnrm);
	vec3 cell = floor(p - n * 0.5);
	float h = vx_hash13(cell + vec3(17.0, 3.0, 11.0));
	vec3 col = palette[id];
	col *= 1.0 + (h - 0.5) * 2.0 * jitter_tab[m];
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	// thin bevel lines between neighbouring voxels (faded out when a voxel gets small on screen)
	vec3 f = fract(p);
	vec3 an = abs(n);
	vec2 uv = an.x > 0.5 ? f.zy : (an.y > 0.5 ? f.xz : f.xy);
	vec2 e2 = min(uv, 1.0 - uv);
	float e = min(e2.x, e2.y);
	float px = v_vs / max(length(fwidth(v_local)), 1e-6);
	float bev = (1.0 - smoothstep(0.0, 0.085, e)) * smoothstep(2.5, 9.0, px);
	col *= 1.0 - bevel_strength * bev;
	// light catch on the upper edge of side faces (reads as rounded voxels)
	if (an.y < 0.5) {
		col *= 1.0 + 0.06 * (1.0 - smoothstep(0.0, 0.12, 1.0 - uv.y)) * smoothstep(2.5, 9.0, px);
	}
	float ao = mix(1.0 - ao_strength, 1.0, clamp(v_ao, 0.0, 1.0));
	ao_out = ao;
	rough = roughness_tab[m];
	emis = emission_tab[id];
	return col;
}
