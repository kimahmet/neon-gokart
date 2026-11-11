class_name Race
extends RefCounted
## One race: kart physics, drift and boost, aim assist, walls, laps and the rival bot.
## Pure simulation, stepped at a fixed DT; drawing and sound read its state and drain `events`.

# ---------- tuning ----------
const LAP_CHOICES := [1, 3, 5]
const V0 := 520.0
const ACC := 700.0
const BRAKE := 1500.0
const DT := 1.0 / 120
const A_GRIP := 1350.0     # tyre grip limit (u/s²)
const LINE_GRIP := .7      # extra grip on the racing line
const BOT_SKILL := .93
const ASSIST_STEP := .2
const ASSIST_MIN := .4
const A_DRIFT := 2600.0    # drift turning strength
const SCRUB := .55         # speed scrubbed by the slide
const FLOW_GAIN := .85     # vmax = V0*(1+0.85F)
const FLOW_TAU := 40.0     # dF/dt=(1-F)/40 while clean
const LVL_AT := [0.0, 0.5, 1.3, 2.3]
const LVLC := [Color.WHITE, Color("38d6ff"), Color("ff9a1f"), Color("ff3df0")]
const LVL_HUE := [0.0, 195.0, 30.0, 300.0]
const HOLD_DRIFT := .3     # holding one side this long at speed starts a drift
const MAX_PARTS := 500
const HW := Track.HW
const GHOST_HZ := 30.0     # ghost path samples per second
const NEAR := 6.0          # close-call band just inside the wall (the racing line stays outside it)

enum { COUNT, GO, FINISH }

class Bot:
	var s := 0.0; var s0 := 0.0; var lat0 := 24.0; var v := 0.0; var F := 0.0; var slip := 0.0
	var pos := Vector2.ZERO; var prev := Vector2.ZERO; var h := 0.0; var hp := 0.0
	var done := false; var total := INF

class Part:
	var pos: Vector2; var vel: Vector2; var life: float; var mx: float; var c: Color; var s: float

class Pop:
	var text: String; var c: Color; var life: float; var mx: float

var T: Track
var ti: int
var rec: Dictionary            # this track's records {lap, total}; updated in place
var pos: Vector2; var prev: Vector2
var h := 0.0; var hp := 0.0
var vel := Vector2.ZERO
var F := 0.0; var charge := 0.0; var lvl := 0
var drift := false; var d_dir := 0; var beta := 0.0; var boost := 0.0
var idx := 0; var prog := 0
var laps_done := 0; var lap_start := 0.0; var time := 0.0; var laps: Array[float] = []
var count := 3.2; var phase := COUNT
var hit_cool := 0.0; var clean_lap := true; var shake := 0.0; var flash := 0.0
var trail := PackedVector2Array()
var parts: Array[Part] = []; var pops: Array[Pop] = []
var apex_hit := {}
var best := INF; var fin := 0.0; var total := 0.0; var new_lap := false; var new_total := false
var thr := 0.0; var st := 0.0; var br := false; var h_dir := 0; var hold_t := 0.0
var on_line := 0.0; var place := 0; var bot: Bot
var sts := 0.0; var wall_grip := 0.0; var assist := ASSIST_MIN; var assist_on := 0.0
var cam_a := 0.0; var cam_ap := 0.0; var fyaw := 0.0; var fyaw_p := 0.0
var events: Array = []         # [name, arg] pairs for sound, drained by the caller every frame
var laps_total := 3; var total_key := "total3"   # best race time is kept per lap count
var combo := 0; var wall_t := 0.0; var near_t := 0.0
var ghost_buf: Array = []      # this lap's path (x, y, heading at GHOST_HZ); becomes the ghost when it beats the best lap
var splits: Array = []         # this lap's times at each apex position
var delta := 0.0; var delta_t := 0.0; var delta_lap := false   # last split against the best lap, shown for delta_t seconds


func _init(track: Track, track_i: int, records: Dictionary, with_bot: bool, laps_n := 3) -> void:
	T = track; ti = track_i; rec = records
	laps_total = laps_n; total_key = "total%d" % laps_n
	var i0 := 4
	pos = T.p[i0]; h = T.tan[i0].angle(); idx = i0; prog = i0
	best = rec.get("lap", INF)
	if with_bot:
		pos -= T.nor[i0] * 24
		bot = Bot.new(); bot.s = i0; bot.s0 = i0; bot.h = h
		_place_bot(0); bot.prev = bot.pos; bot.hp = bot.h
	prev = pos; hp = h; cam_a = h; cam_ap = h; fyaw = h; fyaw_p = h


func speed() -> float:
	return vel.length()


func pop(text: String, c := Color.WHITE, life := 1.2) -> void:
	var q := Pop.new(); q.text = text; q.c = c; q.life = life; q.mx = life
	pops.append(q)


func _spawn(at: Vector2, v: Vector2, life: float, c: Color, s: float) -> void:
	if parts.size() > MAX_PARTS: return
	var q := Part.new(); q.pos = at; q.vel = v; q.life = life; q.mx = life; q.c = c; q.s = s
	parts.append(q)


func _upd_parts(dt: float) -> void:
	var d := 1 - dt * 3
	var i := parts.size() - 1
	while i >= 0:
		var q := parts[i]
		q.life -= dt
		if q.life <= 0:
			parts[i] = parts[-1]; parts.pop_back()
		else:
			q.pos += q.vel * dt; q.vel *= d
		i -= 1


# rival bot: rides the racing line with the speed profile, drifting where the corner load is high
func _place_bot(dt: float) -> void:
	var b := bot; var n := T.n
	var i := int(b.s) % n; var j := (i + 1) % n; var f := b.s - floorf(b.s)
	var bl := smoothstep(0.0, 1.0, clampf(1 - (b.s - b.s0) / 80, 0, 1))
	var lat := (b.lat0 - T.off[i]) * bl
	b.pos = T.line[i].lerp(T.line[j], f) + T.nor[i] * lat
	var load := b.v * b.v * absf(T.lk[i])
	var ts := signf(T.lk[i]) * clampf((load - 1000) / 900, 0, 1) * .45
	b.slip += (ts - b.slip) * minf(1, dt * 5)
	b.h = T.lh[i] + b.slip


func _step_bot(dt: float) -> void:
	var b := bot
	b.prev = b.pos; b.hp = b.h
	if phase == COUNT: return
	var i := int(b.s) % T.n
	b.F = minf(1, b.F + (1 - b.F) / FLOW_TAU * dt)
	var tgt := 0.0 if b.done else minf(T.lv[i], V0 * (1 + FLOW_GAIN * b.F)) * BOT_SKILL
	b.v = minf(tgt, b.v + ACC * .9 * dt) if b.v < tgt else maxf(tgt, b.v - Track.BOT_DEC * 1.4 * dt)
	b.s += b.v * dt / T.lds[i]
	if not b.done and b.s >= laps_total * T.n:
		b.done = true; b.total = time
	_place_bot(dt)
	if absf(b.slip) > .15 and randf() < .7:
		_wheel_sparks(b.pos, b.h, Vector2.from_angle(T.lh[i]) * b.v, Color.WHITE, 2.5)


func _wheel_sparks(at: Vector2, heading: float, v: Vector2, c: Color, s: float) -> void:
	var f := Vector2.from_angle(heading); var side := Vector2(-f.y, f.x)
	for sd: int in [-1, 1]:
		var aa := heading + PI + (randf() - .5) * .9
		_spawn(at - f * 10 + side * 8 * sd, Vector2.from_angle(aa) * (60 + randf() * 120) + v * .3, .35, c, s)


func _end_drift(reward: bool) -> void:
	if not drift: return
	var L := lvl
	drift = false; lvl = 0; charge = 0
	if reward and L > 0:
		boost = [0, .5, .85, 1.3][L]
		var f := Vector2.from_angle(h); var m := mult()
		vel += f * 70 * L * m; F = minf(1, F + .015 * L * m)
		combo += 1
		pop(["", "BOOST", "SUPER BOOST", "ULTRA BOOST"][L], LVLC[L])
		events.append(["boost", L])
		for i in 14 * L:
			var a := h + PI + (randf() - .5) * 1.2
			_spawn(pos - f * 12, Vector2.from_angle(a) * (150 + randf() * 250), .5, LVLC[L], 4)


# camera follows the road ahead, not the steering.
# First-person yaw: the direction of travel blended with the road ahead, low-passed and rate-limited,
# so taps, drift slip and assist corrections never whip the view around
func _cam_follow(dt: float) -> void:
	var n := T.n; var sp := vel.length()
	var vd := vel.angle() if sp > 40 else h
	var road := (T.p[(idx + 28) % n] - T.p[(idx + 6) % n]).angle()
	var tgt := vd + angle_difference(vd, road) * .5
	fyaw_p = fyaw
	fyaw += clampf(angle_difference(fyaw, tgt) * minf(1, dt * 3), -1.8 * dt, 1.8 * dt)
	cam_ap = cam_a
	cam_a += angle_difference(cam_a, (T.p[(idx + 40) % n] - T.p[(idx + 8) % n]).angle()) * minf(1, dt * 1.6)


## Advance the race by dt. Two-button controls: left/right steer, gas is automatic.
func step(dt: float, in_l: bool, in_r: bool) -> void:
	var n := T.n
	prev = pos; hp = h
	var in_st := (1.0 if in_r else 0.0) - (1.0 if in_l else 0.0)
	var dir := int(signf(in_st))
	if dir != 0 and dir == h_dir: hold_t += dt
	else: h_dir = dir; hold_t = 0
	var in_br := ((in_l if d_dir < 0 else in_r) if drift else (dir != 0 and hold_t >= HOLD_DRIFT))
	thr = 1; st = in_st; br = in_br
	if bot: _step_bot(dt)
	shake = maxf(0, shake - dt * 2.5); flash = maxf(0, flash - dt * 2); hit_cool -= dt; delta_t -= dt
	_upd_parts(dt)
	for q in pops: q.life -= dt
	pops = pops.filter(func(q: Pop) -> bool: return q.life > 0)
	if phase == COUNT:
		var before := ceili(count)
		count -= dt
		var now := ceili(count)
		if now < before and now > 0 and now <= 3: events.append(["beep", 440])
		if count <= 0:
			phase = GO; time = 0; lap_start = 0
			events.append(["beep", 880]); pop("GO!", Color.WHITE, 1.1)
		_cam_follow(dt)
		return
	var throttle := 1.0; var s_in := in_st; var brk := in_br
	# steering builds up while held (a tap is a nudge, a hold is full lock) and lets go quickly
	var tight := clampf(absf(T.lk[(idx + 12) % n]) * 400 - 1, 0, 1)   # a tight corner or chicane ahead: steering reacts faster
	var rate := 10.0 if absf(s_in) < absf(sts) or s_in * sts < 0 else 3.5 + 4.5 * tight
	sts = move_toward(sts, s_in, rate * dt); s_in = sts
	if phase == FINISH:
		var des := (T.p[(idx + 14) % n] - pos).angle()
		s_in = clampf(angle_difference(h, des) * 2.2, -1, 1)
		throttle = .6 if vel.length() < V0 * .55 else 0.0
		brk = false; fin += dt
	else:
		time += dt
	var spd := vel.length()
	# on the racing line the tyres grip harder
	var lat0 := (pos - T.p[idx]).dot(T.nor[idx])
	on_line += (clampf(1 - absf(lat0 - T.off[idx]) / 30, 0, 1) - on_line) * minf(1, dt * 8)
	var vmax := V0 * (1 + FLOW_GAIN * F)
	if boost > 0: vmax *= 1.3
	if not drift and brk and absf(s_in) > .3 and spd > V0 * .4 and phase == GO:
		drift = true; d_dir = int(signf(s_in)); charge = 0; lvl = 0; beta = 0
	if drift and (not brk or spd < V0 * .25): _end_drift(not brk)
	if drift:
		# drift: steering sets the slip angle; a wider angle turns the car tighter but scrubs more speed
		var psi := vel.angle()
		var tb := d_dir * clampf(.38 + .32 * s_in * d_dir, .06, .75)
		beta += (tb - beta) * minf(1, dt * 6)
		psi += signf(beta) * minf(4, A_DRIFT * absf(sin(beta)) / maxf(spd, 80)) * dt
		var s := spd + (throttle * ACC * .8 * (1 - spd / vmax) - SCRUB * absf(sin(beta)) * spd) * dt
		if boost > 0: boost -= dt; s += 700 * dt
		s = maxf(0, s)
		vel = Vector2.from_angle(psi) * s; h = psi + beta
		charge += dt * (.4 + 1.6 * absf(beta)) * clampf(spd / V0, .5, 1.6)
		var L := 3 if charge >= LVL_AT[3] else 2 if charge >= LVL_AT[2] else 1 if charge >= LVL_AT[1] else 0
		if L > lvl: lvl = L; events.append(["charge", L])
	else:
		# grip: the tyres cap how fast the kart can turn at speed, so tight corners need a drift
		var want := s_in * 3.6 * clampf(.25 + spd / 170, 0, 1)
		var cap := A_GRIP * (1 + LINE_GRIP * on_line + (.6 if wall_grip > 0 else 0.0)) / maxf(spd, 60)
		wall_grip -= dt
		h += clampf(want, -cap, cap) * dt
		var g := Vector2.from_angle(h); var gl := Vector2(-g.y, g.x)
		var vf := vel.dot(g); var vl := vel.dot(gl)
		var a := throttle * ACC * (1 - vf / vmax)
		if throttle < .05: a -= 160
		if brk: a -= BRAKE
		if vf > vmax: a = minf(a, -(vf - vmax) * 1.2)
		# no brake button: above the speed the racing line can carry into the next corner, ease off automatically
		var safe := T.lv[idx] * 1.1
		if phase == GO and vf > safe: a = minf(a, -minf(BRAKE * .7, (vf - safe) * 3))
		if boost > 0: boost -= dt; a += 700
		vf = maxf(0, vf + a * dt); vl *= exp(-9 * dt)
		vel = g * vf + gl * vl
	# aim assist: in a corner, pressing the right way (or riding a boost) pulls the kart onto the racing line.
	# It starts weak and every apex taken makes it stronger.
	var sp := vel.length()
	var ck := T.lk[(idx + 10) % n]
	var corner := absf(ck) > 1.0 / 420 and signf(s_in) == signf(ck)
	var on := phase == GO and sp > 60 and (corner or boost > 0)
	assist_on += ((1.0 if on else 0.0) - assist_on) * minf(1, dt * 10)
	if on:
		var kk := .4 + .9 * assist
		var des := (T.line[(idx + 6 + int(sp / 60)) % n] - pos).angle()
		var d := angle_difference(vel.angle(), des) * minf(1, dt * 5 * kk)
		vel = vel.rotated(d)
		h += d if drift else angle_difference(h, des) * minf(1, dt * 5 * kk)
	pos += vel * dt
	if drift and randf() < .8: _wheel_sparks(pos, h, vel, LVLC[lvl], 3.5 if lvl > 0 else 2.0)
	# nearest centreline sample (local search keeps progress stable)
	var bd := INF; var bi := idx
	for o in range(-30, 31):
		var i := (idx + o + n) % n
		var d2 := pos.distance_squared_to(T.p[i])
		if d2 < bd: bd = d2; bi = i
	var di := bi - idx
	if di > n / 2: di -= n
	elif di < -n / 2: di += n
	prog += di; idx = bi
	# walls
	var c := T.p[bi]; var dist := sqrt(bd); var lim := HW - 9
	if dist <= lim:
		wall_t = 0
		# close call: skim the wall at speed without touching it, then pull away for a combo point and a small boost
		if phase == GO and dist > lim - NEAR and spd > V0 * .6: near_t += dt
		else:
			if near_t >= .2:
				combo += 1; F = minf(1, F + .03 * mult()); boost = maxf(boost, .2 + .3 * minf(1, near_t))
				pop("CLOSE CALL", Color("fff6c0"), .8); events.append(["near", combo])
			near_t = 0
	else:
		near_t = 0
		var u := (pos - c) / dist
		pos = c + u * lim
		var vn := vel.dot(u)
		if vn > 0:
			# a wall only slows you down: drop the into-wall speed, turn the nose along the track and keep sliding
			vel -= u * vn
			var tg := T.tan[bi]; var t_h := tg.angle()
			# glancing contact rides the wall: sparks and a short grip boost (drift keeps going).
			# Only a head-on hit (into-wall speed > 45% of total) costs a BUMP: speed, flow and assist.
			var hard := vn > 60 and vn > .45 * spd
			if hard and hit_cool <= 0 and phase == GO:
				vel *= .88; F = maxf(0, F - .1); assist = maxf(ASSIST_MIN, assist - ASSIST_STEP); boost = 0
				_combo_break()
				clean_lap = false; hit_cool = .4; shake = clampf(vn / 300, .2, .7); flash = .25
				_end_drift(false); events.append(["hit", vn * .7]); pop("BUMP", Color("ff4d6d"), .6)
				h += angle_difference(h, t_h) * .5
				for i in 16:
					_spawn(pos + u * 9, Vector2.from_angle(randf() * TAU) * (80 + randf() * 220), .4, U.hsl(T.hue, 100, 70), 3)
			# glancing contact still costs speed silently: the steeper the touch the more it scrubs, scraping drags and drains flow
			elif phase == GO:
				wall_grip = .5
				wall_t += dt
				if wall_t > .12: _combo_break()   # a brush is forgiven, riding the wall is not
				boost = maxf(0, boost - dt * 6)   # scraping burns the boost off in a few frames
				vel *= (1 - clampf(.9 * vn / maxf(spd, 1), 0, .35)) * (1 - dt * 2.2)
				F = maxf(0, F - dt * .08)
				if randf() < .5:
					var aa := (-vel).angle() + (randf() - .5) * .8
					_spawn(pos + u * 9, Vector2.from_angle(aa) * (100 + randf() * 200), .3, Color("fff6c0"), 2.5)
			if not drift: h += angle_difference(h, t_h) * minf(1, dt * 6)
			var vt := vel.dot(tg); var vmin := V0 * .3
			if phase == GO and vt < vmin: vel += tg * (vmin - vt)
	# flow grows while clean and fast
	if phase == GO and vel.length() > V0 * .55 and hit_cool <= 0: F = minf(1, F + (1 - F) / FLOW_TAU * dt)
	trail.append(pos - Vector2.from_angle(h) * 12)
	if trail.size() > 260: trail.remove_at(0)
	# apex: pass through the inside of a corner
	if phase == GO:
		for ap in T.apex:
			if apex_hit.has(ap.x): continue
			var d := idx - ap.x
			if d > n / 2: d -= n
			elif d < -n / 2: d += n
			if absi(d) <= 3 and (pos - T.p[ap.x]).dot(T.nor[ap.x]) * ap.y > HW * .15:
				apex_hit[ap.x] = true
				if drift: charge += .9
				combo += 1; F = minf(1, F + .04 * mult()); assist = minf(1, assist + ASSIST_STEP)
				# perfect: right on the inside kerb, where the racing line touches the corner
				if (pos - T.p[ap.x]).dot(T.nor[ap.x]) * ap.y > HW * .55:
					pop("PERFECT APEX", Color.WHITE, .9); events.append(["perfect", 0])
				else:
					pop("APEX  ·  ASSIST %d" % roundi(assist / ASSIST_STEP), U.hsl(T.hue + 180, 100, 70), .9)
				events.append(["apex", combo])
	if phase == GO:
		var lt := time - lap_start
		while ghost_buf.size() / 3 <= int(lt * GHOST_HZ):
			ghost_buf.append_array([snappedf(pos.x, .1), snappedf(pos.y, .1), snappedf(h, .001)])
		var lp := prog - laps_done * n
		var best_s: Array = rec.get("splits", [])
		while splits.size() < T.apex.size() and lp >= T.apex[splits.size()].x:
			if splits.size() < best_s.size():
				delta = lt - best_s[splits.size()]; delta_t = 2.0; delta_lap = false
			splits.append(lt)
	if phase == GO and prog >= (laps_done + 1) * n: _lap_done()
	_cam_follow(dt)


func _lap_done() -> void:
	var lt := time - lap_start
	laps.append(lt); lap_start = time; laps_done += 1
	var old: float = rec.get("lap", INF)
	if is_finite(old): delta = lt - old; delta_t = 2.5; delta_lap = true
	if lt < old:
		rec.lap = lt; new_lap = true; pop("NEW BEST LAP", Color.WHITE, 1.6)
		rec.ghost = ghost_buf; rec.splits = splits
	ghost_buf = []; splits = []
	best = rec.lap
	if clean_lap:
		F = minf(1, F + .06); pop("CLEAN LAP  +FLOW", U.hsl(T.hue, 100, 72), 1.4)
	clean_lap = true; apex_hit.clear(); events.append(["lap", 0])
	if laps_done == laps_total - 1: pop("FINAL LAP", Color("ffd23d"), 1.6)
	if laps_done >= laps_total:
		phase = FINISH
		if bot: place = 2 if bot.done else 1
		total = time
		if total < rec.get(total_key, INF): rec[total_key] = total; new_total = true
		fin = 0; _end_drift(false)
	events.append(["save", 0])


## Combo multiplier: every apex and boost in a row without riding a wall adds 10%, up to x2.
func mult() -> float:
	return 1 + mini(combo, 10) * .1


func _combo_break() -> void:
	if combo >= 3:
		pop("COMBO %d LOST" % combo, Color("ff4d6d"), .9); events.append(["combo_lost", combo])
	combo = 0


## Best-lap ghost at the current lap time as (x, y, heading), or null when there is none.
func ghost_at() -> Variant:
	var gh: Array = rec.get("ghost", [])
	if phase != GO: return null
	var f := (time - lap_start) * GHOST_HZ; var i := int(f) * 3
	if i + 5 >= gh.size(): return null
	var w := f - int(f)
	return Vector3(lerpf(gh[i], gh[i + 3], w), lerpf(gh[i + 1], gh[i + 4], w), lerp_angle(gh[i + 2], gh[i + 5], w))


## Race position against the bot (0 = no bot).
func position() -> int:
	if not bot: return 0
	if phase == FINISH: return place
	return 2 if bot.done or bot.s > prog else 1
