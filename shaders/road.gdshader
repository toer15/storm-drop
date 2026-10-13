shader_type spatial;
// Asphalt road ribbon: UV.x across (0..1), UV.y along (scaled metres). White edge lines + dashed yellow centre line.
uniform vec3 asphalt : source_color = vec3(0.17, 0.17, 0.19);
void fragment() {
	float n = fract(sin(dot(floor(UV * vec2(40.0, 400.0)), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 c = asphalt * (0.9 + 0.2 * n);
	float edge = step(abs(UV.x - 0.5), 0.47) * (1.0 - step(abs(UV.x - 0.5), 0.44));
	float dash = step(abs(UV.x - 0.5), 0.015) * step(0.5, fract(UV.y * 1.2));
	c = mix(c, vec3(0.9), edge);
	c = mix(c, vec3(1.0, 0.8, 0.2), dash);
	ALBEDO = c; ROUGHNESS = 0.85;
}
