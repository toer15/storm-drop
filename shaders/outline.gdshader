shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
// Inverted-hull outline used as a next_pass on characters and props for a toon look.
uniform vec4 color : source_color = vec4(0.08, 0.05, 0.12, 1.0);
uniform float thickness = 0.012;
void vertex() { VERTEX += NORMAL * thickness; }
void fragment() { ALBEDO = color.rgb; }
