shader_type spatial;
render_mode unshaded, cull_disabled;
// Kart body: dark faces (vertex colour) with a neon outline. UV.x = distance to the face edge.
uniform vec3 neon : source_color = vec3(1.0);
uniform float energy = 2.4;
uniform float width = 0.5;
void fragment() {
	float w = max(width, fwidth(UV.x) * 1.3);
	ALBEDO = mix(COLOR.rgb, neon * energy, 1.0 - smoothstep(w * 0.5, w, UV.x));
}
