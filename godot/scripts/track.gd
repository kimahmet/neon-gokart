class_name Track
extends RefCounted
## Track geometry: centreline samples, racing line and the rival bot's speed profile.

const HW := 75.0      # half width of the road
const STEP := 10.0    # distance between centreline samples
# the rival bot's lateral grip and braking (u/s²) set its speed through each corner
const BOT_LAT := 1900.0
const BOT_DEC := 900.0

# Stylised layouts, clockwise, start/finish at the first point. len = real length (km) x ~1700 units.
const DEFS := [
	{id = "monaco", name = "MONACO", sub = "CIRCUIT DE MONACO · 3.34 KM", hue = 322.0, len = 7125.0, pts = [20,60, 28,54, 36,49, 42,47, 46,44, 50,38, 55,31, 60,25, 65,21, 71,21, 75,24, 77,30, 76,36, 72,39, 70,43, 73,47, 78,49, 82,53, 82,59, 78,63, 70,65, 60,66, 52,66, 48,69, 44,67, 38,68, 33,72, 29,70, 25,73, 19,75, 13,72, 12,66, 15,62]},
	{id = "silverstone", name = "SILVERSTONE", sub = "GREAT BRITAIN · 5.89 KM", hue = 158.0, len = 12000.0, pts = [84,30, 86,45, 86,58, 82,66, 76,72, 72,78, 66,80, 62,76, 58,72, 46,74, 34,76, 26,78, 20,74, 18,68, 20,60, 22,50, 28,42, 26,36, 32,30, 48,22, 64,16, 74,12, 80,14, 82,20, 80,26]},
	{id = "monza", name = "MONZA", sub = "AUTODROMO NAZIONALE · 5.79 KM", hue = 36.0, len = 11750.0, pts = [70,80, 55,80, 40,80, 24,80, 16,80, 12,77, 8,77, 4,70, 2,60, 3,50, 6,44, 9,42, 9,38, 12,30, 16,24, 22,20, 28,20, 32,24, 40,34, 48,42, 52,45, 55,50, 58,51, 66,54, 76,58, 84,62, 90,66, 93,72, 90,78, 84,80]},
]

var id: String
var name: String
var sub: String
var hue: float
var n: int
var p: PackedVector2Array      # centreline
var tan: PackedVector2Array    # unit tangent
var nor: PackedVector2Array    # unit normal (right-hand side of travel)
var k: PackedFloat32Array      # centreline curvature
var off: PackedFloat32Array    # racing line offset along the normal
var line: PackedVector2Array   # racing line
var lds: PackedFloat32Array    # racing line segment length
var lh: PackedFloat32Array     # racing line heading
var lk: PackedFloat32Array     # racing line curvature
var lv: PackedFloat32Array     # bot target speed
var apex: Array[Vector2i] = [] # (sample index, side)
var bounds: Rect2


static func build(d: Dictionary) -> Track:
	var t := Track.new()
	t.id = d.id; t.name = d.name; t.sub = d.sub; t.hue = d.hue
	var q := PackedVector2Array()
	for i in range(0, d.pts.size(), 2):
		q.append(Vector2(d.pts[i], d.pts[i + 1]))
	for it in 4:  # Chaikin corner cutting
		var r := PackedVector2Array()
		for i in q.size():
			var a := q[i]; var b := q[(i + 1) % q.size()]
			r.append(a * .75 + b * .25); r.append(a * .25 + b * .75)
		q = r
	var total := 0.0
	for i in q.size():
		total += q[i].distance_to(q[(i + 1) % q.size()])
	var sc: float = d.len / total
	var p := PackedVector2Array()
	var carry := 0.0
	for i in q.size():
		var a := q[i] * sc; var b := q[(i + 1) % q.size()] * sc
		var sl := a.distance_to(b)
		var s := carry
		while s < sl:
			p.append(a.lerp(b, s / sl)); s += STEP
		carry = s - sl
	# a last sample landing on top of the first one would kink the tangents at the start line
	if p[-1].distance_to(p[0]) < STEP * .5: p.remove_at(p.size() - 1)
	var n := p.size()
	t.n = n; t.p = p
	t.tan.resize(n); t.nor.resize(n); t.k.resize(n); t.off.resize(n)
	for i in n:
		var tg := (p[(i + 1) % n] - p[(i - 1 + n) % n]).normalized()
		t.tan[i] = tg; t.nor[i] = Vector2(-tg.y, tg.x)
	for i in n:
		var cr := t.tan[(i - 4 + n) % n].cross(t.tan[(i + 4) % n])
		t.k[i] = asin(clampf(cr, -1, 1)) / (8 * STEP)
	for i in n:
		var ak := absf(t.k[i])
		if ak < 1.0 / 320: continue
		var ok := true
		for o in range(-18, 19):
			if o == 0: continue
			var v := absf(t.k[(i + o + n) % n])
			if v > ak or (v == ak and o < 0): ok = false; break
		if ok: t.apex.append(Vector2i(i, int(signf(t.k[i]))))
	# racing line = an elastic band pulled tight inside the track: it cuts every corner at the apex
	var off := t.off; var nor := t.nor
	var olim := HW - 16
	for span in [48, 30, 18, 10]:
		for it in 40:
			for i in n:
				var a: int = (i - span + n) % n; var b: int = (i + span) % n
				var m := (p[a] + nor[a] * off[a] + p[b] + nor[b] * off[b]) * .5
				off[i] = clampf((m - p[i]).dot(nor[i]), -olim, olim)
	for it in 12:
		var o2 := off.duplicate()
		for i in n:
			off[i] = (o2[(i - 1 + n) % n] + 2 * o2[i] + o2[(i + 1) % n]) / 4
	t.off = off
	t.line.resize(n); t.lds.resize(n); t.lh.resize(n); t.lk.resize(n); t.lv.resize(n)
	for i in n:
		t.line[i] = p[i] + nor[i] * off[i]
	for i in n:
		var dv := t.line[(i + 1) % n] - t.line[i]
		t.lds[i] = maxf(1, dv.length()); t.lh[i] = dv.angle()
	for i in n:
		var sd := 0.0
		for o in range(-3, 3): sd += t.lds[(i + o + n) % n]
		t.lk[i] = angle_difference(t.lh[(i - 3 + n) % n], t.lh[(i + 3) % n]) / sd
	# bot speed profile: corner limit, then braking zones worked backwards from each corner
	for i in n:
		t.lv[i] = minf(3000, sqrt(BOT_LAT / maxf(absf(t.lk[i]), 1e-5)))
	for pass_i in 2:
		for i in range(n - 1, -1, -1):
			var j := (i + 1) % n
			t.lv[i] = minf(t.lv[i], sqrt(t.lv[j] * t.lv[j] + 2 * BOT_DEC * t.lds[i]))
	var bb := Rect2(p[0], Vector2.ZERO)
	for v in p: bb = bb.expand(v)
	t.bounds = bb
	return t


static func build_all() -> Array[Track]:
	var out: Array[Track] = []
	for d in DEFS: out.append(build(d))
	return out
