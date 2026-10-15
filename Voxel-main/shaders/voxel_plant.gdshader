// Colour-voxel plants: same shading as the world plus wind sway and a distance fade.
// INSTANCE_CUSTOM: y = brightness tint (-1..1), z = wind phase
shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/voxel_common.gdshaderinc"

uniform float wind_strength = 0.10;
uniform float wind_speed = 1.6;
uniform vec2 wind_dir = vec2(0.8, 0.35);
uniform float sway = 1.0; // 0 for lily pads
uniform float fade_start = 29.0;
uniform float fade_end = 37.0;
varying float v_tint;

void vertex() {
	VOXEL_VERTEX_SETUP
	v_tint = INSTANCE_CUSTOM.y;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * wind_speed;
	float gust = sin(t * 0.37 + wp.x * 0.05 + wp.z * 0.04) * 0.5 + 0.5;
	float s = sin(t + INSTANCE_CUSTOM.z + wp.x * 0.35 + wp.z * 0.27) * (0.55 + gust * 0.6);
	float k = VERTEX.y * VERTEX.y * 2.0;
	VERTEX.xz += normalize(wind_dir) * s * wind_strength * k * sway * plant_motion;
	VERTEX.y += sin(TIME * 0.8 + INSTANCE_CUSTOM.z) * 0.006 * (1.0 - sway) * plant_motion;
}

void fragment() {
	float d = length(VERTEX);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	if (fade < dither) {
		discard;
	}
	float rough;
	float emis;
	float ao;
	vec3 col = voxel_color(rough, emis, ao) * (1.0 + v_tint * 0.08);
	// darker towards the ground
	col *= mix(0.7, 1.0, smoothstep(0.0, 0.3, v_local.y));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.25, 0.3, 0.15);
	EMISSION = col * ambient_lift;
}
