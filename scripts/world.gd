class_name World
extends RefCounted
## v1.4 island: ~3.7x the v1.3 area. A precomputed height grid (noise + mountains, flattened under points of
## interest and roads) drives the chunked terrain mesh, collisions, prop placement and the map texture.
## Every random choice uses `rng` seeded from the match seed, so all online peers build the same island.
const ISLAND := 230.0
const SIZE := ISLAND * 2.4
const RES := 160
const CHUNKS := 8
const STEP := SIZE / RES
## name, kind, centre (x, z), radius, ground level
const POIS := [
	["Storm City", "city", Vector2(0, 0), 62.0, 3.0],
	["Pine Grove", "town", Vector2(-60, -140), 36.0, 2.0],
	["Sunny Shores", "town", Vector2(118, 112), 34.0, 1.8],
	["Haystack Farm", "farm", Vector2(-70, 128), 46.0, 1.6],
	["Rust Works", "factory", Vector2(140, -72), 42.0, 2.0],
	["Port Gale", "docks", Vector2(186, 22), 30.0, 0.8],
]
const MOUNTAIN := Vector2(-150, -10)
const ROADS := [[0, 1], [0, 2], [0, 3], [0, 4], [4, 5], [5, 2], [1, 4], [3, 2]]
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var h := PackedFloat32Array()
var road_paths: Array = []      # Array of PackedVector2Array
var house_spots: Array = []
var trees: Array = []
var big_spots: Array = []       # [pos, radius] of large structures (no trees there)
var root: Node3D
var low := false
var map_image: Image

func _init(seed_v: int) -> void:
	rng.seed = seed_v; noise.seed = seed_v; noise.frequency = 0.008
	ridge.seed = seed_v + 7; ridge.frequency = 0.02; ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED; ridge.fractal_octaves = 3

# ---------------------------------------------------------------- heights
func _raw(x: float, z: float) -> float:
	var d := Vector2(x, z).length() / ISLAND
	var inland := 1.0 - clampf(d, 0, 1)
	var hills := (noise.get_noise_2d(x, z) * 0.5 + 0.5) * 9.0 * inland
	hills += maxf(0.0, noise.get_noise_2d(x * 0.4 + 500, z * 0.4)) * 14.0 * inland # rolling highlands
	var md := Vector2(x, z).distance_to(MOUNTAIN) / 85.0
	var mount := maxf(0.0, 1.0 - md) ; mount = mount * mount * (3.0 - 2.0 * mount)
	hills += mount * (30.0 + ridge.get_noise_2d(x, z) * 16.0)
	return maxf(-7.0, 0.4 + hills - smoothstep(0.82, 1.0, d) * 1.5 - maxf(0.0, d - 0.95) * 30.0)

func build_heights() -> void:
	h.resize((RES + 1) * (RES + 1))
	for j in RES + 1:
		for i in RES + 1:
			var x := -SIZE / 2 + i * STEP; var z := -SIZE / 2 + j * STEP
			var v := _raw(x, z)
			for p in POIS: # flatten under points of interest
				var dd: float = Vector2(x, z).distance_to(p[2]) / p[3]
				if dd < 1.5: v = lerpf(p[4], v, smoothstep(1.0, 1.5, dd))
			h[j * (RES + 1) + i] = v
	_build_roads()

func _build_roads() -> void:
	for r in ROADS:
		var a: Vector2 = POIS[r[0]][2]; var b: Vector2 = POIS[r[1]][2]
		var mid := (a + b) / 2 + (b - a).orthogonal().normalized() * rng.randf_range(-25, 25)
		var pts := PackedVector2Array()
		for k in 25:
			var t := k / 24.0
			pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
		# skip segments inside the mountain
		road_paths.append(pts)
	# city street grid
	var c: Vector2 = POIS[0][2]
	for k in [-1, 0, 1]:
		road_paths.append(PackedVector2Array([c + Vector2(-58, k * 30), c + Vector2(58, k * 30)]))
		road_paths.append(PackedVector2Array([c + Vector2(k * 30, -58), c + Vector2(k * 30, 58)]))
	# flatten a 10 m wide bed along every road (rasterised on the grid, so it is cheap)
	for pts in road_paths:
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]; var b: Vector2 = pts[k + 1]
			var ha := height(a.x, a.y); var hb := height(b.x, b.y)
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(9, 9); var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(9, 9)
			for j in range(maxi(0, int((lo.y + SIZE / 2) / STEP)), mini(RES, int((hi.y + SIZE / 2) / STEP) + 1) + 1):
				for i in range(maxi(0, int((lo.x + SIZE / 2) / STEP)), mini(RES, int((hi.x + SIZE / 2) / STEP) + 1) + 1):
					var p := Vector2(-SIZE / 2 + i * STEP, -SIZE / 2 + j * STEP)
					var ab := b - a; var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0, 1)
					var dist := p.distance_to(a + ab * t)
					if dist < 9.0:
						var target := lerpf(ha, hb, t)
						if target < 0.5: continue # don't build causeways
						var idx := j * (RES + 1) + i
						h[idx] = lerpf(target, h[idx], smoothstep(4.5, 9.0, dist))

## Exact height of the rendered terrain triangles at (x, z).
func height(x: float, z: float) -> float:
	var fx := (x + SIZE / 2) / STEP; var fz := (z + SIZE / 2) / STEP
	if fx < 0 or fz < 0 or fx >= RES or fz >= RES: return -30.0
	var i := int(fx); var j := int(fz); var u := fx - i; var v := fz - j
	var w := RES + 1
	var h0 := h[j * w + i]; var h1 := h[j * w + i + 1]; var h2 := h[(j + 1) * w + i]; var h3 := h[(j + 1) * w + i + 1]
	if u + v <= 1.0: return h0 + u * (h1 - h0) + v * (h2 - h0)
	return h3 + (1.0 - u) * (h2 - h3) + (1.0 - v) * (h1 - h3)

func ground(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)

func rand_point(r := ISLAND * 0.85) -> Vector3:
	var a := rng.randf() * TAU; var d := sqrt(rng.randf()) * r
	return ground(cos(a) * d, sin(a) * d)

func poi_at(p: Vector3) -> String:
	for q in POIS:
		if Vector2(p.x, p.z).distance_to(q[2]) < q[3] * 1.1: return q[0]
	return ""

func _clear_spot(p: Vector3, pad := 0.0) -> bool:
	for b in big_spots:
		if Vector2(p.x, p.z).distance_to(Vector2(b[0].x, b[0].z)) < b[1] + pad: return false
	for pts in road_paths:
		for k in range(0, pts.size() - 1):
			var a: Vector2 = pts[k]; var bb: Vector2 = pts[k + 1]; var ab := bb - a
			var t := clampf((Vector2(p.x, p.z) - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0, 1)
			if Vector2(p.x, p.z).distance_to(a + ab * t) < 6.0 + pad: return false
	return true

# ---------------------------------------------------------------- terrain mesh (8x8 chunks)
func build_terrain(parent: Node3D) -> void:
	var mat := ShaderMaterial.new(); mat.shader = preload("res://shaders/terrain.gdshader")
	for k in ["grass", "sand", "rock"]: mat.set_shader_parameter(k + "_tex", load("res://assets/textures/%s_diff.jpg" % k))
	mat.set_shader_parameter("grass_nrm", load("res://assets/textures/grass_nor_gl.jpg"))
	mat.set_shader_parameter("rock_nrm", load("res://assets/textures/rock_nor_gl.jpg"))
	var per := RES / CHUNKS
	for cj in CHUNKS:
		for ci in CHUNKS:
			var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var any_land := false
			for j in range(cj * per, (cj + 1) * per):
				for i in range(ci * per, (ci + 1) * per):
					var x0 := -SIZE / 2 + i * STEP; var z0 := -SIZE / 2 + j * STEP; var w := RES + 1
					var p := [Vector3(x0, h[j * w + i], z0), Vector3(x0 + STEP, h[j * w + i + 1], z0),
						Vector3(x0, h[(j + 1) * w + i], z0 + STEP), Vector3(x0 + STEP, h[(j + 1) * w + i + 1], z0 + STEP)]
					if p[0].y > -6.5 or p[3].y > -6.5: any_land = true
					for v in [p[0], p[1], p[2], p[1], p[3], p[2]]: st.add_vertex(v)
			if not any_land: continue
			st.generate_normals()
			var m := st.commit()
			var mi := MeshInstance3D.new(); mi.mesh = m; mi.material_override = mat
			var body := StaticBody3D.new(); body.name = "Terrain%d_%d" % [ci, cj]; body.add_child(mi)
			var cs := CollisionShape3D.new(); cs.shape = m.create_trimesh_shape(); body.add_child(cs)
			body.add_to_group("nav"); body.set_meta("terrain", true); parent.add_child(body)

# ---------------------------------------------------------------- roads
func build_roads(parent: Node3D) -> void:
	var mat := ShaderMaterial.new(); mat.shader = preload("res://shaders/road.gdshader")
	for pts in road_paths:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var dist := 0.0
		# densify so the ribbon hugs the terrain
		var dense := PackedVector2Array()
		for k in pts.size() - 1:
			var n := maxi(1, int(pts[k].distance_to(pts[k + 1]) / 3.0))
			for s in n: dense.append(pts[k].lerp(pts[k + 1], float(s) / n))
		dense.append(pts[pts.size() - 1])
		for k in dense.size() - 1:
			var a := dense[k]; var b := dense[k + 1]
			var side := (b - a).orthogonal().normalized() * 3.5
			var l := a.distance_to(b)
			var q := [a - side, a + side, b - side, b + side]
			var vs := []
			for v2 in q: vs.append(Vector3(v2.x, height(v2.x, v2.y) + 0.12, v2.y))
			if vs[0].y < 0.3 and vs[3].y < 0.3: dist += l; continue
			var uv := [Vector2(0, dist), Vector2(1, dist), Vector2(0, dist + l), Vector2(1, dist + l)]
			for t in [0, 2, 1, 1, 2, 3]:
				st.set_uv(uv[t] * Vector2(1, 0.1)); st.set_normal(Vector3.UP); st.add_vertex(vs[t])
			dist += l
		var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 260.0; parent.add_child(mi)

# ---------------------------------------------------------------- helpers
static func vis(n: Node, end_m: float, begin_m := 0.0, shadow_end := -1.0) -> void:
	for gi in n.find_children("*", "GeometryInstance3D", true, false):
		gi.visibility_range_end = end_m; gi.visibility_range_begin = begin_m
		gi.visibility_range_end_margin = 10.0; gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if shadow_end >= 0 and shadow_end < 1.0: gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Static model with a box collider (cheap for phones) plus an optional occluder.
func box_model(path: String, scale_f: float, pos: Vector3, rot := 0.0, occlude := false) -> StaticBody3D:
	var sb := StaticBody3D.new(); sb.position = pos; sb.rotation.y = rot
	var m: Node3D = load(path).instantiate(); m.scale = Vector3.ONE * scale_f; sb.add_child(m)
	var ab := Gear._bounds(m); ab = AABB(ab.position * scale_f, ab.size * scale_f)
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = ab.size; cs.shape = bs; cs.position = ab.get_center()
	sb.add_child(cs)
	if occlude and not OS.has_feature("web"):
		var oc := OccluderInstance3D.new(); var bo := BoxOccluder3D.new(); bo.size = ab.size * 0.9; oc.occluder = bo
		oc.position = ab.get_center(); sb.add_child(oc)
	return sb

func _place(parent: Node3D, n: Node3D, harvest := 10, nav := true) -> Node3D:
	n.set_meta("harvest", harvest)
	if nav: n.add_to_group("nav")
	parent.add_child(n); return n

# ---------------------------------------------------------------- points of interest
const CITY := "res://assets/city14/%s.glb"
const IND := "res://assets/industry14/%s.glb"
var HOUSES: Array = Array("acdefghkl".split("")).map(func(x): return "res://assets/buildings/building-type-%s.glb" % x)

func build_pois(parent: Node3D) -> void:
	for p in POIS:
		var c: Vector2 = p[2]; var r: float = p[3]
		match p[1]:
			"city": _city(parent, c, r)
			"town": _town(parent, c, r)
			"farm": _farm(parent, c, r)
			"factory": _factory(parent, c, r)
			"docks": _docks(parent, c, r)
		# floating name sign visible from the air (and from the bus)
		var l := Label3D.new(); l.text = p[0].to_upper(); l.font_size = 160; l.outline_size = 36; l.pixel_size = 0.05
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.modulate = Color(1, 0.88, 0.35); l.outline_modulate = Color(0.2, 0.05, 0.35)
		l.position = Vector3(c.x, p[4] + 55, c.y); l.visibility_range_begin = 90.0; l.no_depth_test = false; parent.add_child(l)

func _city(parent: Node3D, c: Vector2, r: float) -> void:
	# blocks between the street grid (streets at -30, 0, 30); each block gets a skyscraper or 2-4 shops
	for bx in [-45, -15, 15, 45]:
		for bz in [-45, -15, 15, 45]:
			var bc := c + Vector2(bx, bz)
			var g := ground(bc.x, bc.y)
			big_spots.append([g, 14.0])
			if abs(bx) <= 15 and abs(bz) <= 15 or rng.randf() < 0.35:
				var k := "abcde"[rng.randi() % 5]
				var hi := box_model(CITY % ("building-skyscraper-" + k), 8.5, g, rng.randi() % 4 * PI / 2, true)
				vis(hi, 700.0)
				Util.stylize(hi, 0.0, 0.15); _place(parent, hi, 12)
				house_spots.append(g)
			else:
				for q in 2:
					var off := Vector2(-5.5 if q == 0 else 5.5, rng.randf_range(-3, 3))
					var k := "abcdefgh"[rng.randi() % 8]
					var pos := ground(bc.x + off.x, bc.y + off.y)
					var b := box_model(CITY % ("building-" + k), 7.0, pos, (PI / 2 if q == 0 else -PI / 2), true)
					vis(b, 150.0)
					var lo: Node3D = load(CITY % ("low-detail-building-" + k)).instantiate(); lo.scale = Vector3.ONE * 7.0
					b.add_child(lo); vis(lo, 650.0, 150.0) # LOD: low-detail mesh beyond 150 m
					Util.stylize(b.get_child(0), 0.0, 0.15); _place(parent, b, 12)
					house_spots.append(pos)
	for k in 8: # parked cars along the streets
		var s := c + Vector2(rng.randf_range(-50, 50), [-30, 0, 30][k % 3] + 4.5)
		var truck := k % 2 == 0
		var v := Util.static_model("res://assets/props13/pickup_truck.glb" if truck else "res://assets/props13/stationwagon.glb",
			1.0 if truck else 4.6, ground(s.x, s.y) + Vector3(0, 0.05, 0))
		v.rotation.y = PI / 2; vis(v, 140.0); _place(parent, v, 25)

func _town(parent: Node3D, c: Vector2, r: float) -> void:
	for i in 9:
		var a := i / 9.0 * TAU + rng.randf_range(-0.15, 0.15); var d := r * rng.randf_range(0.45, 0.9)
		var pos := ground(c.x + cos(a) * d, c.y + sin(a) * d) - Vector3(0, 0.2, 0)
		var hs := Util.static_model(HOUSES[rng.randi() % HOUSES.size()], 8.0, pos)
		hs.rotation.y = atan2(cos(a), sin(a)) + PI # face the town centre
		vis(hs, 380.0); Util.stylize(hs, 0.004 if not low else 0.0, 0.15); _place(parent, hs, 10)
		house_spots.append(pos); big_spots.append([pos, 8.0])
	var wt := box_model(IND % "water-tower", 7.0, ground(c.x, c.y), 0, false); vis(wt, 400.0); _place(parent, wt, 15)
	big_spots.append([ground(c.x, c.y), 5.0])

func _farm(parent: Node3D, c: Vector2, r: float) -> void:
	var g := ground(c.x, c.y)
	var barn := box_model(IND % "building-c", 9.0, g + Vector3(-8, 0, -6), 0.3, true); vis(barn, 420.0); Util.stylize(barn, 0.0, 0.15); _place(parent, barn, 10)
	var mill := box_model(IND % "windmill", 10.0, g + Vector3(18, 0, -14), 0.0, false); vis(mill, 500.0); _place(parent, mill, 10)
	var tw := box_model(IND % "water-tower", 6.0, g + Vector3(-22, 0, 12), 0, false); vis(tw, 400.0); _place(parent, tw, 15)
	var hs := Util.static_model(HOUSES[0], 8.0, g + Vector3(14, -0.2, 16)); vis(hs, 380.0); _place(parent, hs, 10)
	house_spots.append(g + Vector3(14, 0, 16)); house_spots.append(g + Vector3(-8, 0, -6))
	big_spots.append([g, 24.0])
	# crop fields: coloured strips + hay bales
	var crop := StandardMaterial3D.new(); crop.albedo_color = Color(0.85, 0.72, 0.25)
	for k in 6:
		var fp := g + Vector3(-r * 0.7 + k * 9.0, 0.08, r * 0.55)
		var row := MeshInstance3D.new(); row.mesh = Util.box(Vector3(6, 0.5, 26)); row.material_override = crop
		row.position = Vector3(fp.x, height(fp.x, fp.z) + 0.2, fp.z); vis(row, 220.0); parent.add_child(row)
	for k in 10:
		var bp := g + Vector3(rng.randf_range(-r, r) * 0.7, 0, rng.randf_range(-r, -r * 0.3))
		var cyl := CylinderMesh.new(); cyl.top_radius = 0.8; cyl.bottom_radius = 0.8; cyl.height = 1.2
		var bale := Util.static_box(Vector3(1.6, 1.2, 1.6), Color(0.9, 0.78, 0.35), ground(bp.x, bp.z) + Vector3(0, 0.6, 0))
		bale.get_child(0).mesh = cyl; bale.get_child(0).rotation.z = PI / 2; vis(bale, 160.0); _place(parent, bale, 8)
	for k in 12: # fence posts
		var a := k / 12.0 * TAU
		var fpp := g + Vector3(cos(a) * r * 0.95, 0, sin(a) * r * 0.95)
		var f := Util.static_box(Vector3(4.0, 1.0, 0.15), Color(0.55, 0.38, 0.22), ground(fpp.x, fpp.z) + Vector3(0, 0.5, 0))
		f.rotation.y = -a + PI / 2; vis(f, 120.0); _place(parent, f, 5, false)

func _factory(parent: Node3D, c: Vector2, r: float) -> void:
	var g := ground(c.x, c.y)
	var keys := "abdefgh"
	for i in 6:
		var a := i / 6.0 * TAU; var d := r * 0.55
		var pos := ground(c.x + cos(a) * d, c.y + sin(a) * d)
		var b := box_model(IND % ("building-" + keys[i % keys.length()]), 9.0, pos, rng.randi() % 4 * PI / 2, true)
		vis(b, 450.0); Util.stylize(b, 0.0, 0.15); _place(parent, b, 12)
		house_spots.append(pos); big_spots.append([pos, 10.0])
	for k in 3:
		var t := box_model(IND % "detail-tank-large", 7.0, g + Vector3(-6 + k * 7, 0, 0), 0, false); vis(t, 300.0); _place(parent, t, 15)
	var ch := box_model(IND % "chimney-large", 12.0, g + Vector3(0, 0, -12), 0, false); vis(ch, 600.0); _place(parent, ch, 15)
	big_spots.append([g, 14.0])

func _docks(parent: Node3D, c: Vector2, r: float) -> void:
	var g := ground(c.x, c.y)
	var wood := Color(0.5, 0.36, 0.22)
	# three piers reaching out over the water (pointing away from the island centre)
	var out := c.normalized(); var side := out.orthogonal()
	for k in 3:
		var base := c + side * (k - 1) * 16.0 + out * 10.0
		var pier := Util.static_box(Vector3(6, 0.5, 46), wood, Vector3(base.x + out.x * 22, 0.6, base.y + out.y * 22))
		pier.rotation.y = atan2(out.x, out.y); vis(pier, 400.0); _place(parent, pier, 10)
		for pk in 6: # posts
			var pp := base + out * (pk * 8.0) + side * 3.0
			var post := Util.static_box(Vector3(0.5, 4, 0.5), wood.darkened(0.3), Vector3(pp.x, -1.2, pp.y)); vis(post, 200.0); parent.add_child(post)
	# shipping container stacks + crane on the quay
	var cols := "abc"
	for k in 10:
		var p := c + side * rng.randf_range(-r, r) * 0.9 - out * rng.randf_range(2, r * 0.8)
		var stack := 1 + (rng.randi() % 2)
		for s in stack:
			var cont := box_model(IND % ("shipping-container-" + cols[rng.randi() % 3]), 3.0, ground(p.x, p.y) + Vector3(0, s * 3.85, 0), atan2(out.x, out.y) + (PI / 2 if k % 2 == 0 else 0.0), false)
			vis(cont, 380.0); _place(parent, cont, 20)
	var crane := Node3D.new(); crane.position = g + Vector3(out.x * 8, 0, out.y * 8)
	for leg in [Vector3(-3, 0, -3), Vector3(3, 0, -3), Vector3(-3, 0, 3), Vector3(3, 0, 3)]:
		var l := Util.static_box(Vector3(0.7, 22, 0.7), Color(0.95, 0.6, 0.1), leg + Vector3(0, 11, 0)); crane.add_child(l)
	crane.add_child(Util.static_box(Vector3(3, 1.5, 34), Color(0.95, 0.6, 0.1), Vector3(0, 22, 8)))
	crane.rotation.y = atan2(out.x, out.y); vis(crane, 600.0); parent.add_child(crane)
	big_spots.append([g, r])

# ---------------------------------------------------------------- nature
const TREES := ["res://assets/nature/tree_default.glb", "res://assets/nature/tree_cone.glb",
	"res://assets/nature/tree_detailed.glb", "res://assets/nature/tree_oak.glb"]
const ROCKS := ["res://assets/nature/rock_largeA.glb", "res://assets/nature/rock_largeC.glb",
	"res://assets/nature/rock_tallA.glb", "res://assets/nature/rock_smallA.glb"]

## Trees and rocks grouped into 64 m chunk nodes (cheap culling + visibility ranges, nothing far away is drawn).
func build_nature(parent: Node3D) -> void:
	var tree_scenes := TREES.map(func(p): return load(p))
	var chunks := {}
	var tree_n := 200 if low else 340
	var placed := 0; var tries := 0
	while placed < tree_n and tries < tree_n * 6:
		tries += 1
		var p := rand_point(ISLAND * 0.88)
		if p.y < 0.6 or not _clear_spot(p, 2.0) or poi_at(p) == "Storm City": continue
		# forests: denser on the mountain flanks and around Pine Grove
		var dens := 0.35 + 0.65 * clampf(noise.get_noise_2d(p.x * 2.0, p.z * 2.0) + 0.3, 0, 1)
		if p.y > 30: dens *= 0.3 # bare rocky peak
		if rng.randf() > dens: continue
		var ck := Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))
		if not chunks.has(ck):
			var cn := Node3D.new(); cn.name = "Chunk%d_%d" % [ck.x, ck.y]; parent.add_child(cn); chunks[ck] = cn
		var t := StaticBody3D.new(); t.position = p
		var m: Node3D = tree_scenes[rng.randi() % tree_scenes.size()].instantiate()
		var sc := rng.randf_range(4.5, 6.5); m.scale = Vector3.ONE * sc; m.rotation.y = rng.randf() * TAU; t.add_child(m)
		var cs := CollisionShape3D.new(); var cyl := CylinderShape3D.new(); cyl.radius = 0.5; cyl.height = 6
		cs.shape = cyl; cs.position.y = 3; t.add_child(cs); t.set_meta("harvest", 15); chunks[ck].add_child(t)
		vis(t, 170.0 if low else 240.0)
		if not low: Util.stylize(m, 0.01, 0.2)
		trees.append([m, rng.randf() * TAU, rng.randf_range(0.6, 1.2)])
		placed += 1
	for i in (60 if low else 110):
		var p := rand_point()
		if p.y < 0.2 or not _clear_spot(p, 1.0): continue
		if Vector2(p.x, p.z).distance_to(MOUNTAIN) < 70 and rng.randf() < 0.5: p = ground(MOUNTAIN.x + rng.randf_range(-60, 60), MOUNTAIN.y + rng.randf_range(-60, 60))
		var r := Util.static_model(ROCKS[rng.randi() % ROCKS.size()], rng.randf_range(3, 6), p - Vector3(0, 0.3, 0))
		r.rotation.y = rng.randf() * TAU; vis(r, 200.0); _place(parent, r, 20)

# ---------------------------------------------------------------- map texture
func build_map_image(px := 256) -> ImageTexture:
	map_image = Image.create(px, px, false, Image.FORMAT_RGB8)
	for j in px:
		for i in px:
			var x := -SIZE / 2 + (i + 0.5) * SIZE / px; var z := -SIZE / 2 + (j + 0.5) * SIZE / px
			var y := height(x, z)
			var col: Color
			if y < -0.6: col = Color(0.12, 0.4, 0.7).lerp(Color(0.25, 0.65, 0.85), clampf((y + 6) / 6.0, 0, 1))
			elif y < 0.35: col = Color(0.9, 0.84, 0.6)
			elif y > 28: col = Color(0.55, 0.53, 0.5).lerp(Color(0.95, 0.95, 0.97), clampf((y - 38) / 10.0, 0, 1))
			else: col = Color(0.32, 0.62, 0.26).lerp(Color(0.25, 0.45, 0.2), clampf(y / 28.0, 0, 1))
			map_image.set_pixel(i, j, col)
	var road_c := Color(0.25, 0.25, 0.27)
	for pts in road_paths:
		for k in pts.size() - 1:
			var n := int(pts[k].distance_to(pts[k + 1]) / (SIZE / px)) + 1
			for s in n + 1:
				var p: Vector2 = pts[k].lerp(pts[k + 1], float(s) / n)
				var ix := int((p.x + SIZE / 2) / SIZE * px); var iz := int((p.y + SIZE / 2) / SIZE * px)
				if ix >= 0 and iz >= 0 and ix < px and iz < px and height(p.x, p.y) > 0.3: map_image.set_pixel(ix, iz, road_c)
	return ImageTexture.create_from_image(map_image)
