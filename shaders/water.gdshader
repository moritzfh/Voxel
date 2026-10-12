// River water: refraction, depth tint, pixel ripples, shore foam, and waterfalls on vertical faces.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 shallow_tint : source_color = vec3(0.50, 0.86, 0.92);
uniform vec3 deep_color : source_color = vec3(0.03, 0.27, 0.46);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 1.0);
uniform float absorption = 0.75;
uniform float refraction = 0.035;
uniform vec2 flow = vec2(-0.25, 1.0);
uniform float pixel_density = 8.0; // ripples quantised to the 12.5 cm voxel grid

varying vec3 v_world;
varying vec3 v_wn;
varying float v_fall;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float waves(vec2 p, float t) {
	vec2 fl = normalize(flow);
	float h = 0.0;
	h += vnoise(p * 1.3 - fl * t * 0.9) * 0.5;
	h += vnoise(p * 2.7 + vec2(t * 0.35, -t * 0.25) - fl * t * 1.4) * 0.3;
	h += vnoise(p * 5.9 - fl * t * 2.0) * 0.2;
	return h;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_fall = (int(floor(CUSTOM0.r * 255.0 + 0.5)) >> 2) == 37 ? 1.0 : 0.0;
}

void fragment() {
	float t = TIME;
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec3 scene_view = up.xyz / up.w;
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
	float view_thick = max(0.0, length(scene_view) - length(VERTEX));

	if (v_wn.y > 0.5 && v_fall < 0.5) {
		// ---- calm surface
		vec2 pq = floor(v_world.xz * pixel_density) / pixel_density; // pixel-art ripples
		float e = 0.06;
		float h0 = waves(pq, t);
		float hx = waves(pq + vec2(e, 0.0), t);
		float hz = waves(pq + vec2(0.0, e), t);
		vec3 n_world = normalize(vec3((h0 - hx) * 1.6, 1.0, (h0 - hz) * 1.6));
		NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
		float vert = max(0.0, v_world.y - scene_world.y);
		float thick = min(vert * 1.4 + view_thick * 0.15, 12.0);
		vec2 ruv = SCREEN_UV + n_world.xz * refraction * clamp(thick, 0.0, 1.0);
		// avoid refracting things in front of the water
		float d2 = texture(depth_tex, ruv).r;
		vec4 up2 = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, d2, 1.0);
		if (length(up2.xyz / up2.w) < length(VERTEX)) { ruv = SCREEN_UV; }
		vec3 under = textureLod(screen_tex, ruv, 0.0).rgb;
		float trans = exp(-thick * absorption);
		vec3 col = mix(deep_color, under * shallow_tint, trans);
		// shore + rock foam
		float foam_n = vnoise(pq * 3.0 + vec2(t * 0.6, -t * 0.4));
		float foam = (1.0 - smoothstep(0.0, 0.05 + foam_n * 0.04, vert)) * step(0.5, foam_n);
		col = mix(col, foam_color, foam * 0.35);
		// sparkle
		float sp = step(0.985, hash12(floor(v_world.xz * pixel_density * 0.5) + floor(t * 3.0)));
		ALBEDO = vec3(0.0);
		EMISSION = col + sp * 0.35;
		ALPHA = 1.0;
		ROUGHNESS = 0.06 + foam * 0.6;
		METALLIC = 0.0;
		SPECULAR = 0.55;
	} else {
		// ---- waterfall face
		vec3 side = abs(v_wn.x) > 0.5 ? v_world.zyx : v_world.xyz;
		float u = floor(side.x * pixel_density * 0.5) / (pixel_density * 0.5);
		float y = v_world.y;
		if (v_wn.y > 0.5) { // top of a cascade step: churning foam
			u = floor((v_world.x + v_world.z) * pixel_density * 0.5) / (pixel_density * 0.5);
			y = v_world.z * 0.7 - v_world.x * 0.3;
		}
		float streak = vnoise(vec2(u * 3.0, y * 0.35 + t * 2.2));
		float streak2 = vnoise(vec2(u * 7.0 + 3.1, y * 0.8 + t * 3.1));
		float s = smoothstep(0.45, 0.85, streak * 0.6 + streak2 * 0.5);
		vec3 base = mix(vec3(0.30, 0.62, 0.80), vec3(0.95, 0.98, 1.0), s);
		ALBEDO = base;
		EMISSION = base * 0.18;
		ALPHA = mix(0.78, 0.97, s);
		ROUGHNESS = 0.35;
		SPECULAR = 0.4;
	}
}
