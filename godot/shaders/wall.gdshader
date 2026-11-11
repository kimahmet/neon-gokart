shader_type spatial;
render_mode unshaded, cull_disabled;
// Track wall: dark panel with a neon rail along the bottom and top edge (UV.y runs bottom to top).
uniform vec3 fill : source_color = vec3(0.1);
uniform vec3 neon : source_color = vec3(1.0);
uniform float energy = 2.2;
void fragment() {
	float w = clamp(fwidth(UV.y) * 1.5, 0.09, 0.3);  // never thinner than ~1.5 px
	float e = max(1.0 - smoothstep(w * 0.6, w, UV.y), smoothstep(1.0 - w, 1.0 - w * 0.6, UV.y));
	ALBEDO = mix(fill, neon * energy, e);
}
