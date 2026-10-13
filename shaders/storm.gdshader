shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
// Storm wall (300 m cylinder centred on y=0, so UV.y 0 = top, 1 = bottom): purple swirl that is strong
// near the ground and fades out above ~80 m, so it no longer tints the whole sky from inside the circle.
uniform vec4 col : source_color = vec4(0.62, 0.22, 1.0, 0.5);
void fragment() {
	float swirl = 0.75 + 0.25 * sin(UV.x * 120.0 + TIME * 1.5 + UV.y * 40.0);
	float fade = smoothstep(0.22, 0.46, UV.y);
	ALBEDO = col.rgb * swirl;
	ALPHA = col.a * fade * swirl;
}
