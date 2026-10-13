shader_type spatial;
// Stylized terrain: blends Poly Haven grass / sand / rock by height and slope,
// then pushes saturation a little for a "cartoon but realistic" look.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float tile = 0.12;
uniform vec3 grass_tint : source_color = vec3(0.36, 0.82, 0.24);
uniform vec3 sand_tint : source_color = vec3(1.05, 0.95, 0.75);
uniform float saturation = 1.15;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = wpos.xz * tile;
	vec3 g = texture(grass_tex, uv).rgb * grass_tint;
	vec3 s = texture(sand_tex, uv * 1.5).rgb * sand_tint;
	vec3 r = texture(rock_tex, uv * 0.7).rgb;
	float sand_w = 1.0 - smoothstep(0.2, 1.0, wpos.y);
	float rock_w = smoothstep(0.55, 0.8, 1.0 - wnrm.y);
	vec3 col = mix(g, s, sand_w);
	col = mix(col, r, rock_w);
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(l), col, saturation);
	NORMAL_MAP = mix(texture(grass_nrm, uv).rgb, texture(rock_nrm, uv * 0.7).rgb, rock_w);
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = 0.92;
}
