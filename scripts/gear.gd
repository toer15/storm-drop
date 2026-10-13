class_name Gear
## Loads the v1.3 gun / pickaxe / back bling models (Poly Pizza CC0, see CREDITS.md) and normalises them:
## barrel points -Z, origin at the grip, real-world length, with a "Muzzle" marker at the barrel tip.
const GUNS := {
	# path, rotation (deg) that makes the barrel point -Z, length in metres, grip offset (fraction of length from the back)
	"pistol":  ["res://assets/guns13/pistol.glb", Vector3(0, 0, 0), 0.26, 0.35],
	"ar":      ["res://assets/guns13/ar.glb", Vector3(0, 0, 0), 0.88, 0.42],
	"smg":     ["res://assets/guns13/smg.glb", Vector3(0, 0, 0), 0.62, 0.42],
	"shotgun": ["res://assets/guns13/shotgun.glb", Vector3(0, 90, 0), 1.0, 0.4],
	"sniper":  ["res://assets/guns13/sniper.glb", Vector3(0, 90, 0), 1.15, 0.38],
	"rocket":  ["res://assets/guns13/rocket.glb", Vector3(0, 0, 0), 1.15, 0.45],
}
const PICKAXES := {
	"pick_default": ["res://assets/props13/pickaxe.glb", Color(0, 0, 0, 0)],
	"pick_neon": ["res://assets/props13/pickaxe_diamond.glb", Color(0, 0, 0, 0)],
	"pick_gold": ["res://assets/props13/pickaxe_diamond.glb", Color(1, 0.8, 0.1, 0.55)],
	"pick_candy": ["res://assets/props13/pickaxe_stone.glb", Color(1, 0.35, 0.65, 0.5)],
	"pick_void": ["res://assets/props13/pickaxe_diamond.glb", Color(0.55, 0.15, 1.0, 0.6)],
}
static var _flip := {}

static func _bounds(n: Node3D) -> AABB:
	var bb := AABB(); var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY; var p: Node = mi
		while p != n and p is Node3D: t = (p as Node3D).transform * t; p = p.get_parent()
		var a: AABB = t * mi.get_aabb()
		bb = a if first else bb.merge(a); first = false
	return bb

## Wraps a model so its longest horizontal axis has the given length along -Z (after `rot`).
static func _fit(path: String, rot: Vector3, length: float, grip: float, flip := false) -> Node3D:
	var root := Node3D.new()
	var inner := Node3D.new(); inner.name = "Inner"; root.add_child(inner)
	var m: Node3D = load(path).instantiate(); inner.add_child(m)
	m.rotation_degrees = rot + (Vector3(0, 180, 0) if flip else Vector3.ZERO)
	var bb := _bounds(inner)
	var s := length / maxf(bb.size.z, 0.0001)
	inner.scale = Vector3.ONE * s
	var c := bb.get_center() * s
	# grip sits `grip` of the way from the back (+Z end) of the gun
	inner.position = -Vector3(c.x, c.y + bb.size.y * s * 0.15, c.z) + Vector3(0, 0, -length * (0.5 - grip))
	var mz := Marker3D.new(); mz.name = "Muzzle"; root.add_child(mz)
	mz.position = Vector3(0, 0.03, -length * (1.0 - grip))
	root.set_meta("length", length)
	return root

static func make_gun(type: String) -> Node3D:
	var g: Array = GUNS.get(type, GUNS["ar"])
	var n := _fit(g[0], g[1], g[2], g[3], type in ["pistol", "ar", "smg"])
	n.name = "Gun"
	Util.stylize(n, 0.0, 0.25)
	return n

static func make_pickaxe(id: String) -> Node3D:
	var p: Array = PICKAXES.get(id, PICKAXES["pick_default"])
	var root := Node3D.new(); root.name = "Pickaxe"
	var inner := Node3D.new(); root.add_child(inner)
	var m: Node3D = load(p[0]).instantiate(); inner.add_child(m)
	var bb := _bounds(inner)
	var s := 0.95 / maxf(bb.size.y, 0.0001); inner.scale = Vector3.ONE * s
	inner.position = -bb.get_center() * s + Vector3(0, 0.3, 0) # hold near the bottom of the handle
	var tint: Color = p[1]
	if tint.a > 0.0:
		var ov := StandardMaterial3D.new(); ov.albedo_color = tint; ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ov.emission_enabled = true; ov.emission = Color(tint.r, tint.g, tint.b) * 0.5
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false): mi.material_overlay = ov
	Util.stylize(root, 0.0, 0.3)
	return root

## Back blings: real backpack models for the "pack" items, glowing procedural shapes for the magic ones.
static func make_backbling(id: String) -> Node3D:
	var bb: Dictionary = Profile.CATALOG.get(id, {}).get("data", {"shape": "none"})
	if bb.shape == "none": return null
	var root := Node3D.new(); root.name = "BackBling"
	var path := ""
	match bb.shape:
		"box": path = "res://assets/props13/backpack.glb"
		"cylinder": path = "res://assets/props13/vest_pack.glb"
	if path != "":
		var inner := Node3D.new(); root.add_child(inner)
		var m: Node3D = load(path).instantiate(); inner.add_child(m)
		var b := _bounds(inner); var s := 0.42 / maxf(b.size.y, 0.0001)
		inner.scale = Vector3.ONE * s; inner.position = -b.get_center() * s
		if id == "bb_candy":
			var ov := StandardMaterial3D.new(); ov.albedo_color = Color(1, 0.4, 0.75, 0.45); ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false): mi.material_overlay = ov
		Util.stylize(root, 0.0, 0.3)
	else:
		var mesh: Mesh
		if bb.shape == "sphere": var sp := SphereMesh.new(); sp.radius = 0.22; sp.height = 0.44; mesh = sp
		else: var pr := PrismMesh.new(); pr.size = Vector3(0.35, 0.55, 0.25); mesh = pr
		var mi := Util.mesh(mesh, bb.color); mi.material_override.emission_enabled = true
		mi.material_override.emission = bb.color * 0.8; root.add_child(mi)
	return root
