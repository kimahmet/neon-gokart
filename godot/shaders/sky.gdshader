shader_type sky;
// Backdrop behind the first-person view. Everything sits at a fixed compass angle, so it pans as the kart turns.
uniform int mode = 0;            // 0 cyber city, 1 sunset, 2 classic stripes
uniform float sun_az = 0.0;
uniform float spin = 0.0;
uniform vec3 line_col : source_color = vec3(1.0);
uniform vec3 ground : source_color = vec3(0.0);
uniform vec3 stripe_a : source_color = vec3(0.1);
uniform vec3 stripe_b : source_color = vec3(0.05);

float hash(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
vec3 grad3(vec3 a, vec3 b, vec3 c, float mid, float t) {
	return t < mid ? mix(a, b, t / mid) : mix(b, c, (t - mid) / (1.0 - mid));
}

void sky() {
	float az = atan(EYEDIR.z, EYEDIR.x);
	float el = EYEDIR.y / max(length(EYEDIR.xz), 1e-4);   // tan(elevation)
	float t = clamp(1.0 - el / 0.4, 0.0, 1.0);             // 0 high up, 1 at the horizon
	vec3 col;
	if (mode == 2) {
		col = mod(floor((az + spin + PI) / (TAU / 12.0)), 2.0) < 1.0 ? stripe_a : stripe_b;
	} else if (mode == 1) {
		col = grad3(lin(vec3(0.078, 0.02, 0.169)), lin(vec3(0.427, 0.086, 0.388)), lin(vec3(1.0, 0.416, 0.239)), 0.55, t);
		// striped sun
		float sr = 0.18;
		vec2 sd = vec2(atan(sin(az - sun_az), cos(az - sun_az)), el - 0.03);
		if (length(sd) < sr) {
			float v = (sr - sd.y) / (2.0 * sr);            // 0 top, 1 bottom
			col = grad3(lin(vec3(1.0, 0.894, 0.361)), lin(vec3(1.0, 0.31, 0.545)), lin(vec3(0.761, 0.114, 0.604)), 0.6, v) * 1.7;
			float band = (0.45 * sr - sd.y) / (0.13 * sr); // stripes across the lower half, thicker downwards
			if (band >= 0.0 && band < 7.0 && fract(band) < 0.14 + 0.09 * floor(band)) col = lin(vec3(0.427, 0.086, 0.388));
		}
		// wireframe mountains
		float mh = 0.064 * (1.0 + 0.55 * sin(3.0 * az) + 0.3 * sin(7.0 * az + 1.0) + 0.18 * sin(17.0 * az + 2.0));
		if (el < mh) col = lin(vec3(0.086, 0.016, 0.141));
		col = mix(col, lin(vec3(1.0, 0.24, 0.94)) * 2.2, 1.0 - smoothstep(0.0015, 0.004, abs(el - mh)));
	} else {
		col = grad3(lin(vec3(0.012, 0.008, 0.039)), lin(vec3(0.09, 0.039, 0.2)), lin(vec3(0.239, 0.059, 0.369)), 0.65, t);
		// stars
		vec2 sg = vec2(az * 40.0, el * 40.0);
		float sh = hash(floor(sg.x) * 17.0 + floor(sg.y) * 131.0);
		if (sh > 0.93 && el > 0.12) col += vec3(0.8) * (1.0 - smoothstep(0.0, 0.12, length(fract(sg) - 0.5))) * (sh - 0.93) * 14.0;
		// far skyline
		float a1 = (az + PI) / (TAU / 90.0);
		if (fract(a1) < 0.9 && el < 0.055 + 0.11 * hash(floor(a1))) col = lin(vec3(0.071, 0.031, 0.157));
		// near skyline with lit windows and neon signs
		float a2 = (az + PI) / (TAU / 46.0);
		float k = floor(a2), fx = fract(a2) / 0.8, h = 0.08 + 0.18 * hash(k + 50.0);
		if (fx < 1.0 && el < h) {
			col = lin(vec3(0.027, 0.016, 0.059));
			float row = (h - el) / h * 8.0 - 0.4, wc = (fx - 0.15) / 0.28;
			if (row > 0.0 && row < 7.0 && fract(row) < 0.22 && wc > 0.0 && wc < 3.0 && fract(wc) < 0.43
				&& hash(k * 31.0 + floor(row) * 7.0 + floor(wc)) > 0.62) col = lin(vec3(1.0, 0.88, 0.55)) * 0.75;
			if (hash(k + 99.0) > 0.7 && fx > 0.8 && fx < 0.9 && el > h * 0.45 && el < h * 0.85)
				col = (hash(k + 7.0) > 0.5 ? lin(vec3(1.0, 0.24, 0.94)) : lin(vec3(0.22, 0.84, 1.0))) * 2.5;
		}
	}
	if (el < 0.0) col = ground;
	col = mix(col, line_col * 2.0, 1.0 - smoothstep(0.002, 0.005, abs(el)));
	COLOR = col;
}
