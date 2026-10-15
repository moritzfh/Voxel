// Colour-voxel world shader (terrain, buildings, trees, rocks, props).
shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/voxel_common.gdshaderinc"

void vertex() {
	VOXEL_VERTEX_SETUP
}

void fragment() {
	float rough;
	float emis;
	float ao;
	vec3 col = voxel_color(rough, emis, ao);
	ALBEDO = col * mix(ao, 1.0, 0.3);
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	EMISSION = col * (ambient_lift * ao + emis);
}
