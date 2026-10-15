// Vertex-coloured voxel characters with a little ambient lift so they read well in shade.
// UV runs 0..1 across every voxel face (thin bevel lines like the world voxels).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float ambient_lift = 0.08;
uniform float bevel_strength = 0.18;
// multiplayer: recolour (e.g. the scarf) per instance; alpha 0 = keep the original colours
instance uniform vec4 recolor : source_color = vec4(0.0);

void fragment() {
	vec3 col = COLOR.rgb;
	// only the orange scarf colours are swapped (skin, hair and leather stay)
	bool scarf = col.r > 0.15 && col.g < 0.34 * col.r && col.b < 0.12 * col.r;
	if (recolor.a > 0.0 && scarf) {
		float l = col.r * 0.55 + col.g * 0.45;
		vec3 tgt = recolor.rgb;
		float tl = max(dot(tgt, vec3(0.2126, 0.7152, 0.0722)), 1e-3);
		col = mix(col, tgt * (l / tl) * 0.62, recolor.a);
	}
	vec2 e2 = min(UV, 1.0 - UV);
	float e = min(e2.x, e2.y);
	float px = 1.0 / max(length(fwidth(UV)), 1e-4);
	col *= 1.0 - bevel_strength * (1.0 - smoothstep(0.0, 0.09, e)) * smoothstep(2.5, 9.0, px);
	ALBEDO = col;
	EMISSION = col * ambient_lift;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
}
