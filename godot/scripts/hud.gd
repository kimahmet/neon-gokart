class_name Hud
extends Control
## Everything 2D: menus, race HUD, cockpit, overlays and touch input.
## Drawn by hand each frame in logical pixels, in the game's slanted neon slab style.

const FONT := preload("res://assets/RussoOne-Regular.ttf")
const BLACK84 := Color(0, 0, 0, .84)
const SKIES := ["cyber", "sunset", "off"]
const SKY_NAME := {"cyber": "CYBER CITY", "sunset": "SUNSET", "off": "CLASSIC"}

var g: Main
var W := 1.0; var H := 1.0
var ins_l := 0.0; var ins_t := 0.0; var ins_r := 0.0; var ins_b := 0.0
var ui: Array = []                 # [Rect2, Callable, drawn by an overlay]
var draw_ov := false
var touch_l := -1; var touch_r := -1   # finger index steering each side, -1 = none
var swipe_id := -1; var swipe_from := Vector2.ZERO
var wheel := 0.0
var previews := {}                 # track id -> closed centreline for the select screen


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func u() -> float:
	return clampf(minf(W, H) / 420, .75, 1.5)


# ---------- drawing helpers ----------
func slab(x: float, y: float, w: float, h: float, s: float, left: bool, fill: Color) -> PackedVector2Array:
	var p := PackedVector2Array([Vector2(x - s, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]) if left \
		else PackedVector2Array([Vector2(x, y), Vector2(x + w + s, y), Vector2(x + w, y + h), Vector2(x, y + h)])
	if fill.a > 0: draw_colored_polygon(p, fill)
	return p


func tw(s: String, size: float) -> float:
	return FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, roundi(size))).x


func fit(s: String, size: float, max_w: float) -> float:
	var w := tw(s, size)
	return size * max_w / w if w > max_w else size


## Text centred vertically on y. align: -1 left, 0 centre, 1 right.
func txt(s: String, x: float, y: float, size: float, align := -1, color := Color.WHITE, shadow := Color(0, 0, 0, 0)) -> void:
	var fs := maxi(1, roundi(size))
	var ox := x if align < 0 else x - tw(s, fs) * (.5 if align == 0 else 1.0)
	var by := y + (FONT.get_ascent(fs) - FONT.get_descent(fs)) * .5
	if shadow.a > 0: draw_string(FONT, Vector2(ox + size * .06, by + size * .06), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(shadow, shadow.a * color.a))
	draw_string(FONT, Vector2(ox, by), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func button(x: float, y: float, w: float, h: float, label: String, fn: Callable, size := 16.0, slant := 10.0, left := false, stroke := Color(0, 0, 0, 0)) -> void:
	var p := slab(x, y, w, h, slant, left, Color(0, 0, 0, .82))
	if stroke.a > 0:
		p.append(p[0]); draw_polyline(p, stroke, 2, true)
	if label: txt(label, x + w / 2 + (-slant / 2 if left else slant / 2), y + h / 2 + 1, size, 0)
	ui.append([Rect2(x - slant, y, w + 2 * slant, h), fn, draw_ov])


func stripes(cx: float, cy: float, ang: float, hue: float, sat := 70.0) -> void:
	var rr := Vector2(W, H).length() * 1.6; var c := Vector2(cx, cy)
	for i in 6:
		var a0 := ang + i * TAU / 6
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * rr, c + Vector2.from_angle(a0 + TAU / 6) * rr]),
			U.hsl(hue, sat, (8 if i % 2 else 13) + g.pulse * 4))


func poly(cx: float, cy: float, n: int, r: float, rot: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n: p.append(Vector2(cx, cy) + Vector2.from_angle(rot + i * TAU / n) * r)
	return p


func kart2d(at: Vector2, heading: float, hue: float, sc: float) -> void:
	draw_set_transform(at, heading, Vector2(sc, sc))
	draw_circle(Vector2(-2, 0), 20, U.hsl(hue, 100, 60, .22))
	var edge := U.hsl(hue, 100, 72)
	for w in [[8, -8.5, 7], [8, 8.5, 7], [-9, -9.5, 9], [-9, 9.5, 9]]:
		var rc := Rect2(w[0] - w[2] / 2.0, w[1] - 2.8, w[2], 5.6)
		draw_rect(rc, Color.BLACK); draw_rect(rc, edge, false, 1.5)
	var body := PackedVector2Array([Vector2(15, 0), Vector2(9, -5), Vector2(-12, -6.5), Vector2(-15, 0), Vector2(-12, 6.5), Vector2(9, 5)])
	draw_colored_polygon(body, Color("0b0614")); body.append(body[0]); draw_polyline(body, U.hsl(hue, 100, 65), 2, true)
	draw_circle(Vector2(-3, 0), 3.8, Color.WHITE)
	draw_set_transform(Vector2.ZERO)


func gear(c: Vector2, r: float, a: float) -> void:
	for i in 8:
		draw_set_transform(c, a + i * TAU / 8)
		draw_rect(Rect2(-r * .22, -r * 1.3, r * .44, r * .6), Color.WHITE)
	draw_set_transform(Vector2.ZERO)
	draw_circle(c, r, Color.WHITE); draw_circle(c, r * .42, Color.BLACK)


func track_preview(T: Track, c: Vector2, size: float, rot: float) -> void:
	if not previews.has(T.id):
		var pts := T.p.duplicate(); pts.append(pts[0]); previews[T.id] = pts
	var pts: PackedVector2Array = previews[T.id]
	var s := size / maxf(T.bounds.size.x, T.bounds.size.y)
	draw_set_transform_matrix(Transform2D(rot, Vector2(s, s), 0, c) * Transform2D(0, -T.bounds.get_center()))
	var hw := Track.HW * 2
	draw_polyline(pts, U.hsl(T.hue, 85, 20 + 5 * g.pulse), hw + 120)
	draw_polyline(pts, U.hsl(T.hue, 100, 62), hw + 34)
	draw_polyline(pts, Color("06040b"), hw)
	var o := T.p[0]; var f := T.tan[0] * 20; var l := T.nor[0] * 20
	for k in 8:
		for row in 2:
			var a := o + f * (row - 1) + l * (k - 4)
			draw_colored_polygon(PackedVector2Array([a, a + f, a + f + l, a + l]), Color.WHITE if (k + row) % 2 else Color("111111"))
	var d := T.p[int(fmod(g.t * .09, 1.0) * T.n)]
	draw_circle(d, 70, U.hsl(T.hue + 180, 100, 65, .5)); draw_circle(d, 32, Color.WHITE)
	draw_set_transform(Vector2.ZERO)


# ---------- screens ----------
func _draw() -> void:
	var vs := get_viewport_rect().size; W = vs.x; H = vs.y
	ui.clear()
	match g.state:
		"title": _title()
		"select": _select()
		"race": if g.race: _race()
	if g.overlay != "": _overlay()
	if g.toast_life > 0:
		var k := u(); var s := 14 * k; var w := tw(g.toast_text, s) + 40 * k; var y := H - ins_b - 80 * k
		var a := minf(1, g.toast_life * 2)
		slab(W / 2 - w / 2, y - 18 * k, w, 36 * k, 10 * k, false, Color(0, 0, 0, .9 * a))
		txt(g.toast_text, W / 2 + 5 * k, y, s, 0, Color(1, 1, 1, a))


func _title() -> void:
	var t := g.t; var hue := fmod(t * 14, 360); var k := u()
	stripes(W / 2, H / 2, t * .35, hue)
	var rr := minf(W, H) * .13 * (1 + g.pulse * .06)
	var oct := poly(W / 2, H / 2, 8, rr, -t * .6)
	draw_colored_polygon(oct, Color("07040d")); oct.append(oct[0]); draw_polyline(oct, U.hsl(hue, 100, 62), 5, true)
	var a := -t * 1.3; var c := Vector2(W / 2, H / 2)
	for i in range(6, -1, -1):
		draw_circle(c + Vector2.from_angle(a + i * .07) * rr * 1.75, 9 - i, U.hsl(hue + 180, 100, 60, .12 * (1 - i / 7.0)))
	kart2d(c + Vector2.from_angle(a) * rr * 1.75, atan2(-cos(a), sin(a)), hue + 180, 1.5)
	var ts := minf(minf(W * .17, H * .17), 140); var ty := H * .2; var t_w := tw("GOKART", ts)
	slab(-30, ty - ts * .64, W / 2 + t_w / 2 + 40, ts * 1.28, ts * .45, false, BLACK84)
	txt("GOKART", W / 2, ty, ts, 0, Color.WHITE, U.hsl(hue, 100, 45))
	txt("NEON CIRCUIT", W / 2 + t_w / 2, ty + ts * .78, maxf(11, ts * .16), 1, U.hsl(hue, 100, 75))
	var ss := minf(28, W * .065); var sw := tw("TAP TO START", ss); var sy := H * .8
	slab(W / 2 - sw / 2 - 26, sy - ss * .95, sw + 52, ss * 1.9, ss * .5, false, BLACK84)
	txt("TAP TO START", W / 2 + ss * .25, sy + 1, ss, 0, Color(1, 1, 1, .55 + .45 * sin(t * 4)))
	var gs := 54 * k; var gx := W - ins_r - 16 - gs; var gy := H - ins_b - 16 - gs
	button(gx, gy, gs, gs, "", func() -> void: g.overlay = "settings", 16, 12 * k, true)
	gear(Vector2(gx + gs / 2 - 6 * k, gy + gs / 2), gs * .24, t * .4)


func _select() -> void:
	var k := u(); var t := g.t
	var T: Track = g.tracks[g.sel] if g.sel < g.tracks.size() else null
	var hue := T.hue if T else 265.0
	stripes(W / 2, H * .42, t * .25, hue, 70.0 if T else 25.0)
	var pc := Vector2(W / 2 + g.slide * W * .5, H * .42); var ps := minf(W * .7, H * .46)
	if T:
		track_preview(T, pc, ps, sin(t * .4) * .12)
	else:
		var s := ps * .32
		var hx := poly(pc.x, pc.y, 6, s, t * .2 + sin(t * .4) * .12)
		draw_colored_polygon(hx, Color(0, 0, 0, .6))
		for i in 6: draw_dashed_line(hx[i], hx[(i + 1) % 6], U.hsl(hue, 60, 70, .8), 3, 12)
		draw_rect(Rect2(pc.x - s * .32, pc.y - 4, s * .64, 8), Color.WHITE); draw_rect(Rect2(pc.x - 4, pc.y - s * .32, 8, s * .64), Color.WHITE)
	# info band
	var ns := minf(46 * k, H * .085); var bh := ns + 66 * k
	var by := minf(H * .72, H - ins_b - bh - 40 * k)   # leave room for the cue under the band on short screens
	draw_rect(Rect2(-30, by, W + 60, bh), BLACK84)
	var title := T.name if T else "COMING LATER"; var nsz := fit(title, ns, W - 60)
	txt(title, W / 2, by + 12 * k + nsz / 2, nsz, 0, Color.WHITE, U.hsl(hue, 100, 40))
	var rec: Dictionary = g.records.get(T.id, {}) if T else {}
	var laps: int = g.settings.laps
	var line := "BEST LAP  %s     BEST %d-LAP RACE  %s" % [U.fmt(rec.get("lap", INF)), laps, U.fmt(rec.get("total%d" % laps, INF))] if T else "NEW TRACK SLOT"
	txt(line, W / 2, by + 22 * k + ns + 8 * k, fit(line, 14 * k, W - 40), 0, U.hsl(hue, 100, 75))
	if T: txt(T.sub, W / 2, by + 22 * k + ns + 28 * k, fit(T.sub, 11 * k, W - 40), 0, Color(1, 1, 1, .55))
	var cue := "TAP TO RACE  ·  %d LAP%s" % [laps, "" if laps == 1 else "S"] if T else "COMING SOON"
	txt(cue, W / 2, minf(H - ins_b - 22 * k, by + bh + 26 * k), 18 * k, 0, Color(1, 1, 1, .5 + .5 * sin(t * 4) if T else .5))
	# arrows
	var aw := 44 * k; var ah := 58 * k
	button(ins_l + 14 * k, pc.y - ah / 2, aw, ah, "<", g.change_sel.bind(-1), 26 * k, 10 * k)
	button(W - ins_r - 14 * k - aw, pc.y - ah / 2, aw, ah, ">", g.change_sel.bind(1), 26 * k, 10 * k, true)
	# top-left
	var bw := maxf(tw("LEADERBOARD", 15 * k), tw("MAIN MENU", 15 * k)) + 34 * k; var b_h := 40 * k
	var x0 := ins_l + 14 * k; var y0 := ins_t + 14 * k
	button(x0, y0, bw, b_h, "MAIN MENU", func() -> void: g.state = "title", 15 * k, 12 * k)
	button(x0, y0 + b_h + 10 * k, bw, b_h, "LEADERBOARD", func() -> void: g.overlay = "leaderboard", 15 * k, 12 * k)
	# bottom-left: rival bot toggle
	var rw := tw("RIVAL BOT: OFF", 14 * k) + 34 * k
	button(ins_l + 14 * k, H - ins_b - 14 * k - b_h, rw, b_h, "RIVAL BOT: " + ("ON" if g.settings.bot else "OFF"), g.toggle.bind("bot"), 14 * k, 12 * k, false,
		U.hsl(hue, 100, 62) if g.settings.bot else Color(0, 0, 0, 0))
	# bottom-right: lap count
	var lw := tw("LAPS: 5", 14 * k) + 34 * k
	button(W - ins_r - 14 * k - lw, H - ins_b - 14 * k - b_h, lw, b_h, "LAPS: %d" % laps, g.cycle_laps, 14 * k, 12 * k, true)
	# page dots
	var slots := g.tracks.size() + 1
	for i in slots:
		draw_colored_polygon(poly(W / 2 + (i - (slots - 1) / 2.0) * 20 * k, by - 16 * k, 4, (7 if i == g.sel else 4.5) * k, 0),
			Color.WHITE if i == g.sel else Color(1, 1, 1, .35))


# cockpit: low neon dashboard and a butterfly yoke that follows steering and drift
func _cockpit(r: Race, kh: float) -> void:
	var c: float = Race.LVL_HUE[r.lvl] if r.drift and r.lvl > 0 else kh
	var glow := U.hsl(c, 100, 62); var dh := minf(H * .2, W * .14)
	wheel += (r.st * .5 + (r.beta * .6 if r.drift else 0.0) - wheel) * minf(1, g.frame_dt * 10)
	var dash := PackedVector2Array([Vector2(0, H), Vector2(0, H - dh * .5), Vector2(W * .28, H - dh * .78), Vector2(W * .36, H - dh),
		Vector2(W * .64, H - dh), Vector2(W * .72, H - dh * .78), Vector2(W, H - dh * .5), Vector2(W, H)])
	draw_colored_polygon(dash, Color("07040d")); draw_polyline(dash.slice(1, 7), glow, 3, true)
	draw_line(Vector2(W * .37, H - dh * .86), Vector2(W * .63, H - dh * .86), U.hsl(c, 100, 62, .35), 2, true)
	for i in 4:
		var x := W * .05 + i * W * .035
		draw_line(Vector2(x, H - dh * .32), Vector2(x + W * .02, H - dh * .5), U.hsl(c, 100, 62, .45), 2, true)
		draw_line(Vector2(W - x, H - dh * .32), Vector2(W - x - W * .02, H - dh * .5), U.hsl(c, 100, 62, .45), 2, true)
	var r0 := minf(W * .22, H * .32)
	draw_set_transform(Vector2(W / 2, H - dh * .2), wheel)
	var yoke := PackedVector2Array([Vector2(-r0, -r0 * .75), Vector2(-r0, -r0 * .1), Vector2(-r0 * .55, r0 * .3), Vector2(r0 * .55, r0 * .3), Vector2(r0, -r0 * .1), Vector2(r0, -r0 * .75)])
	draw_polyline(yoke, Color("0b0614"), r0 * .2, true)
	for q in yoke: draw_circle(q, r0 * .1, Color("0b0614"))
	draw_polyline(yoke, glow, 3, true)
	draw_rect(Rect2(-2, -r0 * .12, 4, r0 * .18), Color.WHITE)
	draw_set_transform(Vector2.ZERO)


func _race() -> void:
	var r := g.race; var T := r.T; var k := u(); var spd := r.vel.length(); var kh := fposmod(T.hue + 180, 360)
	if g.settings.view == "fps":
		if r.boost > 0: draw_rect(Rect2(0, 0, W, H), U.hsl(kh, 100, 60, .1 * minf(1, r.boost * 2)))
		_cockpit(r, kh)
	if r.flash > 0: draw_rect(Rect2(0, 0, W, H), Color(1, .16, .31, r.flash * .35))
	# top-right: lap, current lap time, best lap
	var right := W - ins_r - 14 * k; var top := ins_t + 12 * k; var s1 := 30 * k; var s2 := 20 * k; var s3 := 14 * k
	var place := r.position()
	var lap_txt := ("P%d  " % place if place else "") + "LAP %d/%d" % [mini(r.laps_done + 1, r.laps_total), r.laps_total]
	var cur := 0.0 if r.phase == Race.COUNT else r.total if r.phase == Race.FINISH else r.time - r.lap_start
	var cur_txt := ("TOTAL " if r.phase == Race.FINISH else "") + U.fmt(cur); var best_txt := "BEST " + U.fmt(r.best)
	var bw := maxf(maxf(tw(lap_txt, s1), tw(cur_txt, s2)), tw(best_txt, s3)) + 30 * k; var bh := s1 + s2 + s3 + 30 * k
	slab(right - bw, top, bw, bh, 18 * k, true, Color(0, 0, 0, .8))
	txt(lap_txt, right - 12 * k, top + 9 * k + s1 / 2, s1, 1)
	txt(cur_txt, right - 12 * k, top + 15 * k + s1 + s2 / 2, s2, 1, U.hsl(T.hue, 100, 72))
	txt(best_txt, right - 12 * k, top + 20 * k + s1 + s2 + s3 / 2, s3, 1, Color(1, 1, 1, .7))
	# split against the best lap at every apex: green ahead, red behind
	if r.delta_t > 0:
		var dc := Color("3dff9a") if r.delta <= 0 else Color("ff4d6d"); dc.a = minf(1, r.delta_t * 2)
		txt(("LAP " if r.delta_lap else "") + "%+.2f" % r.delta, right - 12 * k, top + bh + 20 * k, 26 * k, 1, dc, Color(0, 0, 0, .8))
	# top-left: pause
	var pb := 46 * k; var px := ins_l + 12 * k
	button(px, top, pb, pb, "", func() -> void: g.overlay = "pause", 16, 10 * k)
	draw_rect(Rect2(px + pb / 2 - 7 * k, top + pb / 2 - 9 * k, 5 * k, 18 * k), Color.WHITE)
	draw_rect(Rect2(px + pb / 2 + 3 * k, top + pb / 2 - 9 * k, 5 * k, 18 * k), Color.WHITE)
	# instant restart
	var rx := px + pb + 12 * k; var rc := Vector2(rx + pb / 2 + 2 * k, top + pb / 2)
	button(rx, top, pb, pb, "", g.restart, 16, 10 * k)
	draw_arc(rc, 9 * k, -PI * .3, PI * 1.35, 20, Color.WHITE, 3.5 * k, true)
	var tip := rc + Vector2.from_angle(-PI * .3) * 9 * k
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-7, -5) * k, tip + Vector2(6, -3) * k, tip + Vector2(0, 7) * k]), Color.WHITE)
	# bottom centre: flow + speed + drift charge
	var bwid := minf(W * .46, 300 * k); var bx := W / 2 - bwid / 2; var byy := H - ins_b - 26 * k
	slab(bx - 12 * k, byy - 30 * k, bwid + 24 * k, 44 * k, 10 * k, false, Color(0, 0, 0, .65))
	txt("FLOW x%.2f" % (1 + Race.FLOW_GAIN * r.F), bx, byy - 15 * k, 13 * k)
	txt("%d KM/H" % roundi(spd * .22), bx + bwid, byy - 15 * k, 13 * k, 1, Color(1, 1, 1, .75))
	draw_rect(Rect2(bx, byy, bwid, 6 * k), Color(1, 1, 1, .14)); draw_rect(Rect2(bx, byy, bwid * r.F, 6 * k), U.hsl(kh, 100, 62))
	var pips := roundi(1 / Race.ASSIST_STEP); var lv := roundi(r.assist / Race.ASSIST_STEP); var pw := 12 * k
	txt("ASSIST", bx - 12 * k, byy - 44 * k, 11 * k, -1, U.hsl(kh, 100, 75) if r.assist_on > .5 else Color(1, 1, 1, .55))
	for i in pips:
		slab(bx + 44 * k + i * (pw + 5 * k), byy - 48 * k, pw, 8 * k, 4 * k, false, U.hsl(kh, 100, 65, .5 + .5 * r.assist_on) if i < lv else Color(1, 1, 1, .18))
	if r.combo >= 2:
		txt("COMBO %d  ·  x%.1f" % [r.combo, r.mult()], bx + bwid + 12 * k, byy - 46 * k, (11 + mini(r.combo, 10) * .8) * k, 1,
			U.hsl(kh + r.combo * 14, 100, 70), Color(0, 0, 0, .8))
	if r.drift:
		var dw := 26 * k
		for i: int in [1, 2, 3]:
			slab(W / 2 + (i - 2) * (dw + 8 * k) - dw / 2, byy - 66 * k, dw, 10 * k, 5 * k, false, Race.LVLC[i] if r.lvl >= i else Color(1, 1, 1, .18))
	# touch feedback
	for sd: int in [-1, 1]:
		if not (g.in_l if sd < 0 else g.in_r): continue
		var ex := ins_l + 18 * k if sd < 0 else W - ins_r - 18 * k; var cy := H * .55
		var mine: bool = r.drift and r.d_dir == sd
		draw_polyline(PackedVector2Array([Vector2(ex - sd * 14 * k, cy - 22 * k), Vector2(ex, cy), Vector2(ex - sd * 14 * k, cy + 22 * k)]),
			Race.LVLC[r.lvl] if mine else Color(1, 1, 1, .4), 5 * k, true)
		if mine: txt("DRIFT", ex - sd * 30 * k, cy - 38 * k, 12 * k, 0, Color(1, 1, 1, .75))
	# guides at the start
	if not is_finite(r.best) and (r.phase == Race.COUNT or (r.laps_done == 0 and r.time < 3)):
		var al := .85 if r.phase == Race.COUNT else maxf(0, 1 - r.time / 3) * .85
		var wc := Color(1, 1, 1, al)
		draw_dashed_line(Vector2(W / 2, H * .3), Vector2(W / 2, H * .7), Color(1, 1, 1, al * .25), 2, 9)
		var gs := fit("HOLD LONGER = DRIFT", 14 * k, W * .42)
		txt("TAP = LEFT", W * .25, H * .5, gs, 0, wc); txt("HOLD LONGER = DRIFT", W * .25, H * .5 + 20 * k, gs, 0, wc)
		txt("TAP = RIGHT", W * .75, H * .5, gs, 0, wc); txt("LET GO = BOOST", W * .75, H * .5 + 20 * k, gs, 0, wc)
		if not OS.has_feature("mobile"): txt("KEYS: A D / ← →", W / 2, H * .5 + 50 * k, 11 * k, 0, Color(1, 1, 1, al * .6))
	# countdown
	if r.phase == Race.COUNT:
		var nn := ceili(r.count)
		if nn <= 3 and nn > 0:
			var fr := nn - r.count
			txt(str(nn), W / 2, H * .3, 96 * k * (1.25 - .25 * fr), 0, Color(1, 1, 1, 1 - fr * .6), U.hsl(T.hue, 100, 45))
	# popups
	var py := H * .24
	for q in r.pops:
		var f := q.life / q.mx; var sz := (72.0 if q.text == "GO!" else 24.0) * k
		txt(q.text, W / 2, py - (1 - f) * 30 * k, sz, 0, Color(q.c, minf(1, f * 2)), Color(0, 0, 0, .8))
		py += sz * 1.1


func _view_row(bx: float, y: float, bw: float, bh: float, k: float) -> void:
	var half := (bw - 12 * k) / 2
	button(bx, y, half, bh, "VIEW: " + ("FPS" if g.settings.view == "fps" else "TOP"), g.cycle_view, fit("VIEW: FPS", 15 * k, half - 24 * k))
	button(bx + half + 12 * k, y, half, bh, SKY_NAME.get(g.settings.sky, "CLASSIC"), g.cycle_sky, fit("CYBER CITY", 15 * k, half - 24 * k))


func _panel(title: String, hue: float) -> float:
	draw_rect(Rect2(0, 0, W, H), Color(.016, .008, .031, .74))
	var k := u(); var ts := minf(40 * k, W * .09); var t_w := tw(title, ts); var y := maxf(H * .14, ins_t + ts)
	slab(W / 2 - t_w / 2 - 30 * k, y - ts * .7, t_w + 60 * k, ts * 1.4, ts * .4, false, Color(0, 0, 0, .9))
	txt(title, W / 2 + ts * .2, y + 1, ts, 0, Color.WHITE, U.hsl(hue, 100, 45))
	return y + ts * 1.2


func _overlay() -> void:
	draw_ov = true
	var k := u(); var bw := minf(W - 60, 340 * k); var bh := minf(48 * k, H * .11); var gap := minf(12 * k, H * .025); var bx := W / 2 - bw / 2
	var hue: float = g.race.T.hue if g.state == "race" and g.race else g.tracks[g.sel].hue if g.state == "select" and g.sel < g.tracks.size() else fmod(g.t * 14, 360)
	var close := func() -> void: g.overlay = ""
	var to_menu := func() -> void: g.state = "select"; g.overlay = ""
	match g.overlay:
		"settings":
			var y := _panel("SETTINGS", hue) + 20 * k
			_view_row(bx, y, bw, bh, k); y += bh + gap
			var half := (bw - 12 * k) / 2; var on := U.hsl(hue, 100, 62); var off := Color(0, 0, 0, 0)
			button(bx, y, half, bh, "FX: " + ("ON" if g.settings.sfx else "OFF"), g.toggle.bind("sfx"), 15 * k, 10, false, on if g.settings.sfx else off)
			button(bx + half + 12 * k, y, half, bh, "MUSIC: " + ("ON" if g.settings.music else "OFF"), g.toggle.bind("music"), fit("MUSIC: OFF", 15 * k, half - 24 * k), 10, false, on if g.settings.music else off)
			y += bh + gap * 2
			button(bx, y, bw, bh, "BACK", close, 17 * k)
		"leaderboard":
			var y := _panel("LEADERBOARD", hue) + 10 * k
			var soon := func() -> void: g.toast("COMING IN THE FINAL VERSION")
			var half := (bw - 12 * k) / 2
			button(bx, y, half, bh, "PLAY GAMES", soon, fit("PLAY GAMES", 15 * k, half - 24 * k))
			button(bx + half + 12 * k, y, half, bh, "GAME CENTER", soon, fit("GAME CENTER", 15 * k, half - 24 * k)); y += bh + gap * 1.6
			txt("YOUR RECORDS", W / 2, y, 13 * k, 0, U.hsl(hue, 100, 75)); y += 20 * k
			for T in g.tracks:
				var rc: Dictionary = g.records.get(T.id, {})
				txt(T.name, bx + 8 * k, y, 14 * k); txt(U.fmt(rc.get("lap", INF)), bx + bw - 8 * k, y, 14 * k, 1, Color(1, 1, 1, .8)); y += 22 * k
			y += gap
			button(bx, y, bw, bh, "BACK", close, 17 * k)
		"pause":
			var y := _panel("PAUSED", hue) + 10 * k
			button(bx, y, bw, bh, "RESUME", close, 17 * k); y += bh + gap
			button(bx, y, bw, bh, "RESTART", g.restart, 17 * k); y += bh + gap
			_view_row(bx, y, bw, bh, k); y += bh + gap
			button(bx, y, bw, bh, "RETURN TO MENU", to_menu, 17 * k)
		"finish":
			var r := g.race; var y := _panel("FINISH", hue) + 12 * k
			if r.bot:
				var win := r.place == 1
				var behind := "  +%.2fs" % (r.total - r.bot.total) if not win and is_finite(r.bot.total) else ""
				txt("YOU BEAT THE BOT" if win else "BOT WINS" + behind, W / 2, y, 20 * k, 0, Color("ffd23d") if win else Color("ff4d6d")); y += 28 * k
			txt("TOTAL  " + U.fmt(r.total) + ("   NEW RECORD" if r.new_total else ""), W / 2, y, 22 * k, 0, Color("ffd23d") if r.new_total else Color.WHITE); y += 28 * k
			txt("BEST LAP  " + U.fmt(r.laps.min()) + ("  ★" if r.new_lap else ""), W / 2, y, 17 * k, 0, U.hsl(hue, 100, 75)); y += 24 * k
			var parts: Array = []
			for i in r.laps.size(): parts.append("L%d %s" % [i + 1, U.fmt(r.laps[i])])
			var lt := "   ".join(parts)
			txt(lt, W / 2, y, fit(lt, 12 * k, W - 40), 0, Color(1, 1, 1, .6)); y += 26 * k
			var half := (bw - 12 * k) / 2
			button(bx, y, half, bh, "RACE AGAIN", g.restart, fit("RACE AGAIN", 16 * k, half - 24 * k), 10, false, U.hsl(hue, 100, 62))
			button(bx + half + 12 * k, y, half, bh, "MENU", to_menu, 16 * k)
	draw_ov = false


# ---------- input ----------
func release_all() -> void:
	touch_l = -1; touch_r = -1; swipe_id = -1


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed: _press(e.index, e.position)
		else: _release(e.index, e.position)
	elif e is InputEventKey and e.pressed and not e.echo:
		_key(e.physical_keycode)


func _press(id: int, at: Vector2) -> void:
	for i in range(ui.size() - 1, -1, -1):
		var b: Array = ui[i]
		if g.overlay != "" and not b[2]: continue
		if b[0].has_point(at):
			g.audio.play("click"); b[1].call()
			return
	if g.overlay != "": return
	match g.state:
		"title": g.audio.play("click"); g.state = "select"
		"select": swipe_id = id; swipe_from = at
		"race":
			if at.x < W / 2:
				if touch_l < 0: touch_l = id
			elif touch_r < 0: touch_r = id


func _release(id: int, at: Vector2) -> void:
	if id == touch_l: touch_l = -1
	if id == touch_r: touch_r = -1
	if id == swipe_id:
		swipe_id = -1
		if g.state != "select" or g.overlay != "": return
		var d := at - swipe_from
		if absf(d.x) > 50 and absf(d.x) > absf(d.y): g.change_sel(1 if d.x < 0 else -1)
		elif absf(d.x) < 14 and absf(d.y) < 14: g.audio.play("click"); g.try_start()


func _key(k: Key) -> void:
	if k == KEY_ESCAPE or k == KEY_P:
		g.back()
	elif g.overlay != "":
		if g.overlay == "finish" and (k == KEY_ENTER or k == KEY_R): g.restart()
	elif g.state == "race" and k == KEY_R:
		g.restart()
	elif g.state == "title":
		if k == KEY_ENTER or k == KEY_SPACE: g.state = "select"
	elif g.state == "select":
		if k == KEY_LEFT: g.change_sel(-1)
		elif k == KEY_RIGHT: g.change_sel(1)
		elif k == KEY_ENTER or k == KEY_SPACE: g.try_start()
