extends SceneTree
## Headless self-check: an autopilot drives every track, plus unit checks for walls, combo, ghost, splits and music.
## Run: godot --headless --path godot -s res://tests/sim.gd

static func autopilot(r: Race) -> int:
	var sp := r.vel.length()
	var des := (r.T.line[(r.idx + 8 + int(sp / 50)) % r.T.n] - r.pos).angle()
	var d := angle_difference((r.vel.angle() if sp > 40 else r.h) + r.sts * 0.15, des)
	return 1 if d > .04 else -1 if d < -.04 else 0

func check(ok: bool, what: String) -> void:
	if not ok: printerr("FAIL ", what); failed = true

var failed := false

func _init() -> void:
	var tracks := Track.build_all()
	for ti in tracks.size():
		var T := tracks[ti]
		var rec := {}
		var r := Race.new(T, ti, rec, true, 3)
		var steps := 0; var hits := 0; var boosts := 0; var fsum := 0.0; var max_combo := 0; var deltas := 0
		while r.phase != Race.FINISH and steps < 120 * 600:
			var a := autopilot(r)
			r.step(Race.DT, a < 0, a > 0)
			for e in r.events:
				if e[0] == "hit": hits += 1
				if e[0] == "boost": boosts += 1
			if r.delta_t > 1.99 and not r.delta_lap: deltas += 1
			r.events.clear(); fsum += r.F; steps += 1; max_combo = maxi(max_combo, r.combo)
		var laps := r.laps.map(func(x: float) -> String: return "%.2f" % x)
		print("%s laps=%s total=%.2f bot=%.2f hits=%d boosts=%d combo=%d splits=%d flow=%.2f ghost=%d" % [T.id, laps, r.total, r.bot.total, hits, boosts, max_combo, deltas, fsum / steps, rec.get("ghost", []).size()])
		check(r.phase == Race.FINISH and r.laps.size() == 3 and rec.has("lap") and rec.has("total3") and not rec.has("total"), T.id + " finish")
		check(r.laps.min() > 5 and r.laps.max() < 60, T.id + " lap times")
		# ghost covers the best lap at GHOST_HZ; splits: one per apex, compared on later laps
		var gh: Array = rec.ghost
		var g2 := Race.new(T, ti, rec, false, 3); g2.phase = Race.GO; g2.time = rec.lap * .5
		check(g2.ghost_at() is Vector3, T.id + " ghost playback")
		check(absf(gh.size() / 3.0 / Race.GHOST_HZ - rec.lap) < .1, T.id + " ghost length")
		check(rec.splits.size() == T.apex.size() and deltas >= T.apex.size(), T.id + " splits")
	# a head-on wall hit kills the boost and the combo
	var T0 := tracks[0]; var w := Race.new(T0, 0, {}, false, 1)
	w.phase = Race.GO; w.idx = 200; w.prog = 200
	w.pos = T0.p[200] + T0.nor[200] * (Track.HW - 10); w.prev = w.pos
	w.vel = T0.nor[200] * 400 + T0.tan[200] * 100; w.boost = 1.0; w.combo = 4
	w.step(Race.DT, false, false)
	check(w.boost == 0 and w.combo == 0 and w.events.any(func(e: Array) -> bool: return e[0] == "combo_lost"), "wall resets boost and combo")
	check(absf(w.mult() - 1) < 1e-6, "multiplier back to x1")
	# a close call on a straight earns a combo point and a little boost
	var si := 0
	for i in T0.n:
		if absf(T0.k[i]) < absf(T0.k[si]): si = i
	var c := Race.new(T0, 0, {}, false, 1); c.phase = Race.GO; c.idx = si; c.prog = si
	for i in 30:   # held 3 units inside the wall for a quarter second
		var j := c.idx
		c.pos = T0.p[j] - T0.nor[j] * (Track.HW - 9 - 3); c.vel = T0.tan[j] * 450; c.h = c.vel.angle()
		c.step(Race.DT, false, false)
	c.pos = T0.p[c.idx]; c.step(Race.DT, false, false)
	check(c.combo == 1 and c.boost > 0 and c.events.any(func(e: Array) -> bool: return e[0] == "near"), "close call")
	var t0 := Time.get_ticks_msec()
	var m := Music.build()
	print("music build ms: ", Time.get_ticks_msec() - t0)
	check(m.size() == 5 and m.all(func(s: AudioStreamWAV) -> bool: return s.data.size() == m[0].data.size()), "music layers")
	print("FAILED" if failed else "OK")
	quit(1 if failed else 0)
