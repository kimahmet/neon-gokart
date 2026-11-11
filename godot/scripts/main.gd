class_name Main
extends Node
## Game state, the fixed 120 Hz physics loop, saving, and the glue between race, 3D world, HUD and sound.

const SAVE := "user://save.json"

var state := "title"           # title | select | race
var overlay := ""              # "" | settings | leaderboard | pause | finish
var t := 0.0
var frame_dt := 0.0
var pulse := 0.0
var sel := 0
var slide := 0.0
var toast_text := ""
var toast_life := 0.0
var settings := {"sfx": true, "music": true, "bot": false, "view": "fps", "sky": "cyber", "laps": 3}
var records := {}
var tracks: Array[Track] = []
var race: Race
var acc := 0.0
var dirty := false            # records changed; written when the race stops, not on the lap line
var in_l := false
var in_r := false
var world := World.new()
var hud := Hud.new()
var audio := GameAudio.new()
var demo := {}                 # debug: --shot=file.png --track=0 --at=6 --screen=select --view=top --sky=sunset --bot


func _ready() -> void:
	tracks = Track.build_all()
	_load()
	var win := get_window()
	var dpr := clampf(DisplayServer.screen_get_scale(), 1, 3.5)
	win.content_scale_factor = dpr
	if OS.has_feature("mobile"): get_viewport().scaling_3d_scale = .75   # 3D at 75% resolution, HUD stays sharp
	add_child(world); add_child(audio)
	var layer := CanvasLayer.new(); add_child(layer)
	hud.g = self; layer.add_child(hud)
	audio.set_enabled(settings.sfx); audio.set_music(settings.music)
	if OS.has_feature("mobile"):
		# keep the HUD clear of notches and rounded corners
		var safe := DisplayServer.get_display_safe_area(); var full := DisplayServer.screen_get_size()
		hud.ins_l = safe.position.x / dpr; hud.ins_t = safe.position.y / dpr
		hud.ins_r = maxf(0, full.x - safe.end.x) / dpr; hud.ins_b = maxf(0, full.y - safe.end.y) / dpr
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("="); demo[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if demo.has("view"): settings.view = demo.view
	if demo.has("sky"): settings.sky = demo.sky
	if demo.has("bot"): settings.bot = true
	if demo.has("track"): start_race(int(demo.track))
	elif demo.has("screen"): state = demo.screen


func _load() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE)) if FileAccess.file_exists(SAVE) else null
	if d is Dictionary:
		settings.merge(d.get("settings", {}), true)
		records = d.get("records", {})
	if not Race.LAP_CHOICES.has(int(settings.laps)): settings.laps = 3
	settings.laps = int(settings.laps)


func save() -> void:
	dirty = false
	if not demo.is_empty(): return
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"settings": settings, "records": records}))


func toast(s: String) -> void:
	toast_text = s; toast_life = 2.2


func toggle(key: String) -> void:
	settings[key] = not settings[key]
	audio.set_enabled(settings.sfx); audio.set_music(settings.music); save()


func cycle_view() -> void:
	settings.view = "top" if settings.view == "fps" else "fps"; save()


func cycle_sky() -> void:
	settings.sky = Hud.SKIES[(Hud.SKIES.find(settings.sky) + 1) % Hud.SKIES.size()]; save()


func cycle_laps() -> void:
	var c := Race.LAP_CHOICES
	settings.laps = c[(c.find(settings.laps) + 1) % c.size()]; save()


## Instant retry: same track, no countdown.
func restart() -> void:
	if race: start_race(race.ti, true)


func change_sel(d: int) -> void:
	var slots := tracks.size() + 1   # last slot: future track
	sel = (sel + d + slots) % slots; slide = d; audio.play("click")


func try_start() -> void:
	if sel < tracks.size(): start_race(sel)
	else: toast("A NEW TRACK WILL BE ADDED HERE")


func start_race(ti: int, quick := false) -> void:
	var T := tracks[ti]
	if not records.has(T.id): records[T.id] = {}
	race = Race.new(T, ti, records[T.id], settings.bot, settings.laps)
	if quick: race.count = 0.0
	world.setup(race)
	state = "race"; overlay = ""; acc = 0; hud.release_all()


## Back button / Escape: steps back one screen, quits from the title screen.
func back() -> void:
	if overlay != "" and overlay != "finish": overlay = ""
	elif state == "race":
		if overlay == "": overlay = "pause"
		else: state = "select"; overlay = ""
	elif state == "select": state = "title"
	else: get_tree().quit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST: back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			hud.release_all()
			if dirty: save()
			if state == "race" and race and race.phase != Race.FINISH and overlay == "" and demo.is_empty(): overlay = "pause"


func _process(dt: float) -> void:
	dt = minf(dt, .1); frame_dt = dt; t += dt
	pulse = pow(1 - audio.beat(t), 4)
	slide *= exp(-dt * 10); toast_life -= dt
	var racing := state == "race" and race != null
	if racing and (overlay == "" or overlay == "finish"):
		acc += dt
		while acc >= Race.DT:
			in_l = hud.touch_l >= 0 or Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)
			in_r = hud.touch_r >= 0 or Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)
			if demo.has("auto"):
				var a := _autopilot(); in_l = a < 0; in_r = a > 0
			race.step(Race.DT, in_l, in_r); acc -= Race.DT
		for e in race.events:
			if e[0] == "save": dirty = true
			elif e[0] == "perfect": world.fov_kick = 9.0; hud.white = .3
			else: audio.handle(e)
		race.events.clear()
		if race.phase == Race.FINISH and race.fin > 1.2 and overlay == "": overlay = "finish"
	else:
		acc = 0
	if dirty and (overlay != "" or not racing): save()
	audio.engine(dt, race if racing and overlay != "pause" else null)
	audio.music_tick(dt, 0 if not racing else 2 if overlay == "pause" else 1, race)
	world.visible = racing
	if racing: world.sync(race, acc / Race.DT, dt, t, pulse, settings, hud.get_viewport_rect().size, false)
	hud.queue_redraw()
	if demo.has("shot") and t >= float(demo.get("at", "1")):
		if demo.has("overlay") and overlay == "": overlay = demo.overlay; return
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(demo.shot)
		print("fps ", Engine.get_frames_per_second(), " size ", hud.get_viewport_rect().size, " scale ", get_window().content_scale_factor)
		get_tree().quit()


func _autopilot() -> int:
	var sp := race.vel.length()
	var des := (race.T.line[(race.idx + 8 + int(sp / 50)) % race.T.n] - race.pos).angle()
	var d := angle_difference(race.vel.angle() if sp > 40 else race.h, des)
	return 1 if d > .04 else -1 if d < -.04 else 0
