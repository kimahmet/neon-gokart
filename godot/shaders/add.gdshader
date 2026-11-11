shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
// Additive light: racing line, trail, boost flame.
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.0;
void fragment() { ALBEDO = color.rgb * COLOR.rgb * energy; ALPHA = color.a * COLOR.a; }
