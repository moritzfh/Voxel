shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
global uniform float voxel_borders;
instance uniform float hit_flash = 0.0;
uniform float voxel_size = 0.0625;
varying vec3 local;
varying vec3 normal_local;
void vertex() {
	local = VERTEX;
	normal_local = NORMAL;
}
void fragment() {
	vec3 f = fract(local / voxel_size);
	vec3 n = abs(normal_local);
	vec2 uv = n.x > 0.5 ? f.zy : (n.y > 0.5 ? f.xz : f.xy);
	float edge = min(min(uv.x, 1.0-uv.x), min(uv.y, 1.0-uv.y));
	float pixels = voxel_size / max(length(fwidth(local)), 0.00001);
	float border = (1.0-smoothstep(0.0, 0.085, edge)) * smoothstep(2.5, 9.0, pixels);
	ALBEDO = mix(COLOR.rgb * (1.0 - voxel_borders * border),vec3(1.0,.85,.7),hit_flash);
	EMISSION = vec3(.8,.5,.2)*hit_flash;
	ROUGHNESS = 0.93;
	SPECULAR = 0.15;
}
