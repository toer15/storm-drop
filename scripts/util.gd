extends Node
## Autoload: shared settings and primitive-building helpers.
var sensitivity := 0.25
var bot_count := 15
## Screenshot mode: `godot -- --shot=res_or_user_path.png [--tab=Locker] [--delay=4]` saves the screen then quits.
var shot_path := ""
var shot_tab := ""
var shot_delay := 4.0
var hold_boot := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot_path = a.substr(7)
		elif a.begins_with("--tab="): shot_tab = a.substr(6)
		elif a.begins_with("--delay="): shot_delay = float(a.substr(8))
		elif a == "--hold-boot": hold_boot = true
		elif a == "--touch": touch_enabled = true
	if shot_path != "":
		await get_tree().create_timer(shot_delay).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		get_tree().quit()
## Touch controls: shown automatically on touch devices, can be toggled in Settings.
var touch_enabled := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") \
	or OS.has_feature("web_android") or OS.has_feature("web_ios")
var touch_move := Vector2.ZERO   # virtual joystick, -1..1
var touch_look := Vector2.ZERO   # accumulated look delta (pixels), consumed by player
var touch_fire := false
var touch_sprint := false
var touch_jump := false

func mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c
	if c.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func mesh(m: Mesh, c: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = m; mi.material_override = mat(c); mi.position = pos
	return mi

func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new(); b.size = size; return b

var CHARACTERS: Array = ["a", "b", "c", "d", "e", "f"].map(func(x): return "res://assets/characters/character-male-%s.glb" % x) + \
	["a", "b", "c", "d", "e", "f"].map(func(x): return "res://assets/characters/character-female-%s.glb" % x)
const SFX_PATHS := {
	"shoot": "res://assets/audio/shoot.ogg", "reload": "res://assets/audio/reload.ogg",
	"build": "res://assets/audio/build.ogg", "hit": "res://assets/audio/hit.ogg",
	"click": "res://assets/audio/click.ogg", "victory": "res://assets/audio/victory.ogg",
	"eliminated": "res://assets/audio/eliminated.ogg",
	"step0": "res://assets/audio/footstep_grass_000.ogg", "step1": "res://assets/audio/footstep_grass_001.ogg",
	"step2": "res://assets/audio/footstep_grass_002.ogg", "coin": "res://assets/audio/click.ogg",
}

## Kenney Mini Character (CC0) with cosmetics. skin/backbling/pickaxe are Profile catalog ids ("" = random skin, none).
func make_character(skin := "", backbling := "bb_none", pickaxe := "pick_default") -> Node3D:
	var root := Node3D.new(); root.name = "Model"
	var path: String
	if skin == "": path = CHARACTERS[randi() % CHARACTERS.size()]
	else: path = Profile.CATALOG[skin].data.model
	var model: Node3D = load(path).instantiate()
	model.scale = Vector3.ONE * 2.7
	model.rotation.y = PI # Kenney models face +Z, our forward is -Z
	root.add_child(model)
	var gun: Node3D = load("res://assets/weapons/blaster-a.glb").instantiate(); gun.name = "Gun"
	gun.scale = Vector3.ONE * 0.9; gun.position = Vector3(0.35, 1.0, -0.35); gun.rotation.y = PI
	root.add_child(gun)
	var pick := Node3D.new(); pick.name = "Pickaxe"; pick.position = Vector3(0.45, 0.75, -0.1); pick.rotation = Vector3(-0.9, 0, -0.3); pick.visible = false
	var pc: Color = Profile.CATALOG.get(pickaxe, Profile.CATALOG["pick_default"]).data.color
	pick.add_child(mesh(box(Vector3(0.08, 1.0, 0.08)), Color(0.4, 0.25, 0.1), Vector3(0, 0.3, 0)))
	var head := mesh(box(Vector3(0.6, 0.15, 0.15)), pc, Vector3(0, 0.8, 0))
	head.material_override.emission_enabled = true; head.material_override.emission = pc * 0.4
	pick.add_child(head); root.add_child(pick)
	var bb: Dictionary = Profile.CATALOG.get(backbling, {}).get("data", {"shape": "none"})
	if bb.shape != "none":
		var m: Mesh
		match bb.shape:
			"box": m = box(Vector3(0.5, 0.6, 0.25))
			"sphere": var sp := SphereMesh.new(); sp.radius = 0.3; sp.height = 0.6; m = sp
			"cylinder": var cy := CylinderMesh.new(); cy.top_radius = 0.15; cy.bottom_radius = 0.15; cy.height = 0.7; m = cy
			_: var pr := PrismMesh.new(); pr.size = Vector3(0.4, 0.7, 0.3); m = pr
		var bm := mesh(m, bb.color, Vector3(0, 1.15, 0.35)); bm.name = "BackBling"
		bm.material_override.emission_enabled = true; bm.material_override.emission = bb.color * 0.3
		root.add_child(bm)
	play_anim(root, "holding-right")
	return root

## Show the pickaxe or the gun (tinted by rarity colour).
func hold(model: Node3D, pickaxe: bool, tint := Color.WHITE) -> void:
	var gun: Node3D = model.get_node("Gun"); var pick: Node3D = model.get_node("Pickaxe")
	gun.visible = not pickaxe; pick.visible = pickaxe
	var ov := StandardMaterial3D.new(); ov.albedo_color = Color(tint, 0.35)
	ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; ov.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi in gun.find_children("*", "MeshInstance3D", true, false): mi.material_overlay = ov

func anim_player(model: Node) -> AnimationPlayer:
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	return aps[0] if aps.size() > 0 else null

func play_anim(model: Node, anim: String) -> void:
	var ap := anim_player(model)
	if ap == null or not ap.has_animation(anim): return
	if ap.current_animation != anim:
		var a := ap.get_animation(anim)
		if anim in ["idle", "walk", "sprint", "holding-right", "fall", "sit", "drive"]: a.loop_mode = Animation.LOOP_LINEAR
		ap.play(anim, 0.15)

var _sfx_cache := {}

## One-shot positional (or UI if pos is null) sound.
func sfx(name: String, pos = null, vol := 0.0) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null: return
	var p: Node
	if pos == null:
		p = AudioStreamPlayer.new()
	else:
		p = AudioStreamPlayer3D.new(); p.unit_size = 12.0
	if not _sfx_cache.has(name): _sfx_cache[name] = load(SFX_PATHS[name])
	p.stream = _sfx_cache[name]; p.volume_db = vol
	tree.current_scene.add_child(p)
	if pos != null: p.global_position = pos
	p.play(); p.finished.connect(p.queue_free)

## Instance a model with trimesh collision attached.
func static_model(path: String, scale_f: float, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new(); sb.position = pos
	var m: Node3D = load(path).instantiate(); m.scale = Vector3.ONE * scale_f; sb.add_child(m)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var cs := CollisionShape3D.new(); cs.shape = mi.mesh.create_trimesh_shape()
		var t: Transform3D = mi.transform; var n: Node = mi.get_parent()
		while n != m: t = n.transform * t; n = n.get_parent()
		cs.transform = m.transform * t
		sb.add_child(cs)
	return sb

## Static body with box collider and mesh.
func static_box(size: Vector3, c: Color, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new(); sb.position = pos
	sb.add_child(mesh(box(size), c))
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = size; cs.shape = sh
	sb.add_child(cs); return sb
