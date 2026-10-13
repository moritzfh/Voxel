// Second pass of the build preview: faint outline of the parts hidden inside terrain or walls.
shader_type spatial;
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_back, unshaded, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.55, 1.0, 0.6, 1.0);
uniform float strength = 0.16;

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint.rgb * (strength + rim * strength * 1.5);
}
