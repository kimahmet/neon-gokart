shader_type spatial;
render_mode unshaded;
// Ground under the track: synthwave grid fixed to the world (so it streams past), or rotating stripes.
uniform int mode = 0;            // 0 grid, 1 plain, 2 stripes around `centre`
uniform vec3 base : source_color = vec3(0.0);
uniform vec3 grid_col : source_color = vec3(0.2, 0.8, 1.0);
uniform vec2 centre = vec2(0.0);
uniform float ang = 0.0;
uniform vec3 stripe_a : source_color = vec3(0.1);
uniform vec3 stripe_b : source_color = vec3(0.05);
varying vec3 wp;

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec3 c = base;
	if (mode == 0) {
		vec2 g = wp.xz / 180.0;
		vec2 f = abs(fract(g - 0.5) - 0.5) / max(fwidth(g), vec2(1e-5));
		float l = 1.0 - min(min(f.x, f.y) / 1.5, 1.0);
		float dist = length(wp.xz - CAMERA_POSITION_WORLD.xz);
		c += grid_col * l * (1.0 - smoothstep(500.0, 2200.0, dist));
	} else if (mode == 2) {
		vec2 d = wp.xz - centre;
		c = mod(floor((atan(d.y, d.x) + ang + PI) / (TAU / 6.0)), 2.0) < 1.0 ? stripe_a : stripe_b;
	}
	ALBEDO = c;
}
