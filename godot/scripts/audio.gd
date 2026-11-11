class_name GameAudio
extends Node
## All sound is synthesised at start-up: no audio files.
## Engine = endless-rising Shepard-Risset glissando (the "always climbing" tension) filtered like an EV whine.

const RATE := 22050
const BASE := 252.0   # loop pitch: 44100/252 = 175 samples per cycle exactly

var oscs: Array[AudioStreamPlayer] = []
var whine: AudioStreamPlayer
var hiss: AudioStreamPlayer
var pool: Array[AudioStreamPlayer] = []
var sfx := {}
var phase := 0.0
var lowpass := AudioEffectLowPassFilter.new()
var bandpass := AudioEffectBandPassFilter.new()
var eng_bus: int
var e_gain := 0.0; var e_cut := 600.0; var w_gain := 0.0; var n_gain := 0.0
var noise := PackedFloat32Array()
const LAYER_VOL := [.35, .9, .55, .5, .4]   # pad, kick, bass, drums, arpeggio
var music: Array[AudioStreamPlayer] = []
var m_gain := [0.0, 0.0, 0.0, 0.0, 0.0]
var m_lp := AudioEffectLowPassFilter.new()
var m_cut := 20000.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var comp := AudioEffectCompressor.new(); comp.threshold = -16; comp.ratio = 5; comp.attack_us = 4000; comp.release_ms = 200
	AudioServer.add_bus_effect(0, comp); AudioServer.set_bus_volume_db(0, linear_to_db(.85))
	_bus("FX", "Master")
	var rev := AudioEffectReverb.new(); rev.room_size = .8; rev.wet = .09; rev.dry = 1.0; rev.damping = .4
	AudioServer.add_bus_effect(AudioServer.get_bus_index("FX"), rev)
	eng_bus = _bus("Engine", "FX"); lowpass.cutoff_hz = 600; lowpass.resonance = .7
	AudioServer.add_bus_effect(eng_bus, lowpass)
	var nb := _bus("Hiss", "FX"); bandpass.cutoff_hz = 1800; bandpass.resonance = .8
	AudioServer.add_bus_effect(nb, bandpass)
	seed(7)
	noise.resize(RATE)
	for i in RATE: noise[i] = randf() * 2 - 1
	randomize()
	var tri := PackedFloat32Array(); var sine := PackedFloat32Array()
	for i in 175 * 4:
		var ph := fposmod(i / 175.0, 1.0)
		tri.append(4 * absf(ph - .5) - 1); sine.append(sin(ph * TAU))
	var tri_w := _wav(tri, 44100, true); var sine_w := _wav(sine, 44100, true)
	for k in 6: oscs.append(_loop(tri_w, "Engine"))
	whine = _loop(sine_w, "FX"); hiss = _loop(_wav(noise, RATE, true), "Hiss")
	for i in 8:
		var pl := AudioStreamPlayer.new(); pl.bus = "FX"; add_child(pl); pool.append(pl)
	_make_sfx()
	var mb := _bus("Music", "Master"); m_lp.cutoff_hz = 20000; AudioServer.add_bus_effect(mb, m_lp)
	AudioServer.set_bus_volume_db(mb, -5)
	WorkerThreadPool.add_task(_gen_music)   # takes a moment on phones; the music fades in when ready


func _gen_music() -> void:
	_music_ready.call_deferred(Music.build())


func _music_ready(streams: Array) -> void:
	for s: AudioStreamWAV in streams:
		var pl := AudioStreamPlayer.new(); pl.stream = s; pl.bus = "Music"; pl.volume_db = -80
		add_child(pl); music.append(pl)
	for pl in music: pl.play()   # same frame, same length: the layers stay locked together


## 0..1 position inside the current beat, locked to the music when it plays.
func beat(t: float) -> float:
	if music.is_empty() or not music[1].playing or AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")):
		return fmod(t * 2, 1.0)
	return fmod(music[1].get_playback_position() + AudioServer.get_time_since_last_mix(), .5) / .5


func set_music(on: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not on)


## Layer the music by how well the run is going. mode: 0 menus, 1 racing, 2 paused.
func music_tick(dt: float, mode: int, r: Race) -> void:
	if music.is_empty(): return
	var want := [.8, 0.0, .6, 0.0, 0.0] if mode == 0 else [.5, 0.0, 0.0, 0.0, 0.0] if mode == 2 else [1.0, 0.0, 0.0, 0.0, 0.0]
	if mode == 1 and r and r.phase != Race.COUNT:
		var f := r.F; var c := r.combo
		want = [1.0, 1.0, 1.0 if f > .1 or c >= 2 else 0.0, 1.0 if f > .3 or c >= 3 else 0.0, 1.0 if f > .55 or c >= 5 or r.boost > 0 else 0.0]
	for i in music.size():
		var w: float = want[i]
		m_gain[i] += (w - m_gain[i]) * minf(1, dt * (6.0 if w > m_gain[i] else 2.0))
		music[i].volume_db = linear_to_db(m_gain[i] * LAYER_VOL[i] + 1e-5)
	m_cut = minf(20000, m_cut * exp(dt * 4))   # a crash muffles the music, it opens back up over a second
	m_lp.cutoff_hz = 900.0 if mode == 2 else m_cut


func _bus(bus_name: String, send: String) -> int:
	var i := AudioServer.bus_count
	AudioServer.add_bus(i); AudioServer.set_bus_name(i, bus_name); AudioServer.set_bus_send(i, send)
	return i


func _loop(w: AudioStreamWAV, bus: String) -> AudioStreamPlayer:
	var pl := AudioStreamPlayer.new(); pl.stream = w; pl.bus = bus; pl.volume_db = -80
	add_child(pl); pl.play()
	return pl


static func _wav(s: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray(); data.resize(s.size() * 2)
	for i in s.size(): data.encode_s16(i * 2, int(clampf(s[i], -1, 1) * 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = rate; w.data = data
	if loop: w.loop_mode = AudioStreamWAV.LOOP_FORWARD; w.loop_end = s.size()
	return w


# percussive envelope: 4 ms attack, exponential decay over `d`
static func _env(t: float, peak: float, att: float, d: float) -> float:
	if t < 0: return 0.0
	if t < att: return peak * t / att
	return peak * pow(.0001 / peak, (t - att) / d) if t < att + d else 0.0


func _tone(buf: PackedFloat32Array, type: String, f: float, at: float, v: float, d: float, f2 := 0.0) -> void:
	var ph := 0.0; var i0 := int(at * RATE)
	for i in int((d + .01) * RATE):
		if i0 + i >= buf.size(): break
		var t := float(i) / RATE
		ph += (f * pow(f2 / f, minf(1, t / d)) if f2 > 0 else f) / RATE
		var x := fposmod(ph, 1.0); var y: float
		match type:
			"sine": y = sin(x * TAU)
			"square": y = 1.0 if x < .5 else -1.0
			"triangle": y = 4 * absf(x - .5) - 1
			_: y = 2 * x - 1
		buf[i0 + i] += y * _env(t, v, .004, d)


# filtered noise burst with a sweeping state-variable filter
func _noise_hit(buf: PackedFloat32Array, band: bool, f: float, f2: float, v: float, d: float, q := 1.0) -> void:
	var lo := 0.0; var bp := 0.0
	for i in int((d + .01) * RATE):
		if i >= buf.size(): break
		var t := float(i) / RATE
		var fc := 2 * sin(PI * minf(f * pow(f2 / f, minf(1, t / d)), RATE * .22) / RATE)
		var hi := noise[(i * 3 + 101) % RATE] - lo - bp / q
		bp += fc * hi; lo += fc * bp
		buf[i] += (bp if band else lo) * _env(t, v, .003, d)


func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array(); b.resize(int(sec * RATE))
	return b


func _make_sfx() -> void:
	var b := _buf(.08); _tone(b, "sine", 1250, 0, .12, .05); sfx.click = _wav(b, RATE, false)
	b = _buf(.35); _noise_hit(b, true, 2400, 500, .4, .28, 1.5); sfx.near = _wav(b, RATE, false)
	b = _buf(.4); _tone(b, "square", 600, 0, .1, .3, 150); sfx.drop = _wav(b, RATE, false)
	b = _buf(.25); _tone(b, "square", 440, 0, .12, .18); sfx.beep440 = _wav(b, RATE, false)
	b = _buf(.5); _tone(b, "square", 880, 0, .12, .4); sfx.beep880 = _wav(b, RATE, false)
	b = _buf(.45); _noise_hit(b, false, 900, 200, .55, .35); _tone(b, "sine", 95, 0, .55, .3, 35); sfx.hit = _wav(b, RATE, false)
	b = _buf(.75); _tone(b, "sine", 1568, 0, .12, .6); _tone(b, "sine", 2093, .06, .09, .6); sfx.apex = _wav(b, RATE, false)
	b = _buf(.55)
	for i in 4: _tone(b, "triangle", 440 * pow(2, (74 + [0, 4, 7, 12][i] - 69) / 12.0), i * .07, .14, .25)
	sfx.lap = _wav(b, RATE, false)
	for L: int in [1, 2, 3]:
		b = _buf(.65); _noise_hit(b, true, 300, 4200, .22 + .06 * L, .55, 2); _tone(b, "sawtooth", 110 * L, 0, .06, .5, 440 * L)
		sfx["boost%d" % L] = _wav(b, RATE, false)
		b = _buf(.2); _tone(b, "square", [0, 660, 880, 1175][L], 0, .07, .12); sfx["charge%d" % L] = _wav(b, RATE, false)


func play(sfx_name: String, vol := 1.0, pitch := 1.0) -> void:
	for pl in pool:
		if not pl.playing:
			pl.stream = sfx[sfx_name]; pl.volume_db = linear_to_db(vol); pl.pitch_scale = pitch; pl.play()
			return


func set_enabled(on: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("FX"), not on)


## Play the sounds a race step asked for.
func handle(e: Array) -> void:
	match e[0]:
		"beep": play("beep%d" % e[1])
		"hit": m_cut = 350.0; play("hit", (.15 + .4 * minf(1, e[1] / 250.0)) / .55)
		"boost": play("boost%d" % e[1])
		"charge": play("charge%d" % e[1])
		"apex": play("apex", 1, pow(2, mini(e[1] - 1, 12) / 12.0))   # each apex in a combo rings a semitone higher
		"combo_lost": play("drop", .8)
		"near": play("near", 1, pow(2, mini(e[1] - 1, 12) / 12.0))
		"lap": play("lap")


## Drive the engine sound; pass null while no race is running or the game is paused.
func engine(dt: float, r: Race) -> void:
	var on := 0.0; var sn := 0.0; var thr := 0.0; var dr := 0.0; var lvl := 0
	if r:
		on = 1; thr = r.thr; sn = r.vel.length() / Race.V0; dr = 1.0 if r.drift else 0.0; lvl = r.lvl
		if r.phase == Race.COUNT: sn = r.thr * .45
		if r.phase == Race.FINISH: thr = .2
	phase = fposmod(phase + dt * (.03 + .24 * minf(2, sn) * (.4 + .6 * thr)), 6.0)
	for k in 6:
		var pos := fposmod(k + phase, 6.0)
		oscs[k].pitch_scale = 32 * pow(2, pos) / BASE
		oscs[k].volume_db = linear_to_db(exp(-pow(pos - 3, 2) / 1.8) * .16 + 1e-5)
	e_gain += (on * (.08 + .22 * thr + .14 * minf(1.5, sn)) - e_gain) * minf(1, dt / .06)
	e_cut += (350 + 2400 * minf(1.6, sn) * (.5 + .5 * thr) + 700 * dr - e_cut) * minf(1, dt / .05)
	w_gain += (on * .022 * minf(1.5, sn) - w_gain) * minf(1, dt / .08)
	n_gain += (on * dr * .05 * minf(1, sn) - n_gain) * minf(1, dt / .04)
	AudioServer.set_bus_volume_db(eng_bus, linear_to_db(e_gain + 1e-5))
	lowpass.cutoff_hz = e_cut
	whine.pitch_scale = (220 + 520 * minf(2, sn)) / BASE; whine.volume_db = linear_to_db(w_gain + 1e-5)
	hiss.volume_db = linear_to_db(n_gain * 3 + 1e-5); bandpass.cutoff_hz = 1500 + 500 * lvl
