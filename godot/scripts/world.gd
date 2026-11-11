class_name World
extends Node3D
## The 3D scene for a race: track, walls, karts, sparks, sky and the camera.
## Game space (x, y) maps to world (x, 0, y); one game unit is one world unit.

const HW := Track.HW
const WALL_H := 12.0
const CAM_H := 17.0
const GROUND := {"cyber": Color("06030f"), "sunset": Color("14041f")}

const SH_FLAT := preload("res://shaders/flat.gdshader")
const SH_ADD := preload("res://shaders/add.gdshader")
const SH_WALL := preload("res://shaders/wall.gdshader")
const SH_KART := preload("res://shaders/kart.gdshader")
const SH_GROUND := preload("res://shaders/ground.gdshader")
const SH_SKY := preload("res://shaders/sky.gdshader")
const SH_SPARK := preload("res://shaders/spark.gdshader")

var cam := Camera3D.new()
var env := Environment.new()
var sky_mat := ShaderMaterial.new()
var ground_mat := ShaderMaterial.new()
var line_mat: ShaderMaterial
var track_root: Node3D
var apex_nodes := {}            # sample index -> MeshInstance3D
var apex_mat: ShaderMaterial
var apex_hit_mat: ShaderMaterial
var kart: Node3D
var kart_mat: ShaderMaterial
var flame: MeshInstance3D
var bot_kart: Node3D
var ghost_kart: Node3D
var built := ""
var wall_mat: ShaderMaterial
var kerb_mat: ShaderMaterial
var sparks := MultiMesh.new()
var spark_buf := PackedFloat32Array()
var trail := ImmediateMesh.new()
var trail_mat: ShaderMaterial
var fov_kick := 0.0


func _ready() -> void:
	sky_mat.shader = SH_SKY
	var sky := Sky.new(); sky.sky_material = sky_mat
	# nothing reads the sky's reflection map, but its uniforms change every frame: keep that update tiny
	sky.radiance_size = Sky.RADIANCE_SIZE_32; sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.background_mode = Environment.BG_SKY; env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true; env.glow_intensity = .9; env.glow_strength = 1.0; env.glow_bloom = .0
	env.glow_hdr_threshold = 1.0; env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true; env.fog_sky_affect = 0.0; env.fog_density = .0011; env.fog_light_energy = 1.0
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	cam.near = 1.0; cam.far = 9000.0; add_child(cam)
	ground_mat.shader = SH_GROUND
	var gp := PlaneMesh.new(); gp.size = Vector2(40000, 40000)
	var ground := MeshInstance3D.new(); ground.mesh = gp; ground.material_override = ground_mat
	ground.position.y = -.6; ground.extra_cull_margin = 16000; add_child(ground)
	var quad := QuadMesh.new(); quad.size = Vector2.ONE
	sparks.transform_format = MultiMesh.TRANSFORM_3D; sparks.use_colors = true; sparks.mesh = quad
	sparks.instance_count = Race.MAX_PARTS + 8; sparks.visible_instance_count = 0
	spark_buf.resize(sparks.instance_count * 16)
	var smi := MultiMeshInstance3D.new(); smi.multimesh = sparks; smi.material_override = _mat(SH_SPARK)
	smi.custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5); add_child(smi)
	trail_mat = _mat(SH_ADD, Color.WHITE, 1.6)
	var tmi := MeshInstance3D.new(); tmi.mesh = trail; tmi.material_override = trail_mat
	tmi.custom_aabb = smi.custom_aabb; add_child(tmi)


static func _mat(sh: Shader, c := Color.WHITE, energy := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = sh
	if sh != SH_SPARK:
		m.set_shader_parameter("color", c); m.set_shader_parameter("energy", energy)
	return m


static func v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


## Triangle-list mesh builder.
class Builder:
	var v := PackedVector3Array(); var uv := PackedVector2Array(); var col := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, color := Color.WHITE) -> void:
		v.append_array([a, b, c]); uv.append_array([ua, ub, uc])
		var l := color.srgb_to_linear(); col.append_array([l, l, l])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color := Color.WHITE, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO) -> void:
		tri(a, b, c, ua, ub, uc, color); tri(a, c, d, ua, uc, ud, color)

	## Convex face as a fan from its centre; UV.x = distance to the face edge (for outline shaders).
	func face(pts: Array, color: Color) -> void:
		var c := Vector3.ZERO
		for q: Vector3 in pts: c += q
		c /= pts.size()
		for i in pts.size():
			var a: Vector3 = pts[i]; var b: Vector3 = pts[(i + 1) % pts.size()]
			var e := (b - a).normalized()
			var d := ((c - a) - e * (c - a).dot(e)).length()
			tri(c, a, b, Vector2(d, 0), Vector2.ZERO, Vector2.ZERO, color)

	func mesh() -> ArrayMesh:
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_TEX_UV] = uv; arr[Mesh.ARRAY_COLOR] = col
		var m := ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


func _add(parent: Node3D, b: Builder, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = b.mesh(); mi.material_override = mat
	parent.add_child(mi)
	return mi


## Build the scene for a new race.
func setup(r: Race) -> void:
	var key := r.T.id + ("+bot" if r.bot else "")
	if key == built: return   # same track again (restart): keep the meshes
	built = key
	if track_root: track_root.queue_free()
	track_root = Node3D.new(); add_child(track_root)
	var T := r.T; var n := T.n
	var edge := U.hsl(T.hue, 100, 62); var kh := fposmod(T.hue + 180, 360)
	var road := Builder.new(); var kerb := Builder.new(); var dash := Builder.new(); var start := Builder.new()
	var walls := Builder.new()
	for i in n:
		var j := (i + 1) % n
		for sd: float in [-1.0, 1.0]:
			var a := T.p[i] + T.nor[i] * HW * sd; var b := T.p[j] + T.nor[j] * HW * sd
			walls.quad(v3(a), v3(b), v3(b, WALL_H), v3(a, WALL_H), Color.WHITE, Vector2.ZERO, Vector2.ZERO, Vector2(0, 1), Vector2(0, 1))
			# glowing kerb just outside the wall: the track outline in the top view
			kerb.quad(v3(a, .05), v3(b, .05), v3(T.p[j] + T.nor[j] * (HW + 5) * sd, .05), v3(T.p[i] + T.nor[i] * (HW + 5) * sd, .05))
		road.quad(v3(T.p[i] - T.nor[i] * HW), v3(T.p[i] + T.nor[i] * HW), v3(T.p[j] + T.nor[j] * HW), v3(T.p[j] - T.nor[j] * HW))
	# racing line, dashed in world space
	for i in range(0, n - 2, 4):
		for s in 2:
			var a := T.line[i + s]; var b := T.line[i + s + 1]
			var w := (b - a).normalized().orthogonal() * 1.4
			dash.quad(v3(a - w, .15), v3(a + w, .15), v3(b + w, .15), v3(b - w, .15))
	# start line
	var sq := HW * 2 / 10
	for row in 2:
		for c in 10:
			var o := T.p[0] + T.tan[0] * (row - 1) * sq + T.nor[0] * (c * sq - HW)
			var f := T.tan[0] * sq; var l := T.nor[0] * sq
			start.quad(v3(o, .08), v3(o + f, .08), v3(o + f + l, .08), v3(o + l, .08), Color.WHITE if (row + c) % 2 else Color("1c1c1c"))
	_add(track_root, road, _mat(SH_FLAT, Color("07050d")))
	kerb_mat = _mat(SH_FLAT, edge, 1.6)
	_add(track_root, kerb, kerb_mat)
	_add(track_root, start, _mat(SH_FLAT))
	var wm := ShaderMaterial.new(); wm.shader = SH_WALL
	wm.set_shader_parameter("fill", U.hsl(T.hue, 90, 14)); wm.set_shader_parameter("neon", edge)
	_add(track_root, walls, wm); wall_mat = wm
	line_mat = _mat(SH_ADD, U.hsl(kh, 100, 72), 1.5)
	_add(track_root, dash, line_mat)
	# apex markers on the inside of each corner
	apex_nodes.clear()
	apex_mat = _mat(SH_FLAT, U.hsl(kh, 100, 65), 2.2); apex_hit_mat = _mat(SH_FLAT, Color.WHITE, 2.5)
	var orb := SphereMesh.new(); orb.radius = 4; orb.height = 8; orb.radial_segments = 12; orb.rings = 6
	for ap in T.apex:
		var mi := MeshInstance3D.new(); mi.mesh = orb; mi.material_override = apex_mat
		mi.position = v3(T.p[ap.x] + T.nor[ap.x] * ap.y * (HW - 12), .8)
		track_root.add_child(mi); apex_nodes[ap.x] = mi
	kart = _build_kart(kh); kart_mat = kart.get_child(0).material_override
	flame = MeshInstance3D.new()
	var fb := Builder.new(); fb.tri(Vector3(-14, 4, -4), Vector3(-60, 4, 0), Vector3(-14, 4, 4))
	flame.mesh = fb.mesh(); flame.material_override = _mat(SH_ADD, U.hsl(kh, 100, 70), 2.0); kart.add_child(flame)
	bot_kart = _build_kart(fposmod(T.hue + 90, 360)) if r.bot else null
	ghost_kart = _build_kart(0, true)
	env.fog_light_color = GROUND.get("cyber")


# Kart model: faces in kart space [forward, left-right, height].
# The ghost is the same model drawn as an additive hologram.
func _build_kart(hue: float, ghost := false) -> Node3D:
	var root := Node3D.new(); track_root.add_child(root)
	var b := Builder.new()
	var hull := Color("0b0614"); var top := U.hsl(hue, 50, 13); var wheel := Color("050308"); var rear := Color("1a0610")
	var gm: ShaderMaterial = _mat(SH_ADD, Color(.6, .9, 1, .45), 1.0) if ghost else null
	if ghost:
		hull = Color(.22, .22, .22); top = Color(.5, .5, .5); wheel = Color(.1, .1, .1); rear = hull
	var lo := [[-13, -7], [9, -7], [15, -3], [15, 3], [9, 7], [-13, 7]]
	var hi := []; var lo3 := []
	for q in lo:
		hi.append(Vector3(q[0], 6, q[1] * .75)); lo3.append(Vector3(q[0], 2, q[1]))
	b.face(hi, top)
	for i in 6:
		var j := (i + 1) % 6
		b.face([lo3[i], lo3[j], hi[j], hi[i]], rear if i == 5 else hull)
	for w: Array in [[8, -1, 7], [8, 1, 7], [-9, -1, 9], [-9, 1, 9]]:
		_box(b, w[0] - w[2] / 2.0, w[0] + w[2] / 2.0, 7.5 if w[1] > 0 else -11.5, 11.5 if w[1] > 0 else -7.5, 0, 6, wheel)
	_box(b, -7, 0, -3.5, 3.5, 6, 9, hull)       # seat
	_box(b, -16, -13, -8, 8, 9, 11, hull)       # rear wing
	var km := ShaderMaterial.new(); km.shader = SH_KART; km.set_shader_parameter("neon", U.hsl(hue, 100, 65))
	_add(root, b, gm if ghost else km)
	var helmet := SphereMesh.new(); helmet.radius = 3.4; helmet.height = 6.8; helmet.radial_segments = 12; helmet.rings = 6
	var hm := MeshInstance3D.new(); hm.mesh = helmet; hm.material_override = gm if ghost else _mat(SH_FLAT, Color.WHITE, 1.3)
	hm.position = Vector3(-3.5, 12.5, 0); root.add_child(hm)
	var tl := Builder.new()
	for sd: float in [-1.0, 1.0]: _box(tl, -13.4, -13.1, sd * 5 - 1.3, sd * 5 + 1.3, 3.2, 4.8, Color.WHITE)
	_add(root, tl, gm if ghost else _mat(SH_FLAT, Color("ff2a55"), 3.0))
	return root


func _box(b: Builder, f0: float, f1: float, l0: float, l1: float, h0: float, h1: float, c: Color) -> void:
	var p := func(f: float, l: float, hh: float) -> Vector3: return Vector3(f, hh, l)
	b.face([p.call(f0, l0, h1), p.call(f1, l0, h1), p.call(f1, l1, h1), p.call(f0, l1, h1)], c)
	b.face([p.call(f0, l0, h0), p.call(f1, l0, h0), p.call(f1, l0, h1), p.call(f0, l0, h1)], c)
	b.face([p.call(f0, l1, h0), p.call(f1, l1, h0), p.call(f1, l1, h1), p.call(f0, l1, h1)], c)
	b.face([p.call(f0, l0, h0), p.call(f0, l1, h0), p.call(f0, l1, h1), p.call(f0, l0, h1)], c)
	b.face([p.call(f1, l0, h0), p.call(f1, l1, h0), p.call(f1, l1, h1), p.call(f1, l0, h1)], c)


## Draw the race state. `al` blends the last two physics steps; `size` is the screen in logical pixels.
func sync(r: Race, al: float, dt: float, t: float, pulse: float, st: Dictionary, size: Vector2, calm: bool) -> void:
	if size.x < 1 or size.y < 1: return
	var T := r.T; var fps: bool = st.view == "fps"
	var sky: String = st.sky
	var kh := fposmod(T.hue + 180, 360)
	var p := r.prev.lerp(r.pos, al); var hd := lerp_angle(r.hp, r.h, al)
	var spd := r.vel.length()
	var kcol := U.hsl(Race.LVL_HUE[r.lvl] if r.drift and r.lvl > 0 else kh, 100, 65)
	var sh := Vector2.ZERO if calm or r.shake <= 0 else Vector2(randf() - .5, randf() - .5) * r.shake
	var spin := t * (.03 if calm else .12 * (1 + r.F * 2))
	var sa := U.hsl(T.hue, 70, 13 + pulse * 4); var sb := U.hsl(T.hue, 70, 8 + pulse * 4)
	if fps:
		var yaw := lerp_angle(r.fyaw_p, r.fyaw, al)
		var wide := size.x >= size.y * 1.4
		# same framing as a 90° lens on wide screens, horizon at 40% of the screen height
		fov_kick += ((5.0 if r.boost > 0 and not calm else 0.0) - fov_kick) * minf(1, dt * 4)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.keep_aspect = Camera3D.KEEP_WIDTH if wide else Camera3D.KEEP_HEIGHT
		cam.fov = (90.0 if wide else 71.0) + fov_kick
		var pitch := atan(.2 * size.y / size.x) if wide else atan(.1 / .7)
		var f := Vector3(cos(yaw), 0, sin(yaw))
		cam.position = v3(p, CAM_H)
		cam.look_at(cam.position + f * cos(pitch) + Vector3.DOWN * sin(pitch))
		cam.h_offset = sh.x * .8; cam.v_offset = sh.y * .8
		var plain := not GROUND.has(sky)
		var gc: Color = U.hsl(T.hue, 50, 5) if plain else GROUND[sky]
		env.fog_enabled = true; env.fog_light_color = gc
		sky_mat.set_shader_parameter("mode", 2 if plain else 1 if sky == "sunset" else 0)
		sky_mat.set_shader_parameter("sun_az", yaw + sin(yaw) * .4)   # the sun drifts with the turn so it stays in view
		sky_mat.set_shader_parameter("spin", spin)
		sky_mat.set_shader_parameter("line_col", U.hsl(kh, 100, 65))
		sky_mat.set_shader_parameter("ground", gc)
		sky_mat.set_shader_parameter("stripe_a", sa); sky_mat.set_shader_parameter("stripe_b", sb)
		ground_mat.set_shader_parameter("mode", 1 if plain else 0)
		ground_mat.set_shader_parameter("base", gc)
		ground_mat.set_shader_parameter("grid_col", Color(1, .24, .94) * .5 if sky == "sunset" else Color(.22, .84, 1) * .3)
	else:
		# top view: the road ahead points up the screen, the kart sits in the lower part
		var ca := lerp_angle(r.cam_ap, r.cam_a, al)
		var zoom := 1.0 / 500 * (1 - .38 * clampf(spd / 1000, 0, 1))
		var span := size.y / minf(size.x, size.y) / zoom       # world units across the screen height
		var fwd := Vector3(cos(ca), 0, sin(ca))
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.keep_aspect = Camera3D.KEEP_HEIGHT; cam.size = span
		cam.position = v3(p, 600) + fwd * span * ((.74 if size.x > size.y else .78) - .5)
		cam.look_at(cam.position + Vector3.DOWN, fwd)
		cam.h_offset = sh.x * 12; cam.v_offset = sh.y * 12
		env.fog_enabled = false
		ground_mat.set_shader_parameter("mode", 2); ground_mat.set_shader_parameter("centre", p)
		ground_mat.set_shader_parameter("ang", spin)
		ground_mat.set_shader_parameter("stripe_a", sa); ground_mat.set_shader_parameter("stripe_b", sb)
	# the neon pulses on the beat (harder with flow) and its hue climbs with the combo
	var neon := U.hsl(T.hue + mini(r.combo, 10) * 14, 100, 62)
	wall_mat.set_shader_parameter("neon", neon); wall_mat.set_shader_parameter("energy", 2.0 + 1.6 * pulse * (.3 + .7 * r.F))
	kerb_mat.set_shader_parameter("color", neon); kerb_mat.set_shader_parameter("energy", 1.4 + 1.2 * pulse * (.3 + .7 * r.F))
	line_mat.set_shader_parameter("color", U.hsl(kh, 100, 72, .3 + .6 * r.on_line))
	for i: int in apex_nodes:
		var hit: bool = r.apex_hit.has(i); var mi: MeshInstance3D = apex_nodes[i]
		mi.material_override = apex_hit_mat if hit else apex_mat
		var sc := 1.4 if hit else 1.0 + .15 * pulse
		mi.scale = Vector3(sc, .25 * sc, sc)   # flat disc: a full orb fills the first-person view up close
	kart.visible = not fps
	kart.position = v3(p); kart.rotation.y = -hd
	kart_mat.set_shader_parameter("neon", kcol)
	var bst := minf(1, r.boost * 1.5) if r.boost > 0 else 0.0
	flame.visible = bst > 0; flame.scale = Vector3(.6 + .4 * bst + randf() * .1, 1, 1)
	if bot_kart:
		bot_kart.position = v3(r.bot.prev.lerp(r.bot.pos, al)); bot_kart.rotation.y = -lerp_angle(r.bot.hp, r.bot.h, al)
	var gp: Variant = r.ghost_at()
	# in first person the ghost would fill the screen when it is right on top of the camera
	ghost_kart.visible = gp != null and not (fps and p.distance_to(Vector2(gp.x, gp.y)) < 30)
	if ghost_kart.visible:
		ghost_kart.position = Vector3(gp.x, 0, gp.y); ghost_kart.rotation.y = -gp.z
	# sparks
	var k := 0
	for q in r.parts:
		var a := q.life / q.mx; var s := q.s * (1.3 if fps else 1.0)
		spark_buf[k] = s; spark_buf[k + 1] = 0; spark_buf[k + 2] = 0; spark_buf[k + 3] = q.pos.x
		spark_buf[k + 4] = 0; spark_buf[k + 5] = s; spark_buf[k + 6] = 0; spark_buf[k + 7] = 3.0
		spark_buf[k + 8] = 0; spark_buf[k + 9] = 0; spark_buf[k + 10] = s; spark_buf[k + 11] = q.pos.y
		spark_buf[k + 12] = q.c.r; spark_buf[k + 13] = q.c.g; spark_buf[k + 14] = q.c.b; spark_buf[k + 15] = a
		k += 16
	sparks.buffer = spark_buf; sparks.visible_instance_count = r.parts.size()
	# light trail behind the kart (top view)
	trail.clear_surfaces()
	var tr := r.trail; var m := mini(tr.size(), 40 + int(r.F * 170))
	if not fps and m > 2:
		trail_mat.set_shader_parameter("color", U.hsl(kh, 100, 60))
		trail.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for s in m:
			var i := tr.size() - 1 - s
			var d := (tr[i] - tr[maxi(i - 1, 0)]).normalized().orthogonal() * 2.5
			trail.surface_set_color(Color(1, 1, 1, (1.0 - float(s) / m) * .6))
			trail.surface_add_vertex(v3(tr[i] - d, 1)); trail.surface_add_vertex(v3(tr[i] + d, 1))
		trail.surface_end()
