// Voxel clouds: drift slowly with the wind and wrap around the world.
shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled, shadows_disabled;

#include "res://shaders/voxel_common.gdshaderinc"

uniform float drift_speed = 2.2;
uniform float wrap_half = 1700.0;

void vertex() {
	VOXEL_VERTEX_SETUP
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float nx = mod(o.x + TIME * drift_speed + wrap_half, 2.0 * wrap_half) - wrap_half;
	VERTEX.x += nx - o.x;
}

void fragment() {
	float rough;
	float emis;
	float ao;
	vec3 col = voxel_color(rough, emis, ao);
	ALBEDO = col * 0.85;
	ROUGHNESS = 1.0;
	EMISSION = col * (emis + 0.25);
}
