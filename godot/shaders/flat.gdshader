shader_type spatial;
render_mode unshaded, cull_disabled;
// Solid colour; energy above 1 makes it bloom.
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.0;
void fragment() { ALBEDO = color.rgb * COLOR.rgb * energy; }
