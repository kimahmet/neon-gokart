class_name U
extends RefCounted
## Small shared helpers.

## CSS-style hsl(): h in degrees, s and l in percent.
static func hsl(h: float, s: float, l: float, a := 1.0) -> Color:
	s /= 100.0; l /= 100.0
	var v := l + s * minf(l, 1.0 - l)
	var sv := 0.0 if v <= 0.0 else 2.0 * (1.0 - l / v)
	return Color.from_hsv(fposmod(h, 360.0) / 360.0, sv, v, a)


## Lap time as m:ss.xx; a missing time (INF) shows as dashes.
static func fmt(t: float) -> String:
	if not is_finite(t): return "-:--.--"
	var m := int(t / 60)
	return "%d:%05.2f" % [m, t - m * 60]
