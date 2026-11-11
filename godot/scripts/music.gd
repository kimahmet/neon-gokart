class_name Music
extends RefCounted
## Synthwave loop synthesised at start-up (no audio files), split into layers that GameAudio fades in with flow:
## pad, kick, bass, drums, arpeggio. Every layer has the same length, so they stay in sync while looping.

const RATE := 22050
const STEP := .125                 # one 16th note at 120 BPM
const STEPS := 64                  # 4 bars
const CHORDS := [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]   # Am F C G
enum { PAD, KICK, BASS, DRUMS, ARP }


static func hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69) / 12.0)


static func build() -> Array[AudioStreamWAV]:
	var n := int(STEP * STEPS * RATE)
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	var L: Array[PackedFloat32Array] = []
	for i in 5:
		var b := PackedFloat32Array(); b.resize(n); L.append(b)
	for bar in 4:
		for m: int in CHORDS[bar]:
			_note(L[PAD], bar * 16 * STEP, hz(m), 16 * STEP + .3, .07, 1, .35, .35)
	for s in STEPS:
		var at := s * STEP; var c: Array = CHORDS[s / 16]
		if s % 4 == 0: _note(L[KICK], at, 130, .32, .9, 0, .002, .001, 42)
		var root: int = c[0] - 24
		if root < 33: root += 12
		_note(L[BASS], at, hz(root + (12 if s % 4 == 2 else 0)), .11, .3, 3, .004, .05)
		_noise(L[DRUMS], at, .03 if s % 2 else .07, .12 if s % 2 else .22, rng, true)
		if s % 8 == 4:
			_noise(L[DRUMS], at, .2, .5, rng, false); _note(L[DRUMS], at, 190, .12, .3, 0, .002, .01, 120)
		var arp := [c[0], c[1], c[2], c[0] + 12]
		_note(L[ARP], at, hz(arp[s % 4] + 12), .1, .08, 2, .003, .02)
	_lowpass(L[PAD], .08); _lowpass(L[BASS], .18); _lowpass(L[ARP], .35)
	_echo(L[ARP], int(3 * STEP * RATE), .35)
	var out: Array[AudioStreamWAV] = []
	for b in L: out.append(GameAudio._wav(b, RATE, true))
	return out


## One note, wrapped around the loop end. Gain falls to `sus` over `d`; f_end > 0 sweeps the pitch.
static func _note(b: PackedFloat32Array, at: float, f: float, d: float, v: float, wave: int, att: float, sus: float, f_end := 0.0) -> void:
	var n := b.size(); var i0 := int(at * RATE); var cnt := int(d * RATE)
	var decay := pow(sus, 1.0 / cnt)
	var sweep := pow(f_end / f, 1.0 / cnt) if f_end > 0 else 1.0
	var ph := 0.0; var g := 1.0; var fr := f / RATE
	var na := maxf(1, att * RATE); var nr := RATE * .01
	for i in cnt:
		ph = fmod(ph + fr, 1.0); fr *= sweep; g *= decay
		var y: float
		match wave:
			0: y = sin(ph * TAU)
			1: y = 4.0 * absf(ph - .5) - 1.0
			2: y = 1.0 if ph < .5 else -1.0
			_: y = 2.0 * ph - 1.0
		b[(i0 + i) % n] += y * v * g * minf(1.0, i / na) * minf(1.0, (cnt - i) / nr)


## Noise burst: high-passed for hats, low-passed for the snare.
static func _noise(b: PackedFloat32Array, at: float, d: float, v: float, rng: RandomNumberGenerator, high: bool) -> void:
	var n := b.size(); var i0 := int(at * RATE); var cnt := int(d * RATE)
	var decay := pow(.001, 1.0 / cnt); var g := 1.0; var lp := 0.0
	for i in cnt:
		var x := rng.randf() * 2 - 1
		lp += (.6 if high else .3) * (x - lp); g *= decay
		b[(i0 + i) % n] += (x - lp if high else lp) * v * g


## One-pole low-pass; the first pass only warms the filter up so the loop seam stays smooth.
static func _lowpass(b: PackedFloat32Array, a: float) -> void:
	var n := b.size(); var y := 0.0
	for i in n * 2:
		y += a * (b[i % n] - y)
		if i >= n: b[i - n] = y


static func _echo(b: PackedFloat32Array, delay: int, fb: float) -> void:
	var n := b.size(); var src := b.duplicate()
	for i in n:
		b[i] += src[(i - delay + n) % n] * fb + src[(i - 2 * delay + 2 * n) % n] * fb * fb
