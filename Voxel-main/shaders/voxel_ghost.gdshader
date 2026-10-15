// Build preview ("ghost"): the real voxel colours, see-through, with a soft pulse, a scan line and a tint that
// says what will happen (green = place, red = not possible, orange = subtract, blue = paint / select).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_disabled, shadows_disabled;

#include "res://shaders/voxel_common.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.55, 1.0, 0.6, 1.0);
uniform float tint_mix = 0.25;
uniform float alpha = 0.62;
uniform float height = 2.0;      // object height in metres (for the scan line)
uniform bool solid_colors = true;

void vertex() {
	VOXEL_VERTEX_SETUP
}

void fragment() {
	float rough;
	float emis;
	float ao;
	vec3 col = solid_colors ? voxel_color(rough, emis, ao) : tint.rgb;
	float pulse = 0.5 + 0.5 * sin(TIME * 4.0);
	float scan = fract(TIME * 0.45);
	float sl = 1.0 - smoothstep(0.0, 0.06, abs(v_local.y / max(height, 0.01) - scan));
	col = mix(col, tint.rgb, tint_mix + 0.08 * pulse);
	ALBEDO = col;
	EMISSION = tint.rgb * (0.18 + 0.12 * pulse + 0.9 * sl) + col * 0.25;
	ALPHA = clamp(alpha + 0.08 * pulse + 0.25 * sl, 0.0, 1.0);
}
