shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Stylized water: rolling waves, fresnel shallow->deep colour, animated foam bands near the shore.
uniform vec4 shallow : source_color = vec4(0.25, 0.85, 0.95, 0.85);
uniform vec4 deep : source_color = vec4(0.04, 0.32, 0.65, 0.95);
uniform float wave_height = 0.35;
uniform float island_radius = 120.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.15 + TIME * 1.3) * cos(wpos.z * 0.12 + TIME * 1.1);
	VERTEX.y += w * wave_height;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float d = length(wpos.xz);
	float shore = 1.0 - smoothstep(island_radius * 0.95, island_radius * 1.35, d);
	vec4 c = mix(deep, shallow, clamp(shore * 0.8 + fres * 0.4, 0.0, 1.0));
	float foam = step(0.92, sin(d * 0.6 - TIME * 2.0) * 0.5 + 0.5) * shore * smoothstep(island_radius * 0.85, island_radius * 0.95, d);
	ALBEDO = mix(c.rgb, vec3(1.0), foam * 0.6);
	ALPHA = c.a;
	ROUGHNESS = 0.15;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
